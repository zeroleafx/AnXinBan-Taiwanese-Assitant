import 'package:an_xin_ban/torch_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('anxinban/torch-test');
  const torch = TorchChannel(channel);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('switches the light and reads it back', () async {
    final calls = <MethodCall>[];
    var light = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'set') light = call.arguments as bool;
      return call.method == 'set' ? true : light;
    });

    expect(await torch.set(on: true), true);
    expect(await torch.isOn(), true);
    expect(await torch.set(on: false), true);
    expect(await torch.isOn(), false);
    expect(calls.map((c) => '${c.method} ${c.arguments}'), [
      'set true',
      'isOn null',
      'set false',
      'isOn null',
    ]);
  });

  test('a phone that cannot switch or tell says so', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'set' ? false : null,
    );
    expect(await torch.set(on: true), false);
    expect(await torch.isOn(), isNull);
  });

  test('errors and a missing native side are not thrown at the app', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => throw PlatformException(code: 'torch'),
    );
    expect(await torch.set(on: true), false);
    expect(await torch.isOn(), isNull);

    messenger.setMockMethodCallHandler(channel, null);
    expect(await torch.set(on: false), false);
    expect(await torch.isOn(), isNull);
  });
}
