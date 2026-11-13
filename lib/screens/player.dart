import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../api.dart';
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

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player _player = Player(configuration: PlayerConfiguration(title: 'IPTV Player', bufferSize: 64 * 1024 * 1024));
  late final VideoController _video = VideoController(_player);
  final List<StreamSubscription> _subs = [];

  late List<PlayItem> _items = [...widget.items];
  late int _i = widget.index;
  int? _pendingSeek;
  bool _tracksApplied = false;

  bool _controls = true;
  Timer? _hideTimer;
  bool _playing = false, _buffering = true;
  Duration _pos = Duration.zero, _dur = Duration.zero;
  double? _dragMs;
  String? _error;
  String _epg = '';
  DateTime _lastSave = DateTime.fromMillisecondsSinceEpoch(0);

  PlayItem get _cur => _items[_i];
  bool get _hasNext => !_cur.isLive && _i < _items.length - 1;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable();
    final s = _player.stream;
    _subs.addAll([
      s.playing.listen((v) => _set(() => _playing = v)),
      s.buffering.listen((v) => _set(() => _buffering = v)),
      s.position.listen((v) {
        if (!mounted) return;
        setState(() => _pos = v);
        if (DateTime.now().difference(_lastSave).inSeconds >= 10) _save();
      }),
      s.duration.listen((v) {
        _set(() => _dur = v);
        if (_pendingSeek != null && v > Duration.zero) {
          final ms = _pendingSeek!;
          _pendingSeek = null;
          if (ms < v.inMilliseconds - 5000) _player.seek(Duration(milliseconds: ms));
        }
      }),
      s.tracks.listen((_) => _applyTrackPrefs()),
      s.completed.listen((done) {
        if (done && _hasNext) _go(_i + 1);
      }),
      s.error.listen((e) {
        if (mounted && _pos == Duration.zero) setState(() => _error = e);
      }),
    ]);
    _play(widget.startMs);
    _maybeLoadSeries();
    _armHide();
  }

  void _set(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  Future<void> _play(int? startMs) async {
    setState(() {
      _error = null;
      _pos = Duration.zero;
      _dur = Duration.zero;
      _buffering = true;
      _tracksApplied = false;
      _epg = '';
    });
    _pendingSeek = (startMs != null && startMs > 0) ? startMs : null;
    await _player.open(Media(_cur.url));
    if (_cur.isLive) _loadEpg();
  }

  Future<void> _loadEpg() async {
    final id = _cur.id;
    try {
      final l = await Api.i.shortEpg(id);
      if (!mounted || _cur.id != id) return;
      final now = l.isNotEmpty ? Api.b64(l.first['title']) : '';
      final next = l.length > 1 ? Api.b64(l[1]['title']) : '';
      setState(() => _epg = [if (now.isNotEmpty) now, if (next.isNotEmpty) '${tr('next')}: $next'].join('   ·   '));
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
      if (idx >= 0 && mounted) {
        setState(() {
          _items = list;
          _i = idx;
        });
      }
    } catch (_) {}
  }

  void _applyTrackPrefs() {
    if (_tracksApplied) return;
    final t = _player.state.tracks;
    final subs = _realSubs(t.subtitle);
    final auds = _realAudio(t.audio);
    if (subs.isEmpty && auds.length < 2) return;
    _tracksApplied = true;
    final sp = Store.get('subPref');
    if (sp == 'off') {
      _player.setSubtitleTrack(SubtitleTrack.no());
    } else if (sp is String && sp.isNotEmpty) {
      for (final s in subs) {
        if ((s.language ?? '') == sp) {
          _player.setSubtitleTrack(s);
          break;
        }
      }
    }
    final ap = Store.get('audioPref');
    if (ap is String && ap.isNotEmpty) {
      for (final a in auds) {
        if ((a.language ?? '') == ap) {
          _player.setAudioTrack(a);
          break;
        }
      }
    }
  }

  List<SubtitleTrack> _realSubs(List<SubtitleTrack> l) => l.where((s) => s.id != 'auto' && s.id != 'no').toList();
  List<AudioTrack> _realAudio(List<AudioTrack> l) => l.where((s) => s.id != 'auto' && s.id != 'no').toList();

  String _trackLabel(String id, String? title, String? lang, int n) {
    final parts = [if ((title ?? '').isNotEmpty) title!, if ((lang ?? '').isNotEmpty) lang!.toUpperCase()];
    return parts.isEmpty ? '#$n' : parts.join(' · ');
  }

  void _save() {
    _lastSave = DateTime.now();
    final c = _cur;
    if (c.isLive || _dur.inMilliseconds <= 0) return;
    Store.saveProgress({
      'key': c.key,
      'type': c.type,
      'id': c.id,
      'name': c.title,
      'sub': c.sub,
      'icon': c.icon,
      'ext': c.ext,
      'pos': _pos.inMilliseconds,
      'dur': _dur.inMilliseconds,
      'seriesId': c.seriesId,
      'season': c.season,
    });
  }

  void _go(int i) {
    if (i < 0 || i >= _items.length) return;
    _save();
    setState(() => _i = i);
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
    setState(() => _controls = !_controls);
    if (_controls) _armHide();
  }

  void _seekBy(int sec) {
    final t = _pos + Duration(seconds: sec);
    _player.seek(t < Duration.zero ? Duration.zero : t);
    _armHide();
  }

  @override
  void dispose() {
    _save();
    _hideTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
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
    _hideTimer?.cancel();
    showModalBottomSheet(
      context: context,
      backgroundColor: C.surface,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StreamBuilder<Track>(
        stream: _player.stream.track,
        initialData: _player.state.track,
        builder: (ctx, snap) {
          final cur = snap.data ?? _player.state.track;
          final subs = _realSubs(_player.state.tracks.subtitle);
          final auds = _realAudio(_player.state.tracks.audio);
          final subOff = cur.subtitle.id == 'no' || subs.isEmpty;
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
              if (subs.isEmpty)
                Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(tr('no_subs'), style: const TextStyle(color: C.dimmer)))
              else ...[
                opt(tr('subs_off'), subOff, () {
                  _player.setSubtitleTrack(SubtitleTrack.no());
                  Store.set('subPref', 'off');
                }),
                for (var n = 0; n < subs.length; n++)
                  opt(_trackLabel(subs[n].id, subs[n].title, subs[n].language, n + 1), cur.subtitle.id == subs[n].id, () {
                    _player.setSubtitleTrack(subs[n]);
                    Store.set('subPref', subs[n].language ?? '');
                  }),
              ],
              const Divider(height: 24),
              Padding(padding: const EdgeInsets.all(12), child: Text(tr('audio'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16))),
              if (auds.length < 2)
                Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(tr('one_audio'), style: const TextStyle(color: C.dimmer)))
              else
                for (var n = 0; n < auds.length; n++)
                  opt(_trackLabel(auds[n].id, auds[n].title, auds[n].language, n + 1), cur.audio.id == auds[n].id, () {
                    _player.setAudioTrack(auds[n]);
                    Store.set('audioPref', auds[n].language ?? '');
                  }),
            ]),
          );
        },
      ),
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
    final durMs = _dur.inMilliseconds.toDouble();
    final posMs = (_dragMs ?? _pos.inMilliseconds.toDouble()).clamp(0.0, durMs > 0 ? durMs : 0.0).toDouble();
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        onDoubleTapDown: c.isLive
            ? null
            : (d) {
                final w = MediaQuery.of(context).size.width;
                _seekBy(d.localPosition.dx < w / 2 ? -10 : 10);
              },
        onDoubleTap: c.isLive ? null : () {},
        child: Stack(fit: StackFit.expand, children: [
          Video(
            controller: _video,
            controls: NoVideoControls,
            fill: Colors.black,
            subtitleViewConfiguration: SubtitleViewConfiguration(
              style: TextStyle(fontSize: 26, color: Colors.white, backgroundColor: Color(0x99000000), height: 1.3),
              padding: EdgeInsets.fromLTRB(24, 0, 24, 28),
            ),
          ),
          if (_buffering && _error == null) const Center(child: CircularProgressIndicator(color: C.gold)),
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
            ignoring: !_controls,
            child: AnimatedOpacity(
              opacity: _controls ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: _overlay(c, posMs, durMs),
            ),
          ),
        ]),
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
            // top bar
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
              IconButton(tooltip: tr('subs_audio'), icon: const Icon(Icons.subtitles_outlined), onPressed: _tracksSheet),
            ]),
            const Spacer(),
            // center controls
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
                  _player.playOrPause();
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
            // bottom bar
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
                        _player.seek(Duration(milliseconds: v.toInt()));
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
