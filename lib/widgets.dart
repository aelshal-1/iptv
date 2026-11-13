import 'package:flutter/material.dart';

import 'api.dart';
import 'downloads.dart';
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

/// Download control for a movie or episode. [compact] = icon only (episode rows).
class DownloadButton extends StatelessWidget {
  final PlayItem item;
  final bool compact;
  const DownloadButton({super.key, required this.item, this.compact = false});

  void _menu(BuildContext context, List<(IconData, String, VoidCallback, bool)> actions) {
    showModalBottomSheet(
      context: context,
      backgroundColor: C.surface,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis), subtitle: item.sub != null ? Text(item.sub!, style: const TextStyle(color: C.dimmer)) : null),
          for (final a in actions)
            ListTile(
              leading: Icon(a.$1, color: a.$4 ? C.red : null),
              title: Text(a.$2, style: TextStyle(color: a.$4 ? C.red : null)),
              onTap: () {
                Navigator.pop(ctx);
                a.$3();
              },
            ),
        ]),
      ),
    );
  }

  void _tap(BuildContext context) {
    final d = Downloads.i;
    final k = item.key;
    if (d.isDownloaded(k)) {
      _menu(context, [(Icons.delete_outline, tr('delete_dl'), () => d.remove(k), true)]);
    } else if (d.isFailed(k)) {
      d.retry(k);
    } else if (d.isActive(k)) {
      _menu(context, [
        if (d.isPaused(k)) (Icons.play_arrow_rounded, tr('resume_dl'), () => d.resume(k), false) else (Icons.pause_rounded, tr('pause_dl'), () => d.pause(k), false),
        (Icons.close_rounded, tr('cancel_dl'), () => d.remove(k), true),
      ]);
    } else {
      d.start(key: k, url: item.url, type: item.type, id: item.id, name: item.title, sub: item.sub, icon: item.icon, ext: item.ext, seriesId: item.seriesId, season: item.season);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('${tr('dl_started')}. ${tr('dl_note')}'), duration: const Duration(seconds: 4)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: Downloads.i.tick,
      builder: (context, _, __) {
        final d = Downloads.i;
        final k = item.key;
        final done = d.isDownloaded(k), active = d.isActive(k), failed = d.isFailed(k), paused = d.isPaused(k);
        final p = d.progressOf(k);
        if (compact) {
          Widget icon;
          if (done) {
            icon = const Icon(Icons.download_done_rounded, color: C.gold);
          } else if (failed) {
            icon = const Icon(Icons.error_outline, color: C.red);
          } else if (active) {
            icon = SizedBox(
              width: 24,
              height: 24,
              child: Stack(alignment: Alignment.center, children: [
                CircularProgressIndicator(value: p > 0 ? p : null, strokeWidth: 2.5, color: C.gold, backgroundColor: Colors.white12),
                Icon(paused ? Icons.play_arrow_rounded : Icons.pause_rounded, size: 13),
              ]),
            );
          } else {
            icon = const Icon(Icons.download_rounded, color: C.dim);
          }
          return IconButton(tooltip: tr('download'), icon: icon, onPressed: () => _tap(context));
        }
        final label = done
            ? tr('dl_done')
            : failed
                ? tr('retry_dl')
                : active
                    ? '${tr(paused ? 'paused' : 'downloading')} ${(p * 100).floor()}%'
                    : tr('download');
        return OutlinedButton.icon(
          onPressed: () => _tap(context),
          icon: Icon(done ? Icons.download_done_rounded : failed ? Icons.error_outline : active ? (paused ? Icons.pause_circle_outline : Icons.downloading_rounded) : Icons.download_rounded,
              color: done ? C.gold : failed ? C.red : null),
          label: Text(label),
        );
      },
    );
  }
}
