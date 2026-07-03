import 'entry_tools.dart';
import 'src/rust/api/audit.dart';
import 'src/rust/api/vault.dart';

enum SecurityActionKind { breach, reused, weak, missing2fa, stale, empty }

enum SecurityActionSeverity { critical, high, medium, low }

const travelSafeTag = 'travel-safe';

class SecurityActionItem {
  const SecurityActionItem({
    required this.id,
    required this.title,
    required this.detail,
    required this.kind,
    required this.severity,
    required this.priority,
  });

  final String id;
  final String title;
  final String detail;
  final SecurityActionKind kind;
  final SecurityActionSeverity severity;
  final int priority;
}

class TravelReadinessReport {
  const TravelReadinessReport({
    required this.activeCount,
    required this.safeEntries,
    required this.hiddenEntries,
    required this.highValueHiddenEntries,
  });

  final int activeCount;
  final List<EntryDto> safeEntries;
  final List<EntryDto> hiddenEntries;
  final List<EntryDto> highValueHiddenEntries;

  int get safeCount => safeEntries.length;
  int get hiddenCount => hiddenEntries.length;
  int get highValueHiddenCount => highValueHiddenEntries.length;
  bool get ready => hiddenEntries.isEmpty;
}

List<SecurityActionItem> buildSecurityActionPlan({
  required AuditReportDto report,
  required List<EntryDto> entries,
  BreachReportDto? breaches,
}) {
  final actions = [
    for (final hit in breaches?.hits ?? <BreachHitDto>[])
      _action(
        id: hit.id,
        title: hit.title,
        detail: '${_compactCount(hit.count)}회 노출됨. 즉시 비밀번호를 바꾸세요.',
        kind: SecurityActionKind.breach,
        severity: SecurityActionSeverity.critical,
        priority: 0,
      ),
    for (final group in report.reused)
      for (final ref in group.entries)
        _action(
          id: ref.id,
          title: ref.title,
          detail: '여러 항목에서 같은 비밀번호를 사용 중입니다.',
          kind: SecurityActionKind.reused,
          severity: SecurityActionSeverity.high,
          priority: 10,
        ),
    for (final ref in report.weak)
      _action(
        id: ref.id,
        title: ref.title,
        detail: ref.detail.isEmpty ? '추측하기 쉬운 비밀번호입니다.' : ref.detail,
        kind: SecurityActionKind.weak,
        severity: SecurityActionSeverity.high,
        priority: 20,
      ),
    for (final entry in entries)
      if (_twoFactorService(entry.url) case final service?)
        if (_needsTwoFactor(entry))
          _action(
            id: entry.id,
            title: entry.title,
            detail: '$service 계정에 2FA를 추가하세요.',
            kind: SecurityActionKind.missing2fa,
            severity: SecurityActionSeverity.medium,
            priority: entry.favorite ? 24 : 30,
          ),
    for (final ref in report.stale)
      _action(
        id: ref.id,
        title: ref.title,
        detail: ref.detail.isEmpty ? '오랫동안 바꾸지 않은 비밀번호입니다.' : ref.detail,
        kind: SecurityActionKind.stale,
        severity: SecurityActionSeverity.medium,
        priority: 40,
      ),
    for (final ref in report.empty)
      _action(
        id: ref.id,
        title: ref.title,
        detail: '비밀번호가 비어 있습니다.',
        kind: SecurityActionKind.empty,
        severity: SecurityActionSeverity.low,
        priority: 50,
      ),
  ];
  return _dedupeAndSort(actions);
}

TravelReadinessReport buildTravelReadiness(List<EntryDto> entries) {
  final active = entries.where((entry) => !entry.archived).toList();
  final safe = active.where(_isTravelSafe).toList();
  final hidden = active.where((entry) => !_isTravelSafe(entry)).toList();
  final highValueHidden = hidden.where(_isHighValueTravelEntry).toList();
  return TravelReadinessReport(
    activeCount: active.length,
    safeEntries: safe,
    hiddenEntries: hidden,
    highValueHiddenEntries: highValueHidden,
  );
}

SecurityActionItem _action({
  required String id,
  required String title,
  required String detail,
  required SecurityActionKind kind,
  required SecurityActionSeverity severity,
  required int priority,
}) {
  return SecurityActionItem(
    id: id,
    title: title,
    detail: detail,
    kind: kind,
    severity: severity,
    priority: priority,
  );
}

List<SecurityActionItem> _dedupeAndSort(List<SecurityActionItem> actions) {
  final seen = <String>{};
  final unique = <SecurityActionItem>[
    for (final action in actions)
      if (seen.add('${action.kind.name}:${action.id}')) action,
  ];
  unique.sort((a, b) {
    final priority = a.priority.compareTo(b.priority);
    if (priority != 0) return priority;
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  });
  return unique;
}

bool _needsTwoFactor(EntryDto entry) {
  return entry.itemType == 'login' &&
      !entry.archived &&
      entry.password.isNotEmpty &&
      entry.totp.isEmpty;
}

bool _isTravelSafe(EntryDto entry) {
  return entry.tags.any((tag) => tag.trim().toLowerCase() == travelSafeTag);
}

bool _isHighValueTravelEntry(EntryDto entry) {
  if (entry.favorite || entry.itemType == 'card') return true;
  final text = [entry.title, entry.url, ...entry.tags].join(' ').toLowerCase();
  return _highValueTerms.any(text.contains) ||
      _twoFactorService(entry.url) != null;
}

String? _twoFactorService(String url) {
  if (url.trim().isEmpty) return null;
  final uri = Uri.tryParse(normalizeUrl(url));
  final host = uri?.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
  if (host == null || host.isEmpty) return null;
  for (final MapEntry(key: domain, value: service)
      in _twoFactorDomains.entries) {
    if (host == domain || host.endsWith('.$domain')) return service;
  }
  return null;
}

String _compactCount(BigInt count) {
  final value = count.toInt();
  if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(0)}K';
  return '$value';
}

const _twoFactorDomains = {
  'github.com': 'GitHub',
  'google.com': 'Google',
  'microsoft.com': 'Microsoft',
  'apple.com': 'Apple',
  'amazon.com': 'Amazon',
  'facebook.com': 'Facebook',
  'instagram.com': 'Instagram',
  'x.com': 'X',
  'twitter.com': 'X',
  'discord.com': 'Discord',
  'dropbox.com': 'Dropbox',
  'slack.com': 'Slack',
  'notion.so': 'Notion',
  'paypal.com': 'PayPal',
  'stripe.com': 'Stripe',
  'cloudflare.com': 'Cloudflare',
  'bitbucket.org': 'Bitbucket',
  'gitlab.com': 'GitLab',
};

const _highValueTerms = [
  'bank',
  'finance',
  'card',
  'identity',
  'passport',
  'crypto',
  'wallet',
  'email',
  'tax',
  'insurance',
];
