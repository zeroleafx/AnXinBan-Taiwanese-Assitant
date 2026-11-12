import 'package:an_xin_ban/contact_matcher.dart';
import 'package:an_xin_ban/phone_actions.dart';
import 'package:an_xin_ban/place.dart';
import 'package:an_xin_ban/voice_command.dart';

const home = Place(
  latitude: 24.08123,
  longitude: 120.55861,
  address: '彰化縣彰化市中山路三段185巷16號',
);

/// A phone that records what it was asked to do.
class FakePhone implements PhoneActions {
  /// Apps that open; any other is "not installed".
  final installed = {PhoneApp.line, PhoneApp.maps};

  /// Other apps: spoken name to the name under the icon.
  final namedApps = {'相機': '相機', 'instagram': 'Instagram'};
  bool contactsAllowed = true;
  List<ContactEntry> contacts = const [
    ContactEntry(name: '王小明', numbers: ['0912-345-678']),
    ContactEntry(name: '陳志明', numbers: ['0933-222-111']),
    ContactEntry(name: '林明華', numbers: ['0988-765-432']),
  ];

  /// What the contact picker returns; null means it was cancelled.
  ContactEntry? picked;
  LocationResult location = const LocationFound(home);
  bool hasLine = true;
  bool canDial = true;
  bool canText = true;

  final opened = <PhoneApp>[];
  final openedNamed = <String>[];
  final dialed = <String>[];
  final places = <String>[];
  final maps = <Place>[];
  final searches = <String>[];
  final texts = <(String? number, String body)>[];
  final lineShares = <String>[];
  bool? torch;
  int settingsOpened = 0;
  int locationSettingsOpened = 0;

  @override
  Future<bool> openApp(PhoneApp app) async {
    opened.add(app);
    return installed.contains(app);
  }

  @override
  Future<String?> openNamedApp(String name) async {
    openedNamed.add(name);
    return namedApps[name];
  }

  @override
  Future<bool> dial(String number) async {
    dialed.add(number);
    return canDial;
  }

  @override
  Future<ContactsAccess> loadContacts() async => contactsAllowed
      ? ContactsAccess.granted(contacts)
      : const ContactsAccess.denied();

  @override
  Future<ContactEntry?> pickContact() async => picked;

  @override
  Future<bool> setTorch({required bool on}) async {
    torch = on;
    return true;
  }

  /// False for a phone that cannot tell whether its light is on.
  bool canReadTorch = true;

  @override
  Future<bool?> torchIsOn() async => canReadTorch ? torch ?? false : null;

  @override
  Future<bool> navigate(String place) async {
    places.add(place);
    return true;
  }

  @override
  Future<bool> openMap(Place place) async {
    maps.add(place);
    return true;
  }

  @override
  Future<bool> searchVideo(String query) async {
    searches.add(query);
    return true;
  }

  @override
  Future<bool> searchWeb(String query) async {
    searches.add(query);
    return true;
  }

  @override
  Future<LocationResult> locate() async => location;

  @override
  Future<bool> composeSms({String? number, required String body}) async {
    texts.add((number, body));
    return canText;
  }

  @override
  Future<bool> shareOnLine(String text) async {
    if (hasLine) lineShares.add(text);
    return hasLine;
  }

  @override
  Future<void> openSettings() async => settingsOpened++;

  @override
  Future<void> openLocationSettings() async => locationSettingsOpened++;
}

List<String> names(List<ContactEntry> contacts) => [
  for (final contact in contacts) contact.name,
];
