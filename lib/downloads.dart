import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'store.dart';

/// Offline downloads of movies and episodes (background_downloader keeps going in the background).
/// Metadata lives in Store 'downloads': [{key, tid, type, id, name, sub, icon, ext, seriesId, season, file, done, size}].
class Downloads {
  Downloads._();
  static final Downloads i = Downloads._();

  final tick = ValueNotifier<int>(0);
  final Map<String, double> _progress = {}; // tid -> 0..1
  final Map<String, TaskStatus> _status = {};
  final Map<String, DownloadTask> _tasks = {};
  String _docs = '';
  static const _group = 'iptv';

  static String tidOf(String key) => key.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');

  Future<void> init() async {
    try {
      _docs = (await getApplicationDocumentsDirectory()).path;
      FileDownloader().configureNotification(
        running: const TaskNotification('Downloading', '{displayName}'),
        complete: const TaskNotification('Downloaded', '{displayName}'),
        error: const TaskNotification('Download failed', '{displayName}'),
        paused: const TaskNotification('Download paused', '{displayName}'),
        progressBar: true,
      );
      FileDownloader().updates.listen(_onUpdate);
      await FileDownloader().start();
      for (final r in await FileDownloader().database.allRecords(group: _group)) {
        _status[r.task.taskId] = r.status;
        _progress[r.task.taskId] = r.progress;
        if (r.task is DownloadTask) _tasks[r.task.taskId] = r.task as DownloadTask;
        if (r.status == TaskStatus.complete) _markDone(r.task.taskId);
      }
      tick.value++;
    } catch (_) {}
  }

  List<Map<String, dynamic>> all() => ((Store.get('downloads') as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  Map<String, dynamic>? meta(String key) {
    for (final d in all()) {
      if (d['key'] == key) return d;
    }
    return null;
  }

  void _saveAll(List<Map<String, dynamic>> l) {
    Store.set('downloads', l);
    tick.value++;
  }

  String _pathOf(Map d) => '$_docs/downloads/${d['file']}';

  /// Local file to play, or null if not fully downloaded.
  String? localPath(String key) {
    final d = meta(key);
    if (d == null || d['done'] != true || _docs.isEmpty) return null;
    final p = _pathOf(d);
    return File(p).existsSync() ? p : null;
  }

  bool isDownloaded(String key) => localPath(key) != null;
  bool isActive(String key) {
    final d = meta(key);
    if (d == null || d['done'] == true) return false;
    final s = _status[d['tid']];
    return s != TaskStatus.failed && s != TaskStatus.canceled && s != TaskStatus.notFound;
  }

  bool isPaused(String key) => _status[tidOf(key)] == TaskStatus.paused;
  bool isFailed(String key) {
    final s = _status[tidOf(key)];
    return meta(key)?['done'] != true && (s == TaskStatus.failed || s == TaskStatus.notFound);
  }

  double progressOf(String key) => (_progress[tidOf(key)] ?? 0).clamp(0.0, 1.0).toDouble();

  Future<void> start({
    required String key,
    required String url,
    required String type,
    required String id,
    required String name,
    String? sub,
    String? icon,
    String? ext,
    String? seriesId,
    String? season,
  }) async {
    final tid = tidOf(key);
    final e = (ext ?? url.split('.').last).toLowerCase();
    final file = '$tid.$e';
    final task = DownloadTask(
      taskId: tid,
      url: url,
      filename: file,
      directory: 'downloads',
      baseDirectory: BaseDirectory.applicationDocuments,
      group: _group,
      updates: Updates.statusAndProgress,
      allowPause: true,
      retries: 3,
      displayName: sub == null ? name : '$name · $sub',
    );
    final l = all()..removeWhere((d) => d['key'] == key);
    l.insert(0, {
      'key': key,
      'tid': tid,
      'type': type,
      'id': id,
      'name': name,
      'sub': sub,
      'icon': icon,
      'ext': e,
      'seriesId': seriesId,
      'season': season,
      'file': file,
      'done': false,
      'size': 0,
      'at': DateTime.now().millisecondsSinceEpoch,
    });
    _tasks[tid] = task;
    _status[tid] = TaskStatus.enqueued;
    _progress[tid] = 0;
    _saveAll(l);
    try {
      await FileDownloader().permissions.request(PermissionType.notifications);
    } catch (_) {}
    await FileDownloader().enqueue(task);
  }

  Future<void> pause(String key) async {
    final t = _tasks[tidOf(key)];
    if (t != null) await FileDownloader().pause(t);
  }

  Future<void> resume(String key) async {
    final t = _tasks[tidOf(key)];
    if (t != null) await FileDownloader().resume(t);
  }

  Future<void> retry(String key) async {
    final d = meta(key);
    final t = _tasks[tidOf(key)];
    if (d == null || t == null) return;
    _status[t.taskId] = TaskStatus.enqueued;
    tick.value++;
    await FileDownloader().enqueue(t);
  }

  /// Cancels a running download or deletes a finished one, including the file.
  Future<void> remove(String key) async {
    final tid = tidOf(key);
    final d = meta(key);
    try {
      await FileDownloader().cancelTaskWithId(tid);
    } catch (_) {}
    try {
      await FileDownloader().database.deleteRecordWithId(tid);
    } catch (_) {}
    if (d != null && _docs.isNotEmpty) {
      try {
        final f = File(_pathOf(d));
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    _status.remove(tid);
    _progress.remove(tid);
    _tasks.remove(tid);
    _saveAll(all()..removeWhere((e) => e['key'] == key));
  }

  int totalBytes() => all().fold<int>(0, (s, d) => s + ((d['size'] as num?)?.toInt() ?? 0));

  void _markDone(String tid) {
    final l = all();
    var changed = false;
    for (final d in l) {
      if (d['tid'] == tid && d['done'] != true) {
        d['done'] = true;
        try {
          d['size'] = File(_pathOf(d)).lengthSync();
        } catch (_) {}
        changed = true;
      }
    }
    if (changed) _saveAll(l);
  }

  void _onUpdate(TaskUpdate u) {
    final tid = u.task.taskId;
    if (u.task.group != _group) return;
    if (u.task is DownloadTask) _tasks[tid] = u.task as DownloadTask;
    if (u is TaskStatusUpdate) {
      _status[tid] = u.status;
      if (u.status == TaskStatus.complete) {
        _progress[tid] = 1;
        _markDone(tid);
      }
    } else if (u is TaskProgressUpdate) {
      if (u.progress >= 0) _progress[tid] = u.progress;
    }
    tick.value++;
  }
}
