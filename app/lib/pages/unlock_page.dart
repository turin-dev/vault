import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../src/rust/api/vault.dart';
import '../theme.dart';
import '../widgets.dart';
import 'home_page.dart';
import 'join_page.dart';

/// 볼트가 없으면 생성, 있으면 잠금 해제.
class UnlockPage extends StatefulWidget {
  const UnlockPage({super.key});

  @override
  State<UnlockPage> createState() => _UnlockPageState();
}

class _UnlockPageState extends State<UnlockPage> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool? _vaultExists;
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  // 실패 시 지수 백오프 — 로컬 무차별 대입 억제
  int _failCount = 0;
  DateTime? _retryAt;
  Timer? _countdown;

  @override
  void initState() {
    super.initState();
    vaultExists(path: vaultPath)
        .then((v) => mounted ? setState(() => _vaultExists = v) : null);
  }

  @override
  void dispose() {
    _countdown?.cancel();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  int get _retrySeconds {
    final at = _retryAt;
    if (at == null) return 0;
    final left = at.difference(DateTime.now()).inSeconds;
    return left > 0 ? left : 0;
  }

  void _applyBackoff() {
    _failCount++;
    if (_failCount >= 3) {
      final secs = math.min(30, math.pow(2, _failCount - 2).toInt());
      _retryAt = DateTime.now().add(Duration(seconds: secs));
      _countdown?.cancel();
      _countdown = Timer.periodic(const Duration(seconds: 1), (t) {
        if (_retrySeconds == 0) t.cancel();
        if (mounted) setState(() {});
      });
    }
  }

  Future<void> _submit() async {
    if (_retrySeconds > 0) return;
    final create = !(_vaultExists ?? true);
    final pw = _password.text;
    if (pw.isEmpty) return;
    if (create) {
      if (pw.length < 10) {
        setState(() => _error = '마스터 비밀번호는 10자 이상이어야 합니다');
        return;
      }
      if (pw != _confirm.text) {
        setState(() => _error = '비밀번호가 일치하지 않습니다');
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (create) {
        await createVault(path: vaultPath, password: pw);
      } else {
        await unlockVault(path: vaultPath, password: pw);
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomePage()));
    } catch (e) {
      _applyBackoff();
      setState(() {
        _busy = false;
        _error = '$e'
            .replaceFirst('AnyhowException(', '')
            .replaceFirst(RegExp(r'\)$'), '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final exists = _vaultExists;
    return Scaffold(
      body: GlowBackdrop(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: exists == null
                  ? const SizedBox(
                      height: 220,
                      child: Center(child: CircularProgressIndicator()))
                  : _form(context, create: !exists),
            ),
          ),
        ),
      ),
    );
  }

  Widget _form(BuildContext context, {required bool create}) {
    final retry = _retrySeconds;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 로고
        Center(
          child: Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [G.mint, G.mintDeep],
              ),
              boxShadow: [
                BoxShadow(
                  color: G.mint.withValues(alpha: 0.35),
                  blurRadius: 28,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(Icons.shield_rounded, size: 40, color: G.onMint),
          ),
        ),
        const SizedBox(height: 20),
        const Text('Vault',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            )),
        const SizedBox(height: 6),
        Text(
          create ? '새 보관함을 만듭니다.\n마스터 비밀번호는 복구할 수 없습니다.' : '마스터 비밀번호로 잠금을 해제하세요',
          textAlign: TextAlign.center,
          style: const TextStyle(color: G.sub, fontSize: 14, height: 1.5),
        ),
        const SizedBox(height: 28),
        TextField(
          controller: _password,
          obscureText: _obscure,
          autofocus: true,
          enabled: !_busy,
          onChanged: create ? (_) => setState(() {}) : null,
          onSubmitted: create ? null : (_) => _submit(),
          decoration: InputDecoration(
            labelText: '마스터 비밀번호',
            prefixIcon: const Icon(Icons.key_rounded),
            suffixIcon: IconButton(
              icon: Icon(_obscure
                  ? Icons.visibility_rounded
                  : Icons.visibility_off_rounded),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        if (create) ...[
          const SizedBox(height: 10),
          StrengthBar(password: _password.text),
          const SizedBox(height: 10),
          TextField(
            controller: _confirm,
            obscureText: true,
            enabled: !_busy,
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(
              labelText: '비밀번호 확인',
              prefixIcon: Icon(Icons.key_rounded),
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: G.danger.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: G.danger.withValues(alpha: 0.35)),
            ),
            child: Row(children: [
              const Icon(Icons.error_outline_rounded,
                  size: 18, color: G.danger),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_error!,
                    style: const TextStyle(color: G.danger, fontSize: 13)),
              ),
            ]),
          ),
        ],
        const SizedBox(height: 22),
        FilledButton.icon(
          onPressed: (_busy || retry > 0) ? null : _submit,
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: G.onMint))
              : Icon(create ? Icons.add_rounded : Icons.lock_open_rounded),
          label: Text(retry > 0
              ? '다시 시도까지 $retry초'
              : create
                  ? '보관함 만들기'
                  : '잠금 해제'),
        ),
        if (create) ...[
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: _busy
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const JoinPage())),
            icon: const Icon(Icons.devices_rounded, size: 18),
            label: const Text('다른 기기에서 가져오기'),
          ),
        ],
        const SizedBox(height: 26),
        // 보안 스펙
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: const [
            _SpecChip(icon: Icons.memory_rounded, label: 'Argon2id 64MiB'),
            _SpecChip(icon: Icons.enhanced_encryption_rounded, label: 'XChaCha20-Poly1305'),
            _SpecChip(icon: Icons.visibility_off_rounded, label: 'Zero-knowledge'),
          ],
        ),
      ],
    );
  }
}

class _SpecChip extends StatelessWidget {
  const _SpecChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: G.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: G.border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: G.mint),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(
                fontSize: 11.5, color: G.sub, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}
