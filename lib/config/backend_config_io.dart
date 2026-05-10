import 'dart:io' show Platform;

/// Production URL: set at build time with --dart-define=BACKEND_URL=https://your-server.com
const String _prodUrl = String.fromEnvironment(
  'BACKEND_URL',
  defaultValue: '',
);

/// Backend base URL. Use BACKEND_URL for production; otherwise emulator/local.
String get backendBase {
  if (_prodUrl.isNotEmpty) return _prodUrl.replaceFirst(RegExp(r'/$'), '');
  return Platform.isAndroid ? "http://10.0.2.2:8000" : "http://127.0.0.1:8000";
}
