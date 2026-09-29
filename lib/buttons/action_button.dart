import 'package:flutter/material.dart';

class ActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;
  final bool isActive;

  const ActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
    this.isActive = false,
  });

  @override
  State<ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<ActionButton>
    with TickerProviderStateMixin {
  late final AnimationController _activePulseController;
  late final AnimationController _tapPulseController;

  @override
  void initState() {
    super.initState();

    _activePulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _tapPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    // Drive rebuilds ourselves — no merged listenable, no
    // AnimatedBuilder, no framework-owned listener shuffling.
    _activePulseController.addListener(_onTick);
    _tapPulseController.addListener(_onTick);

    if (widget.isActive) {
      _activePulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant ActionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !_activePulseController.isAnimating) {
      _activePulseController.repeat(reverse: true);
    } else if (!widget.isActive && _activePulseController.isAnimating) {
      _activePulseController.stop();
      _activePulseController.reset();
    }
  }

  @override
  void dispose() {
    _activePulseController.removeListener(_onTick);
    _tapPulseController.removeListener(_onTick);
    _activePulseController.dispose();
    _tapPulseController.dispose();
    super.dispose();
  }

  void _onTick() {
    if (!mounted) return;
    setState(() {});
  }

  void _playTapPulse() {
    if (!mounted) return;
    _tapPulseController.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    // Compute scale directly from controller values — no animation
    // objects, no merged listenables, nothing that can be "used after
    // dispose" because we only read controller state.
    double scale = 1.0;
    if (widget.isActive) {
      final t = Curves.easeInOut.transform(_activePulseController.value);
      scale *= 1.0 + 0.15 * t;
    }
    if (_tapPulseController.isAnimating) {
      final t = Curves.easeOutBack.transform(_tapPulseController.value);
      scale *= 1.0 + 0.2 * t;
    }

    return GestureDetector(
      onTap: () {
        widget.onPressed();
        _playTapPulse();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Transform.scale(
            scale: scale,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withValues(
                  alpha: widget.isActive ? 0.3 : 0.15,
                ),
                boxShadow: widget.isActive
                    ? [
                        BoxShadow(
                          color: widget.color.withValues(alpha: 0.5),
                          blurRadius: 16,
                          spreadRadius: 2,
                        ),
                      ]
                    : [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ],
              ),
              child: Icon(widget.icon, color: widget.color, size: 28),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.label,
            style: TextStyle(
              color: widget.isActive
                  ? widget.color
                  : Colors.white.withValues(alpha: 0.6),
              fontSize: 13,
              fontWeight: widget.isActive ? FontWeight.bold : FontWeight.w500,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
