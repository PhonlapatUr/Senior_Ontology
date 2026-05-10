import 'dart:async';

class Debouncer {
  final int ms;
  Timer? _t;

  Debouncer(this.ms);

  void run(Function() f) {
    _t?.cancel();
    _t = Timer(Duration(milliseconds: ms), f);
  }
}
