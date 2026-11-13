import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Small settings + favorites + watch progress, kept in SharedPreferences.
class Store {
  static late SharedPreferences _p;

  /// Bumped on every change so screens can rebuild (favorites, progress, order…).
  static final tick = ValueNotifier<int>(0);
  static Future<void> init() async => _p = await SharedPreferences.getInstance();

  static dynamic get(String k) {
    final s = _p.getString(k);
    if (s == null) return null;
    try {
      return jsonDecode(s);
    } catch (_) {
      return null;
    }
  }

  static Future<void> set(String k, dynamic v) async {
    if (v == null) {
      await _p.remove(k);
    } else {
      await _p.setString(k, jsonEncode(v));
    }
    tick.value++;
  }

  /* ---- category order / hidden per kind ---- */
  static List<String> strList(String k) => ((get(k) as List?) ?? []).map((e) => '$e').toList();

  /* ---- favorites: [{type, id, name, icon, ext, rating, num}] ---- */
  static List<Map<String, dynamic>> favs() => ((get('favs') as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  static bool isFav(String type, Object? id) => favs().any((f) => f['type'] == type && '${f['id']}' == '$id');

  /// Returns true if it is now a favorite.
  static bool toggleFav(String type, Map<String, dynamic> x) {
    final f = favs();
    final id = x['stream_id'] ?? x['series_id'] ?? x['id'];
    final i = f.indexWhere((e) => e['type'] == type && '${e['id']}' == '$id');
    if (i >= 0) {
      f.removeAt(i);
      set('favs', f);
      return false;
    }
    f.insert(0, {
      'type': type,
      'id': id,
      'name': x['name'],
      'icon': x['stream_icon'] ?? x['cover'],
      'ext': x['container_extension'],
      'rating': x['rating'],
      'num': x['num'],
    });
    set('favs', f);
    return true;
  }

  /* ---- continue watching: [{key, type, id, name, sub, icon, ext, pos, dur, seriesId, season, cover}] ---- */
  static List<Map<String, dynamic>> recent() => ((get('recent') as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  static void saveProgress(Map<String, dynamic> r) {
    final list = recent()..removeWhere((e) => e['key'] == r['key']);
    final pos = (r['pos'] as num?)?.toInt() ?? 0, dur = (r['dur'] as num?)?.toInt() ?? 0;
    if (dur > 0 && pos > 30000 && pos < dur - 120000) list.insert(0, r);
    set('recent', list.take(20).toList());
  }

  static Map<String, dynamic>? progressOf(String key) {
    for (final r in recent()) {
      if (r['key'] == key) return r;
    }
    return null;
  }
}
