import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  
  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _enabled = _prefs?.getBool('bg_enabled') ?? false;
    _imagePath = _prefs?.getString('bg_image_path');
    _imageOpacity = _prefs?.getDouble('bg_image_opacity') ?? 1.0;
    _uiOpacity = _prefs?.getDouble('bg_ui_opacity') ?? 0.8;
  }

  void setEnabled(bool val) {
    _enabled = val;
    notifyListeners();
    _prefs?.setBool('bg_enabled', val);
  }

  void setImagePath(String? val) {
    _imagePath = val;
    notifyListeners();
    if (val != null) {
      _prefs?.setString('bg_image_path', val);
    } else {
      _prefs?.remove('bg_image_path');
    }
  }

  void setImageOpacity(double val) {
    _imageOpacity = val;
    notifyListeners();
    _prefs?.setDouble('bg_image_opacity', val);
  }

  void setUiOpacity(double val) {
    _uiOpacity = val;
    notifyListeners();
    _prefs?.setDouble('bg_ui_opacity', val);
  }
}
