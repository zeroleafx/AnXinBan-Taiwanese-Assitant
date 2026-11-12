import 'package:flutter/material.dart';

import 'dart:async';

import 'app_theme.dart';
import 'recording_controller.dart';

enum MicState { ready, recording, busy }

/// The big round microphone button. It pulses while recording and shows a
/// progress ring while the recording is being understood.
class MicButton extends StatelessWidget {
  const MicButton({
    super.key,
    required this.backend,
    required this.size,
    required this.state,
    required this.onPressed,
  });

  final RecordingBackend backend;
  final double size;
  final MicState state;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final halo = size * 1.22;
    final recording = state == MicState.recording;
    final busy = state == MicState.busy;
    final accent = AppColors.freshGreen;
    final colors = recording
        ? const [AppColors.coralLight, AppColors.coral]
        : busy
        ? const [Color(0xFFA8CC94), Color(0xFF7BAA64)]
        : const [AppColors.leaf, AppColors.green];
    const duration = Duration(milliseconds: 300);

    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: recording ? '停止錄音' : '開始錄音',
      onTap: onPressed,
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: halo,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
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
              if (recording) _MicLevelRing(backend: backend, size: size),
              if (busy)
                SizedBox.square(
                  dimension: halo - 8,
                  child: const CircularProgressIndicator(
                    strokeWidth: 4,
                    strokeCap: StrokeCap.round,
                    color: AppColors.green,
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
                      color: colors.last.withValues(alpha: busy ? 0.15 : 0.4),
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
                    onTap: onPressed,
                    child: Center(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          recording
                              ? Icons.stop_rounded
                              : busy
                              ? Icons.graphic_eq_rounded
                              : Icons.mic_rounded,
                          key: ValueKey(state),
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
}

class _MicLevelRing extends StatefulWidget {
  const _MicLevelRing({required this.backend, required this.size});
  final RecordingBackend backend;
  final double size;

  @override
  State<_MicLevelRing> createState() => _MicLevelRingState();
}

class _MicLevelRingState extends State<_MicLevelRing> {
  double level = 0;
  late final StreamSubscription<double> subscription;

  @override
  void initState() {
    super.initState();
    subscription = widget.backend.decibels.listen(
      (db) {
        if (!mounted) return;
        setState(() {
          level = db.isFinite ? ((db + 55) / 50).clamp(0.0, 1.0) : 0;
        });
      },
      onError: (Object _) {
        // Metering is optional; recording continues if the device cannot report it.
      },
    );
  }

  @override
  void dispose() {
    unawaited(subscription.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final diameter = widget.size * (1.04 + 0.15 * level);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOut,
      width: diameter,
      height: diameter,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.freshGreen,
      ),
    );
  }
}
