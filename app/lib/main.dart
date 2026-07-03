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

  void _goToUnlock() {
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const UnlockPage()),
      (_) => false,
    );
  }

  /// 화면만 잠근다 — 볼트 키는 메모리에 유지해 자동완성이 계속 동작하게 한다.
  /// (업계 표준: 백그라운드에서 키를 즉시 파기하면 자동완성이 불가능)
  Future<void> _lockUiOnly() async {
    if (await isUnlocked()) _goToUnlock();
  }

  /// 완전 잠금 — 볼트 키를 메모리에서 파기(zeroize).
  Future<void> _lockFully() async {
    if (await isUnlocked()) {
      await lockVault();
      _goToUnlock();
    }
  }

  /// 입력이 없으면 5분 후 완전 잠금.
  void _resetIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleLimit, _lockFully);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 백그라운드 진입: UI만 잠근다. 키는 유지되어 다른 앱에서 자동완성이 동작한다.
    // 완전 잠금은 유휴 타이머(5분) 또는 명시적 잠금 버튼이 담당.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _lockUiOnly();
    } else if (state == AppLifecycleState.detached) {
      _lockFully();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vault',
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
