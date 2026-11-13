import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../core/config.dart';
import 'auth_service.dart';

class SupabaseService {
  SupabaseService(this._auth, {http.Client? client})
      : _http = client ?? http.Client();
  final AuthService _auth;
  final http.Client _http;

  String get _url => Config.supabaseUrl;
  String get _key => Config.supabaseAnonKey;

  Future<Map<String, String>> _headers() async {
    final token = await _auth.accessToken();
    return {
      'apikey': _key,
      'Authorization': 'Bearer ${token ?? _key}',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    };
  }

  // ── Generic REST helpers ──
  Future<List<Map<String, dynamic>>> _select(String table,
      {String? filter, String order = 'created_at.desc'}) async {
    final uri = Uri.parse('$_url/rest/v1/$table?${filter ?? ''}&order=$order');
    final res = await _http.get(uri, headers: await _headers());
    if (res.statusCode >= 400)
      throw Exception(
          'Supabase GET $table failed: ${res.statusCode} ${res.body}');
    final data = jsonDecode(utf8.decode(res.bodyBytes));
    return (data as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> _insert(
      String table, Map<String, dynamic> body) async {
    final uri = Uri.parse('$_url/rest/v1/$table');
    final res = await _http.post(uri,
        headers: await _headers(), body: jsonEncode(body));
    if (res.statusCode >= 400)
      throw Exception(
          'Supabase INSERT $table failed: ${res.statusCode} ${res.body}');
    final data = jsonDecode(utf8.decode(res.bodyBytes));
    if (data is List && data.isNotEmpty)
      return data.first as Map<String, dynamic>;
    if (data is Map) return data.cast<String, dynamic>();
    return <String, dynamic>{};
  }

  Future<Map<String, dynamic>> _upsert(
      String table, Map<String, dynamic> body) async {
    final uri = Uri.parse('$_url/rest/v1/$table');
    final h = await _headers();
    h['Prefer'] = 'return=representation,resolution=merge-duplicates';
    final res = await _http.post(uri, headers: h, body: jsonEncode(body));
    if (res.statusCode >= 400)
      throw Exception(
          'Supabase UPSERT $table failed: ${res.statusCode} ${res.body}');
    final data = jsonDecode(utf8.decode(res.bodyBytes));
    if (data is List && data.isNotEmpty)
      return data.first as Map<String, dynamic>;
    if (data is Map) return data.cast<String, dynamic>();
    return <String, dynamic>{};
  }

  Future<void> _delete(String table, String id) async {
    final uri = Uri.parse('$_url/rest/v1/$table?id=eq.$id');
    final res = await _http.delete(uri, headers: await _headers());
    if (res.statusCode >= 400)
      throw Exception(
          'Supabase DELETE $table failed: ${res.statusCode} ${res.body}');
  }

  Future<Map<String, dynamic>> _update(
      String table, String filter, Map<String, dynamic> body) async {
    final uri = Uri.parse('$_url/rest/v1/$table?$filter');
    final res = await _http.patch(uri,
        headers: await _headers(), body: jsonEncode(body));
    if (res.statusCode >= 400)
      throw Exception(
          'Supabase UPDATE $table failed: ${res.statusCode} ${res.body}');
    final data = jsonDecode(utf8.decode(res.bodyBytes));
    if (data is List && data.isNotEmpty)
      return data.first as Map<String, dynamic>;
    return <String, dynamic>{};
  }

  // ── Health Documents ──
  Future<List<Map<String, dynamic>>> fetchDocuments(String userId) =>
      _select('health_documents', filter: 'user_id=eq.$userId');

  Future<Map<String, dynamic>> uploadDocument({
    required String userId,
    required String title,
    required String category,
    String? description,
    String? documentDate,
    String? doctorName,
    String? hospitalName,
    List<String>? tags,
    String? fileUrl,
    String? fileName,
    int? fileSize,
    String? fileType,
  }) =>
      _insert('health_documents', {
        'user_id': userId,
        'title': title,
        'category': category,
        if (description != null) 'description': description,
        if (documentDate != null) 'document_date': documentDate,
        if (doctorName != null) 'doctor_name': doctorName,
        if (hospitalName != null) 'hospital_name': hospitalName,
        if (tags != null) 'tags': tags,
        if (fileUrl != null) 'file_url': fileUrl,
        if (fileName != null) 'file_name': fileName,
        if (fileSize != null) 'file_size': fileSize,
        if (fileType != null) 'file_type': fileType,
      });

  Future<void> deleteDocument(String docId) =>
      _delete('health_documents', docId);

  // ── Vault Settings ──
  Future<Map<String, dynamic>?> getVaultSettings(String userId) async {
    final rows = await _select('vault_settings', filter: 'user_id=eq.$userId');
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> setVaultPassword(String userId, String passwordHash) =>
      _upsert('vault_settings', {
        'user_id': userId,
        'vault_password_hash': passwordHash,
        'is_vault_locked': true,
      });

  // ── MediScan Results ──
  Future<List<Map<String, dynamic>>> fetchScanHistory(String userId) =>
      _select('mediscan_results', filter: 'user_id=eq.$userId');

  Future<Map<String, dynamic>> saveScanResult({
    required String userId,
    required String scanType,
    String? originalImageUrl,
    Map<String, dynamic>? extractedData,
    Map<String, dynamic>? aiAnalysis,
    double? confidenceScore,
    String status = 'completed',
  }) =>
      _insert('mediscan_results', {
        'user_id': userId,
        'scan_type': scanType,
        if (originalImageUrl != null) 'original_image_url': originalImageUrl,
        if (extractedData != null) 'extracted_data': extractedData,
        if (aiAnalysis != null) 'ai_analysis': aiAnalysis,
        if (confidenceScore != null) 'confidence_score': confidenceScore,
        'status': status,
      });

  Future<void> deleteScanResult(String scanId) =>
      _delete('mediscan_results', scanId);

  // ── Symptom Checks ──
  Future<List<Map<String, dynamic>>> fetchSymptomHistory(String userId) =>
      _select('symptom_checks', filter: 'user_id=eq.$userId');

  Future<Map<String, dynamic>> saveSymptomCheck({
    required String userId,
    required Map<String, dynamic> symptoms,
    required String bodyRegion,
    required String severity,
    required String duration,
    Map<String, dynamic>? aiDiagnosis,
    Map<String, dynamic>? recommendedActions,
    String urgencyLevel = 'low',
  }) =>
      _insert('symptom_checks', {
        'user_id': userId,
        'symptoms': symptoms,
        'body_region': bodyRegion,
        'severity': severity,
        'duration': duration,
        if (aiDiagnosis != null) 'ai_diagnosis': aiDiagnosis,
        if (recommendedActions != null)
          'recommended_actions': recommendedActions,
        'urgency_level': urgencyLevel,
      });

  // ── Emergency Contacts ──
  Future<List<Map<String, dynamic>>> fetchContacts(String userId) =>
      _select('emergency_contacts', filter: 'user_id=eq.$userId');

  Future<Map<String, dynamic>> addContact({
    required String userId,
    required String name,
    required String phone,
    String relationship = 'Other',
    bool isPrimary = false,
  }) =>
      _insert('emergency_contacts', {
        'user_id': userId,
        'name': name,
        'phone': phone,
        'relationship': relationship,
        'is_primary': isPrimary,
      });

  Future<void> deleteContact(String contactId) =>
      _delete('emergency_contacts', contactId);

  // ── Emergency Alerts ──
  Future<List<Map<String, dynamic>>> fetchAlerts(String userId) =>
      _select('emergency_alerts', filter: 'user_id=eq.$userId');

  Future<Map<String, dynamic>> createAlert({
    required String userId,
    required String alertType,
    required double latitude,
    required double longitude,
    String? address,
    String status = 'active',
  }) =>
      _insert('emergency_alerts', {
        'user_id': userId,
        'alert_type': alertType,
        'latitude': latitude,
        'longitude': longitude,
        if (address != null) 'address': address,
        'status': status,
      });

  // ── Profiles ──
  Future<Map<String, dynamic>?> getProfile(String userId) async {
    final rows = await _select('profiles', filter: 'id=eq.$userId');
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, dynamic>> updateProfile(
          String userId, Map<String, dynamic> updates) =>
      _update('profiles', 'id=eq.$userId', updates);

  // ── Nearby Facilities (from Supabase) ──
  Future<List<Map<String, dynamic>>> fetchNearbyFacilities() =>
      _select('nearby_facilities', order: 'name.asc');

  // ── Storage ──
  Future<String> uploadStorageFile(
      String bucket, String path, Uint8List bytes, String contentType) async {
    final token = await _auth.accessToken();
    final encodedPath = path.split('/').map(Uri.encodeComponent).join('/');
    final uri = Uri.parse('$_url/storage/v1/object/$bucket/$encodedPath');
    final res = await _http.put(
      uri,
      headers: {
        'apikey': _key,
        'Authorization': 'Bearer ${token ?? _key}',
        'Content-Type': contentType,
        'x-upsert': 'false',
      },
      body: bytes,
    );
    if (res.statusCode >= 400)
      throw Exception('Storage upload failed: ${res.statusCode} ${res.body}');
    return path;
  }

  Future<String> signedStorageUrl(String bucket, String path,
      {int expiresInSeconds = 900}) async {
    final token = await _auth.accessToken();
    final encodedPath = path.split('/').map(Uri.encodeComponent).join('/');
    final uri = Uri.parse('$_url/storage/v1/object/sign/$bucket/$encodedPath');
    final res = await _http.post(
      uri,
      headers: {
        'apikey': _key,
        'Authorization': 'Bearer ${token ?? _key}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'expiresIn': expiresInSeconds}),
    );
    if (res.statusCode >= 400)
      throw Exception('Could not open this document: ${res.statusCode}');
    final signed = (jsonDecode(utf8.decode(res.bodyBytes))
            as Map<String, dynamic>)['signedURL']
        ?.toString();
    if (signed == null || signed.isEmpty)
      throw Exception('Could not create a temporary document link.');
    if (signed.startsWith('https://') || signed.startsWith('http://'))
      return signed;
    return '$_url/storage/v1${signed.startsWith('/') ? signed : '/$signed'}';
  }

  Future<void> deleteStorageFile(String bucket, String path) async {
    final token = await _auth.accessToken();
    final uri = Uri.parse('$_url/storage/v1/object/$bucket');
    final res = await _http.delete(
      uri,
      headers: {
        'apikey': _key,
        'Authorization': 'Bearer ${token ?? _key}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'prefixes': [path]
      }),
    );
    if (res.statusCode >= 400)
      throw Exception('Storage delete failed: ${res.statusCode}');
  }
}
