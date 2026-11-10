/// Build-time configuration. Inject secrets/config via --dart-define-from-file=.env
/// (never hardcode API keys or credentials in source control).
class Config {
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://jeevan-app-backend-production.up.railway.app',
  );

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static const tomtomApiKey = String.fromEnvironment('TOMTOM_API_KEY');

  static const webBaseUrl = String.fromEnvironment(
    'WEB_BASE_URL',
    defaultValue: 'https://jeevan-app-backend-production.up.railway.app',
  );

  static String videoCallUrl(String roomId) =>
      '${webBaseUrl.replaceAll(RegExp(r'/+$'), '')}/video-call?room=${Uri.encodeComponent(roomId)}';

  static String emergencySummaryUrl(String uid) =>
      '${webBaseUrl.replaceAll(RegExp(r'/+$'), '')}/emergency/${Uri.encodeComponent(uid)}';

  static const bleService = '4a455645-0001-4c2b-9d3a-5a65657600a1';
  static const bleVitalsChar = '4a455645-0002-4c2b-9d3a-5a65657600a1';
  static const bleCommandChar = '4a455645-0003-4c2b-9d3a-5a65657600a1';
  static const bleEventChar = '4a455645-0004-4c2b-9d3a-5a65657600a1';

  static const googleServerClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  static const googleAndroidClientId = String.fromEnvironment('GOOGLE_ANDROID_CLIENT_ID');
}
