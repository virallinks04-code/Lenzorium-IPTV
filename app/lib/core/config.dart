/// Build-time configuration. Override with --dart-define, e.g.
///   flutter build apk --dart-define=LICENCE_API=https://activate.lenzorium.com
class AppConfig {
  static const String appName = 'Lenzorium Player';
  static const String company = 'Lenzorium Technologies';
  static const String version = '1.0.0';

  /// Base URL of the Lenzorium licence server (see /server).
  static const String licenceApi = String.fromEnvironment(
    'LICENCE_API',
    defaultValue: 'https://activate.lenzorium.com',
  );

  /// Public activation page shown on the Activate screen.
  static const String activationHost = String.fromEnvironment(
    'ACTIVATION_HOST',
    defaultValue: 'activate.lenzorium.com',
  );

  /// Optional XCIPTV-style provider build: pre-fills the Xtream server so
  /// customers only type a username and password. Empty = generic player.
  ///   --dart-define=DEFAULT_XTREAM_SERVER=http://server.example:8080
  ///   --dart-define=LOCK_XTREAM_SERVER=true   (hides the server field)
  /// Only use for a provider whose content you are licensed to distribute.
  static const String defaultXtreamServer = String.fromEnvironment('DEFAULT_XTREAM_SERVER');
  static const bool lockXtreamServer = bool.fromEnvironment('LOCK_XTREAM_SERVER');

  static const int trialDays = 7;

  /// How long the app keeps working without reaching the licence server.
  static const Duration offlineGrace = Duration(days: 7);

  static const String contentNotice =
      'Lenzorium Player does not provide any content. Use it only with content you are legally allowed to access.';
}
