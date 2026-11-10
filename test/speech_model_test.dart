import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:an_xin_ban/speech_model.dart';

const _size = 1080732108;

class FakeModel implements SpeechModelBackend {
  ModelStatus? current = const ModelStatus(ready: false, totalBytes: _size);
  bool statusFails = false;
  Object? downloadError;
  int downloads = 0;

  /// Holds the download open after its progress was reported.
  Completer<void>? gate;

  @override
  Future<ModelStatus?> status() async {
    if (statusFails) throw PlatformException(code: 'status');
    return current;
  }

  @override
  Future<void> download(void Function(int percent) onPercent) async {
    downloads++;
    for (final percent in const [12, 60, 100]) {
      onPercent(percent);
    }
    await gate?.future;
    final error = downloadError;
    if (error != null) throw error;
    current = const ModelStatus(ready: true, totalBytes: _size);
  }
}

void main() {
  late FakeModel backend;
  late SpeechModelController model;
  setUp(() {
    backend = FakeModel();
    model = SpeechModelController(backend);
  });
  tearDown(() => model.dispose());

  test('platforms that ship the model are ready at once', () async {
    final bundled = SpeechModelController(null);
    addTearDown(bundled.dispose);
    expect(bundled.phase, ModelPhase.ready);
    await bundled.refresh();
    await bundled.download();
    expect(bundled.phase, ModelPhase.ready);
    expect(bundled.blocksSpeech, false);
  });

  test('a missing model blocks speech until it is downloaded', () async {
    expect(model.blocksSpeech, false, reason: 'not known yet');
    await model.refresh();
    expect(model.phase, ModelPhase.missing);
    expect(model.blocksSpeech, true);
    expect(model.status!.sizeLabel, '1.1 GB');
  });

  test('an installed model, or a build that cannot say, is ready', () async {
    backend.current = const ModelStatus(ready: true, totalBytes: _size);
    await model.refresh();
    expect(model.phase, ModelPhase.ready);

    backend.current = null;
    await model.refresh();
    expect(model.phase, ModelPhase.ready);
  });

  test('a failed check never locks the app', () async {
    backend.statusFails = true;
    await model.refresh();
    expect(model.phase, ModelPhase.ready);
  });

  test('downloading reports progress, then verification, then ready', () async {
    await model.refresh();
    backend.gate = Completer<void>();
    final seen = <int>[];
    model.addListener(() => seen.add(model.percent));

    final download = model.download();
    await Future<void>.delayed(Duration.zero);
    expect(model.phase, ModelPhase.downloading);
    expect(model.blocksSpeech, true);
    expect(seen, containsAllInOrder([12, 60, 100]));
    expect(model.verifying, true);

    await model.download();
    await model.refresh();
    expect(backend.downloads, 1, reason: 'no second download while running');
    expect(model.phase, ModelPhase.downloading);

    backend.gate!.complete();
    await download;
    expect(model.phase, ModelPhase.ready);
    expect(model.blocksSpeech, false);
  });

  test('a failed download shows why and can be continued', () async {
    await model.refresh();
    backend.downloadError = PlatformException(
      code: 'download',
      message: '下載中斷了，再試一次會接著下載。',
    );
    backend.current = const ModelStatus(
      ready: false,
      totalBytes: _size,
      downloadedBytes: _size ~/ 2,
    );

    await model.download();
    expect(model.phase, ModelPhase.failed);
    expect(model.error, contains('中斷'));
    expect(model.status!.percent, 50);

    await model.refresh();
    expect(model.phase, ModelPhase.failed, reason: 'keeps the explanation');

    backend.downloadError = null;
    await model.download();
    expect(model.phase, ModelPhase.ready);
    expect(model.error, isNull);
    expect(backend.downloads, 2);
  });

  test('continuing starts the bar where the last download stopped', () async {
    backend.current = const ModelStatus(
      ready: false,
      totalBytes: _size,
      downloadedBytes: _size,
    );
    await model.refresh();
    backend.gate = Completer<void>();
    final percents = <int>[];
    model.addListener(() => percents.add(model.percent));
    final download = model.download();
    expect(percents.first, 99, reason: '100 is reserved for verifying');
    backend.gate!.complete();
    await download;
  });
}
