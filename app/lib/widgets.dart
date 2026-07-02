import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/rust/api/vault.dart';
import 'theme.dart';

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
        content: Row(children: [
          const Icon(Icons.check_circle_rounded, size: 18, color: G.mint),
          const SizedBox(width: 10),
          Expanded(child: Text('$label 복사됨 · 30초 후 자동 삭제')),
        ]),
        duration: const Duration(seconds: 2),
      ));
  }
}

const strengthLabels = ['매우 약함', '약함', '보통', '강함', '매우 강함'];
const strengthColors = [
  Color(0xFFFF6B6B),
  Color(0xFFFF9E6B),
  Color(0xFFFFC24B),
  Color(0xFF9BE05A),
  Color(0xFF2EE6A8),
];

/// 실시간 비밀번호 강도 막대 — 5칸 세그먼트.
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
    if (s == null) return const SizedBox(height: 20);
    final score = s.score.clamp(0, 4);
    final color = strengthColors[score];
    return SizedBox(
      height: 20,
      child: Row(children: [
        for (var i = 0; i < 5; i++) ...[
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              height: 5,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                color: i <= score ? color : G.surfaceHi,
              ),
            ),
          ),
          if (i < 4) const SizedBox(width: 4),
        ],
        const SizedBox(width: 12),
        Text(strengthLabels[score],
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: color)),
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
          style: const TextStyle(color: G.danger, fontSize: 13));
    }
    final t = _totp;
    if (t == null) return const SizedBox(height: 48);
    final code = t.code;
    final grouped = code.length == 6
        ? '${code.substring(0, 3)} ${code.substring(3)}'
        : code;
    final remaining = t.secondsRemaining.toInt();
    final period = t.period.toInt();
    final urgent = remaining <= 5;
    return Row(children: [
      Text(grouped,
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            letterSpacing: 3,
            color: urgent ? G.amber : G.mint,
            fontFeatures: const [FontFeature.tabularFigures()],
          )),
      const SizedBox(width: 16),
      SizedBox(
        width: 34,
        height: 34,
        child: Stack(alignment: Alignment.center, children: [
          TweenAnimationBuilder<double>(
            tween: Tween(end: remaining / period),
            duration: const Duration(milliseconds: 400),
            builder: (_, v, __) => CircularProgressIndicator(
              value: v,
              strokeWidth: 3.5,
              strokeCap: StrokeCap.round,
              backgroundColor: G.surfaceHi,
              color: urgent ? G.amber : G.mint,
            ),
          ),
          Text('$remaining',
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: G.sub)),
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
