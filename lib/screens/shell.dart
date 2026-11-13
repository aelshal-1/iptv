import 'package:flutter/material.dart';

import '../api.dart';
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
    return ValueListenableBuilder(
      valueListenable: Store.tick,
      builder: (context, _, __) {
        final recent = Store.recent();
        final favCh = Store.favs().where((f) => f['type'] == 'live').toList();
        final movies = _latest('vod', 'added');
        final series = _latest('series', 'last_modified');
        final hero = movies.isNotEmpty ? movies.first : null;
        return SafeArea(
          bottom: false,
          child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 8, 0),
              child: Row(children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(color: C.gold, borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.play_arrow_rounded, color: C.onGold),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(tr('app'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600))),
                const LangButton(),
              ]),
            ),
            if (hero != null) _Hero(item: hero),
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
                            [if ((r['sub'] ?? '') != '') r['sub'], '${(((r['dur'] as num) - (r['pos'] as num)) / 60000).ceil()} ${tr('min_left')}'].join(' · '),
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
            if (favCh.isNotEmpty) ...[
              SectionTitle(tr('fav_channels')),
              SizedBox(
                height: 92,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: favCh.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (_, i) {
                    final f = favCh[i];
                    return InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => openItem(context, 'live', {...f, 'stream_id': f['id']},
                          channelList: favCh.map((e) => <String, dynamic>{...e, 'stream_id': e['id'], 'stream_icon': e['icon']}).toList()),
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
              ),
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
                  leading: const Icon(Icons.history),
                  title: Text(tr('clear_history')),
                  onTap: () {
                    Store.set('recent', []);
                    toast(context, tr('history_cleared'));
                  },
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
