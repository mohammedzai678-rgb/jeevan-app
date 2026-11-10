/// Build-time configuration. Inject secrets/config via --dart-define-from-file=.env
/// (never hardcode API keys or credentials in source control).
/// The Supabase *anon* key is public by design (RLS protects data). NEVER put the service-role key in the app.
class Config {
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://jeevan-app-backend-production.up.railway.app',
  );
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

  /// Public origin of the JeevanCare app server (hosted on Railway).
  /// The Emergency QR encodes `<webBaseUrl>/emergency/<userId>` and SOS alerts include
  /// `<webBaseUrl>/video-call?room=<roomId>`.
  static const webBaseUrl = String.fromEnvironment(
    'WEB_BASE_URL',
    defaultValue: 'https://jeevan-app-backend-production.up.railway.app',
  );

  static String videoCallUrl(String roomId) =>
      '${webBaseUrl.replaceAll(RegExp(r'/+$'), '')}/video-call?room=${Uri.encodeComponent(roomId)}';

  static String emergencySummaryUrl(String uid) =>
      '${webBaseUrl.replaceAll(RegExp(r'/+$'), '')}/emergency/${Uri.encodeComponent(uid)}';

  /// BLE contract shared with firmware_ble/jeevan_ble.h
  static const bleService = '4a455645-0001-4c2b-9d3a-5a65657600a1';
  static const bleVitalsChar = '4a455645-0002-4c2b-9d3a-5a65657600a1'; // notify, JSON
  static const bleCommandChar = '4a455645-0003-4c2b-9d3a-5a65657600a1'; // write, ASCII
  static const bleEventChar = '4a455645-0004-4c2b-9d3a-5a65657600a1'; // notify, JSON (sos / med_ack)
}
