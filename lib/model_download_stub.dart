Future<bool> modelExists(String path) async => false;
Future<void> downloadModel(String path, void Function(int) progress) =>
    throw UnsupportedError('此平台未提供本機語音模型');
