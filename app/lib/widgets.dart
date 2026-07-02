import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/rust/api/vault.dart';

/// 민감한 값 복사 — 30초 뒤 클립보드에 같은 값이 남아 있으면 지운다.
Future<void> copySensitive(
    BuildContext context, String label, String value) async {
  await Clipboard.setData(ClipboardData(text: value));
  Timer(const Duration(seconds: 30), () async {
    final cur = await Clipboard.getData('text/plain');
    if (cur?.text == value) {
      await Clipboard.setData(const ClipboardData(text: ''));
    }
  });
  if (context.mounted) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text('$label 복사됨 · 30초 후 클립보드에서 삭제'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
  }
}

const strengthLabels = ['매우 약함', '약함', '보통', '강함', '매우 강함'];
const strengthColors = [
  Color(0xFFE53935),
  Color(0xFFFB8C00),
  Color(0xFFFDD835),
  Color(0xFF7CB342),
  Color(0xFF2E7D32),
];

/// 실시간 비밀번호 강도 막대. 입력이 바뀔 때마다 Rust zxcvbn 호출.
class StrengthBar extends StatefulWidget {
  const StrengthBar({super.key, required this.password});

  final String password;

  @override
  State<StrengthBar> createState() => _StrengthBarState();
}

class _StrengthBarState extends State<StrengthBar> {
  StrengthDto? _strength;

  @override
  void initState() {
    super.initState();
    _evaluate();
  }

  @override
  void didUpdateWidget(StrengthBar old) {
    super.didUpdateWidget(old);
    if (old.password != widget.password) _evaluate();
  }

  Future<void> _evaluate() async {
    if (widget.password.isEmpty) {
      setState(() => _strength = null);
      return;
    }
    final s = await passwordStrength(password: widget.password);
    if (mounted && widget.password.isNotEmpty) setState(() => _strength = s);
  }

  @override
  Widget build(BuildContext context) {
    final s = _strength;
    if (s == null) return const SizedBox(height: 22);
    final score = s.score.clamp(0, 4);
    return SizedBox(
      height: 22,
      child: Row(children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: (score + 1) / 5),
              duration: const Duration(milliseconds: 300),
              builder: (_, v, __) => LinearProgressIndicator(
                value: v,
                minHeight: 6,
                backgroundColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                color: strengthColors[score],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(strengthLabels[score],
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: strengthColors[score])),
      ]),
    );
  }
}

/// TOTP 실시간 코드 + 남은 시간 원형 게이지.
class TotpView extends StatefulWidget {
  const TotpView({super.key, required this.secret});

  final String secret;

  @override
  State<TotpView> createState() => _TotpViewState();
}

class _TotpViewState extends State<TotpView> {
  TotpDto? _totp;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _tick() async {
    try {
      final t = await totpNow(input: widget.secret);
      if (mounted) setState(() => _totp = t);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Text('TOTP 오류: $_error',
          style: TextStyle(color: Theme.of(context).colorScheme.error));
    }
    final t = _totp;
    if (t == null) return const SizedBox(height: 48);
    final code = t.code;
    final grouped = code.length == 6
        ? '${code.substring(0, 3)} ${code.substring(3)}'
        : code;
    final remaining = t.secondsRemaining.toInt();
    final period = t.period.toInt();
    return Row(children: [
      Text(grouped,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
              fontWeight: FontWeight.w700,
              letterSpacing: 2)),
      const SizedBox(width: 16),
      SizedBox(
        width: 32,
        height: 32,
        child: Stack(alignment: Alignment.center, children: [
          CircularProgressIndicator(
            value: remaining / period,
            strokeWidth: 3,
            color: remaining <= 5
                ? Theme.of(context).colorScheme.error
                : Theme.of(context).colorScheme.primary,
          ),
          Text('$remaining', style: const TextStyle(fontSize: 11)),
        ]),
      ),
      const Spacer(),
      IconButton(
        icon: const Icon(Icons.copy_rounded),
        tooltip: '코드 복사',
        onPressed: () => copySensitive(context, 'TOTP 코드', code),
      ),
    ]);
  }
}
