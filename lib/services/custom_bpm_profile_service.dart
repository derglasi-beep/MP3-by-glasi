import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'spinning_playlist_service.dart';

class CustomBpmProfileService {
  static const _profilesKey = 'custom_bpm_profiles_v1';
  static const _activeProfileKey = 'custom_bpm_active_profile_v1';

  Future<List<CustomBpmProfile>> loadProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_profilesKey);
    if (raw == null || raw.isEmpty) return const <CustomBpmProfile>[];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <CustomBpmProfile>[];
      return [
        for (final item in decoded)
          if (item is Map)
            CustomBpmProfile.fromJson(
              Map<String, dynamic>.from(item),
            ),
      ].where((profile) => profile.id.isNotEmpty).toList(growable: false);
    } catch (_) {
      return const <CustomBpmProfile>[];
    }
  }

  Future<void> saveProfiles(List<CustomBpmProfile> profiles) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _profilesKey,
      jsonEncode(
        profiles.map((profile) => profile.toJson()).toList(growable: false),
      ),
    );
  }

  Future<String?> loadActiveProfileId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_activeProfileKey);
  }

  Future<void> saveActiveProfileId(String? id) async {
    final prefs = await SharedPreferences.getInstance();
    if (id == null || id.isEmpty) {
      await prefs.remove(_activeProfileKey);
    } else {
      await prefs.setString(_activeProfileKey, id);
    }
  }
}
