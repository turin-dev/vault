import 'package:flutter/material.dart';

import '../entry_tools.dart';
import '../src/rust/api/sync.dart';
import '../src/rust/api/vault.dart';
import '../theme.dart';
import '../widgets.dart';
import 'archive_page.dart';
import 'data_page.dart';
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
  EntryTypeFilter _filter = EntryTypeFilter.all;
  EntrySortMode _sortMode = EntrySortMode.updatedDesc;
  String? _selectedTag;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
    _autoSync();
  }

  Future<void> _autoSync() async {
    try {
      final config = await getSyncConfig();
      if (config == null) return;
      final result = await syncNow();
      if (!mounted || result.pulled == 0) return;
      await _reload();
      _showMessage('동기화됨: ${result.pulled}개 항목 업데이트');
    } catch (_) {
      return;
    }
  }

  Future<void> _reload() async {
    try {
      final list = await listEntries();
      if (!mounted) return;
      setState(() {
        _entries = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const UnlockPage()),
        (_) => false,
      );
    }
  }

  List<EntryDto> get _visibleEntries {
    final filtered = filterEntries(
      entries: _entries,
      query: _query,
      filter: _filter,
      tag: _selectedTag,
    );
    return sortEntries(filtered, _sortMode);
  }

  Future<void> _lock() async {
    await lockVault();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const UnlockPage()),
      (_) => false,
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final items = _visibleEntries;
    final favorites = items.where((entry) => entry.favorite).toList();
    final others = items.where((entry) => !entry.favorite).toList();
    final tags = collectTags(_entries);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              total: _entries.length,
              onGenerator: () => _push(const GeneratorPage()),
              onSecurity: () => _pushAndReload(const SecurityPage()),
              onSync: () => _pushAndReload(const SyncPage()),
              onArchive: () => _pushAndReload(const ArchivePage()),
              onData: () => _pushAndReload(const DataPage()),
              onLock: _lock,
            ),
            _SummaryStrip(entries: _entries),
            _SearchAndSort(
              query: _query,
              sortMode: _sortMode,
              onQueryChanged: (value) => setState(() => _query = value),
              onSortChanged: (value) => setState(() => _sortMode = value),
            ),
            _FilterRail(
              filter: _filter,
              selectedTag: _selectedTag,
              tags: tags,
              onFilterChanged: (value) => setState(() => _filter = value),
              onTagChanged: (value) => setState(() => _selectedTag = value),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : items.isEmpty
                  ? _EmptyState(query: _query)
                  : RefreshIndicator(
                      onRefresh: _reload,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                        children: [
                          if (favorites.isNotEmpty) ...[
                            _SectionLabel('즐겨찾기', favorites.length),
                            ...favorites.map(_tile),
                            const SizedBox(height: 14),
                          ],
                          if (others.isNotEmpty) ...[
                            if (favorites.isNotEmpty)
                              _SectionLabel('전체', others.length),
                            ...others.map(_tile),
                          ],
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add_rounded),
        label: const Text('추가'),
        onPressed: () async {
          final saved = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => const EntryEditPage()),
          );
          if (saved == true) _reload();
        },
      ),
    );
  }

  Future<void> _push(Widget page) {
    return Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  Future<void> _pushAndReload(Widget page) async {
    await _push(page);
    _reload();
  }

  Widget _tile(EntryDto entry) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => EntryDetailPage(id: entry.id)),
            );
            _reload();
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
            child: Row(
              children: [
                Monogram(seed: entry.title),
                const SizedBox(width: 14),
                Expanded(child: _EntryTileBody(entry: entry)),
                _QuickCopyMenu(entry: entry),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.total,
    required this.onGenerator,
    required this.onSecurity,
    required this.onSync,
    required this.onArchive,
    required this.onData,
    required this.onLock,
  });

  final int total;
  final VoidCallback onGenerator;
  final VoidCallback onSecurity;
  final VoidCallback onSync;
  final VoidCallback onArchive;
  final VoidCallback onData;
  final VoidCallback onLock;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
      child: Row(
        children: [
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
            child: const Icon(Icons.shield_rounded, size: 22, color: G.onMint),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Vault',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                ),
                Text(
                  '$total개 항목 · 잠금 해제됨',
                  style: const TextStyle(fontSize: 12, color: G.faint),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.auto_awesome_rounded),
            tooltip: '비밀번호 생성기',
            onPressed: onGenerator,
          ),
          IconButton(
            icon: const Icon(Icons.verified_user_rounded),
            tooltip: '보안 점검',
            onPressed: onSecurity,
          ),
          IconButton(
            icon: const Icon(Icons.cloud_sync_rounded),
            tooltip: '동기화',
            onPressed: onSync,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: G.sub),
            color: G.surfaceHi,
            onSelected: (value) {
              switch (value) {
                case 'archive':
                  onArchive();
                case 'data':
                  onData();
                case 'lock':
                  onLock();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'archive',
                child: ListTile(
                  leading: Icon(Icons.archive_outlined),
                  title: Text('보관함'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'data',
                child: ListTile(
                  leading: Icon(Icons.import_export_rounded),
                  title: Text('가져오기 / 내보내기'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'lock',
                child: ListTile(
                  leading: Icon(Icons.lock_rounded),
                  title: Text('잠금'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.entries});

  final List<EntryDto> entries;

  @override
  Widget build(BuildContext context) {
    final login = entries.where((entry) => entry.itemType == 'login').length;
    final totp = entries.where((entry) => entry.totp.isNotEmpty).length;
    final favorite = entries.where((entry) => entry.favorite).length;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
      child: Row(
        children: [
          _MetricChip(label: '로그인', value: login, icon: Icons.badge_rounded),
          _MetricChip(label: '2FA', value: totp, icon: Icons.timer_rounded),
          _MetricChip(label: '즐겨찾기', value: favorite, icon: Icons.star_rounded),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final int value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: G.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: G.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: G.mint),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 12, color: G.sub)),
          const SizedBox(width: 8),
          Text(
            '$value',
            style: const TextStyle(fontWeight: FontWeight.w800, color: G.text),
          ),
        ],
      ),
    );
  }
}

class _SearchAndSort extends StatelessWidget {
  const _SearchAndSort({
    required this.query,
    required this.sortMode,
    required this.onQueryChanged,
    required this.onSortChanged,
  });

  final String query;
  final EntrySortMode sortMode;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<EntrySortMode> onSortChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              onChanged: onQueryChanged,
              decoration: const InputDecoration(
                hintText: '제목, 아이디, URL, 태그, 메모 검색',
                prefixIcon: Icon(Icons.search_rounded),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<EntrySortMode>(
            tooltip: '정렬',
            icon: const Icon(Icons.sort_rounded),
            color: G.surfaceHi,
            initialValue: sortMode,
            onSelected: onSortChanged,
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: EntrySortMode.updatedDesc,
                child: Text('최근 수정순'),
              ),
              PopupMenuItem(value: EntrySortMode.titleAsc, child: Text('이름순')),
              PopupMenuItem(
                value: EntrySortMode.createdDesc,
                child: Text('최근 생성순'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FilterRail extends StatelessWidget {
  const _FilterRail({
    required this.filter,
    required this.selectedTag,
    required this.tags,
    required this.onFilterChanged,
    required this.onTagChanged,
  });

  final EntryTypeFilter filter;
  final String? selectedTag;
  final List<String> tags;
  final ValueChanged<EntryTypeFilter> onFilterChanged;
  final ValueChanged<String?> onTagChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          _FilterChip(
            label: '전체',
            selected: filter == EntryTypeFilter.all && selectedTag == null,
            onSelected: () {
              onFilterChanged(EntryTypeFilter.all);
              onTagChanged(null);
            },
          ),
          _FilterChip(
            label: '로그인',
            selected: filter == EntryTypeFilter.login,
            onSelected: () => onFilterChanged(EntryTypeFilter.login),
          ),
          _FilterChip(
            label: '메모',
            selected: filter == EntryTypeFilter.note,
            onSelected: () => onFilterChanged(EntryTypeFilter.note),
          ),
          _FilterChip(
            label: '카드',
            selected: filter == EntryTypeFilter.card,
            onSelected: () => onFilterChanged(EntryTypeFilter.card),
          ),
          _FilterChip(
            label: '2FA',
            selected: filter == EntryTypeFilter.totp,
            onSelected: () => onFilterChanged(EntryTypeFilter.totp),
          ),
          _FilterChip(
            label: '즐겨찾기',
            selected: filter == EntryTypeFilter.favorite,
            onSelected: () => onFilterChanged(EntryTypeFilter.favorite),
          ),
          for (final tag in tags.take(12))
            _FilterChip(
              label: '#$tag',
              selected: selectedTag == tag,
              onSelected: () => onTagChanged(selectedTag == tag ? null : tag),
            ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onSelected(),
        selectedColor: G.mint.withValues(alpha: 0.18),
        labelStyle: TextStyle(
          color: selected ? G.mint : G.sub,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label, this.count);

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: G.faint,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$count',
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: G.mint,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
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
            query.isEmpty ? '표시할 항목이 없습니다.' : '검색 결과가 없습니다.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: G.sub, height: 1.6),
          ),
        ],
      ),
    );
  }
}

class _EntryTileBody extends StatelessWidget {
  const _EntryTileBody({required this.entry});

  final EntryDto entry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                entry.title,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (entry.favorite) ...[
              const SizedBox(width: 6),
              const Icon(Icons.star_rounded, size: 15, color: G.amber),
            ],
            if (entry.totp.isNotEmpty) ...[
              const SizedBox(width: 6),
              const _Badge(label: '2FA'),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Text(
          _subtitle(entry),
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, color: G.sub),
        ),
      ],
    );
  }

  String _subtitle(EntryDto entry) {
    if (entry.username.isNotEmpty) return entry.username;
    if (entry.url.isNotEmpty) return entry.url;
    return itemTypeLabel(entry.itemType);
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: G.mint.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          color: G.mint,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _QuickCopyMenu extends StatelessWidget {
  const _QuickCopyMenu({required this.entry});

  final EntryDto entry;

  @override
  Widget build(BuildContext context) {
    final actions = [
      if (entry.username.isNotEmpty) _CopyAction('아이디', entry.username),
      if (entry.password.isNotEmpty) _CopyAction('비밀번호', entry.password),
      if (entry.url.isNotEmpty) _CopyAction('URL', entry.url),
      if (entry.totp.isNotEmpty) _CopyAction('TOTP secret', entry.totp),
    ];

    if (actions.isEmpty) {
      return const SizedBox(width: 48);
    }

    return PopupMenuButton<_CopyAction>(
      tooltip: '빠른 복사',
      icon: const Icon(Icons.copy_rounded, size: 20),
      color: G.surfaceHi,
      onSelected: (action) =>
          copySensitive(context, action.label, action.value),
      itemBuilder: (_) => actions
          .map(
            (action) => PopupMenuItem(value: action, child: Text(action.label)),
          )
          .toList(),
    );
  }
}

class _CopyAction {
  const _CopyAction(this.label, this.value);

  final String label;
  final String value;
}
