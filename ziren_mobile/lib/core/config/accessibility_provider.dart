import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/theme/app_tokens.dart';

/// Named steps, not a free slider. A slider invites a value nobody chose on
/// purpose and nobody can name back to you; "Large" is something a resident
/// can ask a family member to set the same way on their own phone. Display
/// labels are localized at the call site (see settings_screen.dart) rather
/// than stored here, same as every other user-facing string in this app.
enum TextScaleStep {
  small(0.9),
  normal(1.0),
  large(1.15),
  extraLarge(1.3);

  const TextScaleStep(this.scale);
  final double scale;

  static TextScaleStep nearest(double scale) {
    var best = TextScaleStep.normal;
    var bestDiff = (scale - best.scale).abs();
    for (final step in TextScaleStep.values) {
      final diff = (scale - step.scale).abs();
      if (diff < bestDiff) {
        best = step;
        bestDiff = diff;
      }
    }
    return best;
  }
}

/// Holds display + accessibility preferences: appearance (system/light/dark),
/// text size, reduce motion, and high contrast. Shared by the resident and
/// responder apps, since both are one Flutter build reading one `/settings`
/// screen.
///
/// Modelled directly on LocaleProvider next to this file: a ChangeNotifier,
/// read synchronously at startup so the first frame is already correct
/// (nobody should see a light flash before a dark app settles in), persisted
/// locally via SharedPreferences, and silent on a failed read or write —
/// losing a preference is not a reason to fail to launch.
///
/// Why ZirenTokens gets pushed into, not read from
/// -------------------------------------------------
/// app_tokens.dart's colours are `static` fields, called from ~150 files as
/// bare `ZirenTokens.textPrimary` — not through a BuildContext. Making dark
/// mode work without rewriting every one of those call sites means the
/// brightness has to live as global state those getters can check
/// themselves. This provider is the single writer of that state
/// (`ZirenTokens.setMode`); nothing else should call it.
class AccessibilityProvider extends ChangeNotifier {
  static const _keyThemeMode = 'a11y_theme_mode';
  static const _keyTextScale = 'a11y_text_scale';
  static const _keyReduceMotion = 'a11y_reduce_motion';
  static const _keyHighContrast = 'a11y_high_contrast';

  ThemeMode _themeMode = ThemeMode.system;
  TextScaleStep _textScaleStep = TextScaleStep.normal;
  bool _reduceMotion = false;
  bool _highContrast = false;

  ThemeMode get themeMode => _themeMode;
  TextScaleStep get textScaleStep => _textScaleStep;
  double get textScale => _textScaleStep.scale;
  bool get reduceMotion => _reduceMotion;
  bool get highContrast => _highContrast;

  /// The brightness actually on screen right now — resolves ThemeMode.system
  /// against the OS report. main.dart and ZirenTokens both key off this, so
  /// it is computed once here rather than separately in each place, which is
  /// exactly the kind of duplication that used to let "which theme is this"
  /// disagree between the Scaffold and a hand-painted Container.
  Brightness get resolvedBrightness {
    if (_themeMode == ThemeMode.light) return Brightness.light;
    if (_themeMode == ThemeMode.dark) return Brightness.dark;
    return SchedulerBinding.instance.platformDispatcher.platformBrightness;
  }

  AccessibilityProvider() {
    // Only matters in system mode, but cheap to keep live always — a
    // resident who flips their phone's OS theme while Ziren is open should
    // not have to background and reopen the app to see it follow.
    SchedulerBinding.instance.platformDispatcher.onPlatformBrightnessChanged =
        () {
          if (_themeMode == ThemeMode.system) {
            _applyTokens();
            notifyListeners();
          }
        };
    _applyTokens();
  }

  void _applyTokens() {
    ZirenTokens.setMode(
      brightness: resolvedBrightness,
      highContrast: _highContrast,
    );
  }

  /// Read stored preferences. Call once at startup, before `runApp`, so the
  /// very first frame already renders in the right theme and text size.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final modeName = prefs.getString(_keyThemeMode);
      if (modeName != null) {
        _themeMode = ThemeMode.values.firstWhere(
          (m) => m.name == modeName,
          orElse: () => ThemeMode.system,
        );
      }
      final scale = prefs.getDouble(_keyTextScale);
      if (scale != null) _textScaleStep = TextScaleStep.nearest(scale);
      _reduceMotion = prefs.getBool(_keyReduceMotion) ?? false;
      _highContrast = prefs.getBool(_keyHighContrast) ?? false;
      _applyTokens();
    } catch (_) {
      // Defaults already stand — a failed preferences read must not stop
      // the app from starting.
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == _themeMode) return;
    _themeMode = mode;
    _applyTokens();
    notifyListeners();
    await _persist(_keyThemeMode, mode.name);
  }

  Future<void> setTextScaleStep(TextScaleStep step) async {
    if (step == _textScaleStep) return;
    _textScaleStep = step;
    notifyListeners();
    await _persist(_keyTextScale, step.scale);
  }

  Future<void> setReduceMotion(bool value) async {
    if (value == _reduceMotion) return;
    _reduceMotion = value;
    notifyListeners();
    await _persist(_keyReduceMotion, value);
  }

  Future<void> setHighContrast(bool value) async {
    if (value == _highContrast) return;
    _highContrast = value;
    _applyTokens();
    notifyListeners();
    await _persist(_keyHighContrast, value);
  }

  Future<void> _persist(String key, Object value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value is String) {
        await prefs.setString(key, value);
      } else if (value is double) {
        await prefs.setDouble(key, value);
      } else if (value is bool) {
        await prefs.setBool(key, value);
      }
    } catch (_) {
      // The in-memory change already took effect and already repainted the
      // app; losing the persisted copy only means it resets next launch.
    }
  }

  @override
  void dispose() {
    SchedulerBinding.instance.platformDispatcher.onPlatformBrightnessChanged =
        null;
    super.dispose();
  }
}
