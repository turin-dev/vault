import 'package:flutter/material.dart';

import '../src/rust/api/vault.dart';
import '../widgets.dart';
import 'entry_edit_page.dart';

class EntryDetailPage extends StatefulWidget {
  const EntryDetailPage({super.key, required this.id});

  final String id;

  @override
  State<EntryDetailPage> createState() => _EntryDetailPageState();
}

class _EntryDetailPageState extends State<EntryDetailPage> {
  EntryDto? _entry;
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final e = await getEntry(id: widget.id);
      if (mounted) setState(() => _entry = e);
    } catch (_) {
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('항목 삭제'),
        content: Text('"${_entry?.title}"을(를) 삭제할까요?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소')),
          FilledButton.tonal(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('삭제')),
        ],
      ),
    );
    if (ok == true) {
      await deleteEntry(id: widget.id);
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _toggleFavorite() async {
    final e = _entry;
    if (e == null) return;
    await updateEntry(
        entry: EntryDto(
      id: e.id,
      title: e.title,
      username: e.username,
      password: e.password,
      url: e.url,
      notes: e.notes,
      totp: e.totp,
      tags: e.tags,
      favorite: !e.favorite,
      createdAt: e.createdAt,
      updatedAt: e.updatedAt,
    ));
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final e = _entry;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(e?.title ?? ''),
        actions: [
          IconButton(
            icon: Icon(
              e?.favorite == true ? Icons.star_rounded : Icons.star_outline_rounded,
              color: e?.favorite == true ? Colors.amber.shade600 : null,
            ),
            tooltip: '즐겨찾기',
            onPressed: _toggleFavorite,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: '삭제',
            onPressed: _delete,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.edit_rounded),
        label: const Text('편집'),
        onPressed: () async {
          final saved = await Navigator.of(context).push<bool>(
              MaterialPageRoute(builder: (_) => EntryEditPage(entry: e)));
          if (saved == true) _reload();
        },
      ),
      body: e == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
              children: [
                if (e.username.isNotEmpty)
                  _fieldCard(
                    icon: Icons.person_rounded,
                    label: '아이디',
                    value: e.username,
                    onCopy: () => copySensitive(context, '아이디', e.username),
                  ),
                _fieldCard(
                  icon: Icons.key_rounded,
                  label: '비밀번호',
                  value: _showPassword ? e.password : '••••••••••••',
                  monospace: _showPassword,
                  extra: IconButton(
                    icon: Icon(_showPassword
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded),
                    onPressed: () =>
                        setState(() => _showPassword = !_showPassword),
                  ),
                  onCopy: () => copySensitive(context, '비밀번호', e.password),
                ),
                if (e.totp.isNotEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('일회용 코드 (TOTP)',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(color: scheme.onSurfaceVariant)),
                          const SizedBox(height: 4),
                          TotpView(secret: e.totp),
                        ],
                      ),
                    ),
                  ),
                if (e.url.isNotEmpty)
                  _fieldCard(
                    icon: Icons.link_rounded,
                    label: 'URL',
                    value: e.url,
                    onCopy: () => copySensitive(context, 'URL', e.url),
                  ),
                if (e.tags.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: e.tags
                          .map((t) => Chip(
                              label: Text(t),
                              visualDensity: VisualDensity.compact))
                          .toList(),
                    ),
                  ),
                if (e.notes.isNotEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('메모',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(color: scheme.onSurfaceVariant)),
                          const SizedBox(height: 4),
                          SelectableText(e.notes),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  '생성 ${_fmt(e.createdAt)} · 수정 ${_fmt(e.updatedAt)}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: scheme.outline),
                ),
              ],
            ),
    );
  }

  String _fmt(int unixSeconds) {
    final d = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Widget _fieldCard({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onCopy,
    Widget? extra,
    bool monospace = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        leading: Icon(icon, color: scheme.primary),
        title: Text(label,
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: scheme.onSurfaceVariant)),
        subtitle: Text(
          value,
          style: TextStyle(
            fontSize: 15,
            color: scheme.onSurface,
            fontFamily: monospace ? 'monospace' : null,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (extra != null) extra,
            IconButton(icon: const Icon(Icons.copy_rounded), onPressed: onCopy),
          ],
        ),
      ),
    );
  }
}
