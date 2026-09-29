import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/status.dart' as ws_status;
import 'package:web_socket_channel/web_socket_channel.dart';

enum WsState { disconnected, connecting, connected, gaveUp }

class WebSocketService extends ChangeNotifier {
  WebSocketService({
    this.defaultUrl = 'ws://192.168.1.14:8080/ws',
    this.maxRetries = 5,
    this.retryDelay = const Duration(seconds: 3),
    this.sensitivity = 1.8,
    this.pingInterval = const Duration(seconds: 10),
    this.connectTimeout = const Duration(seconds: 8),
  }) : _serverUrl = defaultUrl;

  final String defaultUrl;
  final int maxRetries;
  final Duration retryDelay;
  final double sensitivity;
  final Duration pingInterval;
  final Duration connectTimeout;

  static const _prefsKey = 'server_url';

  // Plain field — starts at defaultUrl so it's ALWAYS readable.
  // Overwritten in init() from prefs.
  String _serverUrl;

  WsState _state = WsState.disconnected;
  int _retryCount = 0;
  String? _lastError;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _reconnectTimer;
  bool _disposed = false;
  bool _connecting = false; // guard against re-entrant connect()

  // ---- Getters ----
  String get serverUrl => _serverUrl;
  WsState get state => _state;
  int get retryCount => _retryCount;
  int get maxRetryCount => maxRetries;
  String? get lastError => _lastError;
  bool get isConnected => _state == WsState.connected;
  bool get gaveUp => _state == WsState.gaveUp;

  String get statusText {
    switch (_state) {
      case WsState.connected:
        return 'Connected';
      case WsState.gaveUp:
        return 'Tap to enter correct IP';
      case WsState.connecting:
        return _retryCount > 0
            ? 'Connecting… ($_retryCount/$maxRetries)'
            : 'Connecting…';
      case WsState.disconnected:
        return 'Disconnected';
    }
  }

  // ===================================================================
  // Lifecycle
  // ===================================================================
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      if (saved != null && saved.isNotEmpty) _serverUrl = saved;
    } catch (_) {}
    if (_disposed) return;
    await connect();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _teardown();
    super.dispose();
  }

  // ===================================================================
  // Connection management
  // ===================================================================
  Future<void> connect() async {
    if (_disposed) return;

    // Prevent two connect() calls racing each other.
    if (_connecting) {
      debugPrint('[WS] connect() ignored — already connecting');
      return;
    }
    _connecting = true;

    try {
      _teardown();
      _serverUrl = _normalizeUrl(_serverUrl);
      _setState(WsState.connecting, error: null);

      final ch = IOWebSocketChannel.connect(
        Uri.parse(_serverUrl),
        pingInterval: pingInterval,
        connectTimeout: connectTimeout,
      );
      _channel = ch;

      _sub = ch.stream.listen(
        (_) {},
        onDone: () => _onDisconnected(null),
        onError: (Object err, StackTrace _) => _onDisconnected(err),
        cancelOnError: false,
      );

      await ch.ready;
      if (_disposed) return;

      _retryCount = 0;
      _setState(WsState.connected);
      debugPrint('[WS] connected to $_serverUrl');
    } catch (e) {
      debugPrint('[WS] connect failed: $e');
      _onDisconnected(e);
    } finally {
      _connecting = false;
    }
  }

  /// Change the server URL, persist it, and reconnect.
  /// Safe to call at any time, even while connecting.
  Future<void> setServerUrl(String url) async {
    if (_disposed) return;

    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      debugPrint('[WS] setServerUrl called with empty string — ignoring');
      return;
    }

    debugPrint('[WS] changing URL → $trimmed');

    // 1. Tear down whatever is running, without any await that could hang.
    _teardown();

    // 2. Reset the state machine to a clean slate.
    _serverUrl = _normalizeUrl(trimmed);
    _retryCount = 0;
    _promptReentryGuard();
    _setState(WsState.disconnected);

    // 3. Persist asynchronously (never blocks the reconnect).
    unawaited(_persistUrl(_serverUrl));

    // 4. Connect on the next microtask so we're not inside any
    //    dialog's build/dismiss cycle.
    await Future<void>.delayed(Duration.zero);
    if (_disposed) return;
    await connect();
  }

  Future<void> retryNow() async {
    if (_disposed) return;
    _retryCount = 0;
    if (_state == WsState.gaveUp) _state = WsState.disconnected;
    await connect();
  }

  void resetRetries() {
    _retryCount = 0;
    if (_state == WsState.gaveUp) _state = WsState.disconnected;
    _promptReentryGuard();
  }

  // Hook the UI overrides to clear its own prompt flag.
  void Function()? _onRetriesReset;
  void _promptReentryGuard() => _onRetriesReset?.call();

  /// UI can register a callback to be notified when retries are reset.
  set onRetriesReset(void Function()? cb) => _onRetriesReset = cb;

  // ===================================================================
  // Input API (unchanged)
  // ===================================================================
  void moveCursor(Offset delta) => _send({
    'type': 'move',
    'dx': delta.dx * sensitivity,
    'dy': delta.dy * sensitivity,
  });

  void leftClick() => _send({'type': 'click', 'button': 'left'});
  void rightClick() => _send({'type': 'click', 'button': 'right'});
  void longPress() => _send({'type': 'longpress'});

  void scroll(Offset delta) => _send({
    'type': 'scroll',
    'scrollX': -delta.dx * sensitivity,
    'scrollY': -delta.dy * sensitivity,
  });

  void dragStart() => _send({'type': 'mousedown', 'button': 'left'});
  void dragEnd() => _send({'type': 'mouseup', 'button': 'left'});

  // ===================================================================
  // Internals
  // ===================================================================

  /// Fully synchronous, cannot throw, cannot hang. After this returns
  /// there is no live subscription, no live channel, and no timer.
  void _teardown() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    final sub = _sub;
    final ch = _channel;
    _sub = null;
    _channel = null;

    if (sub != null) {
      try {
        sub.cancel().catchError((_) => null);
      } catch (_) {}
    }

    if (ch != null) {
      try {
        ch.sink.close(ws_status.normalClosure);
      } catch (e) {
        debugPrint('[WS] close error (ignored): $e');
      }
    }
  }

  void _onDisconnected([Object? error]) {
    if (_disposed) return;
    if (_state == WsState.disconnected || _state == WsState.gaveUp) return;
    if (_connecting) return; // ignore stray onDone from a torn-down socket

    debugPrint('[WS] disconnected: ${error ?? "clean close"}');
    _setState(WsState.disconnected, error: error?.toString());
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    if (_disposed) return;

    if (_retryCount >= maxRetries) {
      _setState(WsState.gaveUp);
      return;
    }

    _retryCount++;
    _notify();

    _reconnectTimer = Timer(retryDelay, () {
      if (_disposed) return;
      if (_state == WsState.connected || _state == WsState.gaveUp) return;
      connect();
    });
  }

  void _send(Map<String, dynamic> payload) {
    final ch = _channel;
    if (ch == null || _state != WsState.connected) return;
    try {
      ch.sink.add(jsonEncode(payload));
    } catch (e) {
      debugPrint('[WS] send failed: $e');
    }
  }

  Future<void> _persistUrl(String url) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, url);
    } catch (_) {}
  }

  void _setState(WsState newState, {String? error}) {
    if (_disposed) return;
    _state = newState;
    _lastError = error;
    _notify();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  String _normalizeUrl(String input) {
    var s = input.trim();
    s = s.replaceFirst(
      RegExp(r'^(ws|wss|http|https)://', caseSensitive: false),
      '',
    );
    s = s.replaceAll(RegExp(r'/+$'), '');
    if (s.isEmpty) return defaultUrl;
    if (!s.contains('/')) s = '$s/ws';
    return 'ws://$s';
  }
}
