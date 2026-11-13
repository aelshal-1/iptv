import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../api.dart';
import '../cast.dart';
import '../engine.dart';
import '../l10n.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'detail.dart' show episodesBySeason, episodePlayItems, firstImage;

class PlayItem {
  final String key, type, id, title, url;
  final String? ext, sub, icon, seriesId, season;
  const PlayItem({
    required this.key,
    required this.type,
    required this.id,
    required this.title,
    required this.url,
    this.ext,
    this.sub,
    this.icon,
    this.seriesId,
    this.season,
  });
  bool get isLive => type == 'live';

  static const _nativeExt = {'mp4', 'm4v', 'mov', 'm3u8'};

  /// URL the iOS native player (with Picture in Picture) can play, or null.
  String? get nativeUrl {
    if (isLive) return Api.i.liveHlsUrl(id);
    final e = (ext ?? url.split('.').last).toLowerCase();
    return _nativeExt.contains(e) ? url : null;
  }
}

class PlayerScreen extends StatefulWidget {
  final List<PlayItem> items;
  final int index;
  final int? startMs;
  const PlayerScreen({super.key, required this.items, required this.index, this.startMs});

  static Future<void> _push(BuildContext context, PlayerScreen p) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => p, fullscreenDialog: true));

  static void openLive(BuildContext context, List<J> channels, int index) {
    final items = channels
        .map((c) => PlayItem(
              key: 'live:${c['stream_id']}',
              type: 'live',
              id: '${c['stream_id']}',
              title: nameOf(c),
              sub: c['num'] != null ? '${c['num']}' : null,
              icon: iconOf(c),
              url: Api.i.liveUrl(c['stream_id']),
            ))
        .toList();
    _push(context, PlayerScreen(items: items, index: index));
  }

  static void openVod(BuildContext context, List<PlayItem> items, int index, {int? startMs}) =>
      _push(context, PlayerScreen(items: items, index: index, startMs: startMs));

  static void resumeRecent(BuildContext context, Map r) {
    final type = '${r['type']}';
    final id = '${r['id']}';
    final ext = r['ext'] == null ? null : '${r['ext']}';
    final item = PlayItem(
      key: '${r['key']}',
      type: type,
      id: id,
      ext: ext,
      title: '${r['name'] ?? ''}',
      sub: r['sub'] == null ? null : '${r['sub']}',
      icon: r['icon'] == null ? null : '${r['icon']}',
      url: type == 'episode' ? Api.i.episodeUrl(id, ext) : Api.i.movieUrl(id, ext),
      seriesId: r['seriesId'] == null ? null : '${r['seriesId']}',
      season: r['season'] == null ? null : '${r['season']}',
    );
    openVod(context, [item], 0, startMs: (r['pos'] as num?)?.toInt());
  }

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> with WidgetsBindingObserver {
  Engine? _engine;
  late List<PlayItem> _items = [...widget.items];
  late int _i = widget.index;
  bool _tracksApplied = false;
  bool _nativeFailed = false;

  bool _controls = true;
  Timer? _hideTimer;
  bool _playing = false, _buffering = true;
  Duration _pos = Duration.zero, _dur = Duration.zero;
  double? _dragMs;
  String? _error;
  String _epg = '';
  DateTime _lastSave = DateTime.fromMillisecondsSinceEpoch(0);

  bool _pipSupported = false, _inPip = false;

  // Chromecast
  String? _castDevice; // set while this screen is casting
  bool _castPlaying = true;
  StreamSubscription? _castSub;

  // lock + swipe gestures (left half brightness, right half volume)
  bool _locked = false, _lockHint = false;
  Timer? _lockTimer;
  double _bright = 0.5, _vol = 0.5;
  String? _gesture; // 'bright' | 'vol'
  Timer? _gestureTimer;

  PlayItem get _cur => _items[_i];
  bool get _hasNext => !_cur.isLive && _i < _items.length - 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable();
    if (Platform.isAndroid) {
      AndroidPip.onChanged = (v) => _set(() {
            _inPip = v;
            if (v) _controls = false;
          });
      AndroidPip.onStopped = () => _engine?.pause();
      AndroidPip.supported().then((v) {
        _set(() => _pipSupported = v);
        if (v) AndroidPip.setAuto(true);
      });
    }
    _play(widget.startMs);
    _maybeLoadSeries();
    _armHide();
    _initLevels();
  }

  Future<void> _initLevels() async {
    try {
      _bright = await ScreenBrightness.instance.application;
    } catch (_) {}
    try {
      VolumeController.instance.showSystemUI = false;
      _vol = await VolumeController.instance.getVolume();
    } catch (_) {}
  }

  /* ---------------- Chromecast ---------------- */
  Future<void> _startCast() async {
    final dev = await pickCastDevice(context);
    if (dev == null || !mounted) return;
    final c = _cur;
    final url = c.isLive ? (Api.i.liveHlsUrl(c.id) ?? c.url) : c.url;
    final at = _pos;
    // Free the stream first: the account may allow only one connection.
    final e = _engine;
    _engine = null;
    _save();
    setState(() {
      _castDevice = dev.friendlyName;
      _castPlaying = true;
      _controls = true;
    });
    await e?.dispose();
    bool ok = false;
    try {
      ok = await Cast.play(dev, url: url, title: c.title, subtitle: c.sub, image: c.icon, live: c.isLive, start: at);
    } catch (_) {}
    if (!mounted) return;
    if (!ok) {
      toast2(tr('cast_failed'));
      _stopCast(resume: true, at: at);
      return;
    }
    _castSub?.cancel();
    _castSub = GoogleCastRemoteMediaClient.instance.mediaStatusStream.listen((st) {
      _set(() => _castPlaying = st?.playerState != CastMediaPlayerState.paused);
    });
  }

  Future<void> _stopCast({bool resume = true, Duration? at}) async {
    final pos = at ?? Cast.position;
    _castSub?.cancel();
    _castSub = null;
    await Cast.stop();
    if (!mounted) return;
    setState(() => _castDevice = null);
    if (resume) _play(_cur.isLive ? null : pos.inMilliseconds);
  }

  void toast2(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  Widget _castPanel() => Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cast_connected_rounded, size: 64, color: C.gold),
          const SizedBox(height: 14),
          Text('${tr('casting_to')} $_castDevice', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(_cur.title, style: const TextStyle(color: C.dim)),
          const SizedBox(height: 22),
          Row(mainAxisSize: MainAxisSize.min, children: [
            _RoundBtn(
              icon: _castPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              big: true,
              onTap: () {
                Cast.togglePlay();
                setState(() => _castPlaying = !_castPlaying);
              },
            ),
          ]),
          const SizedBox(height: 22),
          OutlinedButton.icon(
            onPressed: () => _stopCast(),
            icon: const Icon(Icons.cast),
            label: Text(tr('stop_casting')),
          ),
        ]),
      );

  /* ---------------- lock ---------------- */
  void _lock() {
    _hideTimer?.cancel();
    setState(() {
      _locked = true;
      _controls = false;
    });
    _flashLockHint();
  }

  void _unlock() {
    _lockTimer?.cancel();
    setState(() {
      _locked = false;
      _lockHint = false;
      _controls = true;
    });
    _armHide();
  }

  void _flashLockHint() {
    _lockTimer?.cancel();
    setState(() => _lockHint = true);
    _lockTimer = Timer(const Duration(seconds: 3), () => _set(() => _lockHint = false));
  }

  /* ---------------- brightness / volume swipe ---------------- */
  void _dragStart(DragStartDetails d) {
    if (_locked || _inPip) return;
    final w = MediaQuery.of(context).size.width;
    _gestureTimer?.cancel();
    setState(() => _gesture = d.localPosition.dx < w / 2 ? 'bright' : 'vol');
  }

  void _dragUpdate(DragUpdateDetails d) {
    final g = _gesture;
    if (g == null) return;
    final h = MediaQuery.of(context).size.height;
    final delta = -d.delta.dy / (h * 0.8);
    if (g == 'bright') {
      final v = (_bright + delta).clamp(0.0, 1.0).toDouble();
      setState(() => _bright = v);
      ScreenBrightness.instance.setApplicationScreenBrightness(v).catchError((_) {});
    } else {
      final v = (_vol + delta).clamp(0.0, 1.0).toDouble();
      setState(() => _vol = v);
      VolumeController.instance.setVolume(v).catchError((_) {});
    }
  }

  void _dragEnd([DragEndDetails? _]) {
    _gestureTimer?.cancel();
    _gestureTimer = Timer(const Duration(milliseconds: 700), () => _set(() => _gesture = null));
  }

  Widget _levelIndicator() {
    final bright = _gesture == 'bright';
    final v = bright ? _bright : _vol;
    final icon = bright
        ? (v < 0.3 ? Icons.brightness_low_rounded : (v < 0.7 ? Icons.brightness_medium_rounded : Icons.brightness_high_rounded))
        : (v == 0 ? Icons.volume_off_rounded : (v < 0.5 ? Icons.volume_down_rounded : Icons.volume_up_rounded));
    return Center(
      child: Container(
        width: 170,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          Icon(icon, color: Colors.white, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: v, minHeight: 6, backgroundColor: Colors.white24, color: C.gold),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(width: 32, child: Text('${(v * 100).round()}', textAlign: TextAlign.end, style: const TextStyle(fontSize: 13))),
        ]),
      ),
    );
  }

  void _set(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  bool _wantNative(PlayItem it) => Platform.isIOS && !_nativeFailed && it.nativeUrl != null;

  /// Create (or swap) the engine that fits the current item.
  Future<Engine> _engineFor(PlayItem it) async {
    final native = _wantNative(it);
    final e = _engine;
    if (e != null && e.isNative == native) return e;
    _engine = null;
    if (e != null) await e.dispose();
    final n = native ? AvEngine() : MpvEngine();
    n.onState = (playing, buffering, pos, dur) {
      _set(() {
        _playing = playing;
        _buffering = buffering;
        _pos = pos;
        _dur = dur;
      });
      if (DateTime.now().difference(_lastSave).inSeconds >= 5) _save();
    };
    n.onTracks = _applyTrackPrefs;
    n.onCompleted = () {
      if (_hasNext) _go(_i + 1);
    };
    n.onError = (msg) {
      if (n.isNative && !_nativeFailed) {
        // AVPlayer can't play it: fall back to libmpv (no PiP for this one).
        _nativeFailed = true;
        _play(_pos.inMilliseconds > 0 ? _pos.inMilliseconds : null);
        return;
      }
      if (_pos == Duration.zero) _set(() => _error = msg);
    };
    n.onSize = (w, h) {
      if (Platform.isAndroid && _pipSupported) AndroidPip.setAuto(true, w: w, h: h);
    };
    n.onPip = (v) => _set(() => _inPip = v);
    _engine = n;
    if (Platform.isIOS) {
      final ok = native && await n.pipSupported();
      _set(() => _pipSupported = ok);
    }
    _set(() {});
    return n;
  }

  Future<void> _play(int? startMs) async {
    _set(() {
      _error = null;
      _pos = Duration.zero;
      _dur = Duration.zero;
      _buffering = true;
      _tracksApplied = false;
      _epg = '';
    });
    final it = _cur;
    final e = await _engineFor(it);
    if (!mounted) return;
    await e.open(e.isNative ? it.nativeUrl! : it.url, startMs: (startMs != null && startMs > 0) ? startMs : null);
    if (it.isLive) {
      Store.addRecentLive({'id': it.id, 'name': it.title, 'icon': it.icon, 'num': it.sub});
      _loadEpg();
    }
  }

  Future<void> _loadEpg() async {
    final id = _cur.id;
    try {
      final l = await Api.i.shortEpg(id);
      if (!mounted || _cur.id != id) return;
      final now = l.isNotEmpty ? Api.b64(l.first['title']) : '';
      final next = l.length > 1 ? Api.b64(l[1]['title']) : '';
      _set(() => _epg = [if (now.isNotEmpty) now, if (next.isNotEmpty) '${tr('next')}: $next'].join('   ·   '));
    } catch (_) {}
  }

  /// Opened from "continue watching" with one episode: fetch the season so Next works.
  Future<void> _maybeLoadSeries() async {
    final c = _cur;
    if (c.type != 'episode' || _items.length > 1 || c.seriesId == null) return;
    try {
      final d = await Api.i.seriesInfo(c.seriesId!);
      final seasons = episodesBySeason(d);
      final s = c.season != null && seasons.containsKey(c.season) ? c.season! : (seasons.keys.isEmpty ? null : seasons.keys.first);
      if (s == null || !mounted) return;
      final info = (d['info'] as Map?) ?? {};
      final list = episodePlayItems({'series_id': c.seriesId}, '${info['name'] ?? c.title}', firstImage(info['cover']) ?? c.icon, s, seasons[s]!);
      final idx = list.indexWhere((p) => p.key == c.key);
      if (idx >= 0) {
        _set(() {
          _items = list;
          _i = idx;
        });
      }
    } catch (_) {}
  }

  Future<void> _applyTrackPrefs() async {
    final e = _engine;
    if (e == null || _tracksApplied) return;
    final t = await e.tracks();
    if (t.subs.isEmpty && t.audio.length < 2) return;
    _tracksApplied = true;
    final sp = Store.get('subPref');
    if (sp == 'off') {
      await e.selectSub(null);
    } else if (sp is String && sp.isNotEmpty) {
      for (final s in t.subs) {
        if (s.lang == sp) {
          await e.selectSub(s.id);
          break;
        }
      }
    }
    final ap = Store.get('audioPref');
    if (ap is String && ap.isNotEmpty) {
      for (final a in t.audio) {
        if (a.lang == ap) {
          await e.selectAudio(a.id);
          break;
        }
      }
    }
  }

  void _save() {
    _lastSave = DateTime.now();
    final c = _cur;
    if (c.isLive || _dur.inMilliseconds <= 0) return;
    final pos = _pos.inMilliseconds, dur = _dur.inMilliseconds;
    Store.saveProgress({
      'key': c.key,
      'type': c.type,
      'id': c.id,
      'name': c.title,
      'sub': c.sub,
      'icon': c.icon,
      'ext': c.ext,
      'pos': pos,
      'dur': dur,
      'seriesId': c.seriesId,
      'season': c.season,
    });
    // Finished an episode: "continue watching" now points at the next one.
    if (pos >= dur - 120000 && _hasNext) {
      final n = _items[_i + 1];
      Store.saveProgress({
        'key': n.key,
        'type': n.type,
        'id': n.id,
        'name': n.title,
        'sub': n.sub,
        'icon': n.icon,
        'ext': n.ext,
        'pos': 0,
        'dur': 0,
        'seriesId': n.seriesId,
        'season': n.season,
        'upNext': true,
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Keep the exact minute even if the app is closed from the background.
    if (state != AppLifecycleState.resumed) _save();
  }

  void _go(int i) {
    if (i < 0 || i >= _items.length) return;
    _save();
    setState(() => _i = i);
    _nativeFailed = false;
    final p = Store.progressOf(_items[i].key);
    _play(_items[i].isLive ? null : (p?['pos'] as num?)?.toInt());
    _armHide();
  }

  void _armHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _playing) setState(() => _controls = false);
    });
  }

  void _toggleControls() {
    if (_inPip) return;
    if (_locked) {
      _flashLockHint();
      return;
    }
    setState(() => _controls = !_controls);
    if (_controls) _armHide();
  }

  void _seekBy(int sec) {
    final t = _pos + Duration(seconds: sec);
    _engine?.seek(t < Duration.zero ? Duration.zero : t);
    _armHide();
  }

  Future<void> _startPip() async {
    if (Platform.isAndroid) {
      await AndroidPip.enter();
    } else {
      await _engine?.startPip();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _save();
    _hideTimer?.cancel();
    if (Platform.isAndroid) {
      AndroidPip.setAuto(false);
      AndroidPip.onChanged = null;
      AndroidPip.onStopped = null;
    }
    _engine?.dispose();
    _lockTimer?.cancel();
    _gestureTimer?.cancel();
    _castSub?.cancel();
    ScreenBrightness.instance.resetApplicationScreenBrightness().catchError((_) {});
    try {
      VolumeController.instance.showSystemUI = true;
    } catch (_) {}
    WakelockPlus.disable();
    SystemChrome.setPreferredOrientations([]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  String _fmt(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  /* ---------------- sheets ---------------- */
  void _tracksSheet() {
    final e = _engine;
    if (e == null) return;
    _hideTimer?.cancel();
    showModalBottomSheet(
      context: context,
      backgroundColor: C.surface,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        Future<TrackSet> load = e.tracks();
        return StatefulBuilder(
          builder: (ctx, setSheet) => FutureBuilder<TrackSet>(
            future: load,
            builder: (ctx, snap) {
              final t = snap.data ?? TrackSet.empty;
              void after(Future<void> f) => f.then((_) => Future.delayed(const Duration(milliseconds: 250))).then((_) => setSheet(() => load = e.tracks()));
              Widget opt(String label, bool sel, VoidCallback onTap) => ListTile(
                    dense: true,
                    title: Text(label),
                    trailing: sel ? const Icon(Icons.check, color: C.gold) : null,
                    onTap: onTap,
                  );
              return ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
                child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(8, 0, 8, 20), children: [
                  Padding(padding: const EdgeInsets.all(12), child: Text(tr('subtitles'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16))),
                  if (t.subs.isEmpty)
                    Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(tr('no_subs'), style: const TextStyle(color: C.dimmer)))
                  else ...[
                    opt(tr('subs_off'), t.subSel == null, () {
                      Store.set('subPref', 'off');
                      after(e.selectSub(null));
                    }),
                    for (final s in t.subs)
                      opt(s.label, t.subSel == s.id, () {
                        Store.set('subPref', s.lang);
                        after(e.selectSub(s.id));
                      }),
                  ],
                  const Divider(height: 24),
                  Padding(padding: const EdgeInsets.all(12), child: Text(tr('audio'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16))),
                  if (t.audio.length < 2)
                    Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(tr('one_audio'), style: const TextStyle(color: C.dimmer)))
                  else
                    for (final a in t.audio)
                      opt(a.label, t.audioSel == a.id, () {
                        Store.set('audioPref', a.lang);
                        after(e.selectAudio(a.id));
                      }),
                ]),
              );
            },
          ),
        );
      },
    ).whenComplete(_armHide);
  }

  void _channelSheet() {
    _hideTimer?.cancel();
    showModalBottomSheet(
      context: context,
      backgroundColor: C.surface,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.85,
        child: ListView.builder(
          controller: ScrollController(initialScrollOffset: (_i * 64.0 - 120).clamp(0.0, double.infinity).toDouble()),
          itemCount: _items.length,
          itemExtent: 64,
          itemBuilder: (_, n) {
            final it = _items[n];
            return ListTile(
              selected: n == _i,
              selectedTileColor: C.glass,
              leading: SizedBox(width: 52, height: 36, child: NetImg(it.icon, fit: BoxFit.contain)),
              title: Text(it.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: it.sub != null ? Text(it.sub!, style: const TextStyle(color: C.dimmer, fontSize: 12)) : null,
              onTap: () {
                Navigator.pop(ctx);
                _go(n);
              },
            );
          },
        ),
      ),
    ).whenComplete(_armHide);
  }

  /* ---------------- build ---------------- */
  @override
  Widget build(BuildContext context) {
    final c = _cur;
    final e = _engine;
    final video = e == null ? const SizedBox.expand() : KeyedSubtree(key: ValueKey(e), child: e.view());
    if (_castDevice != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(children: [
          Positioned.fill(child: _castPanel()),
          SafeArea(child: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context))),
        ]),
      );
    }
    // Android Picture in Picture: the window shows only the video.
    if (_inPip && Platform.isAndroid) {
      return Scaffold(backgroundColor: Colors.black, body: SizedBox.expand(child: video));
    }
    final durMs = _dur.inMilliseconds.toDouble();
    final posMs = (_dragMs ?? _pos.inMilliseconds.toDouble()).clamp(0.0, durMs > 0 ? durMs : 0.0).toDouble();
    return PopScope(
      canPop: !_locked,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _locked) _flashLockHint();
      },
      child: Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        onVerticalDragStart: _dragStart,
        onVerticalDragUpdate: _dragUpdate,
        onVerticalDragEnd: _dragEnd,
        onVerticalDragCancel: _dragEnd,
        onDoubleTapDown: c.isLive || _locked
            ? null
            : (d) {
                final w = MediaQuery.of(context).size.width;
                _seekBy(d.localPosition.dx < w / 2 ? -10 : 10);
              },
        onDoubleTap: c.isLive || _locked ? null : () {},
        child: Stack(fit: StackFit.expand, children: [
          video,
          if (_buffering && _error == null && !_inPip) const Center(child: CircularProgressIndicator(color: C.gold)),
          if (_error != null)
            Center(
              child: Glass(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.error_outline, color: C.red, size: 36),
                  const SizedBox(height: 8),
                  Text(tr('stream_error'), textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: () => _play(_pos.inMilliseconds), child: Text(tr('try_again'))),
                ]),
              ),
            ),
          IgnorePointer(
            ignoring: !_controls || _locked,
            child: AnimatedOpacity(
              opacity: _controls && !_locked ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: _overlay(c, posMs, durMs),
            ),
          ),
          if (_gesture != null) IgnorePointer(child: _levelIndicator()),
          if (_locked)
            IgnorePointer(
              ignoring: !_lockHint,
              child: AnimatedOpacity(
                opacity: _lockHint ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: SafeArea(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 18),
                      child: Material(
                        color: Colors.black.withValues(alpha: 0.7),
                        shape: const StadiumBorder(),
                        child: InkWell(
                          customBorder: const StadiumBorder(),
                          onTap: _unlock,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.lock_rounded, color: C.gold, size: 20),
                              const SizedBox(width: 8),
                              Text(tr('unlock'), style: const TextStyle(fontWeight: FontWeight.w600)),
                            ]),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      ),
      ),
    );
  }

  Widget _overlay(PlayItem c, double posMs, double durMs) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xCC000000), Colors.transparent, Colors.transparent, Color(0xDD000000)],
          stops: [0, 0.3, 0.6, 1],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Column(children: [
            Row(children: [
              IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
              const SizedBox(width: 4),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Row(children: [
                    if (c.isLive)
                      Container(
                        margin: const EdgeInsetsDirectional.only(end: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(color: C.red, borderRadius: BorderRadius.circular(5)),
                        child: Text(tr('live_badge'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                      ),
                    Flexible(child: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600))),
                  ]),
                  if (c.isLive ? _epg.isNotEmpty : (c.sub ?? '').isNotEmpty)
                    Text(c.isLive ? _epg : c.sub!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.dim, fontSize: 13)),
                ]),
              ),
              if (c.isLive)
                IconButton(
                  tooltip: tr('favorite'),
                  icon: Icon(Store.isFav('live', c.id) ? Icons.star_rounded : Icons.star_border_rounded, color: Store.isFav('live', c.id) ? C.gold : null),
                  onPressed: () {
                    Store.toggleFav('live', {'stream_id': c.id, 'name': c.title, 'stream_icon': c.icon, 'num': c.sub});
                    setState(() {});
                  },
                ),
              if (c.isLive && _items.length > 1) IconButton(tooltip: tr('channel_list'), icon: const Icon(Icons.list_rounded), onPressed: _channelSheet),
              if (Cast.ready) IconButton(tooltip: tr('cast_tv'), icon: const Icon(Icons.cast_rounded), onPressed: _startCast),
              if (Platform.isIOS && (_engine?.isNative ?? false))
                const SizedBox(width: 44, height: 44, child: UiKitView(viewType: 'iptv/airplay_button')),
              if (_pipSupported) IconButton(tooltip: tr('pip'), icon: const Icon(Icons.picture_in_picture_alt_rounded), onPressed: _startPip),
              IconButton(tooltip: tr('subs_audio'), icon: const Icon(Icons.subtitles_outlined), onPressed: _tracksSheet),
              IconButton(tooltip: tr('lock'), icon: const Icon(Icons.lock_open_rounded), onPressed: _lock),
            ]),
            const Spacer(),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (c.isLive)
                _RoundBtn(icon: Icons.skip_previous_rounded, onTap: _i > 0 ? () => _go(_i - 1) : null)
              else
                _RoundBtn(icon: Icons.replay_10_rounded, onTap: () => _seekBy(-10)),
              const SizedBox(width: 28),
              _RoundBtn(
                icon: _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                big: true,
                onTap: () {
                  _engine?.playOrPause();
                  _armHide();
                },
              ),
              const SizedBox(width: 28),
              if (c.isLive)
                _RoundBtn(icon: Icons.skip_next_rounded, onTap: _i < _items.length - 1 ? () => _go(_i + 1) : null)
              else
                _RoundBtn(icon: Icons.forward_10_rounded, onTap: () => _seekBy(10)),
            ]),
            const Spacer(),
            if (!c.isLive)
              Row(children: [
                Text(_fmt(Duration(milliseconds: posMs.toInt())), style: const TextStyle(fontSize: 12, fontFeatures: [FontFeature.tabularFigures()])),
                Expanded(
                  child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: Slider(
                      value: posMs,
                      max: durMs > 0 ? durMs : 1,
                      onChangeStart: (_) => _hideTimer?.cancel(),
                      onChanged: durMs > 0 ? (v) => setState(() => _dragMs = v) : null,
                      onChangeEnd: (v) {
                        _engine?.seek(Duration(milliseconds: v.toInt()));
                        setState(() => _dragMs = null);
                        _armHide();
                      },
                    ),
                  ),
                ),
                Text(_fmt(_dur), style: const TextStyle(fontSize: 12, fontFeatures: [FontFeature.tabularFigures()])),
                if (_hasNext) ...[
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () => _go(_i + 1),
                    icon: const Icon(Icons.skip_next_rounded),
                    label: Text(tr('next_episode')),
                  ),
                ],
              ]),
          ]),
        ),
      ),
    );
  }
}

class _RoundBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool big;
  const _RoundBtn({required this.icon, this.onTap, this.big = false});
  @override
  Widget build(BuildContext context) => Material(
        color: big ? C.gold : Colors.black45,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.all(big ? 16 : 12),
            child: Icon(icon, size: big ? 40 : 30, color: big ? C.onGold : (onTap == null ? Colors.white24 : Colors.white)),
          ),
        ),
      );
}
