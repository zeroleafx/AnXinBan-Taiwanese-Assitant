import 'dart:io';

import 'package:crypto/crypto.dart';

const _bytes = 1080732108;
const _hash =
    '60f25e3a21feca12ec082e6d36f08f94455d9900d6343f7fcb2906f71cc7c449';
final _url = Uri.parse(
  'https://huggingface.co/doggy8088/Breeze-ASR-26-GGML/resolve/main/ggml-model-q5_0.bin',
);

Future<bool> modelExists(String path) async {
  final file = File(path);
  return await file.exists() && await file.length() == _bytes;
}

Future<void> downloadModel(String path, void Function(int) progress) async {
  if (await modelExists(path)) return;
  final part = File('$path.part');
  var done = await part.exists() ? await part.length() : 0;
  if (done > _bytes) {
    await part.delete();
    done = 0;
  }
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  try {
    if (done < _bytes) {
      final request = await client.getUrl(_url);
      if (done > 0) request.headers.set('Range', 'bytes=$done-');
      final response = await request.close().timeout(
        const Duration(seconds: 60),
      );
      if (response.statusCode == 200) {
        done = 0;
      } else if (response.statusCode != 206 ||
          !(response.headers.value('content-range') ?? '').startsWith(
            'bytes $done-',
          )) {
        throw HttpException('下載中斷');
      }
      final sink = part.openWrite(
        mode: done == 0 ? FileMode.write : FileMode.append,
      );
      var lastPercent = -1;
      try {
        await sink.addStream(
          response.timeout(const Duration(seconds: 60)).map((chunk) {
            done += chunk.length;
            final percent = (done * 100 ~/ _bytes).clamp(0, 99);
            if (lastPercent != percent) {
              progress(percent);
              lastPercent = percent;
            }
            return chunk;
          }),
        );
      } finally {
        await sink.close();
      }
    }
    if (done < _bytes) throw HttpException('下載中斷');
    progress(99);
    if (done != _bytes ||
        (await sha256.bind(part.openRead()).first).toString() != _hash) {
      await part.delete();
      throw const FormatException('模型驗證失敗');
    }
    await part.rename(path);
    progress(100);
  } finally {
    client.close(force: true);
  }
}
