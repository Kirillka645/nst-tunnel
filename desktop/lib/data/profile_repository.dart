import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'profile.dart';

/// CRUD store for [Profile] objects, backed by SharedPreferences.
///
/// We persist the entire list as one JSON blob under a single key. That keeps
/// the storage layer simple — no schema migrations, no SQL — and is fast enough
/// for the realistic upper bound (a few hundred servers per user).
class ProfileRepository extends ChangeNotifier {
  static const _kKeyProfiles = 'nst.profiles.v1';
  static const _kKeyActive = 'nst.profile.active';

  ProfileRepository(this._prefs) {
    _load();
  }

  final SharedPreferences _prefs;

  final List<Profile> _profiles = [];
  String? _activeId;

  List<Profile> get profiles => List.unmodifiable(_profiles);
  String? get activeId => _activeId;
  Profile? get active => _activeId == null
      ? null
      : _profiles.where((p) => p.id == _activeId).firstOrNull;

  void _load() {
    final raw = _prefs.getString(_kKeyProfiles);
    if (raw != null) {
      try {
        final List<dynamic> decoded = jsonDecode(raw);
        _profiles.addAll(
          decoded.cast<Map<String, dynamic>>().map(Profile.fromJson),
        );
      } catch (e, st) {
        debugPrint('ProfileRepository: failed to parse stored profiles: $e\n$st');
      }
    }
    _activeId = _prefs.getString(_kKeyActive);
  }

  Future<void> _persist() async {
    await _prefs.setString(
      _kKeyProfiles,
      jsonEncode(_profiles.map((p) => p.toJson()).toList()),
    );
    if (_activeId != null) {
      await _prefs.setString(_kKeyActive, _activeId!);
    } else {
      await _prefs.remove(_kKeyActive);
    }
  }

  Future<void> add(Profile profile) async {
    _profiles.add(profile);
    _activeId ??= profile.id;
    await _persist();
    notifyListeners();
  }

  Future<void> update(Profile profile) async {
    final idx = _profiles.indexWhere((p) => p.id == profile.id);
    if (idx < 0) return;
    _profiles[idx] = profile;
    await _persist();
    notifyListeners();
  }

  Future<void> remove(String id) async {
    _profiles.removeWhere((p) => p.id == id);
    if (_activeId == id) {
      _activeId = _profiles.isEmpty ? null : _profiles.first.id;
    }
    await _persist();
    notifyListeners();
  }

  Future<void> setActive(String id) async {
    if (!_profiles.any((p) => p.id == id)) return;
    _activeId = id;
    await _persist();
    notifyListeners();
  }
}

extension on Iterable<Profile> {
  Profile? get firstOrNull => isEmpty ? null : first;
}
