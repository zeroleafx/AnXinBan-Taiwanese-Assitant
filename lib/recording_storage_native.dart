import 'dart:io';

import 'package:path_provider/path_provider.dart';

class RecordingStorage {
  RecordingStorage({this.directory});
  final Directory? directory;

  Future<String?> retainLatest({String? keepPath}) async {
    final root = directory ?? await getApplicationDocumentsDirectory();
    final files = await root
        .list()
        .where((entry) {
          final name = entry.uri.pathSegments.last;
          return entry is File && RegExp(r'^anxinban_\d+\.m4a$').hasMatch(name);
        })
        .cast<File>()
        .toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    final keep = keepPath ?? (files.isEmpty ? null : files.first.path);
    for (final file in files) {
      if (file.path != keep) await file.delete();
    }
    return keep;
  }
}
