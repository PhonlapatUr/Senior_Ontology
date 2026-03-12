// Platform-aware backend URL. Use this everywhere the app talks to the API.
import 'backend_config_io.dart' if (dart.library.html) 'backend_config_web.dart'
    as impl;

String get backendBase => impl.backendBase;
