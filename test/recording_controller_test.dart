import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:an_xin_ban/recording_controller.dart';

class FakeBackend implements RecordingBackend {
  String? retained;
  @override
  Future<String?> retainLatest({String? keepPath}) async {
    retained = keepPath;
    return retained;
  }

  @override
  Stream<double> get decibels => const Stream.empty();

  bool permission = true;
  bool failStart = false;
  bool failStop = false;
  int starts = 0;
  int stops = 0;
  int cancellations = 0;
  String? played;
  Completer<bool>? permissionGate;
  final completed = StreamController<void>.broadcast();
  final events = StreamController<RecordState>.broadcast();
  @override
  Stream<void> get playbackCompleted => completed.stream;
  @override
  Stream<RecordState> get states => events.stream;
  @override
  Future<bool> hasPermission() async =>
      permissionGate == null ? permission : await permissionGate!.future;
  @override
  Future<void> start() async {
    starts++;
    if (failStart) throw StateError('Unavailable');
  }

  @override
  Future<String?> stop() async {
    stops++;
    if (failStop) throw StateError('Cannot save');
    return '/local/recording.m4a';
  }

  @override
  Future<void> cancel() async {
    cancellations++;
  }

  @override
  Future<void> play(String path) async {
    played = path;
  }

  @override
  Future<void> stopPlayback() async {}
  @override
  Future<void> dispose() async {
    await completed.close();
    await events.close();
  }
}

void main() {
  late FakeBackend backend;
  late RecordingController controller;
  setUp(() {
    backend = FakeBackend();
    controller = RecordingController(backend);
  });
  tearDown(() => controller.dispose());

  testWidgets('60 seconds stops and saves once', (tester) async {
    await controller.toggle();
    await tester.pump(const Duration(seconds: 59));
    expect(backend.stops, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(backend.stops, 1);
    expect(controller.lastPath, backend.retained);
    expect(controller.isRecording, false);
  });
  test('denied permission never starts the microphone', () async {
    backend.permission = false;
    await controller.toggle();
    expect(backend.starts, 0);
    expect(controller.isRecording, false);
    expect(controller.busy, false);
    expect(controller.error, contains('麥克風'));
  });
  test('record, save, and replay uses the saved path', () async {
    await controller.toggle();
    expect(controller.isRecording, true);
    await controller.toggle();
    expect(controller.isRecording, false);
    expect(controller.lastPath, '/local/recording.m4a');
    expect(backend.retained, controller.lastPath);
    await controller.togglePlayback();
    expect(backend.played, controller.lastPath);
    expect(controller.isPlaying, true);
    backend.completed.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(controller.isPlaying, false);
  });
  test('rapid taps do not start overlapping recording sessions', () async {
    backend.permissionGate = Completer<bool>();
    final first = controller.toggle();
    await controller.toggle();
    backend.permissionGate!.complete(true);
    await first;
    expect(backend.starts, 1);
    await controller.stop();
  });
  test('backgrounding stops and saves recording', () async {
    await controller.toggle();
    await controller.setForeground(false);
    expect(backend.stops, 1);
    expect(controller.isRecording, false);
    expect(controller.lastPath, isNotNull);
  });
  test('backgrounding during permission does not start recording', () async {
    backend.permissionGate = Completer<bool>();
    final first = controller.toggle();
    await controller.setForeground(false);
    backend.permissionGate!.complete(true);
    await first;
    expect(backend.starts, 0);
  });
  test('start failure allows retry', () async {
    backend.failStart = true;
    await controller.toggle();
    expect(controller.error, isNotNull);
    expect(controller.isRecording, false);
    expect(controller.busy, false);
    backend.failStart = false;
    await controller.toggle();
    expect(controller.isRecording, true);
    await controller.stop();
  });
  test('cancelling throws the recording away without recognizing it', () async {
    final heard = <String>[];
    final recognizing = RecordingController(
      backend,
      transcribe: (path) async => 'text',
    )..onTranscript = (text) async => heard.add(text);
    addTearDown(recognizing.dispose);
    await recognizing.toggle();
    await recognizing.cancel();
    expect(backend.cancellations, 1);
    expect(backend.stops, 0);
    expect(recognizing.isRecording, false);
    expect(recognizing.busy, false);
    expect(recognizing.lastPath, isNull);
    expect(heard, isEmpty);

    await recognizing.cancel();
    expect(backend.cancellations, 1, reason: 'nothing left to cancel');
  });

  test('save failure does not claim a saved recording', () async {
    await controller.toggle();
    backend.failStop = true;
    await controller.stop();
    expect(controller.error, contains('未能儲存'));
    expect(controller.lastPath, isNull);
    expect(backend.cancellations, 1);
    expect(controller.busy, false);
  });
}
