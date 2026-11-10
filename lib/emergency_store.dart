import 'package:shared_preferences/shared_preferences.dart';

import 'contact_matcher.dart';

/// Remembers who is called in an emergency. Kept on the phone only.
abstract interface class EmergencyStore {
  Future<ContactEntry?> load();

  /// Null forgets the contact.
  Future<void> save(ContactEntry? contact);
}

class DeviceEmergencyStore implements EmergencyStore {
  static const _name = 'emergency_contact_name';
  static const _number = 'emergency_contact_number';
  final _preferences = SharedPreferencesAsync();

  @override
  Future<ContactEntry?> load() async {
    final name = await _preferences.getString(_name);
    final number = await _preferences.getString(_number);
    if (name == null || number == null || number.isEmpty) return null;
    return ContactEntry(name: name, numbers: [number]);
  }

  @override
  Future<void> save(ContactEntry? contact) async {
    if (contact == null) {
      await _preferences.remove(_name);
      await _preferences.remove(_number);
    } else {
      await _preferences.setString(_name, contact.name);
      await _preferences.setString(_number, contact.number);
    }
  }
}

/// For tests and previews.
class MemoryEmergencyStore implements EmergencyStore {
  MemoryEmergencyStore([this.contact]);
  ContactEntry? contact;

  @override
  Future<ContactEntry?> load() async => contact;

  @override
  Future<void> save(ContactEntry? contact) async => this.contact = contact;
}
