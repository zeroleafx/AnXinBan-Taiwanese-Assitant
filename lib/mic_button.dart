import 'package:flutter/material.dart';

import 'app_theme.dart';

enum MicState { ready, recording, busy, off }

/// The big round microphone button. It pulses while recording, shows a
/// progress ring while busy, and is greyed out while it cannot be used.
class MicButton extends StatefulWidget {
  const MicButton({
    super.key,
    required this.size,
    required this.state,
    required this.onPressed,
    this.progress,
  });

  final double size;
  final MicState state;
  final VoidCallback? onPressed;

  /// How far the busy work has got, 0..1. Null spins without an end.
  final double? progress;

  @override
  State<MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<MicButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void initState() {
    super.initState();
    _syncPulse();
  }

  @override
  void didUpdateWidget(MicButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPulse();
  }

  void _syncPulse() {
    if (widget.state == MicState.recording) {
      if (!_pulse.isAnimating) _pulse.repeat();
    } else {
      _pulse
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final halo = size * 1.22;
    final recording = widget.state == MicState.recording;
    final busy = widget.state == MicState.busy;
    final muted = busy || widget.state == MicState.off;
    final accent = recording ? AppColors.coral : AppColors.freshGreen;
    final colors = recording
        ? const [AppColors.coralLight, AppColors.coral]
        : muted
        ? const [Color(0xFFA8CC94), Color(0xFF7BAA64)]
        : const [AppColors.leaf, AppColors.green];
    const duration = Duration(milliseconds: 300);

    return Semantics(
      button: true,
      enabled: widget.onPressed != null,
      label: recording ? '停止錄音' : '開始錄音',
      onTap: widget.onPressed,
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: halo,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              if (recording)
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, _) => Stack(
                    alignment: Alignment.center,
                    clipBehavior: Clip.none,
                    children: [
                      for (final offset in const [0.0, 0.5])
                        _ring(halo, (_pulse.value + offset) % 1, accent),
                    ],
                  ),
                ),
              AnimatedContainer(
                duration: duration,
                width: halo,
                height: halo,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.5),
                  border: Border.all(
                    color: accent.withValues(alpha: 0.6),
                    width: 1.5,
                  ),
                ),
              ),
              if (busy)
                SizedBox.square(
                  dimension: halo - 8,
                  child: CircularProgressIndicator(
                    value: widget.progress,
                    strokeWidth: 4,
                    strokeCap: StrokeCap.round,
                    color: AppColors.green,
                    backgroundColor: widget.progress == null
                        ? null
                        : AppColors.freshGreen.withValues(alpha: 0.25),
                  ),
                ),
              AnimatedContainer(
                duration: duration,
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: colors,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: colors.last.withValues(alpha: muted ? 0.15 : 0.4),
                      blurRadius: size * 0.2,
                      offset: Offset(0, size * 0.07),
                    ),
                  ],
                ),
                child: Material(
                  type: MaterialType.transparency,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: widget.onPressed,
                    child: Center(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          switch (widget.state) {
                            MicState.recording => Icons.stop_rounded,
                            MicState.busy => Icons.graphic_eq_rounded,
                            MicState.off => Icons.mic_off_rounded,
                            MicState.ready => Icons.mic_rounded,
                          },
                          key: ValueKey(widget.state),
                          size: size * 0.42,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ring(double base, double t, Color color) {
    final diameter = base * (1 + 0.32 * t);
    return IgnorePointer(
      child: Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: color.withValues(alpha: (1 - t) * 0.5),
            width: 3,
          ),
        ),
      ),
    );
  }
}
