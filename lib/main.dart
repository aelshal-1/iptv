import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'api.dart';
import 'l10n.dart';
import 'screens/login.dart';
import 'screens/shell.dart';
import 'screens/sync.dart';
import 'store.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await Store.init();
  L10n.i.ar = Store.get('lang') == 'ar';
  Widget first = const LoginScreen();
  if (Api.i.restore()) {
    first = await Api.i.loadLibrary() ? const Shell() : const SyncScreen();
  }
  runApp(IptvApp(first: first));
}

class IptvApp extends StatefulWidget {
  final Widget first;
  const IptvApp({super.key, required this.first});
  @override
  State<IptvApp> createState() => _IptvAppState();
}

class _IptvAppState extends State<IptvApp> {
  @override
  void initState() {
    super.initState();
    L10n.i.addListener(_onLang);
  }

  @override
  void dispose() {
    L10n.i.removeListener(_onLang);
    super.dispose();
  }

  /// Language changed: rebuild every screen (texts come from tr()) without losing navigation.
  void _onLang() {
    setState(() {});
    void rebuild(Element e) {
      e.markNeedsBuild();
      e.visitChildren(rebuild);
    }

    (context as Element).visitChildren(rebuild);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IPTV Player',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      builder: (context, child) => Directionality(
        textDirection: L10n.i.ar ? TextDirection.rtl : TextDirection.ltr,
        child: child!,
      ),
      home: widget.first,
    );
  }
}

/// Replace the whole navigation stack with [w].
void goRoot(BuildContext context, Widget w) {
  Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => w), (_) => false);
}

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
}
