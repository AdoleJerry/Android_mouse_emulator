import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// A PC discovered on the LAN.
class DiscoveredServer {
  final String name;
  final String ip;
  final int wsPort;
  final String version;
  final DateTime lastSeen;

  DiscoveredServer({
    required this.name,
    required this.ip,
    required this.wsPort,
    required this.version,
    required this.lastSeen,
  });

  /// Full WebSocket URL ready for WebSocketService.
  String get wsUrl => 'ws://$ip:$wsPort/ws';

  /// Stable key for deduping in lists.
  String get key => '$ip:$wsPort';

  @override
  String toString() => '$name ($ip)';
}

/// Listens for UDP beacons from Go servers on the LAN.
///
/// Usage:
///   final disco = DiscoveryService();
///   disco.addListener(() => print(disco.servers));
///   await disco.start();
///   // ...
///   disco.stop();
class DiscoveryService extends ChangeNotifier {
  DiscoveryService({this.port = 45678});

  final int port;

  static const _magic = 'MOUSEREMOTE_v1';
  static const _probePayload = 'MOUSEREMOTE_DISCOVER';
  static const _staleAfter = Duration(seconds: 6);
  static const _probeInterval = Duration(seconds: 3);

  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _sub;
  Timer? _pruneTimer;
  Timer? _probeTimer;
  bool _disposed = false;
  bool _running = false;

  // Keyed by "ip:port" so duplicates refresh instead of appending.
  final Map<String, DiscoveredServer> _servers = {};

  List<DiscoveredServer> get servers =>
      _servers.values.toList()..sort((a, b) => a.name.compareTo(b.name));

  bool get isRunning => _running;

  // ===================================================================
  // Lifecycle
  // ===================================================================
  Future<bool> start() async {
    if (_disposed || _running) return _running;

    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        port,
        reuseAddress: true,
        reusePort: false,
      );
      socket.broadcastEnabled = true;
      socket.readEventsEnabled = true;

      // IMPORTANT: assign _socket BEFORE any probe is sent, or
      // _sendProbe() will bail out because the socket is null.
      _socket = socket;

      _sub = socket.listen(
        _onSocketEvent,
        onError: (e) => debugPrint('[disco] socket error: $e'),
      );

      // Fire one probe immediately, then on a recurring timer.
      await _sendProbe();
      _probeTimer = Timer.periodic(_probeInterval, (_) => _sendProbe());

      // Prune stale entries every 2 s.
      _pruneTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => _pruneStale(),
      );

      _running = true;
      debugPrint('[disco] listening on UDP $port');
      _notify();
      return true;
    } catch (e) {
      debugPrint('[disco] bind failed: $e');
      _running = false;
      _notify();
      return false;
    }
  }

  void stop() {
    _probeTimer?.cancel();
    _probeTimer = null;
    _pruneTimer?.cancel();
    _pruneTimer = null;
    _sub?.cancel();
    _sub = null;
    try {
      _socket?.close();
    } catch (_) {}
    _socket = null;
    _running = false;
    if (!_disposed) _notify();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    stop();
    super.dispose();
  }

  // ===================================================================
  // Probing — sends a "who's out there" packet to every broadcast
  // address the phone can reach.
  // ===================================================================
  Future<void> _sendProbe() async {
    final socket = _socket;
    if (socket == null) return;

    try {
      final payload = utf8.encode(_probePayload);

      // Global broadcast — works on most home routers.
      socket.send(payload, InternetAddress('255.255.255.255'), port);

      // Subnet broadcast(s) — survives routers that drop 255.255.255.255.
      for (final iface in await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      )) {
        for (final addr in iface.addresses) {
          final bcast = _subnetBroadcast(addr.address);
          if (bcast != null) {
            try {
              socket.send(payload, InternetAddress(bcast), port);
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      debugPrint('[disco] probe error: $e');
    }
  }

  /// Given an IPv4 address like "192.168.1.42", returns "192.168.1.255".
  /// Assumes a /24 subnet, which covers virtually all home Wi-Fi.
  String? _subnetBroadcast(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return null;
    return '${parts[0]}.${parts[1]}.${parts[2]}.255';
  }

  // ===================================================================
  // Internals
  // ===================================================================
  void _onSocketEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final socket = _socket;
    if (socket == null) return;
    final dg = socket.receive();
    if (dg == null) return;
    _handleDatagram(dg);
  }

  void _handleDatagram(Datagram dg) {
    try {
      final text = utf8.decode(dg.data, allowMalformed: true).trim();
      if (text.isEmpty) return;

      final obj = jsonDecode(text);
      if (obj is! Map) return;

      // Ignore anything that isn't our beacon.
      if (obj['magic'] != _magic) return;

      final name = (obj['name'] as String?)?.trim();
      final ip = (obj['ip'] as String?)?.trim();
      final wsPort = (obj['ws_port'] as num?)?.toInt();
      final version = (obj['version'] as String?) ?? '';

      if (wsPort == null) return;

      // Prefer the source address of the datagram over the server's
      // self-reported IP. The datagram's source is what the phone can
      // actually reach; the self-reported IP can be wrong if the PC
      // has multiple network interfaces.
      final srcIp = dg.address.address;
      final useIp = srcIp.isNotEmpty ? srcIp : (ip ?? '');
      if (useIp.isEmpty) return;

      final entry = DiscoveredServer(
        name: (name == null || name.isEmpty) ? 'Unnamed PC' : name,
        ip: useIp,
        wsPort: wsPort,
        version: version,
        lastSeen: DateTime.now(),
      );

      final isNew = !_servers.containsKey(entry.key);
      _servers[entry.key] = entry;

      if (isNew) {
        debugPrint('[disco] found ${entry.name} @ ${entry.wsUrl}');
      }
      _notify();
    } catch (_) {
      // Malformed packet — ignore.
    }
  }

  void _pruneStale() {
    final now = DateTime.now();
    final before = _servers.length;
    _servers.removeWhere((_, s) => now.difference(s.lastSeen) > _staleAfter);
    if (_servers.length != before) {
      debugPrint('[disco] pruned ${before - _servers.length} stale entries');
      _notify();
    }
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }
}
