import 'package:flutter/material.dart';

/// A small filled circle used to indicate device sync status.
/// Pass [pulse] to animate the dot for in-progress states.
///
/// Static (non-pulsing) dots — the common case, one per on-device song/album —
/// are a plain [Container] with no [AnimationController]. Only a pulsing dot
/// allocates a ticker, so a fully-synced library list doesn't spin up hundreds
/// of idle controllers.
class SyncDot extends StatelessWidget {
  const SyncDot({
    super.key,
    required this.color,
    this.size = 7.0,
    this.pulse = false,
  });

  final Color color;
  final double size;
  final bool pulse;

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
    return pulse ? _PulsingDot(child: dot) : dot;
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.child});
  final Widget child;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: 0.35, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: _opacity, child: widget.child);
}
