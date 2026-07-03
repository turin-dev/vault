import 'package:flutter/material.dart';

import '../entry_tools.dart';
import '../src/rust/api/vault.dart';
import '../theme.dart';
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
  final Set<int> _revealedFields = {};

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
        content: Text(
          '"${_entry?.title}"을(를) 삭제할까요?',
          style: const TextStyle(color: G.sub),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: G.danger,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 44),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await deleteEntry(id: widget.id);
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _toggleArchive() async {
    final e = _entry;
    if (e == null) return;
    await setArchived(id: e.id, archived: !e.archived);
    if (mounted) Navigator.of(context).pop();
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
        itemType: e.itemType,
        customFields: e.customFields,
        passwordHistory: e.passwordHistory,
        archived: e.archived,
      ),
    );
    _reload();
  }

  Future<void> _copyLoginBundle() async {
    final e = _entry;
    if (e == null) return;
    final lines = [
      if (e.username.isNotEmpty) '아이디: ${e.username}',
      if (e.password.isNotEmpty) '비밀번호: ${e.password}',
      if (e.url.isNotEmpty) 'URL: ${e.url}',
    ];
    if (lines.isEmpty) return;
    await copySensitive(context, '로그인 정보', lines.join('\n'));
  }

  @override
  Widget build(BuildContext context) {
    final e = _entry;
    return Scaffold(
      appBar: AppBar(
        title: e == null
            ? const SizedBox.shrink()
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Monogram(seed: e.title, size: 32),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(e.title, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
        actions: [
          if (e != null &&
              (e.username.isNotEmpty ||
                  e.password.isNotEmpty ||
                  e.url.isNotEmpty))
            IconButton(
              icon: const Icon(Icons.copy_all_rounded),
              tooltip: '로그인 정보 복사',
              onPressed: _copyLoginBundle,
            ),
          IconButton(
            icon: Icon(
              e?.favorite == true
                  ? Icons.star_rounded
                  : Icons.star_outline_rounded,
              color: e?.favorite == true ? G.amber : null,
            ),
            tooltip: '즐겨찾기',
            onPressed: _toggleFavorite,
          ),
          IconButton(
            icon: Icon(
              e?.archived == true
                  ? Icons.unarchive_rounded
                  : Icons.archive_outlined,
            ),
            tooltip: e?.archived == true ? '보관 해제' : '보관함으로',
            onPressed: _toggleArchive,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: '삭제',
            onPressed: _delete,
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.edit_rounded),
        label: const Text('편집'),
        onPressed: () async {
          final saved = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => EntryEditPage(entry: e)),
          );
          if (saved == true) _reload();
        },
      ),
      body: e == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                _typeCard(e),
                if (e.username.isNotEmpty)
                  _fieldCard(
                    icon: Icons.person_rounded,
                    label: '아이디',
                    value: e.username,
                    onCopy: () => copySensitive(context, '아이디', e.username),
                  ),
                if (e.password.isNotEmpty)
                  _fieldCard(
                    icon: Icons.key_rounded,
                    label: e.itemType == 'card' ? 'CVC / PIN' : '비밀번호',
                    value: _showPassword ? e.password : '••••••••••••',
                    monospace: true,
                    extra: IconButton(
                      icon: Icon(
                        _showPassword
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                      ),
                      onPressed: () =>
                          setState(() => _showPassword = !_showPassword),
                    ),
                    onCopy: () => copySensitive(context, '비밀번호', e.password),
                  ),
                if (e.totp.isNotEmpty) _totpCard(e),
                if (e.url.isNotEmpty)
                  _fieldCard(
                    icon: Icons.link_rounded,
                    label: 'URL',
                    value: e.url,
                    onCopy: () => copySensitive(context, 'URL', e.url),
                  ),
                // 커스텀 필드
                ...e.customFields.map((f) => _customFieldCard(f)),
                if (e.passwordHistory.isNotEmpty) _historyCard(e),
                if (e.tags.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: e.tags
                          .map(
                            (t) => Chip(
                              label: Text('# $t'),
                              visualDensity: VisualDensity.compact,
                            ),
                          )
                          .toList(),
                    ),
                  ),
                if (e.notes.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '메모',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: G.faint,
                                letterSpacing: 0.6,
                              ),
                            ),
                            const SizedBox(height: 8),
                            SelectableText(
                              e.notes,
                              style: const TextStyle(height: 1.6),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Text(
                  '생성 ${_fmt(e.createdAt)} · 수정 ${_fmt(e.updatedAt)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: G.faint),
                ),
              ],
            ),
    );
  }

  Widget _customFieldCard(CustomFieldDto f) {
    final idx = _entry!.customFields.indexOf(f);
    final revealed = !f.hidden || _revealedFields.contains(idx);
    return _fieldCard(
      icon: f.hidden ? Icons.password_rounded : Icons.notes_rounded,
      label: f.label.isEmpty ? '필드' : f.label,
      value: revealed ? f.value : '••••••••••',
      monospace: f.hidden,
      extra: f.hidden
          ? IconButton(
              icon: Icon(
                revealed
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
              ),
              onPressed: () => setState(() {
                if (revealed) {
                  _revealedFields.remove(idx);
                } else {
                  _revealedFields.add(idx);
                }
              }),
            )
          : null,
      onCopy: () => copySensitive(context, f.label, f.value),
    );
  }

  Widget _typeCard(EntryDto e) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Card(
        child: ListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: G.mint.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_typeIcon(e.itemType), size: 20, color: G.mint),
          ),
          title: Text(
            itemTypeLabel(e.itemType),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            e.archived ? '보관된 항목' : '활성 항목',
            style: const TextStyle(fontSize: 12, color: G.faint),
          ),
        ),
      ),
    );
  }

  IconData _typeIcon(String itemType) {
    return switch (itemType) {
      'note' => Icons.sticky_note_2_rounded,
      'card' => Icons.credit_card_rounded,
      _ => Icons.badge_rounded,
    };
  }

  Widget _historyCard(EntryDto e) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Card(
        child: ListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: G.surfaceHi,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.history_rounded, size: 20, color: G.sub),
          ),
          title: const Text(
            '비밀번호 이력',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            '이전 비밀번호 ${e.passwordHistory.length}개',
            style: const TextStyle(fontSize: 12, color: G.faint),
          ),
          trailing: const Icon(Icons.chevron_right_rounded, color: G.faint),
          onTap: () => _showHistory(e),
        ),
      ),
    );
  }

  void _showHistory(EntryDto e) {
    showModalBottomSheet(
      context: context,
      backgroundColor: G.surfaceHi,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                '비밀번호 이력',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
            ...e.passwordHistory.map(
              (h) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: SelectableText(
                    h.password,
                    style: const TextStyle(fontSize: 14, letterSpacing: 0.5),
                  ),
                  subtitle: Text(
                    _fmt(h.changedAt),
                    style: const TextStyle(fontSize: 12, color: G.faint),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 20),
                    onPressed: () => copySensitive(ctx, '이전 비밀번호', h.password),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _totpCard(EntryDto e) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: G.mint.withValues(alpha: 0.30)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [G.mint.withValues(alpha: 0.07), G.surface],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.timer_rounded, size: 14, color: G.mint),
                SizedBox(width: 6),
                Text(
                  '일회용 코드 · TOTP',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: G.mint,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            TotpView(secret: e.totp),
          ],
        ),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: G.surfaceHi,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 20, color: G.mint),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: G.faint,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      value,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        letterSpacing: monospace ? 0.8 : 0,
                      ),
                    ),
                  ],
                ),
              ),
              if (extra != null) extra,
              IconButton(
                icon: const Icon(Icons.copy_rounded, size: 20),
                onPressed: onCopy,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
