const modelBytes = 1080732108;
Future<int> partialModelBytes(String path) async => 0;
Future<bool> modelExists(String path) async => false;
Future<void> downloadModel(String path, void Function(int) progress) =>
    throw UnsupportedError('此平台未提供本機語音模型');
