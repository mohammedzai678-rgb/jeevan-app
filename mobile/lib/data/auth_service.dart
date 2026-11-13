import 'dart:async';
import 'dart:convert';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../core/config.dart';
import 'models.dart';
import 'secure_store.dart';

class AuthException implements Exception {
  AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Supabase GoTrue over plain REST (no SDK: one fewer dependency and full control of refresh timing).
class AuthService {
  AuthService(this._store, {http.Client? client})
      : _http = client ?? http.Client();
  final SecureStore _store;
  final http.Client _http;

  Session? _session;
  Completer<Session?>? _refreshing;
  final _controller = StreamController<Session?>.broadcast();

  Session? get session => _session;
  Stream<Session?> get changes => _controller.stream;

  Future<void> init() async {
    _session = await _store.readSession();
    if (_session != null &&
        (!_supabaseConfigured || !_isUuid(_session!.userId))) {
      // Discard sessions created by the removed local, email-only auth path.
      await _set(null);
    } else if (_session != null && _session!.expiringSoon) {
      // Try to refresh the token
      try {
        final fresh = await _grant(
            'refresh_token', {'refresh_token': _session!.refreshToken});
        await _set(fresh);
      } catch (_) {
        // Token expired, clear session
        await _set(null);
      }
    }
    _controller.add(_session);
  }

  Map<String, String> get _headers =>
      {'apikey': Config.supabaseAnonKey, 'Content-Type': 'application/json'};

  bool get _supabaseConfigured =>
      Config.supabaseAnonKey.isNotEmpty && Config.supabaseUrl.isNotEmpty;

  Future<void> signIn(String email, String password) async {
    _requireSupabaseAuth();
    final s = await _grant('password', {'email': email, 'password': password});
    await _set(s);
  }

  /// Returns true when signed in immediately, false when email confirmation is required.
  Future<bool> signUp(String email, String password, String name) async {
    _requireSupabaseAuth();
    final res = await _http
        .post(Uri.parse('${Config.supabaseUrl}/auth/v1/signup'),
            headers: _headers,
            body: jsonEncode({
              'email': email,
              'password': password,
              'data': {'name': name}
            }))
        .timeout(const Duration(seconds: 15));
    final body = _decode(res);
    if (res.statusCode >= 400) {
      throw AuthException(_message(body));
    }
    if (body['access_token'] == null) return false;
    await _set(_parse(body));
    return true;
  }

  Future<void> recoverPassword(String email) async {
    _requireSupabaseAuth();
    final res = await _http
        .post(
          Uri.parse('${Config.supabaseUrl}/auth/v1/recover'),
          headers: _headers,
          body: jsonEncode({'email': email}),
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode >= 400) {
      final body = _decode(res);
      throw AuthException(_message(body));
    }
  }

  Future<void> signOut() => _set(null);

  /// Google Sign-In: exchange Google's verified ID token with Supabase Auth.
  Future<void> signInWithGoogle() async {
    _requireSupabaseAuth();
    final serverClientId = Config.googleServerClientId.isNotEmpty
        ? Config.googleServerClientId
        : null;

    final googleSignIn = GoogleSignIn(
      serverClientId: serverClientId,
      scopes: ['email', 'profile'],
    );
    final account = await googleSignIn.signIn();
    if (account == null) throw AuthException('Google sign-in cancelled');

    final googleAuth = await account.authentication;
    final idToken = googleAuth.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw AuthException('Google did not return a verifiable ID token.');
    }

    final res = await _http
        .post(
          Uri.parse('${Config.supabaseUrl}/auth/v1/token?grant_type=id_token'),
          headers: _headers,
          body: jsonEncode({'provider': 'google', 'id_token': idToken}),
        )
        .timeout(const Duration(seconds: 15));
    final body = _decode(res);
    if (res.statusCode >= 400) throw AuthException(_message(body));
    if (body['access_token'] == null) {
      throw AuthException('Supabase did not return an authenticated session.');
    }
    await _set(_parse(body));
  }

  /// Always returns a token that is valid for at least a minute (refreshing if needed). Null if signed out.
  Future<String?> accessToken({bool force = false}) async {
    final s = _session;
    if (s == null) return null;
    if (!force && !s.expiringSoon) return s.accessToken;
    // De-duplicate concurrent refreshes (WS reconnect + REST call at the same time).
    if (_refreshing != null) return (await _refreshing!.future)?.accessToken;
    final c = _refreshing = Completer<Session?>();
    try {
      final fresh =
          await _grant('refresh_token', {'refresh_token': s.refreshToken});
      await _set(fresh);
      c.complete(fresh);
      return fresh.accessToken;
    } on AuthException {
      await _set(null); // refresh token revoked/expired: force re-login
      c.complete(null);
      return null;
    } catch (_) {
      c.complete(s); // network blip: keep the old session, caller will retry
      return s.accessToken;
    } finally {
      _refreshing = null;
    }
  }

  Future<Session> _grant(String type, Map<String, dynamic> body) async {
    _requireSupabaseAuth();
    final res = await _http
        .post(Uri.parse('${Config.supabaseUrl}/auth/v1/token?grant_type=$type'),
            headers: _headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 15));
    final json = _decode(res);
    if (res.statusCode >= 400) throw AuthException(_message(json));
    return _parse(json);
  }

  Session _parse(Map<String, dynamic> j) {
    final user = (j['user'] as Map?)?.cast<String, dynamic>() ?? {};
    final accessToken = j['access_token'];
    final refreshToken = j['refresh_token'];
    final userId = user['id'];
    if (accessToken is! String ||
        accessToken.isEmpty ||
        refreshToken is! String ||
        refreshToken.isEmpty ||
        userId is! String ||
        !_isUuid(userId)) {
      throw AuthException('Supabase returned an invalid user session.');
    }
    final expiresIn = (j['expires_in'] as num?)?.toInt() ?? 3600;
    return Session(
      accessToken,
      refreshToken,
      userId,
      user['email'] as String?,
      DateTime.now().add(Duration(seconds: expiresIn)),
    );
  }

  Map<String, dynamic> _decode(http.Response r) {
    try {
      final d = jsonDecode(utf8.decode(r.bodyBytes));
      return d is Map<String, dynamic> ? d : {};
    } catch (_) {
      return {};
    }
  }

  String _message(Map<String, dynamic> j) => (j['error_description'] ??
          j['msg'] ??
          j['message'] ??
          'Authentication failed')
      .toString();

  void _requireSupabaseAuth() {
    if (!_supabaseConfigured) {
      throw AuthException(
        'Supabase Auth is not configured. Add SUPABASE_URL and SUPABASE_ANON_KEY to the app build.',
      );
    }
  }

  bool _isUuid(String value) => RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      ).hasMatch(value);

  Future<void> _set(Session? s) async {
    if (s == null || (_session != null && _session!.userId != s.userId)) {
      _store.setVaultUnlockedFor(null);
    }
    _session = s;
    await _store.writeSession(s);
    _controller.add(s);
  }
}
