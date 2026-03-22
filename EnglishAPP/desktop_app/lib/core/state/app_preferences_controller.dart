import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppPreferencesState {
  const AppPreferencesState({
    required this.initialized,
    required this.readingFontSize,
    required this.autoPlayWordAudio,
  });

  final bool initialized;
  final String readingFontSize;
  final bool autoPlayWordAudio;

  double get readingBodyFontSize {
    switch (readingFontSize) {
      case 'small':
        return 15;
      case 'large':
        return 18;
      default:
        return 16;
    }
  }

  AppPreferencesState copyWith({
    bool? initialized,
    String? readingFontSize,
    bool? autoPlayWordAudio,
  }) {
    return AppPreferencesState(
      initialized: initialized ?? this.initialized,
      readingFontSize: readingFontSize ?? this.readingFontSize,
      autoPlayWordAudio: autoPlayWordAudio ?? this.autoPlayWordAudio,
    );
  }
}

class AppPreferencesController extends StateNotifier<AppPreferencesState> {
  AppPreferencesController()
      : super(const AppPreferencesState(initialized: false, readingFontSize: 'medium', autoPlayWordAudio: false)) {
    _restore();
  }

  static const _kReadingFontSizeKey = 'prefs_reading_font_size';
  static const _kAutoPlayWordAudioKey = 'prefs_auto_play_word_audio';

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    state = AppPreferencesState(
      initialized: true,
      readingFontSize: prefs.getString(_kReadingFontSizeKey) ?? 'medium',
      autoPlayWordAudio: prefs.getBool(_kAutoPlayWordAudioKey) ?? false,
    );
  }

  Future<void> setReadingFontSize(String value) async {
    state = state.copyWith(initialized: true, readingFontSize: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kReadingFontSizeKey, value);
  }

  Future<void> setAutoPlayWordAudio(bool value) async {
    state = state.copyWith(initialized: true, autoPlayWordAudio: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAutoPlayWordAudioKey, value);
  }
}

final appPreferencesProvider =
    StateNotifierProvider<AppPreferencesController, AppPreferencesState>((ref) => AppPreferencesController());
