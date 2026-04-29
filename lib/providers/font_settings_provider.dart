import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:posh_flutter_components/font/posh_font_service.dart';

const String _uiFontKey = 'ui_font_v1';

/// Manages the global UI font with SharedPreferences persistence.
/// Uses [PoshFontService] from posh_flutter_components for font discovery.
class FontSettingsProvider extends ChangeNotifier {
  String _uiFont = '';

  String get uiFont => _uiFont.isNotEmpty ? _uiFont : 'System';

  FontSettingsProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_uiFontKey);
    if (stored != null && stored.isNotEmpty) {
      _uiFont = stored;
      // Load the saved font into Flutter's font engine
      if (_uiFont != 'System') {
        await PoshFontService.loadFont(_uiFont);
      }
      notifyListeners();
    }
  }

  Future<void> setUIFont(String font) async {
    if (font == _uiFont) return;
    _uiFont = font;
    notifyListeners();

    if (font != 'System') {
      await PoshFontService.loadFont(font);
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_uiFontKey, font);
  }

  /// Get available system fonts (discovered lazily).
  static Future<List<String>> getAvailableFonts() async {
    return PoshFontService.getAvailableFonts();
  }
}
