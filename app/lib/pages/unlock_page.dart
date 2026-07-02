import 'package:flutter/material.dart';

import '../app_state.dart';
import '../src/rust/api/vault.dart';
import '../widgets.dart';
import 'home_page.dart';

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

  @override
  void initState() {
    super.initState();
    vaultExists(path: vaultPath)
        .then((v) => mounted ? setState(() => _vaultExists = v) : null);
  }

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final create = !(_vaultExists ?? true);
    final pw = _password.text;
    if (pw.isEmpty) return;
    if (create) {
      if (pw.length < 8) {
        setState(() => _error = '마스터 비밀번호는 8자 이상이어야 합니다');
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
      setState(() {
        _busy = false;
        _error = '$e'.replaceFirst('AnyhowException(', '').replaceFirst(RegExp(r'\)$'), '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final exists = _vaultExists;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [scheme.primaryContainer, scheme.surface],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: exists == null
                      ? const SizedBox(
                          height: 200,
                          child: Center(child: CircularProgressIndicator()))
                      : _form(context, create: !exists),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _form(BuildContext context, {required bool create}) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.lock_rounded, size: 56, color: scheme.primary),
        const SizedBox(height: 12),
        Text('금고',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(
          create ? '새 금고를 만듭니다. 마스터 비밀번호는 복구할 수 없으니 잊지 마세요.' : '마스터 비밀번호를 입력하세요',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
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
              icon: Icon(
                  _obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        if (create) ...[
          const SizedBox(height: 8),
          StrengthBar(password: _password.text),
          const SizedBox(height: 8),
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
          const SizedBox(height: 12),
          Text(_error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.error)),
        ],
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _busy ? null : _submit,
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(create ? Icons.add_rounded : Icons.lock_open_rounded),
          label: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text(create ? '금고 만들기' : '잠금 해제',
                style: const TextStyle(fontSize: 16)),
          ),
        ),
      ],
    );
  }
}
