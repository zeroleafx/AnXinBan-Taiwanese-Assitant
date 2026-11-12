import 'dart:convert';

import 'package:http/http.dart' as http;

const spaceUrl = String.fromEnvironment('BREEZE_SPACE_URL');

Future<String> uploadForTranscription(String blobUrl) async {
  final audio = await http.get(Uri.parse(blobUrl));
  if (audio.statusCode != 200) throw StateError('無法讀取錄音');
  final response = await http
      .post(
        Uri.parse(spaceUrl).resolve('/transcribe'),
        headers: {'Content-Type': 'application/octet-stream'},
        body: audio.bodyBytes,
      )
      .timeout(const Duration(minutes: 10));
  if (response.statusCode != 200) throw StateError('雲端辨識暫時無法使用');
  return (jsonDecode(utf8.decode(response.bodyBytes)) as Map)['text'] as String;
}
