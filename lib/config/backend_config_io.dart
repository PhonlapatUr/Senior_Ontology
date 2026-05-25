import 'dart:io' show Platform;

const String _prodUrl = String.fromEnvironment('BACKEND_URL', defaultValue: '');

String get backendBase {
  if (_prodUrl.isNotEmpty) return _prodUrl.replaceFirst(RegExp(r'/$'), '');
  return Platform.isAndroid ? "http://10.0.2.2:8000" : "http://127.0.0.1:8000";
}
