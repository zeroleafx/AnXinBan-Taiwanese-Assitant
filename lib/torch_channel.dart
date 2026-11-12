import 'package:flutter/services.dart';

/// The flashlight, through the app's own native code. Unlike a plain on/off
/// switch it can also say whether the light is on, which matters when it is
/// switched off from the phone's control centre instead of in the app.
class TorchChannel {
  const TorchChannel([this._channel = const MethodChannel('anxinban/torch')]);

  final MethodChannel _channel;

  /// True when the light was switched as asked.
  Future<bool> set({required bool on}) async {
    try {
      return await _channel.invokeMethod<bool>('set', on) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Whether the light is on right now, or null when the phone cannot say.
  Future<bool?> isOn() async {
    try {
      return await _channel.invokeMethod<bool>('isOn');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
