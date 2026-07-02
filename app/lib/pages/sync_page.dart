import 'package:flutter/material.dart';

import '../src/rust/api/sync.dart';
import '../theme.dart';

/// 동기화 설정 — 계정 등록, 수동 동기화, 상태 표시.
class SyncPage extends StatefulWidget {
  const SyncPage({super.key});

  @override
  State<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends State<SyncPage> {
  final _url = TextEditingController(text: 'https://sync.turin.my');
  final _username = TextEditingController();
  SyncConfigDto? _config;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _status;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _url.dispose();
    _username.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final c = await getSyncConfig();
      if (mounted) {
        setState(() {
          _config = c;
          _loading = false;
          if (c != null) {
            _url.text = c.url;
            _username.text = c.username;
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _clean(Object e) => '$e'
      .replaceFirst('AnyhowException(', '')
      .replaceFirst(RegExp(r'\)$'), '');

  Future<void> _register() async {
    setState(() {
      _busy = true;
      _error = null;
      _status = null;
    });
    try {
      await registerAccount(url: _url.text, username: _username.text.trim());
      setState(() => _status = '계정이 등록되고 볼트가 업로드되었습니다');
      await _reload();
    } catch (e) {
      setState(() => _error = _clean(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sync() async {
    setState(() {
      _busy = true;
      _error = null;
      _status = null;
    });
    try {
      final r = await syncNow();
      setState(() =>
          _status = '동기화 완료 — 받음 ${r.pulled}개 · 서버 리비전 ${r.serverRevision}');
      await _reload();
    } catch (e) {
      setState(() => _error = _clean(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _fmtTime(int unix) {
    if (unix == 0) return '-';
    final d = DateTime.fromMillisecondsSinceEpoch(unix * 1000);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final connected = _config != null;
    return Scaffold(
      appBar: AppBar(title: const Text('동기화')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 상태 카드
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                        color: connected
                            ? G.mint.withValues(alpha: 0.30)
                            : G.border),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        connected
                            ? G.mint.withValues(alpha: 0.07)
                            : G.surfaceHi.withValues(alpha: 0.4),
                        G.surface,
                      ],
                    ),
                  ),
                  padding: const EdgeInsets.all(18),
                  child: Row(children: [
                    Icon(
                      connected
                          ? Icons.cloud_done_rounded
                          : Icons.cloud_off_rounded,
                      size: 34,
                      color: connected ? G.mint : G.faint,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              connected ? '동기화 연결됨' : '동기화 미설정',
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              connected
                                  ? '${_config!.username} @ ${_config!.url.replaceFirst(RegExp('https?://'), '')}\n'
                                      '마지막 동기화 ${_fmtTime(_config!.lastSyncAt)} · 리비전 ${_config!.sinceRevision}'
                                  : '서버에 계정을 만들면 모든 기기에서\n암호화된 볼트가 실시간 공유됩니다',
                              style: const TextStyle(
                                  fontSize: 12.5, color: G.sub, height: 1.5),
                            ),
                          ]),
                    ),
                  ]),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _url,
                  enabled: !connected && !_busy,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: '서버 주소',
                    prefixIcon: Icon(Icons.dns_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _username,
                  enabled: !connected && !_busy,
                  decoration: const InputDecoration(
                    labelText: '사용자명 (소문자/숫자/._-@)',
                    prefixIcon: Icon(Icons.person_rounded),
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
                      border:
                          Border.all(color: G.danger.withValues(alpha: 0.35)),
                    ),
                    child: Text(_error!,
                        style:
                            const TextStyle(color: G.danger, fontSize: 13)),
                  ),
                ],
                if (_status != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: G.mint.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: G.mint.withValues(alpha: 0.30)),
                    ),
                    child: Text(_status!,
                        style: const TextStyle(color: G.mint, fontSize: 13)),
                  ),
                ],
                const SizedBox(height: 20),
                if (!connected)
                  FilledButton.icon(
                    onPressed: _busy ? null : _register,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: G.onMint))
                        : const Icon(Icons.cloud_upload_rounded),
                    label: const Text('계정 만들고 업로드'),
                  )
                else
                  FilledButton.icon(
                    onPressed: _busy ? null : _sync,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: G.onMint))
                        : const Icon(Icons.sync_rounded),
                    label: const Text('지금 동기화'),
                  ),
                const SizedBox(height: 24),
                const Text(
                  '서버는 암호화된 블롭만 저장합니다 (zero-knowledge).\n'
                  '마스터 비밀번호와 볼트 키는 절대 기기 밖으로 나가지 않으며,\n'
                  '다른 기기에서는 "다른 기기에서 가져오기"로 같은 계정에 합류합니다.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: G.faint, height: 1.6),
                ),
              ],
            ),
    );
  }
}
