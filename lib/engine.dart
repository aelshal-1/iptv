import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// One selectable audio or subtitle track.
class TrackOpt {
  final String id, label, lang;
  const TrackOpt(this.id, this.label, this.lang);
}

class TrackSet {
  final List<TrackOpt> audio, subs;
  final String? audioSel, subSel; // subSel null = subtitles off
  const TrackSet(this.audio, this.subs, this.audioSel, this.subSel);
  static const empty = TrackSet([], [], null, null);
}

/// Playback engine used by the player screen: libmpv (all formats) or AVPlayer (iOS, with PiP).
abstract class Engine {
  void Function(bool playing, bool buffering, Duration pos, Duration dur)? onState;
  void Function()? onCompleted;
  void Function(String message)? onError;
  void Function()? onTracks;
  void Function(int w, int h)? onSize;
  void Function(bool active)? onPip;

  bool get isNative;
  Widget view();
  Future<void> open(String url, {int? startMs});
  Future<void> playOrPause();
  Future<void> pause();
  Future<void> seek(Duration d);
  Future<TrackSet> tracks();
  Future<void> selectAudio(String id);
  Future<void> selectSub(String? id);
  Future<bool> pipSupported() async => false;
  Future<void> startPip() async {}
  Future<void> dispose();
}

/* ======================= libmpv (media_kit) ======================= */
class MpvEngine extends Engine {
  final Player _p = Player(configuration: PlayerConfiguration(title: 'IPTV Player', bufferSize: 64 * 1024 * 1024));
  late final VideoController _vc = VideoController(_p);
  final List<StreamSubscription> _subs = [];
  bool _playing = false, _buffering = true;
  Duration _pos = Duration.zero, _dur = Duration.zero;
  int? _pendingSeek;
  int _w = 0, _h = 0;

  MpvEngine() {
    final s = _p.stream;
    void emit() => onState?.call(_playing, _buffering, _pos, _dur);
    _subs.addAll([
      s.playing.listen((v) {
        _playing = v;
        emit();
      }),
      s.buffering.listen((v) {
        _buffering = v;
        emit();
      }),
      s.position.listen((v) {
        _pos = v;
        emit();
      }),
      s.duration.listen((v) {
        _dur = v;
        emit();
        if (_pendingSeek != null && v > Duration.zero) {
          final ms = _pendingSeek!;
          _pendingSeek = null;
          if (ms < v.inMilliseconds - 5000) _p.seek(Duration(milliseconds: ms));
        }
      }),
      s.tracks.listen((_) => onTracks?.call()),
      s.track.listen((_) => onTracks?.call()),
      s.completed.listen((d) {
        if (d) onCompleted?.call();
      }),
      s.error.listen((e) {
        if (_pos == Duration.zero) onError?.call(e);
      }),
      s.width.listen((w) {
        _w = w ?? 0;
        if (_w > 0 && _h > 0) onSize?.call(_w, _h);
      }),
      s.height.listen((h) {
        _h = h ?? 0;
        if (_w > 0 && _h > 0) onSize?.call(_w, _h);
      }),
    ]);
  }

  @override
  bool get isNative => false;

  @override
  Widget view() => Video(
        controller: _vc,
        controls: NoVideoControls,
        fill: Colors.black,
        subtitleViewConfiguration: SubtitleViewConfiguration(
          style: const TextStyle(fontSize: 26, color: Colors.white, backgroundColor: Color(0x99000000), height: 1.3),
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
        ),
      );

  @override
  Future<void> open(String url, {int? startMs}) async {
    _pos = Duration.zero;
    _dur = Duration.zero;
    _pendingSeek = (startMs != null && startMs > 0) ? startMs : null;
    await _p.open(Media(url));
  }

  @override
  Future<void> playOrPause() => _p.playOrPause();
  @override
  Future<void> pause() => _p.pause();
  @override
  Future<void> seek(Duration d) => _p.seek(d);

  bool _real(String id) => id != 'auto' && id != 'no';
  String _label(String? title, String? lang, int n) {
    final parts = [if ((title ?? '').isNotEmpty) title!, if ((lang ?? '').isNotEmpty) lang!.toUpperCase()];
    return parts.isEmpty ? '#$n' : parts.join(' · ');
  }

  @override
  Future<TrackSet> tracks() async {
    final t = _p.state.tracks, cur = _p.state.track;
    final subs = t.subtitle.where((s) => _real(s.id)).toList();
    final auds = t.audio.where((s) => _real(s.id)).toList();
    return TrackSet(
      [for (var i = 0; i < auds.length; i++) TrackOpt(auds[i].id, _label(auds[i].title, auds[i].language, i + 1), auds[i].language ?? '')],
      [for (var i = 0; i < subs.length; i++) TrackOpt(subs[i].id, _label(subs[i].title, subs[i].language, i + 1), subs[i].language ?? '')],
      cur.audio.id,
      cur.subtitle.id == 'no' ? null : cur.subtitle.id,
    );
  }

  @override
  Future<void> selectAudio(String id) async {
    for (final a in _p.state.tracks.audio) {
      if (a.id == id) return _p.setAudioTrack(a);
    }
  }

  @override
  Future<void> selectSub(String? id) async {
    if (id == null) return _p.setSubtitleTrack(SubtitleTrack.no());
    for (final s in _p.state.tracks.subtitle) {
      if (s.id == id) return _p.setSubtitleTrack(s);
    }
  }

  @override
  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    await _p.dispose();
  }
}

/* ======================= AVPlayer (iOS, PiP) ======================= */
class AvEngine extends Engine {
  static const _m = MethodChannel('iptv/avplayer');
  static const _e = EventChannel('iptv/avplayer/events');
  StreamSubscription? _sub;
  bool _playing = false, _ready = false;

  AvEngine() {
    _sub = _e.receiveBroadcastStream().listen((ev) {
      if (ev is! Map) return;
      switch (ev['type']) {
        case 'tick':
          _playing = ev['playing'] == true;
          onState?.call(
            _playing,
            ev['buffering'] == true || !_ready,
            Duration(milliseconds: (ev['pos'] as num? ?? 0).toInt()),
            Duration(milliseconds: (ev['dur'] as num? ?? 0).toInt()),
          );
          break;
        case 'ready':
          _ready = true;
          onTracks?.call();
          break;
        case 'completed':
          onCompleted?.call();
          break;
        case 'error':
          onError?.call('${ev['message']}');
          break;
        case 'pip':
          onPip?.call(ev['active'] == true);
          break;
      }
    });
  }

  static bool get available => Platform.isIOS;

  @override
  bool get isNative => true;

  @override
  Widget view() => const UiKitView(
        viewType: 'iptv/avplayer_view',
        hitTestBehavior: PlatformViewHitTestBehavior.transparent,
      );

  @override
  Future<void> open(String url, {int? startMs}) async {
    _ready = false;
    await _m.invokeMethod('open', {'url': url, 'start': startMs ?? 0});
  }

  @override
  Future<void> playOrPause() => _m.invokeMethod(_playing ? 'pause' : 'play');
  @override
  Future<void> pause() => _m.invokeMethod('pause');
  @override
  Future<void> seek(Duration d) => _m.invokeMethod('seek', {'ms': d.inMilliseconds});

  @override
  Future<TrackSet> tracks() async {
    final r = await _m.invokeMethod('tracks');
    if (r is! Map) return TrackSet.empty;
    List<TrackOpt> list(Object? l) => (l as List? ?? []).whereType<Map>().map((e) => TrackOpt('${e['id']}', '${e['label']}', '${e['lang'] ?? ''}')).toList();
    final a = (r['audioSel'] as num? ?? -1).toInt(), s = (r['subSel'] as num? ?? -1).toInt();
    return TrackSet(list(r['audio']), list(r['subs']), a >= 0 ? '$a' : null, s >= 0 ? '$s' : null);
  }

  @override
  Future<void> selectAudio(String id) => _m.invokeMethod('selectAudio', {'index': int.tryParse(id) ?? -1});
  @override
  Future<void> selectSub(String? id) => _m.invokeMethod('selectSub', {'index': id == null ? -1 : int.tryParse(id) ?? -1});

  @override
  Future<bool> pipSupported() async => (await _m.invokeMethod('pipSupported')) == true;
  @override
  Future<void> startPip() => _m.invokeMethod('startPip');

  @override
  Future<void> dispose() async {
    await _sub?.cancel();
    try {
      await _m.invokeMethod('dispose');
    } catch (_) {}
  }
}

/* ======================= Android activity PiP ======================= */
class AndroidPip {
  static const _c = MethodChannel('iptv/pip');
  static void Function(bool active)? onChanged;
  static void Function()? onStopped;
  static bool _init = false;

  static void _ensure() {
    if (_init) return;
    _init = true;
    _c.setMethodCallHandler((call) async {
      if (call.method == 'pipChanged') onChanged?.call(call.arguments == true);
      if (call.method == 'stopped') onStopped?.call();
    });
  }

  static Future<bool> supported() async {
    if (!Platform.isAndroid) return false;
    _ensure();
    try {
      return (await _c.invokeMethod('isSupported')) == true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setAuto(bool enabled, {int w = 16, int h = 9}) async {
    if (!Platform.isAndroid) return;
    _ensure();
    try {
      await _c.invokeMethod('setAuto', {'enabled': enabled, 'w': w, 'h': h});
    } catch (_) {}
  }

  static Future<void> enter() async {
    try {
      await _c.invokeMethod('enter');
    } catch (_) {}
  }
}
