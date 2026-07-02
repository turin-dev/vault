import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app_state.dart';
import 'pages/unlock_page.dart';
import 'src/rust/api/vault.dart';
import 'src/rust/frb_generated.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  final dir = await getApplicationSupportDirectory();
  vaultPath = '${dir.path}/geumgo.vault';
  runApp(const GeumgoApp());
}

final navigatorKey = GlobalKey<NavigatorState>();

class GeumgoApp extends StatefulWidget {
  const GeumgoApp({super.key});

  @override
  State<GeumgoApp> createState() => _GeumgoAppState();
}

class _GeumgoAppState extends State<GeumgoApp> with WidgetsBindingObserver {
  static const _idleLimit = Duration(minutes: 5);
  Timer? _idleTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _resetIdleTimer();
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _lockNow() async {
    if (await isUnlocked()) {
      await lockVault();
      navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const UnlockPage()),
        (_) => false,
      );
    }
  }

  /// 입력이 없으면 5분 후 자동 잠금.
  void _resetIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleLimit, _lockNow);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 백그라운드로 가면 즉시 잠금 (모바일 앱 전환, 데스크톱 최소화)
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _lockNow();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '금고',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: buildGeumgoTheme(),
      home: const UnlockPage(),
      builder: (context, child) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _resetIdleTimer(),
        onPointerSignal: (_) => _resetIdleTimer(),
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
