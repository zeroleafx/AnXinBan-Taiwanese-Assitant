import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The connection a model download would use.
enum ModelNetwork { none, metered, unmetered }

class ModelStatus {
  const ModelStatus({
    required this.ready,
    this.totalBytes = 0,
    this.downloadedBytes = 0,
    this.network = ModelNetwork.unmetered,
  });

  final bool ready;
  final int totalBytes;
  final int downloadedBytes;
  final ModelNetwork network;

  /// How much is already on the device, 0..100.
  int get percent =>
      totalBytes <= 0 ? 0 : (downloadedBytes * 100 ~/ totalBytes).clamp(0, 100);

  /// For example "1.1 GB".
  String get sizeLabel => '${(totalBytes / 1e9).toStringAsFixed(1)} GB';
}

/// Where the on-device speech model comes from on this platform.
abstract interface class SpeechModelBackend {
  /// Null when the model needs no separate download.
  Future<ModelStatus?> status();

  /// Completes once the model is installed. [onPercent] gets 0..100, where
  /// 100 means the finished file is being verified.
  Future<void> download(void Function(int percent) onPercent);
}

enum ModelPhase { checking, ready, missing, downloading, failed }

/// Asks before the large speech model is downloaded and tracks the download.
class SpeechModelController extends ChangeNotifier {
  SpeechModelController(this.backend)
    : phase = backend == null ? ModelPhase.ready : ModelPhase.checking;

  /// Null on platforms that ship the model inside the app.
  final SpeechModelBackend? backend;
  ModelPhase phase;
  ModelStatus? status;
  int percent = 0;
  String? error;
  bool _disposed = false;

  /// True while it is known that speech cannot be recognized yet.
  bool get blocksSpeech =>
      phase == ModelPhase.missing ||
      phase == ModelPhase.downloading ||
      phase == ModelPhase.failed;

  bool get verifying => phase == ModelPhase.downloading && percent >= 100;

  /// Re-reads whether the model is installed and which network is in use.
  Future<void> refresh() async {
    final backend = this.backend;
    if (backend == null || phase == ModelPhase.downloading) return;
    try {
      final latest = await backend.status();
      if (_disposed || phase == ModelPhase.downloading) return;
      status = latest;
      if (latest == null || latest.ready) {
        phase = ModelPhase.ready;
      } else if (phase != ModelPhase.failed) {
        phase = ModelPhase.missing;
      }
    } catch (_) {
      // Never lock the app over a failed check; recognition reports real errors.
      phase = ModelPhase.ready;
    }
    _notify();
  }

  Future<void> download() async {
    final backend = this.backend;
    if (backend == null ||
        phase == ModelPhase.downloading ||
        phase == ModelPhase.ready) {
      return;
    }
    phase = ModelPhase.downloading;
    percent = (status?.percent ?? 0).clamp(0, 99);
    error = null;
    _notify();
    try {
      await backend.download((value) {
        percent = value;
        _notify();
      });
      phase = ModelPhase.ready;
    } on PlatformException catch (e) {
      error = e.message;
      phase = ModelPhase.failed;
    } catch (_) {
      phase = ModelPhase.failed;
    }
    if (phase == ModelPhase.failed) {
      // How much is on the device now decides between "start" and "continue".
      try {
        status = await backend.status() ?? status;
      } catch (_) {}
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
