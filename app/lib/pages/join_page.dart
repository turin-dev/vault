import 'package:flutter/material.dart';

import '../app_state.dart';
import '../src/rust/api/sync.dart';
import '../theme.dart';
import 'home_page.dart';

/// 다른 기기에서 가져오기 — 서버 계정으로 이 기기에 볼트 복제.
class JoinPage extends StatefulWidget {
  const JoinPage({super.key});

  @override
  State<JoinPage> createState() => _JoinPageState();
}

class _JoinPageState extends State<JoinPage> {
  final _url = TextEditingController(text: 'https://sync.turin.my');
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    if (_username.text.trim().isEmpty || _password.text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await joinRemoteVault(
        path: vaultPath,
        url: _url.text,
        username: _username.text.trim(),
        password: _password.text,
      );
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomePage()), (_) => false);
    } catch (e) {
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
    return Scaffold(
      appBar: AppBar(title: const Text('다른 기기에서 가져오기')),
      body: GlowBackdrop(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.devices_rounded, size: 44, color: G.mint),
                  const SizedBox(height: 12),
                  const Text(
                    '동기화 서버의 계정으로 이 기기에\n암호화된 볼트를 내려받습니다',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: G.sub, height: 1.6),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _url,
                    enabled: !_busy,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: '서버 주소',
                      prefixIcon: Icon(Icons.dns_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _username,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                      labelText: '사용자명',
                      prefixIcon: Icon(Icons.person_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: _obscure,
                    enabled: !_busy,
                    onSubmitted: (_) => _join(),
                    decoration: InputDecoration(
                      labelText: '마스터 비밀번호',
                      prefixIcon: const Icon(Icons.key_rounded),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure
                            ? Icons.visibility_rounded
                            : Icons.visibility_off_rounded),
                        onPressed: () =>
                            setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: G.danger.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: G.danger.withValues(alpha: 0.35)),
                      ),
                      child: Text(_error!,
                          style: const TextStyle(
                              color: G.danger, fontSize: 13)),
                    ),
                  ],
                  const SizedBox(height: 22),
                  FilledButton.icon(
                    onPressed: _busy ? null : _join,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: G.onMint))
                        : const Icon(Icons.cloud_download_rounded),
                    label: const Text('가져오기'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
