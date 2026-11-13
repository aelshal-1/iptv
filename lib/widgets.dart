import 'package:flutter/material.dart';

import 'api.dart';
import 'l10n.dart';
import 'main.dart';
import 'screens/detail.dart';
import 'screens/player.dart';
import 'store.dart';
import 'theme.dart';

String nameOf(Map x) => '${x['name'] ?? x['title'] ?? ''}'.trim();
String? iconOf(Map x) {
  final s = '${x['stream_icon'] ?? x['cover'] ?? x['icon'] ?? ''}'.trim();
  return s.isEmpty ? null : s;
}

String ratingOf(Map x) {
  final r = double.tryParse('${x['rating'] ?? ''}') ?? 0;
  return r > 0 ? r.toStringAsFixed(1) : '';
}

/// Ordered categories for a kind (user order first, then server order). Hidden ones removed unless [withHidden].
List<J> orderedCats(String kind, {bool withHidden = false}) {
  final cats = Api.i.categories(kind);
  final order = Store.strList('catOrder.$kind');
  final hidden = Store.strList('catHidden.$kind').toSet();
  int pos(J c) {
    final i = order.indexOf('${c['category_id']}');
    return i < 0 ? order.length + cats.indexOf(c) : i;
  }

  final list = [...cats]..sort((a, b) => pos(a).compareTo(pos(b)));
  if (withHidden) return list;
  return list.where((c) => !hidden.contains('${c['category_id']}')).toList();
}

String catName(String kind, String id) {
  if (id.isEmpty || id == 'all') return tr(kind == 'live' ? 'all_channels' : 'all');
  for (final c in Api.i.categories(kind)) {
    if ('${c['category_id']}' == id) return '${c['category_name']}';
  }
  return '';
}

/// Open an item from any list.
void openItem(BuildContext context, String kind, Map src, {List<J>? channelList}) {
  final x = Map<String, dynamic>.from(src);
  if (kind == 'live') {
    final list = channelList != null ? [...channelList] : <J>[x];
    var i = list.indexWhere((c) => '${c['stream_id']}' == '${x['stream_id'] ?? x['id']}');
    if (i < 0) {
      list.insert(0, {...x, 'stream_id': x['stream_id'] ?? x['id']});
      i = 0;
    }
    PlayerScreen.openLive(context, list, i);
  } else if (kind == 'vod' || kind == 'movie') {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => MovieDetail(item: {...x, 'stream_id': x['stream_id'] ?? x['id']})));
  } else {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => SeriesDetail(item: {...x, 'series_id': x['series_id'] ?? x['id']})));
  }
}

class Poster extends StatelessWidget {
  final Map item;
  final VoidCallback onTap;
  final double? progress;
  final String? sub;
  const Poster({super.key, required this.item, required this.onTap, this.progress, this.sub});

  @override
  Widget build(BuildContext context) {
    final r = ratingOf(item);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(fit: StackFit.expand, children: [
              NetImg(iconOf(item), label: nameOf(item)),
              if (r.isNotEmpty)
                PositionedDirectional(
                  top: 6,
                  end: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.65), borderRadius: BorderRadius.circular(8)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.star_rounded, size: 13, color: C.gold),
                      const SizedBox(width: 2),
                      Text(r, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
              if (progress != null)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: LinearProgressIndicator(value: progress, minHeight: 4, backgroundColor: Colors.black54, color: C.gold),
                ),
            ]),
          ),
        ),
        const SizedBox(height: 6),
        Text(nameOf(item), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        if (sub != null) Text(sub!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: C.dimmer)),
      ]),
    );
  }
}

class ChannelTile extends StatelessWidget {
  final Map ch;
  final VoidCallback onTap;
  final bool playing;
  const ChannelTile({super.key, required this.ch, required this.onTap, this.playing = false});

  @override
  Widget build(BuildContext context) {
    final fav = Store.isFav('live', ch['stream_id'] ?? ch['id']);
    return ListTile(
      onTap: onTap,
      onLongPress: () => toggleFavToast(context, 'live', ch),
      selected: playing,
      selectedTileColor: C.glass,
      leading: SizedBox(
        width: 56,
        height: 40,
        child: ClipRRect(borderRadius: BorderRadius.circular(8), child: NetImg(iconOf(ch), label: '', fit: BoxFit.contain)),
      ),
      title: Text(nameOf(ch), maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: ch['num'] != null ? Text('${ch['num']}', style: const TextStyle(color: C.dimmer, fontSize: 12)) : null,
      trailing: IconButton(
        icon: Icon(fav ? Icons.star_rounded : Icons.star_border_rounded, color: fav ? C.gold : C.dimmer),
        onPressed: () => toggleFavToast(context, 'live', ch),
      ),
    );
  }
}

void toggleFavToast(BuildContext context, String type, Map x) {
  final on = Store.toggleFav(type, Map<String, dynamic>.from(x));
  toast(context, tr(on ? 'added_fav' : 'removed_fav'));
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 18, 8, 8),
        child: Row(children: [
          Expanded(child: Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
          if (trailing != null) trailing!,
        ]),
      );
}

class EmptyNote extends StatelessWidget {
  final String text;
  final IconData icon;
  const EmptyNote(this.text, {super.key, this.icon = Icons.inbox_outlined});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 44, color: C.dimmer),
            const SizedBox(height: 10),
            Text(text, textAlign: TextAlign.center, style: const TextStyle(color: C.dim)),
          ]),
        ),
      );
}

/// Runs a category refresh with a progress dialog. Returns the item count or null on error.
Future<int?> refreshWithProgress(BuildContext context, String kind, String cat) async {
  final frac = ValueNotifier<double>(0);
  final bytes = ValueNotifier<int>(0);
  final saving = ValueNotifier<bool>(false);
  int? count;
  Object? error;
  final nav = Navigator.of(context, rootNavigator: true);
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: C.surface,
        title: Text('${tr('refreshing')} · ${catName(kind, cat)}', style: const TextStyle(fontSize: 17)),
        content: ListenableBuilder(
          listenable: Listenable.merge([frac, bytes, saving]),
          builder: (_, __) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('${(frac.value * 100).floor()}%', style: const TextStyle(fontSize: 34, color: C.gold, fontWeight: FontWeight.w300)),
            const SizedBox(height: 8),
            ClipRRect(borderRadius: BorderRadius.circular(5), child: LinearProgressIndicator(value: frac.value, minHeight: 8, backgroundColor: C.card, color: C.gold)),
            const SizedBox(height: 10),
            Text(saving.value ? tr('saving') : '${mb(bytes.value)} ${tr('downloaded')}', style: const TextStyle(color: C.dim, fontSize: 13)),
          ]),
        ),
      ),
    ),
  );
  try {
    count = await Api.i.refreshCategory(kind, cat, (f, b, s) {
      frac.value = f;
      bytes.value = b;
      saving.value = s;
    });
    frac.value = 1;
  } catch (e) {
    error = e;
  }
  nav.pop();
  Store.tick.value++;
  if (context.mounted) {
    toast(context, error != null ? errText(error, tr) : '${tr('updated')} · $count ${tr('items')}');
  }
  return count;
}
