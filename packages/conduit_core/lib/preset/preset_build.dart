/// Server and email compiled into a preset build (`--dart-define-from-file`).
/// The password is never compiled in.
const String presetServerUrl = String.fromEnvironment('PRESET_SERVER_URL');
const String presetEmail = String.fromEnvironment('PRESET_EMAIL');

/// Whether this build carries a preset server.
bool get isPresetBuild => presetServerUrl.trim().isNotEmpty;
