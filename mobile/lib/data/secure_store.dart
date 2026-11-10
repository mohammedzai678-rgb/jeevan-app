import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// Tokens go in the Android Keystore / iOS Keychain; non-secret preferences in SharedPreferences.
class SecureStore {
  SecureStore._(this._secure, this._prefs);
  final FlutterSecureStorage _secure;
  final SharedPreferences _prefs;

  static Future<SecureStore> open() async => SecureStore._(
        const FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true)),
        await SharedPreferences.getInstance(),
      );

  Future<Session?> readSession() async {
    final raw = await _secure.read(key: 'session');
    if (raw == null) return null;
    try {
      return Session.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> writeSession(Session? s) =>
      s == null ? _secure.delete(key: 'session') : _secure.write(key: 'session', value: jsonEncode(s.toJson()));

  String? get serverUrlOverride => _prefs.getString('server_url');
  Future<void> setServerUrl(String? v) async =>
      v == null || v.isEmpty ? _prefs.remove('server_url') : _prefs.setString('server_url', v);

  String? get lastBleId => _prefs.getString('ble_id');
  Future<void> setLastBleId(String? v) async => v == null ? _prefs.remove('ble_id') : _prefs.setString('ble_id', v);

  String? get lastDeviceId => _prefs.getString('device_id');
  Future<void> setLastDeviceId(String? v) async => v == null ? _prefs.remove('device_id') : _prefs.setString('device_id', v);

  String get patientName => _prefs.getString('patient_name') ?? 'User';
  Future<void> setPatientName(String v) => _prefs.setString('patient_name', v.trim().isEmpty ? 'User' : v.trim());

  String get bloodGroup => _prefs.getString('blood_group') ?? 'Not specified';
  Future<void> setBloodGroup(String v) => _prefs.setString('blood_group', v.trim().isEmpty ? 'Not specified' : v.trim());

  String get allergies => _prefs.getString('med_allergies') ?? 'None reported';
  Future<void> setAllergies(String v) =>
      _prefs.setString('med_allergies', v.trim().isEmpty ? 'None reported' : v.trim());

  String get conditions => _prefs.getString('med_conditions') ?? 'None reported';
  Future<void> setConditions(String v) =>
      _prefs.setString('med_conditions', v.trim().isEmpty ? 'None reported' : v.trim());

  String get medications => _prefs.getString('med_current') ?? 'None';
  Future<void> setMedications(String v) =>
      _prefs.setString('med_current', v.trim().isEmpty ? 'None' : v.trim());

  String get medicalDetailsSummary =>
      'Allergies: $allergies | Conditions: $conditions | Medications: $medications';

  String get contactName => _prefs.getString('ice_name') ?? 'Emergency Contact';
  Future<void> setContactName(String v) => _prefs.setString('ice_name', v.trim().isEmpty ? 'Emergency Contact' : v.trim());

  String get contactRelation => _prefs.getString('ice_relation') ?? 'Family';
  Future<void> setContactRelation(String v) => _prefs.setString('ice_relation', v.trim().isEmpty ? 'Family' : v.trim());

  String get contactPhone => _prefs.getString('ice_phone') ?? '';
  Future<void> setContactPhone(String v) => _prefs.setString('ice_phone', v.trim());

  String get contactEmail => _prefs.getString('ice_email') ?? '';
  Future<void> setContactEmail(String v) => _prefs.setString('ice_email', v.trim());
}
