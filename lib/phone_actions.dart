import 'package:flutter/foundation.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:torch_light/torch_light.dart';
import 'package:url_launcher/url_launcher.dart';

import 'contact_matcher.dart';
import 'voice_command.dart';

class ContactsAccess {
  const ContactsAccess.granted(this.contacts) : granted = true;
  const ContactsAccess.denied() : granted = false, contacts = const [];

  final bool granted;
  final List<ContactEntry> contacts;
}

/// Everything the assistant can do on the phone. Each call returns false
/// when the phone could not do it (for example, the app is not installed).
abstract interface class PhoneActions {
  Future<bool> openApp(PhoneApp app);
  Future<bool> dial(String number);
  Future<ContactsAccess> loadContacts();
  Future<bool> setTorch({required bool on});
  Future<bool> navigate(String place);
  Future<bool> searchVideo(String query);
  Future<bool> searchWeb(String query);
  Future<void> openSettings();
}

class DevicePhoneActions implements PhoneActions {
  static const _app = LaunchMode.externalApplication;
  static const _appOnly = LaunchMode.externalNonBrowserApplication;

  bool get _iOS => defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Future<bool> openApp(PhoneApp app) => _firstThatOpens(switch (app) {
    PhoneApp.line => [('line://', _app), ('https://line.me/R/', _appOnly)],
    PhoneApp.youtube => [
      ('youtube://', _app),
      ('https://www.youtube.com/', _appOnly),
      ('https://www.youtube.com/', _app),
    ],
    PhoneApp.facebook => [
      ('fb://', _app),
      ('https://www.facebook.com/', _appOnly),
      ('https://www.facebook.com/', _app),
    ],
    PhoneApp.maps => [
      if (_iOS) ('comgooglemaps://', _app),
      if (_iOS) ('maps://', _app),
      if (!_iOS) ('geo:0,0', _app),
    ],
    PhoneApp.messages => [('sms:', _app)],
  });

  /// iOS asks before calling; Android opens the dialer with the number filled.
  @override
  Future<bool> dial(String number) {
    final digits = number.replaceAll(RegExp(r'[^0-9+*#]'), '');
    if (digits.isEmpty) return Future.value(false);
    return _open(Uri(scheme: 'tel', path: digits), _app);
  }

  @override
  Future<ContactsAccess> loadContacts() async {
    final status = await FlutterContacts.permissions.request(
      PermissionType.read,
    );
    if (status != PermissionStatus.granted &&
        status != PermissionStatus.limited) {
      return const ContactsAccess.denied();
    }
    final contacts = await FlutterContacts.getAll(
      properties: {ContactProperty.name, ContactProperty.phone},
    );
    return ContactsAccess.granted([
      for (final contact in contacts)
        if (contact.phones.isNotEmpty)
          ContactEntry(
            name: contact.displayName ?? '',
            nickname: contact.name?.nickname,
            numbers: [for (final phone in contact.phones) phone.number],
          ),
    ]);
  }

  @override
  Future<bool> setTorch({required bool on}) async {
    try {
      if (on) {
        await TorchLight.enableTorch();
      } else {
        await TorchLight.disableTorch();
      }
      return true;
    } on Exception {
      return false;
    }
  }

  @override
  Future<bool> navigate(String place) {
    final to = Uri.encodeQueryComponent(place);
    return _firstThatOpens([
      if (_iOS) ('comgooglemaps://?daddr=$to', _app),
      if (_iOS) ('https://maps.apple.com/?daddr=$to', _app),
      ('https://www.google.com/maps/dir/?api=1&destination=$to', _app),
    ]);
  }

  @override
  Future<bool> searchVideo(String query) => _open(
    Uri.https('www.youtube.com', '/results', {'search_query': query}),
    _app,
  );

  @override
  Future<bool> searchWeb(String query) =>
      _open(Uri.https('www.google.com', '/search', {'q': query}), _app);

  @override
  Future<void> openSettings() => FlutterContacts.permissions.openSettings();

  Future<bool> _firstThatOpens(List<(String, LaunchMode)> links) async {
    for (final (link, mode) in links) {
      if (await _open(Uri.parse(link), mode)) return true;
    }
    return false;
  }

  Future<bool> _open(Uri uri, LaunchMode mode) async {
    try {
      return await launchUrl(uri, mode: mode);
    } on Exception {
      return false;
    }
  }
}
