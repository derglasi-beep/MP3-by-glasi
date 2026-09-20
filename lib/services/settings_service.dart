import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static const _volume='volume'; static const _speed='speed'; static const _bass='bass'; static const _treble='treble'; static const _preamp='preamp'; static const _crossfade='crossfade';
  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();
  Future<double> get volume async => (await _prefs).getDouble(_volume) ?? .8;
  Future<double> get speed async => (await _prefs).getDouble(_speed) ?? 1.0;
  Future<double> get bass async => (await _prefs).getDouble(_bass) ?? 0;
  Future<double> get treble async => (await _prefs).getDouble(_treble) ?? 0;
  Future<double> get preamp async => (await _prefs).getDouble(_preamp) ?? 0;
  Future<double> get crossfade async => (await _prefs).getDouble(_crossfade) ?? 0;
  Future<void> setVolume(double v) async => (await _prefs).setDouble(_volume,v);
  Future<void> setSpeed(double v) async => (await _prefs).setDouble(_speed,v);
  Future<void> setBass(double v) async => (await _prefs).setDouble(_bass,v);
  Future<void> setTreble(double v) async => (await _prefs).setDouble(_treble,v);
  Future<void> setPreamp(double v) async => (await _prefs).setDouble(_preamp,v);
  Future<void> setCrossfade(double v) async => (await _prefs).setDouble(_crossfade,v);
}
