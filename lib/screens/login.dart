import 'package:flutter/material.dart';

import '../api.dart';
import '../l10n.dart';
import '../main.dart';
import '../store.dart';
import '../theme.dart';
import 'sync.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _url = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false, _hide = true;
  String? _err;

  @override
  void initState() {
    super.initState();
    final last = Store.get('lastLogin');
    if (last is Map) {
      _url.text = '${last['url'] ?? ''}';
      _user.text = '${last['user'] ?? ''}';
    }
  }

  Future<void> _connect() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await Api.i.login(_url.text, _user.text, _pass.text);
      if (!mounted) return;
      goRoot(context, const SyncScreen());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _err = errText(e, tr);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(alignment: AlignmentDirectional.centerEnd, child: const LangButton()),
                  const SizedBox(height: 12),
                  Row(children: [
                    const AppLogo(size: 56),
                    const SizedBox(width: 12),
                    Text(tr('app'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
                  ]),
                  const SizedBox(height: 28),
                  Text(tr('connect_title'), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text(tr('connect_sub'), style: const TextStyle(color: C.dim)),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _url,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(labelText: tr('server'), hintText: 'http://example.com:8080', prefixIcon: const Icon(Icons.dns_outlined)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _user,
                    autocorrect: false,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(labelText: tr('username'), prefixIcon: const Icon(Icons.person_outline)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pass,
                    obscureText: _hide,
                    autocorrect: false,
                    textDirection: TextDirection.ltr,
                    onSubmitted: (_) => _busy ? null : _connect(),
                    decoration: InputDecoration(
                      labelText: tr('password'),
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined), onPressed: () => setState(() => _hide = !_hide)),
                    ),
                  ),
                  if (_err != null) ...[
                    const SizedBox(height: 14),
                    Text(_err!, style: const TextStyle(color: C.red)),
                  ],
                  const SizedBox(height: 22),
                  SizedBox(
                    height: 54,
                    child: FilledButton(
                      onPressed: _busy ? null : _connect,
                      child: _busy
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: C.onGold))
                          : Text(tr('connect'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(tr('legal'), textAlign: TextAlign.center, style: const TextStyle(color: C.dimmer, fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class LangButton extends StatelessWidget {
  const LangButton({super.key});
  @override
  Widget build(BuildContext context) => TextButton.icon(
        icon: const Icon(Icons.translate, size: 18),
        label: Text(L10n.i.ar ? 'English' : 'العربية'),
        onPressed: () {
          final ar = !L10n.i.ar;
          Store.set('lang', ar ? 'ar' : 'en');
          L10n.i.set(ar);
        },
      );
}
