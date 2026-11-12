import 'dart:io';

import 'package:an_xin_ban/model_download.dart';
import 'package:an_xin_ban/speech_model.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

class DownloadBackend implements SpeechModelBackend {
  DownloadBackend(this.path, this.source, this.bytes, this.hash);
  final String path;
  final Uri source;
  final int bytes;
  final String hash;

  @override
  Future<ModelStatus> status() async => ModelStatus(
    ready: await File(path).exists(),
    totalBytes: bytes,
    downloadedBytes: await partialModelBytes(path),
  );

  @override
  Future<void> download(void Function(int) progress) => downloadModel(
    path,
    progress,
    source: source,
    expectedBytes: bytes,
    expectedSha256: hash,
  );
}

void main() {
  final content = List<int>.generate(4096, (i) => i % 251);
  final hash = sha256.convert(content).toString();
  late Directory directory;
  late String path;
  late HttpServer server;
  late Uri source;
  late void Function(HttpRequest) respond;
  final ranges = <String?>[];

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('breeze-download-test');
    path = '${directory.path}/model.bin';
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    source = Uri.parse('http://127.0.0.1:${server.port}/model');
    ranges.clear();
    server.listen((request) {
      ranges.add(request.headers.value('range'));
      respond(request);
    });
  });

  tearDown(() async {
    await server.close(force: true);
    await directory.delete(recursive: true);
  });

  test('interrupted transfer resumes, verifies, then enables speech', () async {
    var attempt = 0;
    respond = (request) {
      attempt++;
      if (attempt == 1) {
        request.response.add(content.sublist(0, 2048));
      } else {
        request.response.statusCode = 206;
        request.response.headers.set('Content-Range', 'bytes 2048-4095/4096');
        request.response.add(content.sublist(2048));
      }
      request.response.close();
    };
    final model = SpeechModelController(
      DownloadBackend(path, source, content.length, hash),
    );
    addTearDown(model.dispose);
    await model.refresh();
    expect(
      ranges,
      isEmpty,
      reason: 'checking must not download without consent',
    );
    await model.download();
    expect(model.phase, ModelPhase.failed);
    expect(model.blocksSpeech, true);
    expect(model.status!.percent, 50);
    expect(await File(path).exists(), false);

    bool verifiedWhileBlocked = false;
    model.addListener(() {
      if (model.verifying) verifiedWhileBlocked = model.blocksSpeech;
    });
    await model.download();
    expect(ranges, [null, 'bytes=2048-']);
    expect(verifiedWhileBlocked, true);
    expect(model.phase, ModelPhase.ready);
    expect(await File(path).readAsBytes(), content);
    expect(await File('$path.part').exists(), false);
  });

  test('same-sized corrupt download is rejected and retry succeeds', () async {
    var corrupt = true;
    respond = (request) {
      request.response.add(corrupt ? List.filled(content.length, 0) : content);
      request.response.close();
    };
    final model = SpeechModelController(
      DownloadBackend(path, source, content.length, hash),
    );
    addTearDown(model.dispose);
    await model.refresh();
    await model.download();
    expect(model.phase, ModelPhase.failed);
    expect(model.blocksSpeech, true);
    expect(await File(path).exists(), false);
    expect(await File('$path.part').exists(), false);
    corrupt = false;
    await model.download();
    expect(model.phase, ModelPhase.ready);
    expect(await File(path).readAsBytes(), content);
  });

  test(
    'server ignoring range replaces partial file before verification',
    () async {
      await File('$path.part').writeAsBytes(content.sublist(0, 100));
      respond = (request) {
        request.response.add(content);
        request.response.close();
      };
      await downloadModel(
        path,
        (_) {},
        source: source,
        expectedBytes: content.length,
        expectedSha256: hash,
      );
      expect(ranges, ['bytes=100-']);
      expect(await File(path).readAsBytes(), content);
    },
  );
}
