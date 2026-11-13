import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'store.dart';

typedef J = Map<String, dynamic>;

class ApiError implements Exception {
  final String code; // missing | auth | status | timeout | http | net | parse
  final int? status;
  ApiError(this.code, [this.status]);
  @override
  String toString() => 'ApiError($code${status != null ? ' $status' : ''})';
}

class Account {
  final String url, user, pass;
  final J info;
  Account(this.url, this.user, this.pass, this.info);
  J toJson() => {'url': url, 'user': user, 'pass': pass, 'info': info};
  static Account? fromJson(dynamic j) {
    if (j is! Map) return null;
    return Account('${j['url']}', '${j['user']}', '${j['pass'] ?? ''}', Map<String, dynamic>.from((j['info'] as Map?) ?? {}));
  }
}

/// Sync progress: overall fraction 0..1, current step label key, bytes so far.
class SyncProgress {
  final double frac;
  final int step, steps;
  final String labelKey;
  final int bytes;
  final bool saving;
  SyncProgress(this.frac, this.step, this.steps, this.labelKey, this.bytes, {this.saving = false});
}

List<dynamic> _decodeList(String body) {
  final d = jsonDecode(body);
  if (d is List) return d;
  if (d is Map) return d.values.toList();
  return [];
}

String _encode(Object o) => jsonEncode(o);
dynamic _decode(String s) => jsonDecode(s);

/// Xtream Codes client. The whole catalog is downloaded once and kept in a file;
/// lists and search are then served from memory. Details, episodes and EPG stay live.
class Api {
  Api._();
  static final Api i = Api._();

  Account? acc;
  J? lib; // liveCats, vodCats, seriesCats, live, vod, series, at
  final Map<String, Map<String, List<J>>> _idx = {};
  final Map<String, dynamic> _cache = {};

  static const kinds = {
    'live': ['get_live_categories', 'get_live_streams', 'liveCats'],
    'vod': ['get_vod_categories', 'get_vod_streams', 'vodCats'],
    'series': ['get_series_categories', 'get_series', 'seriesCats'],
  };
  static const _keep = {
    'live': ['num', 'name', 'stream_id', 'stream_icon', 'category_id', 'category_ids', 'epg_channel_id', 'tv_archive'],
    'vod': ['num', 'name', 'stream_id', 'stream_icon', 'rating', 'added', 'category_id', 'category_ids', 'container_extension', 'year'],
    'series': ['num', 'name', 'series_id', 'cover', 'rating', 'genre', 'releaseDate', 'last_modified', 'category_id', 'category_ids'],
  };

  static String normalizeUrl(String u) {
    u = u.trim();
    if (u.isEmpty) return '';
    if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(u)) u = 'http://$u';
    u = u.replaceAll(RegExp(r'/(player_api|get|xmltv)\.php.*$', caseSensitive: false), '');
    return u.replaceAll(RegExp(r'/+$'), '');
  }

  String _base(Account a) => '${a.url}/player_api.php?username=${Uri.encodeQueryComponent(a.user)}&password=${Uri.encodeQueryComponent(a.pass)}';

  Future<String> _get(String url, {Duration timeout = const Duration(seconds: 45), void Function(int loaded, int total)? onProgress}) async {
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(url));
      final res = await client.send(req).timeout(const Duration(seconds: 25));
      if (res.statusCode < 200 || res.statusCode >= 300) throw ApiError('http', res.statusCode);
      final total = res.contentLength ?? 0;
      final bytes = <int>[];
      final done = Completer<void>();
      late StreamSubscription sub;
      Timer? idle;
      void resetIdle() {
        idle?.cancel();
        idle = Timer(timeout, () {
          sub.cancel();
          if (!done.isCompleted) done.completeError(ApiError('timeout'));
        });
      }

      resetIdle();
      sub = res.stream.listen((chunk) {
        bytes.addAll(chunk);
        resetIdle();
        onProgress?.call(bytes.length, total);
      }, onDone: () {
        idle?.cancel();
        if (!done.isCompleted) done.complete();
      }, onError: (e) {
        idle?.cancel();
        if (!done.isCompleted) done.completeError(ApiError('net'));
      }, cancelOnError: true);
      await done.future;
      onProgress?.call(bytes.length, bytes.length);
      return utf8.decode(bytes, allowMalformed: true);
    } on ApiError {
      rethrow;
    } on TimeoutException {
      throw ApiError('timeout');
    } on SocketException {
      throw ApiError('net');
    } on HandshakeException {
      throw ApiError('net');
    } on http.ClientException {
      throw ApiError('net');
    } finally {
      client.close();
    }
  }

  Future<dynamic> _call(String action, {Map<String, String> params = const {}, bool cache = true, void Function(int, int)? onProgress, Duration timeout = const Duration(seconds: 45)}) async {
    final a = acc!;
    var q = '&action=$action';
    params.forEach((k, v) {
      if (v.isNotEmpty) q += '&$k=${Uri.encodeQueryComponent(v)}';
    });
    if (cache && _cache.containsKey(q)) return _cache[q];
    final body = await _get(_base(a) + q, onProgress: onProgress, timeout: timeout);
    dynamic data;
    try {
      data = body.length > 200000 ? await compute(_decode, body) : jsonDecode(body);
    } catch (_) {
      throw ApiError('parse');
    }
    if (cache) _cache[q] = data;
    return data;
  }

  /* ---------------- account ---------------- */
  Future<Account> login(String url, String user, String pass) async {
    final a0 = Account(normalizeUrl(url), user.trim(), pass, {});
    if (a0.url.isEmpty || a0.user.isEmpty) throw ApiError('missing');
    final body = await _get(_base(a0), timeout: const Duration(seconds: 20));
    dynamic d;
    try {
      d = jsonDecode(body);
    } catch (_) {
      throw ApiError('parse');
    }
    final ui = (d is Map) ? d['user_info'] : null;
    if (ui is! Map || '${ui['auth']}' != '1') throw ApiError('auth');
    final st = '${ui['status'] ?? ''}'.toLowerCase();
    if (st.isNotEmpty && st != 'active') throw ApiError('status');
    final a = Account(a0.url, a0.user, a0.pass, Map<String, dynamic>.from(ui));
    acc = a;
    lib = null;
    _idx.clear();
    _cache.clear();
    await Store.set('account', a.toJson());
    await Store.set('lastLogin', {'url': a.url, 'user': a.user});
    return a;
  }

  bool restore() {
    acc = Account.fromJson(Store.get('account'));
    return acc != null;
  }

  Future<void> logout() async {
    final f = await _libFile();
    acc = null;
    lib = null;
    _idx.clear();
    _cache.clear();
    await Store.set('account', null);
    try {
      if (f != null && await f.exists()) await f.delete();
    } catch (_) {}
  }

  /* ---------------- library ---------------- */
  Future<File?> _libFile() async {
    if (acc == null) return null;
    final dir = await getApplicationSupportDirectory();
    final key = base64Url.encode(utf8.encode('${acc!.user}@${acc!.url}')).replaceAll('=', '');
    return File('${dir.path}/lib_$key.json');
  }

  Future<bool> loadLibrary() async {
    try {
      final f = await _libFile();
      if (f == null || !await f.exists()) return false;
      final s = await f.readAsString();
      final d = await compute(_decode, s);
      if (d is Map && d['live'] != null && d['vod'] != null && d['series'] != null) {
        lib = Map<String, dynamic>.from(d);
        _idx.clear();
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<void> _saveLibrary() async {
    lib!['at'] = DateTime.now().millisecondsSinceEpoch;
    final f = await _libFile();
    if (f == null) return;
    final s = await compute(_encode, lib! as Object);
    await f.writeAsString(s, flush: true);
  }

  DateTime? get libraryDate => lib?['at'] is int ? DateTime.fromMillisecondsSinceEpoch(lib!['at'] as int) : null;

  int _sizeOf(String key) => ((Store.get('sizes') as Map?)?[key] as num?)?.toInt() ?? 0;
  void _rememberSize(String key, int bytes) {
    if (bytes <= 0) return;
    final z = Map<String, dynamic>.from((Store.get('sizes') as Map?) ?? {});
    z[key] = bytes;
    Store.set('sizes', z);
  }

  double _part(int loaded, int total, String key) {
    final t = total > 0 ? total : _sizeOf(key);
    if (t > 0) return math.min(0.99, loaded / t);
    return 1 - math.exp(-loaded / 6291456);
  }

  static List<J> _slim(String kind, List<dynamic> list) {
    final keep = _keep[kind]!;
    return list.whereType<Map>().map((s) {
      final o = <String, dynamic>{};
      for (final k in keep) {
        final v = s[k];
        if (v != null && v != '') o[k] = v;
      }
      return o;
    }).toList();
  }

  static List<J> _slimArgs(List<Object> a) => _slim(a[0] as String, _decodeList(a[1] as String));

  Future<List<J>> _fetchList(String kind, String action, {String cat = '', void Function(int, int)? onProgress, Duration timeout = const Duration(seconds: 90)}) async {
    final a = acc!;
    var url = '${_base(a)}&action=$action';
    if (cat.isNotEmpty) url += '&category_id=${Uri.encodeQueryComponent(cat)}';
    final body = await _get(url, onProgress: onProgress, timeout: timeout);
    try {
      return await compute(_slimArgs, <Object>[kind, body]);
    } catch (_) {
      throw ApiError('parse');
    }
  }

  Future<void> syncAll(void Function(SyncProgress) progress) async {
    final steps = [
      ['liveCats', 'get_live_categories', '', 's_live_cats', 2],
      ['vodCats', 'get_vod_categories', '', 's_vod_cats', 2],
      ['seriesCats', 'get_series_categories', '', 's_series_cats', 2],
      ['live', 'get_live_streams', 'live', 's_live', 20],
      ['vod', 'get_vod_streams', 'vod', 's_vod', 40],
      ['series', 'get_series', 'series', 's_series', 30],
    ];
    final totalW = steps.fold<int>(0, (s, e) => s + (e[4] as int)) + 4;
    var doneW = 0, bytesAll = 0;
    final fresh = <String, dynamic>{};
    for (var i = 0; i < steps.length; i++) {
      final s = steps[i];
      final key = 'all.${s[1]}';
      var last = 0;
      void rep(double part) => progress(SyncProgress((doneW + (s[4] as int) * part) / totalW, i + 1, steps.length, s[3] as String, bytesAll + last));
      rep(0);
      void onP(int loaded, int total) {
        last = loaded;
        rep(_part(loaded, total, key));
      }

      if ((s[2] as String).isEmpty) {
        final body = await _get('${_base(acc!)}&action=${s[1]}', onProgress: onP, timeout: const Duration(seconds: 60));
        try {
          fresh[s[0] as String] = _decodeList(body);
        } catch (_) {
          throw ApiError('parse');
        }
      } else {
        fresh[s[0] as String] = await _fetchList(s[2] as String, s[1] as String, onProgress: onP, timeout: const Duration(seconds: 120));
      }
      _rememberSize(key, last);
      bytesAll += last;
      doneW += s[4] as int;
    }
    progress(SyncProgress(doneW / totalW, steps.length, steps.length, 'saving', bytesAll, saving: true));
    lib = fresh;
    _idx.clear();
    await _saveLibrary();
    progress(SyncProgress(1, steps.length, steps.length, 'done', bytesAll));
  }

  /// Re-download one category ('' or 'all' = everything of that kind). Returns item count.
  Future<int> refreshCategory(String kind, String cat, void Function(double frac, int bytes, bool saving) progress) async {
    if (lib == null) throw ApiError('net');
    final k = kinds[kind]!;
    final all = cat.isEmpty || cat == 'all';
    final key = all ? 'all.${k[1]}' : 'cat.$kind.$cat';
    var last = 0;
    final fresh = await _fetchList(kind, k[1], cat: all ? '' : cat, onProgress: (l, t) {
      last = l;
      progress(_part(l, t, key) * 0.95, l, false);
    });
    _rememberSize(key, last);
    progress(0.97, last, true);
    if (all) {
      lib![kind] = fresh;
    } else {
      final seen = fresh.map((e) => '${e['stream_id'] ?? e['series_id']}').toSet();
      final keep = <dynamic>[];
      for (final o in (lib![kind] as List)) {
        final cs = _catsOf(o as Map);
        final inCat = cs.contains(cat);
        if ((!inCat || cs.length > 1) && !seen.contains('${o['stream_id'] ?? o['series_id']}')) keep.add(o);
      }
      lib![kind] = [...keep, ...fresh];
    }
    try {
      final cats = await _call(k[0], cache: false);
      if (cats is List) lib![k[2]] = cats;
    } catch (_) {}
    _idx.clear();
    await _saveLibrary();
    return fresh.length;
  }

  static List<String> _catsOf(Map x) {
    final ids = x['category_ids'];
    if (ids is List && ids.isNotEmpty) return ids.map((e) => '$e').toList();
    return ['${x['category_id']}'];
  }

  List<J> categories(String kind) {
    final l = lib?[kinds[kind]![2]];
    if (l is! List) return [];
    return l.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  List<J> items(String kind, [String cat = '']) {
    final l = lib?[kind];
    if (l is! List) return [];
    if (cat.isEmpty || cat == 'all') return l.whereType<Map>().map((e) => e as J).toList();
    var map = _idx[kind];
    if (map == null) {
      map = {};
      for (final o in l) {
        if (o is! Map) continue;
        for (final c in _catsOf(o)) {
          (map[c] ??= []).add(o as J);
        }
      }
      _idx[kind] = map;
    }
    return map[cat] ?? [];
  }

  /* ---------------- live details ---------------- */
  Future<J> vodInfo(Object id) async => Map<String, dynamic>.from((await _call('get_vod_info', params: {'vod_id': '$id'})) as Map);
  Future<J> seriesInfo(Object id) async => Map<String, dynamic>.from((await _call('get_series_info', params: {'series_id': '$id'})) as Map);
  Future<List<J>> shortEpg(Object id) async {
    final d = await _call('get_short_epg', params: {'stream_id': '$id', 'limit': '3'}, cache: false);
    final l = (d is Map) ? d['epg_listings'] : null;
    if (l is! List) return [];
    return l.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  static String b64(Object? s) {
    if (s == null) return '';
    try {
      return utf8.decode(base64.decode('$s'), allowMalformed: true);
    } catch (_) {
      return '$s';
    }
  }

  /* ---------------- stream URLs ---------------- */
  String _p(String s) => Uri.encodeComponent(s);
  String liveUrl(Object id) {
    final f = (acc!.info['allowed_output_formats'] as List?)?.map((e) => '$e').toList() ?? [];
    final ext = f.isEmpty || f.contains('ts') ? 'ts' : 'm3u8';
    return '${acc!.url}/live/${_p(acc!.user)}/${_p(acc!.pass)}/$id.$ext';
  }

  String movieUrl(Object id, Object? ext) => '${acc!.url}/movie/${_p(acc!.user)}/${_p(acc!.pass)}/$id.${ext ?? 'mp4'}';
  String episodeUrl(Object id, Object? ext) => '${acc!.url}/series/${_p(acc!.user)}/${_p(acc!.pass)}/$id.${ext ?? 'mp4'}';
}

String errText(Object e, String Function(String) tr) {
  if (e is ApiError) {
    switch (e.code) {
      case 'missing':
        return tr('err_missing');
      case 'auth':
        return tr('err_auth');
      case 'status':
        return tr('err_status');
      case 'timeout':
        return tr('err_timeout');
      case 'http':
        return '${tr('err_net')} (${e.status})';
    }
  }
  return tr('err_net');
}

String mb(int bytes) => '${(bytes / 1048576).toStringAsFixed(bytes < 10485760 ? 1 : 0)} MB';
