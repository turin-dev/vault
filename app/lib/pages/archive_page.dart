import 'package:flutter/material.dart';

import '../src/rust/api/vault.dart';
import '../theme.dart';
import 'entry_detail_page.dart';

/// 보관함 — 아카이브된 항목 목록 + 복원.
class ArchivePage extends StatefulWidget {
  const ArchivePage({super.key});

  @override
  State<ArchivePage> createState() => _ArchivePageState();
}

class _ArchivePageState extends State<ArchivePage> {
  List<EntryDto> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final list = await listArchived();
      if (mounted) setState(() { _items = list; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _restore(EntryDto e) async {
    await setArchived(id: e.id, archived: false);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('보관함')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: G.surface,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: G.border),
                      ),
                      child: const Icon(Icons.archive_outlined,
                          size: 34, color: G.faint),
                    ),
                    const SizedBox(height: 16),
                    const Text('보관된 항목이 없습니다',
                        style: TextStyle(color: G.sub)),
                  ]),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: _items
                      .map((e) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Card(
                              child: ListTile(
                                leading: Monogram(seed: e.title, size: 40),
                                title: Text(e.title,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                                subtitle: e.username.isEmpty
                                    ? null
                                    : Text(e.username),
                                trailing: IconButton(
                                  icon: const Icon(Icons.unarchive_rounded),
                                  tooltip: '복원',
                                  onPressed: () => _restore(e),
                                ),
                                onTap: () async {
                                  await Navigator.of(context).push(
                                      MaterialPageRoute(
                                          builder: (_) =>
                                              EntryDetailPage(id: e.id)));
                                  _reload();
                                },
                              ),
                            ),
                          ))
                      .toList(),
                ),
    );
  }
}
