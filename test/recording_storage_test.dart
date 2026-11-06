import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:an_xin_ban/recording_storage_native.dart';

void main() {
  late Directory directory;
  late RecordingStorage storage;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('anxinban_storage_test_');
    storage = RecordingStorage(directory: directory);
  });
  tearDown(() => directory.delete(recursive: true));

  Future<File> create(String name) =>
      File('${directory.path}/$name').writeAsString('audio');

  test(
    'startup keeps newest app recording and leaves unrelated files alone',
    () async {
      final first = await create('anxinban_100.m4a');
      final second = await create('anxinban_200.m4a');
      final unrelated = await create('personal.m4a');
      expect(await storage.retainLatest(), second.path);
      expect(await first.exists(), false);
      expect(await second.exists(), true);
      expect(await unrelated.exists(), true);
    },
  );

  test(
    'saving the next recording deletes all previous app recordings',
    () async {
      final first = await create('anxinban_100.m4a');
      final second = await create('anxinban_200.m4a');
      await storage.retainLatest(keepPath: second.path);
      expect(await first.exists(), false);
      expect(await second.exists(), true);
    },
  );

  test('empty storage has no recording to restore', () async {
    expect(await storage.retainLatest(), isNull);
  });
}
