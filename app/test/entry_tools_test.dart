import 'package:app/entry_tools.dart';
import 'package:app/src/rust/api/vault.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('filters by query, type, tag, favorite, and totp', () {
    final entries = [
      _entry(
        title: 'GitHub',
        username: 'octo',
        itemType: 'login',
        tags: ['work', 'code'],
        favorite: true,
        totp: 'JBSWY3DPEHPK3PXP',
      ),
      _entry(
        title: 'Passport',
        itemType: 'note',
        notes: 'safe',
        tags: ['identity'],
      ),
      _entry(title: 'Corporate Card', itemType: 'card', tags: ['work']),
    ];

    expect(
      filterEntries(
        entries: entries,
        query: 'octo',
        filter: EntryTypeFilter.all,
      ).map((entry) => entry.title),
      ['GitHub'],
    );
    expect(
      filterEntries(
        entries: entries,
        query: '',
        filter: EntryTypeFilter.note,
      ).map((entry) => entry.title),
      ['Passport'],
    );
    expect(
      filterEntries(
        entries: entries,
        query: '',
        filter: EntryTypeFilter.all,
        tag: 'work',
      ).map((entry) => entry.title),
      ['GitHub', 'Corporate Card'],
    );
    expect(
      filterEntries(
        entries: entries,
        query: '',
        filter: EntryTypeFilter.favorite,
      ).map((entry) => entry.title),
      ['GitHub'],
    );
    expect(
      filterEntries(
        entries: entries,
        query: '',
        filter: EntryTypeFilter.totp,
      ).map((entry) => entry.title),
      ['GitHub'],
    );
  });

  test('sorts without mutating the original list', () {
    final entries = [
      _entry(title: 'Beta', createdAt: 10, updatedAt: 20),
      _entry(title: 'Alpha', createdAt: 30, updatedAt: 10),
    ];

    final sorted = sortEntries(entries, EntrySortMode.titleAsc);

    expect(sorted.map((entry) => entry.title), ['Alpha', 'Beta']);
    expect(entries.map((entry) => entry.title), ['Beta', 'Alpha']);
  });

  test('collects unique tags in stable alphabetical order', () {
    final tags = collectTags([
      _entry(title: 'A', tags: ['Work', 'code']),
      _entry(title: 'B', tags: ['code', ' personal ']),
    ]);

    expect(tags, ['code', 'personal', 'Work']);
  });

  test('merges tags immutably and case-insensitively', () {
    final merged = mergeTags(['Work', ' personal '], ['work', 'banking', '']);

    expect(merged, ['Work', 'personal', 'banking']);
  });

  test('copies entry with selected immutable updates', () {
    final original = _entry(title: 'GitHub', tags: ['work']);
    final copied = copyEntryWith(
      entry: original,
      favorite: true,
      tags: mergeTags(original.tags, ['code']),
    );

    expect(copied.favorite, isTrue);
    expect(copied.tags, ['work', 'code']);
    expect(original.favorite, isFalse);
    expect(original.tags, ['work']);
  });

  test('validates title, web url, and totp shape', () {
    expect(
      validateEntryDraft(
        title: '',
        itemType: 'login',
        url: '',
        totp: '',
      ).isValid,
      isFalse,
    );
    expect(
      validateEntryDraft(
        title: 'GitHub',
        itemType: 'login',
        url: 'not a url',
        totp: '',
      ).message,
      'URL은 올바른 웹 주소여야 합니다.',
    );
    expect(
      validateEntryDraft(
        title: 'GitHub',
        itemType: 'login',
        url: 'github.com',
        totp: 'not-valid!',
      ).message,
      'TOTP 값은 base32 secret 또는 otpauth:// URI여야 합니다.',
    );
    expect(
      validateEntryDraft(
        title: 'GitHub',
        itemType: 'login',
        url: 'github.com',
        totp: 'JBSWY3DPEHPK3PXP',
      ).isValid,
      isTrue,
    );
  });

  test('normalizes bare web domains', () {
    expect(normalizeUrl('example.com'), 'https://example.com');
    expect(normalizeUrl('https://example.com'), 'https://example.com');
  });
}

EntryDto _entry({
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
    id: title,
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
