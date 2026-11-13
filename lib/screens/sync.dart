import 'package:flutter/material.dart';

import '../api.dart';
import '../l10n.dart';
import '../main.dart';
import '../theme.dart';
import 'login.dart';
import 'shell.dart';

/// First-time (or full) download of the library with a progress bar.
class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});
  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  SyncProgress? _p;
  String? _err;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _err = null;
      _p = null;
    });
    try {
      await Api.i.syncAll((p) {
        if (mounted) setState(() => _p = p);
      });
      if (!mounted) return;
      goRoot(context, const Shell());
    } catch (e) {
      if (mounted) setState(() => _err = errText(e, tr));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    final pct = ((p?.frac ?? 0) * 100).floor();
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(tr('sync_title'), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text(tr('sync_sub'), style: const TextStyle(color: C.dim)),
                  const SizedBox(height: 36),
                  Text('$pct%', style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w300, color: C.gold)),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(value: p?.frac ?? 0, minHeight: 10, backgroundColor: C.card, color: C.gold),
                  ),
                  const SizedBox(height: 14),
                  if (_err == null && p != null)
                    Row(children: [
                      Expanded(
                        child: Text(
                          p.saving ? tr('saving') : '${p.step}/${p.steps} · ${tr(p.labelKey)}',
                          style: const TextStyle(color: C.dim),
                        ),
                      ),
                      Text('${mb(p.bytes)} ${tr('downloaded')}', style: const TextStyle(color: C.dimmer, fontSize: 13)),
                    ]),
                  if (_err != null) ...[
                    Text(_err!, style: const TextStyle(color: C.red)),
                    const SizedBox(height: 18),
                    FilledButton(onPressed: _run, child: Text(tr('try_again'))),
                    const SizedBox(height: 8),
                    if (Api.i.lib != null) OutlinedButton(onPressed: () => goRoot(context, const Shell()), child: Text(tr('continue'))),
                    TextButton(
                      onPressed: () async {
                        await Api.i.logout();
                        if (context.mounted) goRoot(context, const LoginScreen());
                      },
                      child: Text(tr('sign_out')),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
