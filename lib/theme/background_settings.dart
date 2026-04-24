import 'package:flutter/material.dart';
import '../services/settings_manager.dart';

class BackgroundSettings extends ChangeNotifier {
  bool _enabled = false;
  String? _imagePath;
  double _imageOpacity = 1.0;
  double _uiOpacity = 0.8;

  bool get enabled => _enabled;
  String? get imagePath => _imagePath;
  double get imageOpacity => _imageOpacity;
  double get uiOpacity => _uiOpacity;

  BackgroundSettings._();
  static final instance = BackgroundSettings._();
  
  Future<void> init() async {
    final settings = SettingsManager.instance;
    _enabled = settings.bgEnabled;
    _imagePath = settings.bgImagePath;
    _imageOpacity = settings.bgImageOpacity;
    _uiOpacity = settings.bgUiOpacity;
  }

  void setEnabled(bool val) {
    _enabled = val;
    notifyListeners();
    SettingsManager.instance.setBgEnabled(val);
  }

  void setImagePath(String? val) {
    _imagePath = val;
    notifyListeners();
    SettingsManager.instance.setBgImagePath(val);
  }

  void setImageOpacity(double val) {
    _imageOpacity = val;
    notifyListeners();
    SettingsManager.instance.setBgImageOpacity(val);
  }

  void setUiOpacity(double val) {
    _uiOpacity = val;
    notifyListeners();
    SettingsManager.instance.setBgUiOpacity(val);
  }
}
