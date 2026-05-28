import 'package:flutter/material.dart';

/// A small filled circle used to indicate device sync status.
/// Pass [pulse] to animate the dot for in-progress states.
class SyncDot extends StatefulWidget {
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
  State<SyncDot> createState() => _SyncDotState();
}

class _SyncDotState extends State<SyncDot> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _opacity = Tween<double>(begin: 0.35, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    if (widget.pulse) _ctrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(SyncDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulse == oldWidget.pulse) return;
    if (widget.pulse) {
      _ctrl.repeat(reverse: true);
    } else {
      _ctrl.stop();
      _ctrl.value = 1.0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color),
    );
    if (!widget.pulse) return dot;
    return FadeTransition(opacity: _opacity, child: dot);
  }
}
