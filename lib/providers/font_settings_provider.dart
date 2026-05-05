import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:posh_flutter_components/font/posh_font_service.dart';

const String _uiFontKey = 'ui_font_v1';
const String _voicesEnabledKey = 'voices_enabled';

/// Manages the global UI font and app settings with SharedPreferences persistence.
/// Uses [PoshFontService] from posh_flutter_components for font discovery.
class FontSettingsProvider extends ChangeNotifier {
  String _uiFont = '';
  bool _voicesEnabled = true;

  String get uiFont => _uiFont.isNotEmpty ? _uiFont : 'System';
  bool get voicesEnabled => _voicesEnabled;

  FontSettingsProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _voicesEnabled = prefs.getBool(_voicesEnabledKey) ?? true;

    final stored = prefs.getString(_uiFontKey);
    if (stored != null && stored.isNotEmpty) {
      _uiFont = stored;
      // Load the saved font into Flutter's font engine
      if (!kIsWeb && _uiFont != 'System') {
        await PoshFontService.loadFont(_uiFont);
      } else if (kIsWeb && _uiFont != 'System') {
        _uiFont = 'System';
        await prefs.setString(_uiFontKey, _uiFont);
      }
      notifyListeners();
    }
  }

  Future<void> setUIFont(String font) async {
    if (font == _uiFont) return;
    _uiFont = font;
    notifyListeners();

    if (!kIsWeb && font != 'System') {
      await PoshFontService.loadFont(font);
    } else if (kIsWeb && font != 'System') {
      _uiFont = 'System';
      notifyListeners();
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_uiFontKey, font);
  }

  /// Toggle voice input on/off.
  Future<void> setVoicesEnabled(bool enabled) async {
    if (enabled == _voicesEnabled) return;
    _voicesEnabled = enabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_voicesEnabledKey, enabled);
  }

  /// Get available system fonts (discovered lazily).
  static Future<List<String>> getAvailableFonts() async {
    return PoshFontService.getAvailableFonts();
  }
}
