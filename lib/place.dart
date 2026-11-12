/// Where the phone is, with the street address when one was found.
class Place {
  const Place({required this.latitude, required this.longitude, this.address});

  final double latitude;
  final double longitude;
  final String? address;

  String get _coordinates =>
      '${latitude.toStringAsFixed(5)},${longitude.toStringAsFixed(5)}';

  /// Opens this spot in Google Maps, or in a browser without the app.
  String get mapLink =>
      'https://www.google.com/maps/search/?api=1&query=$_coordinates';

  /// The address, or the coordinates when there is none.
  String get label =>
      address ??
      '${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}';

  /// The text sent to someone else.
  String message({bool urgent = false}) => [
    if (urgent) '我需要幫忙。',
    '我在這裡：',
    if (address != null) '$address ',
    mapLink,
  ].join();
}

sealed class LocationResult {
  const LocationResult();
}

final class LocationFound extends LocationResult {
  const LocationFound(this.place);
  final Place place;
}

/// The app is not allowed to use the location.
final class LocationDenied extends LocationResult {
  const LocationDenied();
}

/// Location is switched off for the whole phone.
final class LocationOff extends LocationResult {
  const LocationOff();
}

/// No position could be found in time, for example indoors.
final class LocationUnavailable extends LocationResult {
  const LocationUnavailable();
}

/// Builds a Taiwanese address ("彰化縣彰化市中山路三段185巷16號") from what the
/// phone's geocoder returns. iOS gives the parts; Android also gives one full
/// line in [street], starting with the postal code and the country.
String? formatAddress({
  String? administrativeArea,
  String? locality,
  String? subLocality,
  String? thoroughfare,
  String? subThoroughfare,
  String? street,
  String? name,
}) {
  String? clean(String? value) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? null : text;
  }

  final region = <String>[];
  for (final part in [administrativeArea, locality, subLocality]) {
    final text = clean(part);
    // Villages (里、村) are left out, as people do when saying an address.
    if (text == null || text.endsWith('里') || text.endsWith('村')) continue;
    if (!region.any((known) => known.contains(text))) region.add(text);
  }

  final line = clean(clean(street)?.replaceFirst(_postalAndCountry, ''));
  final road = clean(thoroughfare);
  var number = clean(subThoroughfare) ?? '';

  if ([...region, ?line, ?road].any(_latin.hasMatch)) {
    // A phone set to English: smallest part first, separated by commas.
    if (line != null && region.every(line.contains)) return line;
    final local =
        line ??
        (road == null ? null : [if (number.isNotEmpty) number, road].join(' '));
    final address = [?local, ...region.reversed].join(', ');
    return address.isEmpty ? null : address;
  }

  if (line != null && region.isNotEmpty && line.startsWith(region.first)) {
    return line;
  }
  if (_digits.hasMatch(number)) number = '$number號';
  final local =
      (road == null ? null : '$road$number') ??
      (line == null || _digits.hasMatch(line) ? null : line) ??
      (_digits.hasMatch(name ?? '') ? null : clean(name));
  final address = [...region, ?local].join();
  return address.isEmpty ? null : address;
}

final _postalAndCountry = RegExp(r'^(?:\d{3,6})?\s*(?:台灣|臺灣|中華民國)?\s*');
final _digits = RegExp(r'^\d+$');
final _latin = RegExp(r'[A-Za-z]');
