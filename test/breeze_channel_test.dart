import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:an_xin_ban/breeze_channel.dart';
import 'package:an_xin_ban/speech_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('anxinban/breeze');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late BreezeChannel breeze;
  final calls = <String>[];

  void native(Future<Object?> Function(MethodCall call)? handler) {
    messenger.setMockMethodCallHandler(
      channel,
      handler == null
          ? null
          : (call) {
              calls.add(call.method);
              return handler(call);
            },
    );
  }

  /// A call from Android to Dart.
  Future<void> fromNative(String method, Object? arguments) =>
      messenger.handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(MethodCall(method, arguments)),
        (_) {},
      );

  setUp(() {
    calls.clear();
    breeze = BreezeChannel();
  });
  tearDown(() {
    breeze.dispose();
    native(null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('reads the Android model status', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    native(
      (call) async => {
        'ready': false,
        'totalBytes': 1080732108,
        'downloadedBytes': 540366054,
        'network': 'metered',
      },
    );
    final status = (await breeze.status())!;
    expect(status.ready, false);
    expect(status.percent, 50);
    expect(status.network, ModelNetwork.metered);
    expect(calls, ['modelStatus']);
    debugDefaultTargetPlatformOverride = null;
  });

  test('iOS checks its local model file', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    native((call) async => '/missing-test-directory/model.bin');
    expect((await breeze.status())!.ready, false);
    expect(calls, ['modelPath']);
    debugDefaultTargetPlatformOverride = null;
  });

  test('an Android build without modelStatus is treated as ready', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    native(null);
    expect(await breeze.status(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  test('download forwards native progress until it finishes', () async {
    native((call) async {
      await fromNative('downloadProgress', 40);
      await fromNative('downloadProgress', 100);
      await fromNative('downloadProgress', null);
      return null;
    });
    final percents = <int>[];
    await breeze.download(percents.add);
    expect(percents, [40, 100]);
    expect(breeze.downloadPercent.value, isNull);

    await fromNative('downloadProgress', 7);
    expect(percents, [40, 100], reason: 'stops listening afterwards');
  });

  test('a failed download surfaces the native message', () async {
    native(
      (call) async =>
          throw PlatformException(code: 'download', message: '連不上網路'),
    );
    await expectLater(
      breeze.download((_) {}),
      throwsA(
        isA<PlatformException>().having((e) => e.message, 'message', '連不上網路'),
      ),
    );
  });

  test('transcribe returns the recognized text', () async {
    native((call) async => call.arguments == '/a.m4a' ? '幫我開LINE' : null);
    expect(await breeze.transcribe('/a.m4a'), '幫我開LINE');
  });
}
