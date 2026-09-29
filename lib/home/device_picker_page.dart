import 'dart:async';

import 'package:flutter/material.dart';

import 'package:windows_app/services/discovery_service.dart';
import 'package:windows_app/theme/app_colors.dart';

/// Shows a modal sheet listing discovered PCs. Returns the picked one,
/// or null if dismissed.
Future<DiscoveredServer?> showDevicePicker(
  BuildContext context,
  DiscoveryService disco, {
  String? currentUrl,
}) {
  return showModalBottomSheet<DiscoveredServer>(
    context: context,
    backgroundColor: AppColors.surfaceHi,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    isScrollControlled: true,
    builder: (ctx) => _DevicePickerSheet(disco: disco, currentUrl: currentUrl),
  );
}

class _DevicePickerSheet extends StatefulWidget {
  final DiscoveryService disco;
  final String? currentUrl;

  const _DevicePickerSheet({required this.disco, this.currentUrl});

  @override
  State<_DevicePickerSheet> createState() => _DevicePickerSheetState();
}

class _DevicePickerSheetState extends State<_DevicePickerSheet> {
  Timer? _timeoutTimer;
  bool _timedOut = false;

  static const _searchTimeout = Duration(seconds: 8);

  @override
  void initState() {
    super.initState();
    widget.disco.addListener(_onDiscoveryChanged);
    _startTimeout();
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    widget.disco.removeListener(_onDiscoveryChanged);
    super.dispose();
  }

  void _onDiscoveryChanged() {
    if (!mounted) return;
    if (widget.disco.servers.isNotEmpty) {
      _timeoutTimer?.cancel();
      _timedOut = false;
    }
    setState(() {});
  }

  void _startTimeout() {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(_searchTimeout, () {
      if (!mounted) return;
      if (widget.disco.servers.isEmpty) {
        setState(() => _timedOut = true);
      }
    });
  }

  void _pick(DiscoveredServer s) => Navigator.of(context).pop(s);

  void _cancel() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final servers = widget.disco.servers;
    final hasCurrent = widget.currentUrl != null;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildDragHandle(),
            _buildHeader(),
            const SizedBox(height: 16),

            if (hasCurrent) ...[
              _buildCurrentCard(widget.currentUrl!),
              const SizedBox(height: 12),
            ],

            if (servers.isNotEmpty)
              _buildServerList(servers)
            else if (_timedOut)
              _buildNoResultsState()
            else
              _buildSearchingState(),

            const SizedBox(height: 16),
            TextButton(
              onPressed: _cancel,
              child: const Text(
                'Cancel',
                style: TextStyle(color: AppColors.text2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDragHandle() {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: AppColors.border,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Text(
          'Select your PC',
          style: TextStyle(
            color: AppColors.text,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: 4),
        Text(
          'Make sure MouseRemote is running on the PC',
          style: TextStyle(color: AppColors.text2, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildCurrentCard(String url) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.successSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.successSoft,
            ),
            child: const Icon(
              Icons.link_rounded,
              color: AppColors.success,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Currently connected',
                  style: TextStyle(
                    color: AppColors.success,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  url,
                  style: const TextStyle(
                    color: AppColors.text3,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServerList(List<DiscoveredServer> servers) {
    return Flexible(
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: servers.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) => _buildServerTile(servers[i]),
      ),
    );
  }

  Widget _buildServerTile(DiscoveredServer s) {
    final isCurrent =
        widget.currentUrl != null && _urlsMatch(widget.currentUrl!, s.wsUrl);

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _pick(s),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.accentSoft,
                  border: Border.all(
                    color: AppColors.accent.withValues(alpha: 0.4),
                  ),
                ),
                child: const Icon(
                  Icons.desktop_windows_rounded,
                  color: AppColors.accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            s.name,
                            style: const TextStyle(
                              color: AppColors.text,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isCurrent) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.successSoft,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'CURRENT',
                              style: TextStyle(
                                color: AppColors.success,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      s.wsUrl,
                      style: const TextStyle(
                        color: AppColors.text3,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.text3),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchingState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(
                AppColors.accent.withValues(alpha: 0.7),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Searching…',
            style: TextStyle(
              color: AppColors.text,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Looking for MouseRemote on your network',
            style: TextStyle(color: AppColors.text2, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildNoResultsState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          const Icon(
            Icons.wifi_tethering_off_rounded,
            color: AppColors.text3,
            size: 32,
          ),
          const SizedBox(height: 12),
          const Text(
            'No PCs found',
            style: TextStyle(
              color: AppColors.text,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Make sure:\n'
            '• MouseRemote is running on the PC\n'
            '• Both devices are on the same Wi‑Fi\n'
            '• The network allows device discovery',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.text2, fontSize: 12, height: 1.5),
          ),
        ],
      ),
    );
  }

  bool _urlsMatch(String a, String b) {
    String norm(String s) =>
        s.trim().replaceAll(RegExp(r'/+$'), '').toLowerCase();
    return norm(a) == norm(b);
  }
}
