import 'package:flutter/material.dart';

import '../src/rust/api/vault.dart';
import '../widgets.dart';
import 'entry_detail_page.dart';
import 'entry_edit_page.dart';
import 'generator_page.dart';
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
      // 잠금 상태에서 호출됨 — 잠금 화면으로
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
    final scheme = Theme.of(context).colorScheme;
    final items = _filtered;
    final favorites = items.where((e) => e.favorite).toList();
    final others = items.where((e) => !e.favorite).toList();
    final ordered = [...favorites, ...others];

    return Scaffold(
      appBar: AppBar(
        title: const Text('금고', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome_rounded),
            tooltip: '비밀번호 생성기',
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const GeneratorPage())),
          ),
          IconButton(
            icon: const Icon(Icons.lock_rounded),
            tooltip: '잠금',
            onPressed: _lock,
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SearchBar(
              hintText: '검색 (제목, 아이디, URL, 태그)',
              leading: const Icon(Icons.search_rounded),
              elevation: const WidgetStatePropertyAll(0),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ordered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inbox_rounded,
                          size: 64, color: scheme.outlineVariant),
                      const SizedBox(height: 12),
                      Text(
                        _query.isEmpty ? '아직 항목이 없습니다.\n+ 버튼으로 추가하세요.' : '검색 결과 없음',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
                  itemCount: ordered.length,
                  itemBuilder: (context, i) {
                    final e = ordered[i];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        leading: CircleAvatar(
                          backgroundColor: scheme.primaryContainer,
                          foregroundColor: scheme.onPrimaryContainer,
                          child: Text(
                              e.title.isEmpty
                                  ? '?'
                                  : e.title.characters.first.toUpperCase(),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                        title: Row(children: [
                          Flexible(
                              child: Text(e.title,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600))),
                          if (e.favorite) ...[
                            const SizedBox(width: 6),
                            Icon(Icons.star_rounded,
                                size: 16, color: Colors.amber.shade600),
                          ],
                          if (e.totp.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Icon(Icons.timer_rounded,
                                size: 15, color: scheme.outline),
                          ],
                        ]),
                        subtitle: e.username.isEmpty ? null : Text(e.username),
                        trailing: IconButton(
                          icon: const Icon(Icons.copy_rounded),
                          tooltip: '비밀번호 복사',
                          onPressed: () =>
                              copySensitive(context, '비밀번호', e.password),
                        ),
                        onTap: () async {
                          await Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => EntryDetailPage(id: e.id)));
                          _reload();
                        },
                      ),
                    );
                  },
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
}
