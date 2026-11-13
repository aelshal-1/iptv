import 'package:flutter/material.dart';

import '../api.dart';
import '../l10n.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'player.dart';

String? firstImage(Object? v) {
  if (v is List && v.isNotEmpty) return '${v.first}';
  if (v is String && v.isNotEmpty) return v;
  return null;
}

String fmtDuration(Object? d) {
  final s = '${d ?? ''}';
  if (RegExp(r'^\d{1,2}:\d{2}:\d{2}$').hasMatch(s)) {
    final p = s.split(':').map(int.parse).toList();
    final m = p[0] * 60 + p[1];
    return m >= 60 ? '${m ~/ 60}h ${m % 60}m' : '${m}m';
  }
  final secs = int.tryParse(s);
  if (secs != null && secs > 0) return '${secs ~/ 60}m';
  return '';
}

/// Shared scaffold for movie and series pages: backdrop, poster, title, meta, plot.
class _DetailFrame extends StatelessWidget {
  final String title;
  final String? backdrop, poster;
  final List<String> meta;
  final String plot, cast, director;
  final List<Widget> actions;
  final List<Widget> below;
  final bool loading;
  const _DetailFrame({
    required this.title,
    this.backdrop,
    this.poster,
    this.meta = const [],
    this.plot = '',
    this.cast = '',
    this.director = '',
    this.actions = const [],
    this.below = const [],
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(backgroundColor: Colors.transparent),
      body: ListView(padding: EdgeInsets.zero, children: [
        SizedBox(
          height: w * 9 / 16 + 90,
          child: Stack(fit: StackFit.expand, children: [
            Positioned(top: 0, left: 0, right: 0, height: w * 9 / 16, child: NetImg(backdrop ?? poster, label: '')),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: w * 9 / 16 + 2,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x66060709), Colors.transparent, C.bg], stops: [0, 0.4, 1]),
                ),
              ),
            ),
            PositionedDirectional(
              start: 16,
              end: 16,
              bottom: 0,
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(width: 100, height: 150, child: NetImg(poster, label: title)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(title, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w600, height: 1.2)),
                    const SizedBox(height: 6),
                    Text(meta.where((m) => m.isNotEmpty).join('  ·  '), style: const TextStyle(color: C.dim, fontSize: 13)),
                  ]),
                ),
              ]),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
          child: Wrap(spacing: 10, runSpacing: 10, children: actions),
        ),
        if (loading) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(color: C.gold))),
        if (plot.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
            child: Text(plot, style: const TextStyle(color: C.dim, height: 1.5)),
          ),
        if (director.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text('${tr('director')}: $director', style: const TextStyle(color: C.dimmer, fontSize: 13)),
          ),
        if (cast.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Text('${tr('cast')}: $cast', style: const TextStyle(color: C.dimmer, fontSize: 13)),
          ),
        ...below,
        const SizedBox(height: 32),
      ]),
    );
  }
}

/* ============================ MOVIE ============================ */
class MovieDetail extends StatefulWidget {
  final J item;
  const MovieDetail({super.key, required this.item});
  @override
  State<MovieDetail> createState() => _MovieDetailState();
}

class _MovieDetailState extends State<MovieDetail> {
  J? _info;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    Api.i.vodInfo(widget.item['stream_id']).then((d) {
      if (mounted) {
        setState(() {
          _info = d;
          _loading = false;
        });
      }
    }).catchError((_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  PlayItem _playItem() {
    final x = widget.item;
    final md = (_info?['movie_data'] as Map?) ?? {};
    final ext = md['container_extension'] ?? x['container_extension'] ?? x['ext'];
    final id = x['stream_id'];
    return PlayItem(
      key: 'vod:$id',
      type: 'vod',
      id: '$id',
      ext: ext == null ? null : '$ext',
      title: nameOf(x),
      icon: iconOf(x) ?? firstImage((_info?['info'] as Map?)?['movie_image']),
      url: Api.i.movieUrl(id, ext),
    );
  }

  @override
  Widget build(BuildContext context) {
    final x = widget.item;
    final info = (_info?['info'] as Map?) ?? {};
    return ValueListenableBuilder(
      valueListenable: Store.tick,
      builder: (context, _, __) {
        final prog = Store.progressOf('vod:${x['stream_id']}');
        final fav = Store.isFav('vod', x['stream_id']);
        final r = ratingOf(info.isNotEmpty ? info : x);
        return _DetailFrame(
          title: '${info['name'] ?? nameOf(x)}',
          backdrop: firstImage(info['backdrop_path']),
          poster: firstImage(info['movie_image']) ?? iconOf(x),
          meta: [
            '${info['releasedate'] ?? x['year'] ?? ''}'.split('-').first,
            fmtDuration(info['duration_secs'] ?? info['duration']),
            '${info['genre'] ?? ''}',
            if (r.isNotEmpty) '★ $r',
          ],
          plot: '${info['plot'] ?? info['description'] ?? ''}'.trim(),
          cast: '${info['cast'] ?? info['actors'] ?? ''}'.trim(),
          director: '${info['director'] ?? ''}'.trim(),
          loading: _loading,
          actions: [
            if (prog != null)
              FilledButton.icon(
                onPressed: () => PlayerScreen.openVod(context, [_playItem()], 0, startMs: (prog['pos'] as num).toInt()),
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text('${tr('resume')} · ${(((prog['dur'] as num) - (prog['pos'] as num)) / 60000).ceil()} ${tr('min_left')}'),
              ),
            if (prog != null)
              OutlinedButton.icon(
                onPressed: () => PlayerScreen.openVod(context, [_playItem()], 0),
                icon: const Icon(Icons.replay),
                label: Text(tr('from_start')),
              )
            else
              FilledButton.icon(
                onPressed: () => PlayerScreen.openVod(context, [_playItem()], 0),
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(tr('play')),
              ),
            DownloadButton(item: _playItem()),
            OutlinedButton.icon(
              onPressed: () => toggleFavToast(context, 'vod', x),
              icon: Icon(fav ? Icons.star_rounded : Icons.star_border_rounded, color: fav ? C.gold : null),
              label: Text(tr(fav ? 'in_favorites' : 'favorite')),
            ),
          ],
        );
      },
    );
  }
}

/* ============================ SERIES ============================ */
/// Episodes grouped by season from get_series_info (map or list form).
Map<String, List<J>> episodesBySeason(J data) {
  final eps = data['episodes'];
  final out = <String, List<J>>{};
  void add(Object? e, String fallbackSeason) {
    if (e is! Map) return;
    final s = '${e['season'] ?? fallbackSeason}';
    (out[s] ??= []).add(Map<String, dynamic>.from(e));
  }

  if (eps is Map) {
    eps.forEach((k, v) {
      if (v is List) {
        for (final e in v) {
          add(e, '$k');
        }
      }
    });
  } else if (eps is List) {
    for (final v in eps) {
      if (v is List) {
        for (final e in v) {
          add(e, '1');
        }
      } else {
        add(v, '1');
      }
    }
  }
  for (final l in out.values) {
    l.sort((a, b) => (int.tryParse('${a['episode_num']}') ?? 0).compareTo(int.tryParse('${b['episode_num']}') ?? 0));
  }
  final keys = out.keys.toList()..sort((a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));
  return {for (final k in keys) k: out[k]!};
}

List<PlayItem> episodePlayItems(J series, String seriesName, String? cover, String season, List<J> eps) => eps.map((e) {
      final info = (e['info'] as Map?) ?? {};
      final n = e['episode_num'] ?? '';
      final t = '${e['title'] ?? ''}';
      return PlayItem(
        key: 'ep:${e['id']}',
        type: 'episode',
        id: '${e['id']}',
        ext: e['container_extension'] == null ? null : '${e['container_extension']}',
        title: seriesName,
        sub: 'S$season · E$n${t.isNotEmpty && !t.contains(seriesName) ? ' · $t' : ''}',
        icon: firstImage(info['movie_image']) ?? cover,
        url: Api.i.episodeUrl(e['id'], e['container_extension']),
        seriesId: '${series['series_id']}',
        season: season,
      );
    }).toList();

class SeriesDetail extends StatefulWidget {
  final J item;
  const SeriesDetail({super.key, required this.item});
  @override
  State<SeriesDetail> createState() => _SeriesDetailState();
}

class _SeriesDetailState extends State<SeriesDetail> {
  J? _data;
  bool _loading = true, _failed = false;
  String? _season;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _loading = true;
      _failed = false;
    });
    Api.i.seriesInfo(widget.item['series_id']).then((d) {
      if (!mounted) return;
      final s = episodesBySeason(d);
      setState(() {
        _data = d;
        _loading = false;
        _season = s.keys.isNotEmpty ? s.keys.first : null;
      });
    }).catchError((_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final x = widget.item;
    final info = (_data?['info'] as Map?) ?? {};
    final seasons = _data == null ? <String, List<J>>{} : episodesBySeason(_data!);
    final name = '${info['name'] ?? nameOf(x)}';
    final cover = firstImage(info['cover']) ?? iconOf(x);
    return ValueListenableBuilder(
      valueListenable: Store.tick,
      builder: (context, _, __) {
        final fav = Store.isFav('series', x['series_id']);
        final eps = _season == null ? <J>[] : (seasons[_season] ?? <J>[]);
        final items = _season == null ? <PlayItem>[] : episodePlayItems(x, name, cover, _season!, eps);
        // first episode with progress (most recent) in this series
        Map<String, dynamic>? resume;
        for (final r in Store.recent()) {
          if ('${r['seriesId']}' == '${x['series_id']}') {
            resume = r;
            break;
          }
        }
        final r = ratingOf(info.isNotEmpty ? info : x);
        return _DetailFrame(
          title: name,
          backdrop: firstImage(info['backdrop_path']),
          poster: cover,
          meta: [
            '${info['releaseDate'] ?? info['releasedate'] ?? x['releaseDate'] ?? ''}'.split('-').first,
            if (seasons.isNotEmpty) '${seasons.length} ${tr('season')}',
            '${info['genre'] ?? x['genre'] ?? ''}',
            if (r.isNotEmpty) '★ $r',
          ],
          plot: '${info['plot'] ?? ''}'.trim(),
          cast: '${info['cast'] ?? ''}'.trim(),
          director: '${info['director'] ?? ''}'.trim(),
          loading: _loading,
          actions: [
            if (resume != null)
              FilledButton.icon(
                onPressed: () => PlayerScreen.resumeRecent(context, resume!),
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text('${tr(resume['upNext'] == true ? 'play' : 'resume')} · ${resume['sub'] ?? ''}'),
              )
            else if (items.isNotEmpty)
              FilledButton.icon(
                onPressed: () => PlayerScreen.openVod(context, items, 0),
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(tr('play')),
              ),
            OutlinedButton.icon(
              onPressed: () => toggleFavToast(context, 'series', x),
              icon: Icon(fav ? Icons.star_rounded : Icons.star_border_rounded, color: fav ? C.gold : null),
              label: Text(tr(fav ? 'in_favorites' : 'favorite')),
            ),
            if (_failed) TextButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: Text(tr('retry'))),
          ],
          below: [
            if (seasons.isNotEmpty) ...[
              const SizedBox(height: 18),
              SizedBox(
                height: 42,
                child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
                  for (final s in seasons.keys)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(label: Text('${tr('season')} $s'), selected: s == _season, onSelected: (_) => setState(() => _season = s)),
                    ),
                ]),
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < items.length; i++) _EpisodeTile(ep: eps[i], item: items[i], onTap: () => PlayerScreen.openVod(context, items, i, startMs: _startOf(items[i]))),
            ] else if (!_loading && !_failed)
              Padding(padding: const EdgeInsets.all(24), child: Text(tr('no_episodes'), style: const TextStyle(color: C.dim))),
          ],
        );
      },
    );
  }

  int? _startOf(PlayItem p) => (Store.progressOf(p.key)?['pos'] as num?)?.toInt();
}

class _EpisodeTile extends StatelessWidget {
  final J ep;
  final PlayItem item;
  final VoidCallback onTap;
  const _EpisodeTile({required this.ep, required this.item, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final info = (ep['info'] as Map?) ?? {};
    final prog = Store.progressOf(item.key);
    final pd = (prog?['dur'] as num?) ?? 0;
    final frac = prog == null || pd <= 0 ? null : ((prog['pos'] as num) / pd).toDouble();
    final plot = '${info['plot'] ?? ''}'.trim();
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 140,
              height: 79,
              child: Stack(fit: StackFit.expand, children: [
                NetImg(item.icon, label: 'E${ep['episode_num'] ?? ''}'),
                const Center(child: Icon(Icons.play_circle_outline_rounded, color: Colors.white70, size: 30)),
                if (frac != null)
                  Align(alignment: Alignment.bottomCenter, child: LinearProgressIndicator(value: frac, minHeight: 3, backgroundColor: Colors.black54, color: C.gold)),
                if (Store.isWatched(item.key))
                  const PositionedDirectional(
                    top: 6,
                    end: 6,
                    child: CircleAvatar(radius: 11, backgroundColor: C.gold, child: Icon(Icons.check_rounded, size: 15, color: C.onGold)),
                  ),
              ]),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${ep['episode_num'] ?? ''}. ${ep['title'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500)),
              if (fmtDuration(info['duration_secs'] ?? info['duration']).isNotEmpty)
                Text(fmtDuration(info['duration_secs'] ?? info['duration']), style: const TextStyle(color: C.dimmer, fontSize: 12)),
              if (plot.isNotEmpty) Text(plot, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.dim, fontSize: 12)),
            ]),
          ),
          DownloadButton(item: item, compact: true),
        ]),
      ),
    );
  }
}
