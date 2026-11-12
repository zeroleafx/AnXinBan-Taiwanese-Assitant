import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:geolocator/geolocator.dart' as geolocator;
import 'package:url_launcher/url_launcher.dart';

import 'app_matcher.dart';
import 'contact_matcher.dart';
import 'place.dart';
import 'torch_channel.dart';
import 'voice_command.dart';

class ContactsAccess {
  const ContactsAccess.granted(this.contacts) : granted = true;
  const ContactsAccess.denied() : granted = false, contacts = const [];

  final bool granted;
  final List<ContactEntry> contacts;
}

/// Everything the assistant can do on the phone. Calls that return a bool
/// return false when the phone could not do it (for example, the app is not
/// installed).
abstract interface class PhoneActions {
  Future<bool> openApp(PhoneApp app);

  /// Opens the installed app that [name] most likely means and returns the
  /// name under its icon, or null when there is no such app.
  Future<String?> openNamedApp(String name);
  Future<bool> dial(String number);
  Future<ContactsAccess> loadContacts();

  /// Lets the person pick someone from the contacts. Null when they did not.
  Future<ContactEntry?> pickContact();
  Future<bool> setTorch({required bool on});

  /// Whether the flashlight is on right now, or null when the phone cannot
  /// say. It can be switched outside the app, from the control centre.
  Future<bool?> torchIsOn();
  Future<bool> navigate(String place);
  Future<bool> openMap(Place place);
  Future<bool> searchVideo(String query);
  Future<bool> searchWeb(String query);
  Future<LocationResult> locate();

  /// Opens a text message with [body] filled in, to [number] if there is
  /// one. The person presses send.
  Future<bool> composeSms({String? number, required String body});

  /// Opens LINE's "share with" screen with [text]. The person picks who gets
  /// it and presses send.
  Future<bool> shareOnLine(String text);
  Future<void> openSettings();
  Future<void> openLocationSettings();
}

class DevicePhoneActions implements PhoneActions {
  static const _app = LaunchMode.externalApplication;
  static const _appOnly = LaunchMode.externalNonBrowserApplication;
  static const _apps = MethodChannel('anxinban/apps');
  late final _geocoder = geocoding.Geocoding();

  bool get _iOS => defaultTargetPlatform == TargetPlatform.iOS;
  bool get _android => defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<bool> openApp(PhoneApp app) async {
    // On Android the sure way to open an app is by its package.
    final package = _packages[app];
    if (_android && package != null && await _launchPackage(package)) {
      return true;
    }
    return _firstThatOpens(switch (app) {
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
  }

  @override
  Future<String?> openNamedApp(String name) async {
    if (_android) {
      final app = matchApp(name, await _installedApps());
      if (app == null || !await _launchPackage(app.package)) return null;
      return app.label;
    }
    // iOS cannot list apps, so only apps with a known link can be opened.
    final asked = normalizeTranscript(name);
    for (final (names, label, link) in _iosApps) {
      if (!names.contains(asked)) continue;
      return await _open(Uri.parse(link), _app) ? label : null;
    }
    return null;
  }

  Future<List<InstalledApp>> _installedApps() async {
    try {
      final apps = await _apps.invokeListMethod<Map<Object?, Object?>>('list');
      return [
        for (final app in apps ?? const <Map<Object?, Object?>>[])
          InstalledApp(label: '${app['label']}', package: '${app['package']}'),
      ];
    } on Exception {
      return const [];
    }
  }

  Future<bool> _launchPackage(String package) async {
    try {
      return await _apps.invokeMethod<bool>('launch', package) ?? false;
    } on Exception {
      return false;
    }
  }

  /// iOS asks before calling; Android opens the dialer with the number filled.
  @override
  Future<bool> dial(String number) {
    final digits = _phoneDigits(number);
    if (digits.isEmpty) return Future.value(false);
    return _open(Uri(scheme: 'tel', path: digits), _app);
  }

  @override
  Future<ContactsAccess> loadContacts() async {
    if (!await _mayReadContacts()) return const ContactsAccess.denied();
    final contacts = await FlutterContacts.getAll(
      properties: {ContactProperty.name, ContactProperty.phone},
    );
    return ContactsAccess.granted([
      for (final contact in contacts)
        if (contact.phones.isNotEmpty) _entry(contact),
    ]);
  }

  @override
  Future<ContactEntry?> pickContact() async {
    try {
      // The iOS picker needs no permission; Android's does.
      if (_android && !await _mayReadContacts()) return null;
      final picked = await FlutterContacts.native.showPicker(
        properties: {ContactProperty.name, ContactProperty.phone},
      );
      return picked == null || picked.phones.isEmpty ? null : _entry(picked);
    } on Exception {
      return null;
    }
  }

  Future<bool> _mayReadContacts() async {
    final status = await FlutterContacts.permissions.request(
      PermissionType.read,
    );
    return status == PermissionStatus.granted ||
        status == PermissionStatus.limited;
  }

  ContactEntry _entry(Contact contact) => ContactEntry(
    name: contact.displayName ?? '',
    nickname: contact.name?.nickname,
    numbers: [for (final phone in contact.phones) phone.number],
  );

  @override
  Future<bool> setTorch({required bool on}) => const TorchChannel().set(on: on);

  @override
  Future<bool?> torchIsOn() => const TorchChannel().isOn();

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
  Future<bool> openMap(Place place) {
    final spot = '${place.latitude},${place.longitude}';
    return _firstThatOpens([
      if (_iOS) ('comgooglemaps://?q=$spot', _app),
      if (_iOS) ('https://maps.apple.com/?ll=$spot&q=$spot', _app),
      (place.mapLink, _app),
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
  Future<LocationResult> locate() async {
    try {
      if (!await geolocator.Geolocator.isLocationServiceEnabled()) {
        return const LocationOff();
      }
      var permission = await geolocator.Geolocator.checkPermission();
      if (permission == geolocator.LocationPermission.denied) {
        permission = await geolocator.Geolocator.requestPermission();
      }
      if (permission == geolocator.LocationPermission.denied ||
          permission == geolocator.LocationPermission.deniedForever) {
        return const LocationDenied();
      }
      final position = await _position();
      if (position == null) return const LocationUnavailable();
      return LocationFound(
        Place(
          latitude: position.latitude,
          longitude: position.longitude,
          address: await _address(position.latitude, position.longitude),
        ),
      );
    } on Exception {
      return const LocationUnavailable();
    }
  }

  Future<geolocator.Position?> _position() async {
    try {
      return await geolocator.Geolocator.getCurrentPosition(
        locationSettings: const geolocator.LocationSettings(
          accuracy: geolocator.LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
    } on TimeoutException {
      // Indoors a fresh fix can take too long; a recent one beats none.
      return geolocator.Geolocator.getLastKnownPosition();
    }
  }

  /// The address in the phone's own language, or null without one in time.
  Future<String?> _address(double latitude, double longitude) async {
    try {
      final places = await _geocoder
          .placemarkFromCoordinates(latitude, longitude)
          .timeout(const Duration(seconds: 6));
      if (places.isEmpty) return null;
      final place = places.first;
      return formatAddress(
        administrativeArea: place.administrativeArea,
        locality: place.locality,
        subLocality: place.subLocality,
        thoroughfare: place.thoroughfare,
        subThoroughfare: place.subThoroughfare,
        street: place.street,
        name: place.name,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> composeSms({String? number, required String body}) {
    final to = _phoneDigits(number ?? '');
    final text = body.isEmpty
        ? ''
        // iOS reads the text after "&body=", Android after "?body=".
        : '${_iOS ? '&' : '?'}body=${Uri.encodeComponent(body)}';
    return _open(Uri.parse('sms:$to$text'), _app);
  }

  @override
  Future<bool> shareOnLine(String text) {
    final encoded = Uri.encodeComponent(text);
    return _firstThatOpens([
      ('https://line.me/R/share?text=$encoded', _appOnly),
      // The older form, for phones where the link above opens a browser.
      ('line://msg/text/$encoded', _app),
    ]);
  }

  @override
  Future<void> openSettings() => FlutterContacts.permissions.openSettings();

  @override
  Future<void> openLocationSettings() async {
    await geolocator.Geolocator.openLocationSettings();
  }

  String _phoneDigits(String number) =>
      number.replaceAll(RegExp(r'[^0-9+*#]'), '');

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

const _packages = {
  PhoneApp.line: 'jp.naver.line.android',
  PhoneApp.youtube: 'com.google.android.youtube',
  PhoneApp.facebook: 'com.facebook.katana',
  PhoneApp.maps: 'com.google.android.apps.maps',
};

/// Apps iOS can open by name: (spoken names, shown name, link).
const _iosApps = [
  ({'instagram', 'ig'}, 'Instagram', 'instagram://app'),
  ({'messenger'}, 'Messenger', 'fb-messenger://'),
  ({'whatsapp'}, 'WhatsApp', 'whatsapp://'),
  ({'chrome', 'google瀏覽器'}, 'Chrome', 'googlechrome://'),
  ({'gmail'}, 'Gmail', 'googlegmail://'),
  ({'spotify'}, 'Spotify', 'spotify://'),
  ({'相簿', '相片', '照片', 'photos'}, '相簿', 'photos-redirect://'),
  ({'音樂', 'applemusic', 'music'}, '音樂', 'music://'),
  ({'行事曆', '日曆', 'calendar'}, '行事曆', 'calshow://'),
];
