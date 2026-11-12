import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'recording_storage.dart';

abstract class RecordingBackend {
  Future<String?> retainLatest({String? keepPath});
  Stream<double> get decibels;
  Future<bool> hasPermission();
  Future<void> start();
  Future<String?> stop();
  Future<void> cancel();
  Future<void> play(String path);
  Future<void> stopPlayback();
  Stream<void> get playbackCompleted;
  Stream<RecordState> get states;
  Future<void> dispose();
}

class DeviceRecordingBackend implements RecordingBackend {
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();
  final _storage = RecordingStorage();

  @override
  Future<String?> retainLatest({String? keepPath}) =>
      _storage.retainLatest(keepPath: keepPath);

  @override
  Stream<double> get decibels => _recorder
      .onAmplitudeChanged(const Duration(milliseconds: 100))
      .map((amplitude) => amplitude.current);

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<void> start() async {
    final name = 'anxinban_${DateTime.now().microsecondsSinceEpoch}.m4a';
    final path = kIsWeb
        ? name
        : '${(await getApplicationDocumentsDirectory()).path}/$name';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, numChannels: 1),
      path: path,
    );
  }

  @override
  Future<String?> stop() => _recorder.stop();
  @override
  Future<void> cancel() => _recorder.cancel();
  @override
  Future<void> play(String path) =>
      _player.play(kIsWeb ? UrlSource(path) : DeviceFileSource(path));
  @override
  Future<void> stopPlayback() => _player.stop();
  @override
  Stream<void> get playbackCompleted => _player.onPlayerComplete;
  @override
  Stream<RecordState> get states => _recorder.onStateChanged();
  @override
  Future<void> dispose() async {
    await _recorder.dispose();
    await _player.dispose();
  }
}

class RecordingController extends ChangeNotifier {
  RecordingController(
    this.backend, {
    this.transcribe,
    this.autoTranscribe = true,
  }) {
    _playbackSubscription = backend.playbackCompleted.listen((_) {
      isPlaying = false;
      _notify();
    });
    _stateSubscription = backend.states.listen((state) {
      // End and save a session interrupted by a call or audio-route change.
      if (state != RecordState.record && isRecording && !busy) {
        unawaited(stop());
      }
    });
  }

  final RecordingBackend backend;
  final bool autoTranscribe;
  Future<String> Function(String path)? transcribe;

  /// Called with each non-empty transcript, e.g. to run it as a command.
  Future<void> Function(String transcript)? onTranscript;
  String? transcript;
  String? speechError;
  bool recognizing = false;

  Future<void> _recognize(String path) async {
    final run = transcribe;
    if (run == null || _disposed) return;
    recognizing = true;
    speechError = null;
    _notify();
    String? heard;
    try {
      final text = (await run(path)).trim();
      heard = text.isEmpty ? null : text;
      transcript = heard;
      if (heard == null) speechError = '沒有聽到聲音，請再講一次。';
    } catch (_) {
      speechError = '這段沒有聽清楚，可以再試一次。';
    } finally {
      recognizing = false;
      _notify();
    }
    if (heard != null && !_disposed) unawaited(onTranscript?.call(heard));
  }

  Future<void> recognizeLatest() async {
    final path = lastPath;
    if (busy || isPlaying || isRecording || path == null || _disposed) return;
    busy = true;
    try {
      await _recognize(path);
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> initialize() async {
    busy = true;
    _notify();
    try {
      lastPath = await backend.retainLatest();
    } catch (_) {
      error = '無法清理舊錄音，請重新開啟 App 再試一次。';
    } finally {
      busy = false;
      _notify();
    }
  }

  bool isRecording = false;
  bool isPlaying = false;
  bool busy = false;

  /// True after the microphone permission was refused.
  bool micDenied = false;
  String? lastPath;
  String? error;
  Duration elapsed = Duration.zero;
  bool _disposed = false;
  bool _foreground = true;
  final _watch = Stopwatch();
  Timer? _timer;
  Timer? _limitTimer;
  static const maxDuration = Duration(minutes: 1);
  late final StreamSubscription<void> _playbackSubscription;
  late final StreamSubscription<RecordState> _stateSubscription;

  String get durationLabel {
    final seconds = elapsed.inSeconds;
    return '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> toggle() async {
    if (busy || _disposed) return;
    if (isRecording) {
      await stop();
      return;
    }
    busy = true;
    error = null;
    micDenied = false;
    _notify();
    try {
      await backend.stopPlayback();
      isPlaying = false;
      if (!await backend.hasPermission()) {
        micDenied = true;
        error = '需要麥克風權限，請到設定打開。';
        return;
      }
      if (_disposed || !_foreground) return;
      await backend.start();
      if (_disposed || !_foreground) {
        await backend.stop();
        return;
      }
      isRecording = true;
      elapsed = Duration.zero;
      _watch
        ..reset()
        ..start();
      _limitTimer = Timer(maxDuration, () => unawaited(stop()));
      _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        elapsed = _watch.elapsed;
        _notify();
      });
    } catch (_) {
      await _cancelSafely();
      error = '無法開始錄音，請確認麥克風未被其他 App 使用，再試一次。';
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> stop() async {
    if (busy || !isRecording || _disposed) return;
    busy = true;
    _notify();
    _limitTimer?.cancel();
    try {
      final path = await backend.stop();
      if (path == null || path.isEmpty) {
        error = '錄音未能儲存，請重新錄音。';
      } else {
        _watch.stop();
        _timer?.cancel();
        elapsed = _watch.elapsed;
        isRecording = false;
        lastPath = path;
        transcript = null;
        speechError = null;
        error = null;
        try {
          await backend.retainLatest(keepPath: path);
        } catch (_) {
          error = '新錄音已儲存，但舊錄音未能刪除，請重新開啟 App 再試一次。';
        }
        if (_foreground && autoTranscribe) await _recognize(path);
      }
    } catch (_) {
      await _cancelSafely();
      error = '錄音未能儲存，請重新錄音。';
    } finally {
      _watch.stop();
      elapsed = _watch.elapsed;
      _timer?.cancel();
      isRecording = false;
      busy = false;
      _notify();
    }
  }

  /// Stops recording and throws the recording away, without recognizing it.
  Future<void> cancel() async {
    if (busy || !isRecording || _disposed) return;
    busy = true;
    _notify();
    _limitTimer?.cancel();
    await _cancelSafely();
    _watch.stop();
    _timer?.cancel();
    isRecording = false;
    busy = false;
    _notify();
  }

  Future<void> togglePlayback() async {
    if (busy || isRecording || lastPath == null || _disposed) return;
    busy = true;
    error = null;
    _notify();
    try {
      if (isPlaying) {
        await backend.stopPlayback();
        isPlaying = false;
      } else {
        await backend.play(lastPath!);
        isPlaying = true;
      }
    } catch (_) {
      isPlaying = false;
      error = '無法播放這段錄音，請再試一次。';
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> _cancelSafely() async {
    try {
      await backend.cancel();
    } catch (_) {
      // Preserve the original recording error if native cleanup also fails.
    }
  }

  Future<void> setForeground(bool foreground) async {
    _foreground = foreground;
    if (!foreground) {
      await stop();
      try {
        await backend.stopPlayback();
      } catch (_) {
        error = '無法停止播放，請關閉 App 後重試。';
      }
      isPlaying = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _limitTimer?.cancel();
    _timer?.cancel();
    _watch.stop();
    unawaited(_playbackSubscription.cancel());
    unawaited(_stateSubscription.cancel());
    unawaited(backend.dispose());
    super.dispose();
  }
}
