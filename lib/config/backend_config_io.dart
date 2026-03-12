// Used when running on Android, iOS, or desktop (dart:io available).
import 'dart:io' show Platform;

/// Backend base URL. Android emulator uses 10.0.2.2 to reach host machine.
String get backendBase =>
    Platform.isAndroid ? "http://10.0.2.2:8000" : "http://127.0.0.1:8000";
