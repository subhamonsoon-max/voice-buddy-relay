class AppConfig {
  // Update this to your deployed Render URL or local IP for testing
  // e.g., 'https://voice-buddy-relay.onrender.com'
  static const String backendHost = 'voice-buddy-relay.onrender.com';
  static const bool useSecure = true;

  static String get wsUrl =>
      '${useSecure ? "wss" : "ws"}://$backendHost/ws/audio';

  static String get httpUrl =>
      '${useSecure ? "https" : "http"}://$backendHost';

  // Parent PIN to unlock session summaries
  static const String parentPin = '1234';

  // Audio configuration
  static const int inputSampleRate = 16000;
  static const int outputSampleRate = 24000;
}
