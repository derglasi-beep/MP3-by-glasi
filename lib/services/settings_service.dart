import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static const _volume='volume';
  static const _speed='speed';
  static const _bass='bass';
  static const _treble='treble';
  static const _preamp='preamp';
  static const _crossfade='crossfade';
  static const _lastTrackId='last_track_id';
  static const _shuffle='playback_shuffle';
  static const _repeatMode='playback_repeat_mode';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<double> get volume async => (await _prefs).getDouble(_volume) ?? .8;
  Future<double> get speed async => (await _prefs).getDouble(_speed) ?? 1.0;
  Future<double> get bass async => (await _prefs).getDouble(_bass) ?? 0;
  Future<double> get treble async => (await _prefs).getDouble(_treble) ?? 0;
  Future<double> get preamp async => (await _prefs).getDouble(_preamp) ?? 0;
  Future<double> get crossfade async => (await _prefs).getDouble(_crossfade) ?? 0;
  Future<String?> get lastTrackId async => (await _prefs).getString(_lastTrackId);
  Future<bool> get shuffle async => (await _prefs).getBool(_shuffle) ?? false;
  Future<int> get repeatMode async => (await _prefs).getInt(_repeatMode) ?? 0;

  Future<List<double>> get eqBands async {
    final p = await _prefs;
    return List.generate(10, (i) => p.getDouble('eq_$i') ?? 0);
  }

  Future<void> setVolume(double v) async => (await _prefs).setDouble(_volume,v);
  Future<void> setSpeed(double v) async => (await _prefs).setDouble(_speed,v);
  Future<void> setBass(double v) async => (await _prefs).setDouble(_bass,v);
  Future<void> setTreble(double v) async => (await _prefs).setDouble(_treble,v);
  Future<void> setPreamp(double v) async => (await _prefs).setDouble(_preamp,v);
  Future<void> setCrossfade(double v) async => (await _prefs).setDouble(_crossfade,v);
  Future<void> setLastTrackId(String id) async => (await _prefs).setString(_lastTrackId,id);
  Future<void> setShuffle(bool value) async => (await _prefs).setBool(_shuffle, value);
  Future<void> setRepeatMode(int value) async => (await _prefs).setInt(_repeatMode, value);
  Future<void> setEqBand(int i,double v) async => (await _prefs).setDouble('eq_$i',v);
}
