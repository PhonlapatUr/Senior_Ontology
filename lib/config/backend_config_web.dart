const String _prodUrl = String.fromEnvironment(
  'BACKEND_URL',
  defaultValue: '',
);

String get backendBase {
  if (_prodUrl.isNotEmpty) return _prodUrl.replaceFirst(RegExp(r'/$'), '');
  return "http://127.0.0.1:8000";
}
