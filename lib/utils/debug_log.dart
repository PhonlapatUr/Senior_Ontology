import 'dart:convert';
import 'package:http/http.dart' as http;

const String _kIngestUrl =
    'http://127.0.0.1:7667/ingest/234234c2-748b-4fb0-820a-7861ecd2da64';
const String _kSessionId = '9bfe97';

void debugLog(String location, String message,
    {String? runId, String? hypothesisId, Map<String, dynamic>? data}) {
  final payload = {
    'sessionId': _kSessionId,
    if (runId != null) 'runId': runId,
    'location': location,
    'message': message,
    'timestamp': DateTime.now().millisecondsSinceEpoch,
    if (hypothesisId != null) 'hypothesisId': hypothesisId,
    if (data != null) 'data': data,
  };
  print('[DEBUG_SESSION_9bfe97] ${jsonEncode(payload)}');
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
