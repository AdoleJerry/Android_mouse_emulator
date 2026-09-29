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
  late final Animation<double> _activePulseAnimation;
  late final AnimationController _tapPulseController;
  late final Animation<double> _tapPulseAnimation;

  @override
  void initState() {
    super.initState();

    _activePulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _activePulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _activePulseController, curve: Curves.easeInOut),
    );
    if (widget.isActive) {
      _activePulseController.repeat(reverse: true);
    }

    _tapPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _tapPulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _tapPulseController, curve: Curves.easeOutBack),
    );
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
    _activePulseController.dispose();
    _tapPulseController.dispose();
    super.dispose();
  }

  void _playTapPulse() => _tapPulseController.forward(from: 0.0);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        widget.onPressed();
        _playTapPulse();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: Listenable.merge([
              _activePulseAnimation,
              _tapPulseAnimation,
            ]),
            builder: (context, child) {
              double scale = 1.0;
              if (widget.isActive) scale *= _activePulseAnimation.value;
              if (_tapPulseController.isAnimating) {
                scale *= _tapPulseAnimation.value;
              }
              return Transform.scale(scale: scale, child: child);
            },
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
