class AppConfig {
  // Your Render URL hostname (WITHOUT https:// or http://)
  static const String backendHost = 'voice-buddy-relay.onrender.com';
  static const bool useSecure = true;

  // Helper to ensure clean domain even if https:// is accidentally typed
  static String get _cleanHost => backendHost
      .replaceAll('https://', '')
      .replaceAll('http://', '')
      .replaceAll('wss://', '')
      .replaceAll('ws://', '')
      .replaceAll('/', '');

  static String get wsUrl =>
      '${useSecure ? "wss" : "ws"}://$_cleanHost/ws/audio';

  static String get httpUrl =>
      '${useSecure ? "https" : "http"}://$_cleanHost';

  // Parent PIN to unlock session summaries
  static const String parentPin = '1234';

  // Audio configuration
  static const int inputSampleRate = 16000;
  static const int outputSampleRate = 24000;
}
