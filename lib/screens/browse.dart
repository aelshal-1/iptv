import 'package:flutter/material.dart';

import '../api.dart';
import '../l10n.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'shell.dart' show normalizeSearch;

String kindTitle(String kind) => tr(kind == 'vod' ? 'movies' : kind);

/// Side-list of categories for one kind, with Arrange (reorder + hide).
class BrowseTab extends StatefulWidget {
  final String kind;
  const BrowseTab({super.key, required this.kind});
  @override
  State<BrowseTab> createState() => _BrowseTabState();
}

class _BrowseTabState extends State<BrowseTab> {
  bool _arrange = false;

  String get kind => widget.kind;

  void _saveOrder(List<J> cats) => Store.set('catOrder.$kind', cats.map((c) => '${c['category_id']}').toList());

  void _toggleHidden(String id) {
    final h = Store.strList('catHidden.$kind');
    h.contains(id) ? h.remove(id) : h.add(id);
    Store.set('catHidden.$kind', h);
  }

  void _open(String cat) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ItemsScreen(kind: kind, cat: cat)));

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: Store.tick,
      builder: (context, _, __) {
        final cats = orderedCats(kind, withHidden: _arrange);
        final hidden = Store.strList('catHidden.$kind').toSet();
        final total = Api.i.items(kind).length;
        return SafeArea(
          bottom: false,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 8, 4),
              child: Row(children: [
                Expanded(child: Text(kindTitle(kind), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600))),
                if (!_arrange)
                  IconButton(
                    tooltip: tr('search_in'),
                    icon: const Icon(Icons.search),
                    onPressed: () => _open('all'),
                  ),
                if (!_arrange)
                  IconButton(
                    tooltip: tr('refresh'),
                    icon: const Icon(Icons.refresh),
                    onPressed: () => refreshWithProgress(context, kind, 'all'),
                  ),
                TextButton.icon(
                  icon: Icon(_arrange ? Icons.check : Icons.swap_vert, size: 18),
                  label: Text(tr(_arrange ? 'done' : 'arrange')),
                  onPressed: () => setState(() => _arrange = !_arrange),
                ),
              ]),
            ),
            if (_arrange)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(tr('arrange_hint'), style: const TextStyle(color: C.dimmer, fontSize: 13)),
              ),
            Expanded(
              child: _arrange
                  ? ReorderableListView.builder(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: cats.length,
                      onReorder: (a, b) {
                        if (b > a) b--;
                        final l = [...cats];
                        l.insert(b, l.removeAt(a));
                        _saveOrder(l);
                      },
                      itemBuilder: (_, i) {
                        final c = cats[i];
                        final id = '${c['category_id']}';
                        final off = hidden.contains(id);
                        return ListTile(
                          key: ValueKey(id),
                          leading: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_indicator, color: C.dimmer)),
                          title: Text('${c['category_name']}', style: TextStyle(color: off ? C.dimmer : C.text, decoration: off ? TextDecoration.lineThrough : null)),
                          trailing: IconButton(
                            icon: Icon(off ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: off ? C.dimmer : C.gold),
                            onPressed: () => _toggleHidden(id),
                          ),
                        );
                      },
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: cats.length + 1,
                      itemBuilder: (_, i) {
                        if (i == 0) {
                          return _CatTile(name: kind == 'live' ? tr('all_channels') : tr('all'), count: total, icon: Icons.apps_rounded, onTap: () => _open('all'));
                        }
                        final c = cats[i - 1];
                        final id = '${c['category_id']}';
                        return _CatTile(name: '${c['category_name']}', count: Api.i.items(kind, id).length, onTap: () => _open(id));
                      },
                    ),
            ),
          ]),
        );
      },
    );
  }
}

class _CatTile extends StatelessWidget {
  final String name;
  final int count;
  final IconData? icon;
  final VoidCallback onTap;
  const _CatTile({required this.name, required this.count, required this.onTap, this.icon});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        child: Material(
          color: C.glass,
          borderRadius: BorderRadius.circular(14),
          child: ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            onTap: onTap,
            leading: icon != null ? Icon(icon, color: C.gold) : null,
            title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('$count', style: const TextStyle(color: C.dimmer)),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, color: C.dimmer),
            ]),
          ),
        ),
      );
}

/// Items of one category: search, sort, refresh.
class ItemsScreen extends StatefulWidget {
  final String kind, cat;
  const ItemsScreen({super.key, required this.kind, required this.cat});
  @override
  State<ItemsScreen> createState() => _ItemsScreenState();
}

class _ItemsScreenState extends State<ItemsScreen> {
  final _q = TextEditingController();
  late String _sort = '${Store.get('sort.${widget.kind}') ?? 'default'}';

  String get kind => widget.kind;

  List<String> get _sorts => kind == 'live' ? ['default', 'name'] : ['default', 'added', 'name', 'rating'];

  List<J> _list() {
    var l = Api.i.items(kind, widget.cat);
    final q = normalizeSearch(_q.text);
    if (q.isNotEmpty) l = l.where((x) => normalizeSearch(nameOf(x)).contains(q)).toList();
    if (_sort != 'default') {
      l = [...l];
      int n(J x, String f) => int.tryParse('${x[f] ?? 0}') ?? 0;
      double r(J x) => double.tryParse('${x['rating'] ?? 0}') ?? 0;
      switch (_sort) {
        case 'name':
          l.sort((a, b) => nameOf(a).toLowerCase().compareTo(nameOf(b).toLowerCase()));
          break;
        case 'added':
          final f = kind == 'series' ? 'last_modified' : 'added';
          l.sort((a, b) => n(b, f).compareTo(n(a, f)));
          break;
        case 'rating':
          l.sort((a, b) => r(b).compareTo(r(a)));
          break;
      }
    }
    return l;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: Store.tick,
      builder: (context, _, __) {
        final items = _list();
        final title = catName(kind, widget.cat);
        return Scaffold(
          appBar: AppBar(
            title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18)),
              Text('${kindTitle(kind)} · ${items.length}', style: const TextStyle(fontSize: 12, color: C.dimmer)),
            ]),
            actions: [
              PopupMenuButton<String>(
                tooltip: tr('sort'),
                icon: const Icon(Icons.sort),
                initialValue: _sort,
                onSelected: (s) {
                  setState(() => _sort = s);
                  Store.set('sort.$kind', s);
                },
                itemBuilder: (_) => [for (final s in _sorts) CheckedPopupMenuItem(value: s, checked: s == _sort, child: Text(tr('sort_$s')))],
              ),
              IconButton(tooltip: tr('refresh'), icon: const Icon(Icons.refresh), onPressed: () => refreshWithProgress(context, kind, widget.cat)),
            ],
          ),
          body: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                controller: _q,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: '${tr('search_in')} $title',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _q.text.isEmpty ? null : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(_q.clear)),
                ),
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? EmptyNote(tr(_q.text.isEmpty ? 'nothing' : 'no_results'))
                  : kind == 'live'
                      ? ListView.builder(
                          padding: const EdgeInsets.only(bottom: 24),
                          itemCount: items.length,
                          itemBuilder: (_, i) => ChannelTile(ch: items[i], onTap: () => openItem(context, 'live', items[i], channelList: items)),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
                          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 140,
                            childAspectRatio: 0.54,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 14,
                          ),
                          itemCount: items.length,
                          itemBuilder: (_, i) {
                            final x = items[i];
                            final y = '${x['year'] ?? x['releaseDate'] ?? ''}';
                            return Poster(
                              item: x,
                              sub: y.length >= 4 ? y.substring(0, 4) : null,
                              onTap: () => openItem(context, kind, x),
                            );
                          },
                        ),
            ),
          ]),
        );
      },
    );
  }
}
