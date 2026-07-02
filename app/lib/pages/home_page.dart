import 'package:flutter/material.dart';

import '../src/rust/api/sync.dart';
import '../src/rust/api/vault.dart';
import '../theme.dart';
import '../widgets.dart';
import 'entry_detail_page.dart';
import 'entry_edit_page.dart';
import 'generator_page.dart';
import 'security_page.dart';
import 'sync_page.dart';
import 'unlock_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<EntryDto> _entries = [];
  String _query = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
    _autoSync();
  }

  /// 동기화가 설정돼 있으면 진입 시 조용히 한 번 동기화.
  Future<void> _autoSync() async {
    try {
      final config = await getSyncConfig();
      if (config == null) return;
      final r = await syncNow();
      if (r.pulled > 0 && mounted) {
        _reload();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('동기화됨 — ${r.pulled}개 항목 업데이트'),
          duration: const Duration(seconds: 2),
        ));
      }
    } catch (_) {
      // 오프라인 등 — 조용히 무시, 수동 동기화는 동기화 화면에서
    }
  }

  Future<void> _reload() async {
    try {
      final list = await listEntries();
      if (mounted) {
        setState(() {
          _entries = list;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const UnlockPage()),
            (_) => false);
      }
    }
  }

  List<EntryDto> get _filtered {
    if (_query.isEmpty) return _entries;
    final q = _query.toLowerCase();
    return _entries
        .where((e) =>
            e.title.toLowerCase().contains(q) ||
            e.username.toLowerCase().contains(q) ||
            e.url.toLowerCase().contains(q) ||
            e.tags.any((t) => t.toLowerCase().contains(q)))
        .toList();
  }

  Future<void> _lock() async {
    await lockVault();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const UnlockPage()), (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered;
    final favorites = items.where((e) => e.favorite).toList();
    final others = items.where((e) => !e.favorite).toList();

    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          // 헤더
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
            child: Row(children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [G.mint, G.mintDeep],
                  ),
                ),
                child:
                    const Icon(Icons.shield_rounded, size: 22, color: G.onMint),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('금고',
                    style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3)),
                Text('${_entries.length}개 항목 · 잠금 해제됨',
                    style: const TextStyle(fontSize: 12, color: G.faint)),
              ]),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.auto_awesome_rounded),
                tooltip: '비밀번호 생성기',
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const GeneratorPage())),
              ),
              IconButton(
                icon: const Icon(Icons.verified_user_rounded),
                tooltip: '보안 점검',
                onPressed: () async {
                  await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SecurityPage()));
                  _reload();
                },
              ),
              IconButton(
                icon: const Icon(Icons.cloud_sync_rounded),
                tooltip: '동기화',
                onPressed: () async {
                  await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SyncPage()));
                  _reload();
                },
              ),
              IconButton(
                icon: const Icon(Icons.lock_rounded),
                tooltip: '잠금',
                onPressed: _lock,
              ),
            ]),
          ),
          // 검색
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                hintText: '검색 — 제목, 아이디, URL, 태그',
                prefixIcon: Icon(Icons.search_rounded),
                isDense: true,
              ),
            ),
          ),
          // 목록
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : (favorites.isEmpty && others.isEmpty)
                    ? _empty()
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                        children: [
                          if (favorites.isNotEmpty) ...[
                            _sectionLabel('즐겨찾기', favorites.length),
                            ...favorites.map(_tile),
                            const SizedBox(height: 14),
                          ],
                          if (others.isNotEmpty) ...[
                            if (favorites.isNotEmpty)
                              _sectionLabel('전체', others.length),
                            ...others.map(_tile),
                          ],
                        ],
                      ),
          ),
        ]),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add_rounded),
        label: const Text('추가'),
        onPressed: () async {
          final saved = await Navigator.of(context).push<bool>(
              MaterialPageRoute(builder: (_) => const EntryEditPage()));
          if (saved == true) _reload();
        },
      ),
    );
  }

  Widget _sectionLabel(String label, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Row(children: [
        Text(label.toUpperCase(),
            style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: G.faint,
                letterSpacing: 1.2)),
        const SizedBox(width: 8),
        Text('$count',
            style: const TextStyle(
                fontSize: 11.5, fontWeight: FontWeight.w700, color: G.mint)),
      ]),
    );
  }

  Widget _empty() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: G.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: G.border),
          ),
          child: const Icon(Icons.inbox_rounded, size: 34, color: G.faint),
        ),
        const SizedBox(height: 16),
        Text(
          _query.isEmpty ? '아직 항목이 없습니다\n+ 버튼으로 첫 항목을 추가하세요' : '검색 결과가 없습니다',
          textAlign: TextAlign.center,
          style: const TextStyle(color: G.sub, height: 1.6),
        ),
      ]),
    );
  }

  Widget _tile(EntryDto e) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () async {
            await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => EntryDetailPage(id: e.id)));
            _reload();
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
            child: Row(children: [
              Monogram(seed: e.title),
              const SizedBox(width: 14),
              Expanded(
                child:
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(
                      child: Text(e.title,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 15.5, fontWeight: FontWeight.w700)),
                    ),
                    if (e.favorite) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.star_rounded, size: 15, color: G.amber),
                    ],
                    if (e.totp.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: G.mint.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('2FA',
                            style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                color: G.mint,
                                letterSpacing: 0.5)),
                      ),
                    ],
                  ]),
                  if (e.username.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(e.username,
                        overflow: TextOverflow.ellipsis,
                        style:
                            const TextStyle(fontSize: 13, color: G.sub)),
                  ],
                ]),
              ),
              IconButton(
                icon: const Icon(Icons.copy_rounded, size: 20),
                tooltip: '비밀번호 복사',
                onPressed: () => copySensitive(context, '비밀번호', e.password),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
