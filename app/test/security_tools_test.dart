import 'package:app/security_tools.dart';
import 'package:app/src/rust/api/audit.dart';
import 'package:app/src/rust/api/vault.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'prioritizes breach, reuse, weak, missing 2fa, stale, and empty actions',
    () {
      final actions = buildSecurityActionPlan(
        report: AuditReportDto(
          score: 40,
          total: BigInt.from(5),
          withPassword: BigInt.from(4),
          weak: const [
            AuditEntryRefDto(
              id: 'weak',
              title: 'Weak',
              detail: 'Weak password',
            ),
          ],
          reused: const [
            ReuseGroupDto(
              entries: [
                AuditEntryRefDto(id: 'reuse', title: 'Reuse', detail: ''),
              ],
            ),
          ],
          stale: const [
            AuditEntryRefDto(id: 'stale', title: 'Stale', detail: ''),
          ],
          empty: const [
            AuditEntryRefDto(id: 'empty', title: 'Empty', detail: ''),
          ],
        ),
        entries: [
          _entry(
            id: 'github',
            title: 'GitHub',
            url: 'https://github.com',
            password: 'secret',
          ),
        ],
        breaches: BreachReportDto(
          checked: BigInt.from(1),
          hits: [
            BreachHitDto(
              id: 'breach',
              title: 'Breach',
              count: BigInt.from(1200),
            ),
          ],
        ),
      );

      expect(actions.map((action) => action.kind), [
        SecurityActionKind.breach,
        SecurityActionKind.reused,
        SecurityActionKind.weak,
        SecurityActionKind.missing2fa,
        SecurityActionKind.stale,
        SecurityActionKind.empty,
      ]);
      expect(actions.first.severity, SecurityActionSeverity.critical);
      expect(actions.first.detail, contains('1K회'));
    },
  );

  test('recommends 2fa for supported login domains only', () {
    final actions = buildSecurityActionPlan(
      report: _emptyReport(),
      entries: [
        _entry(
          id: 'github',
          title: 'GitHub',
          url: 'github.com',
          password: 'secret',
        ),
        _entry(
          id: 'google',
          title: 'Google',
          url: 'https://accounts.google.com',
          password: 'secret',
          totp: 'JBSWY3DPEHPK3PXP',
        ),
        _entry(
          id: 'archived',
          title: 'Archived GitLab',
          url: 'gitlab.com',
          password: 'secret',
          archived: true,
        ),
        _entry(
          id: 'unknown',
          title: 'Unknown',
          url: 'https://example.invalid',
          password: 'secret',
        ),
      ],
    );

    expect(actions.map((action) => action.id), ['github']);
    expect(actions.single.detail, 'GitHub 계정에 2FA를 추가하세요.');
  });

  test('builds travel readiness from travel-safe tags', () {
    final report = buildTravelReadiness([
      _entry(
        id: 'safe',
        title: 'Travel Mail',
        tags: [' Travel-Safe '],
        password: 'secret',
      ),
      _entry(id: 'bank', title: 'Bank', tags: ['finance'], password: 'secret'),
      _entry(
        id: 'github',
        title: 'GitHub',
        url: 'github.com',
        password: 'secret',
      ),
      _entry(
        id: 'archived',
        title: 'Archived',
        archived: true,
        password: 'secret',
      ),
    ]);

    expect(report.activeCount, 3);
    expect(report.safeEntries.map((entry) => entry.id), ['safe']);
    expect(report.hiddenEntries.map((entry) => entry.id), ['bank', 'github']);
    expect(report.highValueHiddenEntries.map((entry) => entry.id), [
      'bank',
      'github',
    ]);
    expect(report.ready, isFalse);
  });
}

AuditReportDto _emptyReport() {
  return AuditReportDto(
    score: 100,
    total: BigInt.zero,
    withPassword: BigInt.zero,
    weak: const [],
    reused: const [],
    stale: const [],
    empty: const [],
  );
}

EntryDto _entry({
  required String id,
  required String title,
  String username = '',
  String password = '',
  String url = '',
  String notes = '',
  String totp = '',
  List<String> tags = const [],
  bool favorite = false,
  int createdAt = 0,
  int updatedAt = 0,
  String itemType = 'login',
  List<CustomFieldDto> customFields = const [],
  List<PasswordHistoryDto> passwordHistory = const [],
  bool archived = false,
}) {
  return EntryDto(
    id: id,
    title: title,
    username: username,
    password: password,
    url: url,
    notes: notes,
    totp: totp,
    tags: tags,
    favorite: favorite,
    createdAt: createdAt,
    updatedAt: updatedAt,
    itemType: itemType,
    customFields: customFields,
    passwordHistory: passwordHistory,
    archived: archived,
  );
}
