import 'package:flutter/foundation.dart';

class DeveloperMode extends ChangeNotifier {
  static final DeveloperMode _instance = DeveloperMode._internal();
  factory DeveloperMode() => _instance;
  DeveloperMode._internal();

  bool _isEnabled = false;
  bool get isEnabled => _isEnabled;

  void enable() {
    _isEnabled = true;
    notifyListeners();
  }

  void disable() {
    _isEnabled = false;
    notifyListeners();
  }
}
