import 'dart:convert';
import 'package:http/http.dart' as http;

// #region agent log
const String _kIngestUrl =
    'http://127.0.0.1:7667/ingest/234234c2-748b-4fb0-820a-7861ecd2da64';
const String _kSessionId = '319aeb';

void debugLog(String location, String message,
    {String? hypothesisId, Map<String, dynamic>? data}) {
  final payload = {
    'sessionId': _kSessionId,
    'location': location,
    'message': message,
    'timestamp': DateTime.now().millisecondsSinceEpoch,
    if (hypothesisId != null) 'hypothesisId': hypothesisId,
    if (data != null) 'data': data,
  };
  print('[DEBUG_SESSION_319aeb] ${jsonEncode(payload)}');
  http
      .post(
    Uri.parse(_kIngestUrl),
    headers: {
      'Content-Type': 'application/json',
      'X-Debug-Session-Id': _kSessionId,
    },
    body: jsonEncode(payload),
  )
      .catchError((_) {});
}
// #endregion
