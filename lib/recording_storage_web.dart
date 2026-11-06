import 'dart:js_interop';

@JS('URL.revokeObjectURL')
external void _revokeObjectURL(JSString url);

class RecordingStorage {
  String? _lastPath;

  Future<String?> retainLatest({String? keepPath}) async {
    if (keepPath != null && _lastPath != keepPath) {
      if (_lastPath != null) _revokeObjectURL(_lastPath!.toJS);
      _lastPath = keepPath;
    }
    return _lastPath;
  }
}
