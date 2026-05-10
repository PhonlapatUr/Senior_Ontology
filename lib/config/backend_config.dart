import 'backend_config_io.dart' if (dart.library.html) 'backend_config_web.dart'
    as impl;

String get backendBase => impl.backendBase;
