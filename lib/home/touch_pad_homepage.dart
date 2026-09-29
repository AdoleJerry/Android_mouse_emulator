import 'package:flutter/material.dart';
import 'package:windows_app/home/device_picker_page.dart';
import 'package:windows_app/services/discovery_service.dart';

import 'package:windows_app/services/websocket_service.dart';
import 'package:windows_app/theme/app_colors.dart';

class TouchpadHomePage extends StatefulWidget {
  const TouchpadHomePage({super.key});

  @override
  State<TouchpadHomePage> createState() => _TouchpadHomePageState();
}

class _TouchpadHomePageState extends State<TouchpadHomePage> {
  late final WebSocketService _ws;
  late final DiscoveryService _disco;

  // ---- Local UI-only state (modes are a UI concept) ----
  bool _scrollMode = false;
  bool _dragMode = false;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _disco = DiscoveryService();
    _disco.start();
    _ws = WebSocketService();
    _ws.addListener(_onServiceChanged);
    _ws.init();
  }

  @override
  void dispose() {
    _disco.dispose();
    _ws.removeListener(_onServiceChanged);
    _ws.dispose();
    super.dispose();
  }

  void _onServiceChanged() {
    // If the service gave up, prompt the user.
    if (_ws.gaveUp) _maybeShowGiveUpPrompt();
    if (mounted) setState(() {});
  }

  bool _promptShown = false;

  Future<void> _maybeShowGiveUpPrompt() async {
    if (_promptShown) return;
    _promptShown = true;
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceHi,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.border),
        ),
        title: const Text(
          'Connection failed',
          style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600),
        ),
        content: const Text(
          'Could not reach the server after 5 attempts.\n\n'
          'Check that:\n'
          '• Your phone and PC are on the same Wi-Fi\n'
          '• The Go server is running on your PC\n'
          '• The network allows device discovery\n\n'
          'Tap "Pick Device" to try again.',
          style: TextStyle(color: AppColors.text2, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Dismiss',
              style: TextStyle(color: AppColors.text2),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Future.delayed(const Duration(milliseconds: 250), () {
                if (mounted) _openSettings();
              });
            },
            child: const Text(
              'Pick Device',
              style: TextStyle(color: AppColors.accent),
            ),
          ),
        ],
      ),
    );
    _promptShown = false;
  }

  // ===================================================================
  // UI callbacks — all delegate to the service
  // ===================================================================
  void _onCursorMove(Offset d) => _ws.moveCursor(d);
  void _onScroll(Offset d) => _ws.scroll(d);
  void _onLeftClick() => _ws.leftClick();
  void _onRightClick() => _ws.rightClick();
  void _onLongPress() => _ws.longPress();

  void _onDragStart() {
    if (_isDragging) return;
    _isDragging = true;
    _ws.dragStart();
    setState(() {});
  }

  void _onDragEnd() {
    if (!_isDragging) return;
    _isDragging = false;
    _ws.dragEnd();
    setState(() {});
  }

  Future<void> _openSettings() async {
    // Make sure discovery is running.
    if (!_disco.isRunning) {
      final ok = await _disco.start();
      if (!ok) {
        debugPrint('[UI] discovery failed to start');
        return;
      }
    }

    if (!mounted) return;

    final picked = await showDevicePicker(
      context,
      _disco,
      currentUrl: _ws.isConnected ? _ws.serverUrl : null,
    );

    if (picked == null) return;

    _promptShown = false;
    await _ws.setServerUrl(picked.wsUrl);
  }

  // ===================================================================
  // Build
  // ===================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgTop,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.bgTop, AppColors.bgBottom],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              children: [
                _buildStatusBar(),
                const SizedBox(height: 16),
                Expanded(child: _buildTouchpad()),
                const SizedBox(height: 16),
                _buildBottomBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBar() {
    final connected = _ws.isConnected;
    final gaveUp = _ws.gaveUp;

    final dotColor = connected
        ? AppColors.success
        : gaveUp
        ? AppColors.danger
        : AppColors.warning;
    final dotSoft = connected
        ? AppColors.successSoft
        : gaveUp
        ? AppColors.dangerSoft
        : AppColors.warningSoft;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              if (_ws.gaveUp) {
                _openSettings();
              } else {
                _ws.retryNow();
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dotSoft,
                border: Border.all(color: dotColor.withValues(alpha: 0.5)),
              ),
              child: Center(
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: dotColor,
                    boxShadow: [
                      BoxShadow(
                        color: dotColor.withValues(alpha: 0.7),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'My PC',
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _ws.statusText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.text2,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _openSettings,
            icon: const Icon(
              Icons.tune_rounded,
              color: AppColors.text2,
              size: 20,
            ),
            splashRadius: 22,
          ),
        ],
      ),
    );
  }

  Widget _buildTouchpad() {
    final active = _scrollMode || _dragMode;
    final activeColor = _scrollMode ? AppColors.warning : AppColors.cyan;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: AppColors.surface,
        border: Border.all(
          color: active ? activeColor.withValues(alpha: 0.4) : AppColors.border,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: active
                ? activeColor.withValues(alpha: 0.15)
                : Colors.black.withValues(alpha: 0.3),
            blurRadius: active ? 28 : 18,
            spreadRadius: active ? 0 : -2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 0.8,
                    colors: [
                      active
                          ? activeColor.withValues(alpha: 0.06)
                          : AppColors.accent.withValues(alpha: 0.04),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Listener(
              onPointerDown: (_) {
                if (_dragMode) _onDragStart();
              },
              onPointerUp: (_) {
                if (_dragMode) _onDragEnd();
              },
              onPointerCancel: (_) {
                if (_dragMode) _onDragEnd();
              },
              onPointerMove: (event) {
                if (_scrollMode) {
                  _onScroll(event.delta);
                } else {
                  _onCursorMove(event.delta);
                }
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _dragMode ? null : _onLeftClick,
                onSecondaryTap: _dragMode ? null : _onRightClick,
                onLongPress: _dragMode ? null : _onLongPress,
                child: Stack(
                  children: [
                    Positioned(
                      top: 16,
                      left: 16,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 200),
                        opacity: _scrollMode ? 1.0 : 0.0,
                        child: _modeBadge(
                          label: 'SCROLL',
                          icon: Icons.swap_vert_rounded,
                          color: AppColors.warning,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 16,
                      left: 16,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 200),
                        opacity: _dragMode ? 1.0 : 0.0,
                        child: _modeBadge(
                          label: 'DRAG',
                          icon: Icons.drag_indicator_rounded,
                          color: AppColors.cyan,
                        ),
                      ),
                    ),
                    Center(
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 250),
                        opacity: active ? 0.0 : 0.35,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.touch_app_rounded,
                              size: 44,
                              color: AppColors.text3.withValues(alpha: 0.9),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'TOUCHPAD',
                              style: TextStyle(
                                color: AppColors.text3,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeBadge({
    required String label,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _MouseClickWidget(
            onLeft: _onLeftClick,
            onRight: _onRightClick,
            isDragging: _isDragging,
          ),
          const SizedBox(width: 16),
          Container(width: 1, height: 96, color: AppColors.border),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ModeToggle(
                  icon: Icons.swap_vert_rounded,
                  label: 'Scroll',
                  color: AppColors.warning,
                  active: _scrollMode,
                  onTap: () {
                    setState(() {
                      _scrollMode = !_scrollMode;
                      if (_scrollMode) _dragMode = false;
                    });
                  },
                ),
                const SizedBox(height: 10),
                _ModeToggle(
                  icon: Icons.drag_indicator_rounded,
                  label: 'Drag',
                  color: AppColors.cyan,
                  active: _dragMode,
                  onTap: () {
                    if (_isDragging) _onDragEnd();
                    setState(() {
                      _dragMode = !_dragMode;
                      if (_dragMode) _scrollMode = false;
                    });
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// Mouse widget (pure UI)
// =====================================================================
class _MouseClickWidget extends StatefulWidget {
  final VoidCallback onLeft;
  final VoidCallback onRight;
  final bool isDragging;

  const _MouseClickWidget({
    required this.onLeft,
    required this.onRight,
    this.isDragging = false,
  });

  @override
  State<_MouseClickWidget> createState() => _MouseClickWidgetState();
}

class _MouseClickWidgetState extends State<_MouseClickWidget> {
  bool _leftDown = false;
  bool _rightDown = false;

  static const double _w = 84;
  static const double _h = 120;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _w,
      height: _h,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_w * 0.45),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF202A3D), Color(0xFF131A28)],
              ),
              border: Border.all(color: AppColors.borderHi, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, -1),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            width: _w / 2,
            height: _h * 0.55,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) => setState(() => _leftDown = true),
              onTapUp: (_) => setState(() => _leftDown = false),
              onTapCancel: () => setState(() => _leftDown = false),
              onTap: widget.onLeft,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                decoration: BoxDecoration(
                  color: (_leftDown || widget.isDragging)
                      ? AppColors.accent.withValues(alpha: 0.22)
                      : Colors.transparent,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(_w * 0.45),
                    topRight: const Radius.circular(4),
                  ),
                ),
                child: Align(
                  alignment: const Alignment(0, 0.55),
                  child: Text(
                    'L',
                    style: TextStyle(
                      color: (_leftDown || widget.isDragging)
                          ? AppColors.accent
                          : AppColors.text2,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            width: _w / 2,
            height: _h * 0.55,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) => setState(() => _rightDown = true),
              onTapUp: (_) => setState(() => _rightDown = false),
              onTapCancel: () => setState(() => _rightDown = false),
              onTap: widget.onRight,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                decoration: BoxDecoration(
                  color: _rightDown
                      ? AppColors.accent.withValues(alpha: 0.22)
                      : Colors.transparent,
                  borderRadius: BorderRadius.only(
                    topRight: Radius.circular(_w * 0.45),
                    topLeft: const Radius.circular(4),
                  ),
                ),
                child: Align(
                  alignment: const Alignment(0, 0.55),
                  child: Text(
                    'R',
                    style: TextStyle(
                      color: _rightDown ? AppColors.accent : AppColors.text2,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: _w / 2 - 0.5,
            top: 10,
            width: 1,
            height: _h * 0.55 - 10,
            child: Container(color: AppColors.borderHi),
          ),
          Positioned(
            left: 10,
            right: 10,
            top: _h * 0.55,
            height: 1,
            child: Container(color: AppColors.border),
          ),
          Positioned(
            left: _w / 2 - 3,
            top: 10,
            width: 6,
            height: 18,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(3),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.accent.withValues(alpha: 0.4),
                    blurRadius: 5,
                    spreadRadius: 0.5,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: _w / 2 - 3,
            bottom: 16,
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.text3.withValues(alpha: 0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// Mode toggle
// =====================================================================
class _ModeToggle extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool active;
  final VoidCallback onTap;

  const _ModeToggle({
    required this.icon,
    required this.label,
    required this.color,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.15) : AppColors.surfaceHi,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active ? color.withValues(alpha: 0.5) : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: active ? color : AppColors.text2),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: active ? color : AppColors.text2,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
