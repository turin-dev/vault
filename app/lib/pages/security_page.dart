import 'package:flutter/material.dart';

import '../security_tools.dart';
import '../src/rust/api/audit.dart';
import '../src/rust/api/vault.dart';
import '../theme.dart';
import 'entry_detail_page.dart';

/// 보안 대시보드 — 점수 링 + 취약/재사용/오래됨/유출 카테고리.
class SecurityPage extends StatefulWidget {
  const SecurityPage({super.key});

  @override
  State<SecurityPage> createState() => _SecurityPageState();
}

class _SecurityPageState extends State<SecurityPage> {
  AuditReportDto? _report;
  BreachReportDto? _breaches;
  List<EntryDto> _entries = [];
  bool _loading = true;
  bool _checkingBreaches = false;
  String? _breachError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await auditVault();
      final entries = await listEntries();
      if (mounted) {
        setState(() {
          _report = r;
          _entries = entries;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _checkBreaches() async {
    setState(() {
      _checkingBreaches = true;
      _breachError = null;
    });
    try {
      final b = await checkBreaches();
      if (mounted) setState(() => _breaches = b);
    } catch (e) {
      if (mounted) {
        setState(
          () => _breachError = '$e'
              .replaceFirst('AnyhowException(', '')
              .replaceFirst(RegExp(r'\)$'), ''),
        );
      }
    } finally {
      if (mounted) setState(() => _checkingBreaches = false);
    }
  }

  Future<void> _prepareTravelMode() async {
    final report = buildTravelReadiness(_entries);
    if (report.hiddenEntries.isEmpty) {
      _showMessage('여행 중 노출될 추가 항목이 없습니다');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('여행 모드 준비'),
        content: Text(
          '${report.hiddenCount}개 항목을 보관함으로 이동합니다.\n'
          '$travelSafeTag 태그가 붙은 ${report.safeCount}개 항목만 활성 목록에 남습니다.',
          style: const TextStyle(color: G.sub, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('준비'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    for (final entry in report.hiddenEntries) {
      await setArchived(id: entry.id, archived: true);
    }
    if (!mounted) return;
    await _load();
    if (mounted) {
      _showMessage('${report.hiddenCount}개 항목을 보관함으로 이동했습니다');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Color _scoreColor(int score) {
    if (score >= 85) return G.mint;
    if (score >= 60) return G.amber;
    return G.danger;
  }

  String _scoreLabel(int score) {
    if (score >= 85) return '안전';
    if (score >= 60) return '주의';
    return '위험';
  }

  @override
  Widget build(BuildContext context) {
    final r = _report;
    return Scaffold(
      appBar: AppBar(title: const Text('보안 점검')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : r == null
          ? const Center(
              child: Text('점검할 수 없습니다', style: TextStyle(color: G.sub)),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _scoreCard(r),
                _actionPlan(r),
                _travelReadinessCard(),
                const SizedBox(height: 20),
                _breachSection(),
                const SizedBox(height: 8),
                if (r.reused.isNotEmpty)
                  _category(
                    icon: Icons.content_copy_rounded,
                    color: G.danger,
                    title: '재사용된 비밀번호',
                    count: r.reused.fold<int>(
                      0,
                      (s, g) => s + g.entries.length,
                    ),
                    subtitle: '${r.reused.length}개 그룹에서 같은 비밀번호를 여러 곳에 사용',
                    refs: r.reused.expand((g) => g.entries).toList(),
                  ),
                if (r.weak.isNotEmpty)
                  _category(
                    icon: Icons.warning_amber_rounded,
                    color: G.amber,
                    title: '취약한 비밀번호',
                    count: r.weak.length,
                    subtitle: '추측하기 쉬운 비밀번호',
                    refs: r.weak,
                  ),
                if (r.stale.isNotEmpty)
                  _category(
                    icon: Icons.history_rounded,
                    color: G.sub,
                    title: '오래된 비밀번호',
                    count: r.stale.length,
                    subtitle: '180일 이상 변경하지 않음',
                    refs: r.stale,
                  ),
                if (r.empty.isNotEmpty)
                  _category(
                    icon: Icons.password_rounded,
                    color: G.faint,
                    title: '비밀번호 없음',
                    count: r.empty.length,
                    subtitle: '비밀번호가 비어 있는 항목',
                    refs: r.empty,
                  ),
                if (r.reused.isEmpty && r.weak.isEmpty && r.stale.isEmpty)
                  _allClear(),
              ],
            ),
    );
  }

  Widget _scoreCard(AuditReportDto r) {
    final score = r.score.clamp(0, 100);
    final color = _scoreColor(score);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.30)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: 0.09), G.surface],
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            height: 96,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 96,
                  height: 96,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: score / 100),
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, __) => CircularProgressIndicator(
                      value: v,
                      strokeWidth: 8,
                      strokeCap: StrokeCap.round,
                      backgroundColor: G.surfaceHi,
                      color: color,
                    ),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$score',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                    const Text(
                      '/100',
                      style: TextStyle(fontSize: 11, color: G.faint),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 22),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _scoreLabel(score),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${r.withPassword}개 항목 분석 완료',
                  style: const TextStyle(fontSize: 13, color: G.sub),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionPlan(AuditReportDto r) {
    final actions = buildSecurityActionPlan(
      report: r,
      entries: _entries,
      breaches: _breaches,
    );
    if (actions.isEmpty) return const SizedBox(height: 12);
    return Container(
      margin: const EdgeInsets.only(top: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: G.surface,
        border: Border.all(color: G.border),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          shape: const Border(),
          collapsedShape: const Border(),
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _severityColor(
                actions.first.severity,
              ).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.task_alt_rounded,
              color: _severityColor(actions.first.severity),
              size: 22,
            ),
          ),
          title: Row(
            children: [
              const Text(
                '우선 조치',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: G.mint.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${actions.length}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: G.mint,
                  ),
                ),
              ),
            ],
          ),
          subtitle: const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Text(
              '침해, 재사용, 취약, 2FA 누락 순으로 정렬',
              style: TextStyle(fontSize: 12, color: G.sub),
            ),
          ),
          children: actions.take(8).map(_actionTile).toList(),
        ),
      ),
    );
  }

  Widget _actionTile(SecurityActionItem action) {
    final color = _severityColor(action.severity);
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 16, right: 8),
      dense: true,
      leading: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(_actionIcon(action.kind), size: 18, color: color),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              action.title,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _severityLabel(action.severity),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
      subtitle: Text(
        action.detail,
        style: const TextStyle(fontSize: 12, color: G.faint),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, color: G.faint),
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => EntryDetailPage(id: action.id))),
    );
  }

  Color _severityColor(SecurityActionSeverity severity) {
    return switch (severity) {
      SecurityActionSeverity.critical => G.danger,
      SecurityActionSeverity.high => G.danger,
      SecurityActionSeverity.medium => G.amber,
      SecurityActionSeverity.low => G.sub,
    };
  }

  String _severityLabel(SecurityActionSeverity severity) {
    return switch (severity) {
      SecurityActionSeverity.critical => '긴급',
      SecurityActionSeverity.high => '높음',
      SecurityActionSeverity.medium => '중간',
      SecurityActionSeverity.low => '낮음',
    };
  }

  IconData _actionIcon(SecurityActionKind kind) {
    return switch (kind) {
      SecurityActionKind.breach => Icons.travel_explore_rounded,
      SecurityActionKind.reused => Icons.content_copy_rounded,
      SecurityActionKind.weak => Icons.warning_amber_rounded,
      SecurityActionKind.suspiciousUrl => Icons.link_off_rounded,
      SecurityActionKind.missing2fa => Icons.timer_rounded,
      SecurityActionKind.stale => Icons.history_rounded,
      SecurityActionKind.empty => Icons.password_rounded,
    };
  }

  Widget _travelReadinessCard() {
    final report = buildTravelReadiness(_entries);
    if (report.activeCount == 0) return const SizedBox.shrink();
    final color = report.ready
        ? G.mint
        : report.highValueHiddenCount > 0
        ? G.danger
        : G.amber;
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: G.surface,
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.flight_takeoff_rounded,
                  color: color,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      report.ready ? '여행 준비 완료' : 'Travel Readiness',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${report.safeCount}개 유지 · ${report.hiddenCount}개 보관 대상',
                      style: const TextStyle(fontSize: 12, color: G.sub),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: report.ready ? null : _prepareTravelMode,
                child: const Text('준비'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _travelChip('활성', report.activeCount, G.sub),
              _travelChip(travelSafeTag, report.safeCount, G.mint),
              _travelChip('보관 대상', report.hiddenCount, G.amber),
              _travelChip('고가치', report.highValueHiddenCount, G.danger),
            ],
          ),
          if (report.highValueHiddenEntries.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...report.highValueHiddenEntries.take(3).map(_travelRiskTile),
          ],
        ],
      ),
    );
  }

  Widget _travelChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Text(
        '$label $count',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }

  Widget _travelRiskTile(EntryDto entry) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: const Icon(Icons.priority_high_rounded, color: G.danger),
      title: Text(
        entry.title,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
      ),
      subtitle: const Text(
        '여행 전 보관하거나 travel-safe 태그를 명확히 지정하세요',
        style: TextStyle(fontSize: 12, color: G.faint),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, color: G.faint),
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => EntryDetailPage(id: entry.id))),
    );
  }

  Widget _breachSection() {
    final b = _breaches;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: G.surface,
        border: Border.all(
          color: (b != null && b.hits.isNotEmpty)
              ? G.danger.withValues(alpha: 0.35)
              : G.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.travel_explore_rounded,
                size: 22,
                color: (b != null && b.hits.isNotEmpty) ? G.danger : G.mint,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  '데이터 유출 검사',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              if (b == null)
                TextButton(
                  onPressed: _checkingBreaches ? null : _checkBreaches,
                  child: _checkingBreaches
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('검사'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (b == null && _breachError == null)
            const Text(
              '알려진 유출 데이터베이스와 대조합니다. 비밀번호는 전송되지 않으며,\n'
              'SHA-1 해시의 앞 5자만 보내는 k-익명성 방식을 사용합니다.',
              style: TextStyle(fontSize: 12, color: G.faint, height: 1.5),
            ),
          if (_breachError != null)
            Text(
              _breachError!,
              style: const TextStyle(fontSize: 12.5, color: G.danger),
            ),
          if (b != null && b.hits.isEmpty)
            Row(
              children: const [
                Icon(Icons.verified_user_rounded, size: 18, color: G.mint),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '유출된 비밀번호가 없습니다',
                    style: TextStyle(fontSize: 13, color: G.mint),
                  ),
                ),
              ],
            ),
          if (b != null && b.hits.isNotEmpty) ...[
            Text(
              '${b.hits.length}개 항목의 비밀번호가 유출 데이터에서 발견됨',
              style: const TextStyle(fontSize: 13, color: G.danger),
            ),
            const SizedBox(height: 10),
            ...b.hits.map(
              (h) => _refTile(
                h.id,
                h.title,
                '${_fmtCount(h.count)}회 유출 — 즉시 변경 권장',
                G.danger,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _fmtCount(BigInt count) {
    final n = count.toInt();
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)}K';
    return '$n';
  }

  Widget _category({
    required IconData icon,
    required Color color,
    required String title,
    required int count,
    required String subtitle,
    required List<AuditEntryRefDto> refs,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: G.surface,
        border: Border.all(color: G.border),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          title: Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              subtitle,
              style: const TextStyle(fontSize: 12, color: G.sub),
            ),
          ),
          children: refs
              .take(50)
              .map((r) => _refTile(r.id, r.title, r.detail, color))
              .toList(),
        ),
      ),
    );
  }

  Widget _refTile(String id, String title, String detail, Color color) {
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 16, right: 8),
      dense: true,
      leading: Container(
        width: 8,
        height: 8,
        margin: const EdgeInsets.only(left: 4),
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      title: Text(
        title,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        detail,
        style: const TextStyle(fontSize: 12, color: G.faint),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, color: G.faint),
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => EntryDetailPage(id: id))),
    );
  }

  Widget _allClear() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: G.mint.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(
              Icons.verified_user_rounded,
              size: 36,
              color: G.mint,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '모든 비밀번호가 안전합니다',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: G.mint,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '취약하거나 재사용된 비밀번호가 없습니다',
            style: TextStyle(fontSize: 13, color: G.sub),
          ),
        ],
      ),
    );
  }
}
