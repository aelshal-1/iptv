import 'package:flutter/material.dart';

import '../api.dart';
import '../downloads.dart';
import '../l10n.dart';
import '../main.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'browse.dart';
import 'login.dart';
import 'player.dart';
import 'sync.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      const HomeTab(),
      const BrowseTab(kind: 'live'),
      const BrowseTab(kind: 'vod'),
      const BrowseTab(kind: 'series'),
      const SearchTab(),
      const MoreTab(),
    ];
    return Scaffold(
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home_rounded), label: tr('home')),
          NavigationDestination(icon: const Icon(Icons.live_tv_outlined), selectedIcon: const Icon(Icons.live_tv_rounded), label: tr('live')),
          NavigationDestination(icon: const Icon(Icons.movie_outlined), selectedIcon: const Icon(Icons.movie_rounded), label: tr('movies')),
          NavigationDestination(icon: const Icon(Icons.video_library_outlined), selectedIcon: const Icon(Icons.video_library_rounded), label: tr('series')),
          NavigationDestination(icon: const Icon(Icons.search), label: tr('search')),
          NavigationDestination(icon: const Icon(Icons.more_horiz), label: tr('more')),
        ],
      ),
    );
  }
}

/* ============================ HOME ============================ */
class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  List<J> _latest(String kind, String field) {
    final l = [...Api.i.items(kind)];
    l.sort((a, b) => (int.tryParse('${b[field] ?? 0}') ?? 0).compareTo(int.tryParse('${a[field] ?? 0}') ?? 0));
    return l.take(24).toList();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([Store.tick, Downloads.i.tick]),
      builder: (context, _) {
        final recent = Store.recent();
        final favs = Store.favs();
        final favCh = favs.where((f) => f['type'] == 'live').toList();
        final favPosters = favs
            .where((f) => f['type'] == 'vod' || f['type'] == 'series')
            .map((f) => <String, dynamic>{
                  ...f,
                  if (f['type'] == 'vod') 'stream_id': f['id'] else 'series_id': f['id'],
                  'stream_icon': f['icon'],
                  'cover': f['icon'],
                  'container_extension': f['ext'],
                })
            .toList();
        final recentLive = Store.recentLive();
        final movies = _latest('vod', 'added');
        final series = _latest('series', 'last_modified');
        final hero = movies.isNotEmpty ? movies.first : null;
        return SafeArea(
          bottom: false,
          child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 8, 0),
              child: Row(children: [
                const AppLogo(size: 38),
                const SizedBox(width: 10),
                Expanded(child: Text(tr('app'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600))),
                const LangButton(),
              ]),
            ),
            if (recent.isNotEmpty) ...[
              SectionTitle(tr('continue_watching')),
              SizedBox(
                height: 150,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: recent.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (_, i) {
                    final r = recent[i];
                    final frac = ((r['pos'] as num?) ?? 0) / (((r['dur'] as num?) ?? 1).clamp(1, 1 << 40));
                    return SizedBox(
                      width: 210,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => PlayerScreen.resumeRecent(context, r),
                        onLongPress: () => _removeRecent(context, r),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: Stack(fit: StackFit.expand, children: [
                                NetImg('${r['icon'] ?? ''}', label: '${r['name']}'),
                                Container(color: Colors.black26),
                                const Center(child: Icon(Icons.play_circle_fill_rounded, size: 40, color: Colors.white)),
                                Align(
                                  alignment: Alignment.bottomCenter,
                                  child: LinearProgressIndicator(value: frac.toDouble(), minHeight: 4, backgroundColor: Colors.black54, color: C.gold),
                                ),
                              ]),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text('${r['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                          Text(
                            [
                              if ((r['sub'] ?? '') != '') r['sub'],
                              r['upNext'] == true ? tr('up_next') : '${((((r['dur'] as num?) ?? 0) - ((r['pos'] as num?) ?? 0)) / 60000).ceil()} ${tr('min_left')}',
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11.5, color: C.dimmer),
                          ),
                        ]),
                      ),
                    );
                  },
                ),
              ),
            ],
            if (Downloads.i.all().isNotEmpty) ...[
              SectionTitle(tr('downloads'),
                  trailing: TextButton(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DownloadsScreen())),
                    child: Text(tr('all')),
                  )),
              SizedBox(
                height: 104,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: Downloads.i.all().length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (_, i) {
                    final d = Downloads.i.all()[i];
                    final it = playItemFromDownload(d);
                    final done = Downloads.i.isDownloaded(it.key);
                    return SizedBox(
                      width: 150,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => done
                            ? PlayerScreen.openVod(context, [it], 0, startMs: (Store.progressOf(it.key)?['pos'] as num?)?.toInt())
                            : Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DownloadsScreen())),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Stack(fit: StackFit.expand, children: [
                                NetImg(it.icon, label: it.title),
                                Positioned(
                                  top: 6,
                                  right: 6,
                                  child: Icon(done ? Icons.download_done_rounded : Icons.downloading_rounded, color: C.gold, size: 20),
                                ),
                                if (!done)
                                  Align(
                                    alignment: Alignment.bottomCenter,
                                    child: LinearProgressIndicator(value: Downloads.i.progressOf(it.key), minHeight: 3, backgroundColor: Colors.black54, color: C.gold),
                                  ),
                              ]),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text([it.title, if (it.sub != null) it.sub].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                        ]),
                      ),
                    );
                  },
                ),
              ),
            ],
            if (hero != null) _Hero(item: hero),
            if (favPosters.isNotEmpty) ...[
              SectionTitle(tr('favorites'),
                  trailing: TextButton(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FavoritesScreen())),
                    child: Text(tr('all')),
                  )),
              SizedBox(
                height: 210,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: favPosters.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (_, i) {
                    final f = favPosters[i];
                    final kind = '${f['type']}';
                    return SizedBox(
                      width: 118,
                      child: Poster(item: f, sub: tr(kind == 'vod' ? 'movies' : 'series'), onTap: () => openItem(context, kind, f)),
                    );
                  },
                ),
              ),
            ],
            if (favCh.isNotEmpty) ...[
              SectionTitle(tr('fav_channels')),
              _ChannelRow(channels: favCh),
            ],
            if (recentLive.isNotEmpty) ...[
              SectionTitle(tr('recent_channels')),
              _ChannelRow(channels: recentLive),
            ],
            if (movies.isNotEmpty) ...[
              SectionTitle('${tr('latest')} · ${tr('movies')}'),
              _PosterRow(kind: 'vod', items: movies),
            ],
            if (series.isNotEmpty) ...[
              SectionTitle('${tr('latest')} · ${tr('series')}'),
              _PosterRow(kind: 'series', items: series),
            ],
          ]),
        );
      },
    );
  }
}

/// Horizontal row of channel logos (favorites, recently watched).
class _ChannelRow extends StatelessWidget {
  final List<Map<String, dynamic>> channels;
  const _ChannelRow({required this.channels});
  @override
  Widget build(BuildContext context) {
    final list = channels.map((e) => <String, dynamic>{...e, 'stream_id': e['id'], 'stream_icon': e['icon']}).toList();
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: list.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final f = list[i];
          return InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => openItem(context, 'live', f, channelList: list),
            child: SizedBox(
              width: 110,
              child: Column(children: [
                Expanded(
                  child: Glass(
                    padding: const EdgeInsets.all(8),
                    radius: 14,
                    child: SizedBox.expand(child: NetImg('${f['icon'] ?? ''}', label: '${f['name']}', fit: BoxFit.contain)),
                  ),
                ),
                const SizedBox(height: 4),
                Text('${f['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
              ]),
            ),
          );
        },
      ),
    );
  }
}

void _removeRecent(BuildContext context, Map<String, dynamic> r) {
  showModalBottomSheet(
    context: context,
    backgroundColor: C.surface,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          title: Text('${r['name']}', maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: (r['sub'] ?? '') != '' ? Text('${r['sub']}', style: const TextStyle(color: C.dimmer)) : null,
        ),
        ListTile(
          leading: const Icon(Icons.remove_circle_outline, color: C.red),
          title: Text(tr('remove_continue'), style: const TextStyle(color: C.red)),
          onTap: () {
            Store.set('recent', Store.recent().where((e) => e['key'] != r['key']).toList());
            Navigator.pop(ctx);
            toast(context, tr('removed'));
          },
        ),
      ]),
    ),
  );
}

/// Choose exactly which saved data to clear.
class ClearDataScreen extends StatefulWidget {
  const ClearDataScreen({super.key});
  @override
  State<ClearDataScreen> createState() => _ClearDataScreenState();
}

class _ClearDataScreenState extends State<ClearDataScreen> {
  final Set<String> _sel = {};

  List<(String, String, int)> _items() {
    final recent = Store.recent();
    final favs = Store.favs();
    final prefs = (Store.get('subPref') != null ? 1 : 0) + (Store.get('audioPref') != null ? 1 : 0);
    return [
      ('cw_movies', tr('cw_movies'), recent.where((e) => e['type'] == 'vod').length),
      ('cw_series', tr('cw_series'), recent.where((e) => e['type'] == 'episode').length),
      ('watched', tr('watched_marks'), Store.watched().length),
      ('recent_live', tr('recent_channels'), Store.recentLive().length),
      ('fav_live', tr('fav_channels'), favs.where((f) => f['type'] == 'live').length),
      ('fav_vod', '${tr('favorites')} · ${tr('movies')}', favs.where((f) => f['type'] == 'vod').length),
      ('fav_series', '${tr('favorites')} · ${tr('series')}', favs.where((f) => f['type'] == 'series').length),
      ('track_prefs', tr('track_prefs'), prefs),
    ];
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.surface,
        title: Text(tr('clear_confirm')),
        content: Text(_items().where((i) => _sel.contains(i.$1)).map((i) => i.$2).join('\n')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('clear'))),
        ],
      ),
    );
    if (ok != true) return;
    var recent = Store.recent();
    if (_sel.contains('cw_movies')) recent = recent.where((e) => e['type'] != 'vod').toList();
    if (_sel.contains('cw_series')) recent = recent.where((e) => e['type'] != 'episode').toList();
    await Store.set('recent', recent);
    if (_sel.contains('watched')) await Store.set('watched', null);
    if (_sel.contains('recent_live')) await Store.set('recentLive', null);
    final drop = {
      if (_sel.contains('fav_live')) 'live',
      if (_sel.contains('fav_vod')) 'vod',
      if (_sel.contains('fav_series')) 'series',
    };
    if (drop.isNotEmpty) await Store.set('favs', Store.favs().where((f) => !drop.contains(f['type'])).toList());
    if (_sel.contains('track_prefs')) {
      await Store.set('subPref', null);
      await Store.set('audioPref', null);
    }
    if (!mounted) return;
    setState(_sel.clear);
    toast(context, tr('cleared'));
  }

  @override
  Widget build(BuildContext context) {
    final items = _items();
    return Scaffold(
      appBar: AppBar(title: Text(tr('clear_data'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(8, 4, 8, 24), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Text(tr('clear_data_hint'), style: const TextStyle(color: C.dim)),
        ),
        for (final i in items)
          CheckboxListTile(
            value: _sel.contains(i.$1),
            onChanged: i.$3 == 0 ? null : (v) => setState(() => v == true ? _sel.add(i.$1) : _sel.remove(i.$1)),
            title: Text(i.$2, style: TextStyle(color: i.$3 == 0 ? C.dimmer : C.text)),
            subtitle: Text('${i.$3} ${tr('items')}', style: const TextStyle(color: C.dimmer, fontSize: 12)),
            activeColor: C.gold,
            checkColor: C.onGold,
            controlAffinity: ListTileControlAffinity.leading,
          ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: _sel.isEmpty ? null : _clear,
              style: FilledButton.styleFrom(backgroundColor: C.red, foregroundColor: Colors.white),
              child: Text(_sel.isEmpty ? tr('clear_pick') : '${tr('clear')} (${_sel.length})'),
            ),
          ),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  final J item;
  const _Hero({required this.item});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => openItem(context, 'vod', item),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(fit: StackFit.expand, children: [
              NetImg(iconOf(item), label: nameOf(item)),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0xEE060709)], stops: [0.35, 1]),
                ),
              ),
              PositionedDirectional(
                start: 16,
                end: 16,
                bottom: 14,
                child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(tr('latest').toUpperCase(), style: const TextStyle(color: C.gold, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(nameOf(item), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(onPressed: () => openItem(context, 'vod', item), icon: const Icon(Icons.play_arrow_rounded), label: Text(tr('play'))),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _PosterRow extends StatelessWidget {
  final String kind;
  final List<J> items;
  const _PosterRow({required this.kind, required this.items});
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 210,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (_, i) => SizedBox(width: 118, child: Poster(item: items[i], onTap: () => openItem(context, kind, items[i]))),
        ),
      );
}

/* ============================ SEARCH ============================ */
class SearchTab extends StatefulWidget {
  const SearchTab({super.key});
  @override
  State<SearchTab> createState() => _SearchTabState();
}

String normalizeSearch(String s) {
  s = s.toLowerCase().trim();
  const map = {'أ': 'ا', 'إ': 'ا', 'آ': 'ا', 'ة': 'ه', 'ى': 'ي', 'ـ': ''};
  map.forEach((k, v) => s = s.replaceAll(k, v));
  return s.replaceAll(RegExp(r'[ً-ْ]'), '');
}

class _SearchTabState extends State<SearchTab> {
  final _q = TextEditingController();
  String _scope = 'all';

  List<J> _find(String kind, String q) {
    final out = <J>[];
    for (final x in Api.i.items(kind)) {
      if (normalizeSearch(nameOf(x)).contains(q)) {
        out.add(x);
        if (out.length >= 60) break;
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final q = normalizeSearch(_q.text);
    final kinds = _scope == 'all' ? ['live', 'vod', 'series'] : [_scope];
    final results = {for (final k in kinds) k: q.length < 2 ? <J>[] : _find(k, q)};
    final any = results.values.any((l) => l.isNotEmpty);
    return SafeArea(
      bottom: false,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: TextField(
            controller: _q,
            onChanged: (_) => setState(() {}),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: tr('search_all'),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _q.text.isEmpty ? null : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(_q.clear)),
            ),
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
            for (final s in ['all', 'live', 'vod', 'series'])
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: Text(tr(s == 'vod' ? 'movies' : s)),
                  selected: _scope == s,
                  onSelected: (_) => setState(() => _scope = s),
                ),
              ),
          ]),
        ),
        Expanded(
          child: q.length < 2
              ? EmptyNote(tr('search_all'), icon: Icons.search)
              : !any
                  ? EmptyNote(tr('no_results'), icon: Icons.search_off)
                  : ListView(padding: const EdgeInsets.only(bottom: 24), children: [
                      for (final k in kinds)
                        if (results[k]!.isNotEmpty) ...[
                          SectionTitle('${tr(k == 'vod' ? 'movies' : k)} · ${results[k]!.length}'),
                          if (k == 'live')
                            ...results[k]!.take(30).map((c) => ChannelTile(ch: c, onTap: () => openItem(context, 'live', c, channelList: results[k]!)))
                          else
                            _PosterRow(kind: k, items: results[k]!),
                        ],
                    ]),
        ),
      ]),
    );
  }
}

/* ============================ MORE ============================ */
class MoreTab extends StatelessWidget {
  const MoreTab({super.key});

  String _date(Object? v) {
    final n = int.tryParse('${v ?? ''}');
    if (n == null || n <= 0) return tr('unlimited');
    final d = DateTime.fromMillisecondsSinceEpoch(n * 1000);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: Store.tick,
      builder: (context, _, __) {
        final a = Api.i.acc;
        final info = a?.info ?? {};
        final libDate = Api.i.libraryDate;
        final favs = Store.favs();
        return SafeArea(
          bottom: false,
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
            Text(tr('more'), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            Glass(
              padding: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.star_rounded, color: C.gold),
                title: Text(tr('favorites')),
                subtitle: Text('${favs.length} ${tr('items')}', style: const TextStyle(color: C.dimmer)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FavoritesScreen())),
              ),
            ),
            const SizedBox(height: 10),
            Glass(
              padding: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.download_for_offline_rounded, color: C.gold),
                title: Text(tr('downloads')),
                subtitle: Text('${Downloads.i.all().length} ${tr('items')} · ${mb(Downloads.i.totalBytes())}', style: const TextStyle(color: C.dimmer)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DownloadsScreen())),
              ),
            ),
            const SizedBox(height: 16),
            Glass(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('account'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                const SizedBox(height: 10),
                _kv(tr('username'), a?.user ?? ''),
                _kv(tr('server'), a?.url ?? ''),
                _kv(tr('status'), '${info['status'] ?? ''}'),
                _kv(tr('expires'), _date(info['exp_date'])),
                _kv(tr('connections'), '${info['active_cons'] ?? 0} / ${info['max_connections'] ?? '-'}'),
              ]),
            ),
            const SizedBox(height: 16),
            Glass(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(children: [
                ListTile(
                  leading: const Icon(Icons.cloud_download_outlined),
                  title: Text(tr('refresh_all')),
                  subtitle: Text(
                    libDate == null ? tr('library_never') : '${tr('library_saved')} ${libDate.toString().substring(0, 16)}',
                    style: const TextStyle(color: C.dimmer),
                  ),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SyncScreen())),
                ),
                ListTile(
                  leading: const Icon(Icons.translate),
                  title: Text(tr('language')),
                  trailing: SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: const [ButtonSegment(value: false, label: Text('EN')), ButtonSegment(value: true, label: Text('ع'))],
                    selected: {L10n.i.ar},
                    onSelectionChanged: (s) {
                      Store.set('lang', s.first ? 'ar' : 'en');
                      L10n.i.set(s.first);
                    },
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.cleaning_services_outlined),
                  title: Text(tr('clear_data')),
                  subtitle: Text(tr('clear_data_sub'), style: const TextStyle(color: C.dimmer)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ClearDataScreen())),
                ),
                ListTile(
                  leading: const Icon(Icons.logout, color: C.red),
                  title: Text(tr('sign_out'), style: const TextStyle(color: C.red)),
                  onTap: () async {
                    await Api.i.logout();
                    if (context.mounted) goRoot(context, const LoginScreen());
                  },
                ),
              ]),
            ),
          ]),
        );
      },
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 110, child: Text(k, style: const TextStyle(color: C.dimmer))),
          Expanded(child: Text(v, textDirection: TextDirection.ltr, textAlign: L10n.i.ar ? TextAlign.right : TextAlign.left)),
        ]),
      );
}

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('favorites'))),
      body: ValueListenableBuilder(
        valueListenable: Store.tick,
        builder: (context, _, __) {
          final favs = Store.favs();
          if (favs.isEmpty) return EmptyNote(tr('no_favs'), icon: Icons.star_border_rounded);
          final ch = favs.where((f) => f['type'] == 'live').map((e) => <String, dynamic>{...e, 'stream_id': e['id'], 'stream_icon': e['icon']}).toList();
          final mv = favs.where((f) => f['type'] == 'vod').map((e) => <String, dynamic>{...e, 'stream_id': e['id'], 'stream_icon': e['icon'], 'container_extension': e['ext']}).toList();
          final sr = favs.where((f) => f['type'] == 'series').map((e) => <String, dynamic>{...e, 'series_id': e['id'], 'cover': e['icon']}).toList();
          return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
            if (ch.isNotEmpty) ...[
              SectionTitle(tr('live')),
              ...ch.map((c) => ChannelTile(ch: c, onTap: () => openItem(context, 'live', c, channelList: ch))),
            ],
            if (mv.isNotEmpty) ...[SectionTitle(tr('movies')), _PosterRow(kind: 'vod', items: mv)],
            if (sr.isNotEmpty) ...[SectionTitle(tr('series')), _PosterRow(kind: 'series', items: sr)],
          ]);
        },
      ),
    );
  }
}


PlayItem playItemFromDownload(Map d) {
  final type = '${d['type']}', id = '${d['id']}', ext = d['ext'] == null ? null : '${d['ext']}';
  return PlayItem(
    key: '${d['key']}',
    type: type,
    id: id,
    ext: ext,
    title: '${d['name'] ?? ''}',
    sub: d['sub'] == null ? null : '${d['sub']}',
    icon: d['icon'] == null ? null : '${d['icon']}',
    url: type == 'episode' ? Api.i.episodeUrl(id, ext) : Api.i.movieUrl(id, ext),
    seriesId: d['seriesId'] == null ? null : '${d['seriesId']}',
    season: d['season'] == null ? null : '${d['season']}',
  );
}

/// Downloaded and downloading movies and episodes; finished ones play offline.
class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('downloads'))),
      body: ValueListenableBuilder(
        valueListenable: Downloads.i.tick,
        builder: (context, _, __) {
          final list = Downloads.i.all();
          if (list.isEmpty) return EmptyNote(tr('no_downloads'), icon: Icons.download_for_offline_outlined);
          return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text('${tr('storage_used')}: ${mb(Downloads.i.totalBytes())}', style: const TextStyle(color: C.dimmer)),
            ),
            for (final d in list) _DownloadTile(d: d),
          ]);
        },
      ),
    );
  }
}

class _DownloadTile extends StatelessWidget {
  final Map<String, dynamic> d;
  const _DownloadTile({required this.d});
  @override
  Widget build(BuildContext context) {
    final it = playItemFromDownload(d);
    final dl = Downloads.i;
    final done = dl.isDownloaded(it.key);
    final p = dl.progressOf(it.key);
    final status = done
        ? '${tr('dl_done')} · ${mb((d['size'] as num?)?.toInt() ?? 0)}'
        : dl.isFailed(it.key)
            ? '${tr('retry_dl')}${dl.errorOf(it.key) != null ? ' · ${dl.errorOf(it.key)}' : ''}'
            : '${tr(dl.isPaused(it.key) ? 'paused' : 'downloading')} ${(p * 100).floor()}%';
    return InkWell(
      onTap: done
          ? () {
              final pos = (Store.progressOf(it.key)?['pos'] as num?)?.toInt();
              PlayerScreen.openVod(context, [it], 0, startMs: pos);
            }
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 120,
              height: 68,
              child: Stack(fit: StackFit.expand, children: [
                NetImg(it.icon, label: it.title),
                if (done) const Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 30)),
                if (!done)
                  Align(alignment: Alignment.bottomCenter, child: LinearProgressIndicator(value: p, minHeight: 3, backgroundColor: Colors.black54, color: C.gold)),
              ]),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(it.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500)),
              if (it.sub != null) Text(it.sub!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.dim, fontSize: 12.5)),
              const SizedBox(height: 2),
              Text(status, style: TextStyle(color: dl.isFailed(it.key) ? C.red : C.dimmer, fontSize: 12)),
            ]),
          ),
          DownloadButton(item: it, compact: true),
        ]),
      ),
    );
  }
}
