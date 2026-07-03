import 'src/rust/api/vault.dart';

enum EntryTypeFilter { all, login, note, card, totp, favorite }

enum EntrySortMode { updatedDesc, titleAsc, createdDesc }

class EntryDraftValidation {
  const EntryDraftValidation({required this.isValid, this.message});

  final bool isValid;
  final String? message;
}

List<EntryDto> filterEntries({
  required List<EntryDto> entries,
  required String query,
  required EntryTypeFilter filter,
  String? tag,
}) {
  final normalizedQuery = query.trim().toLowerCase();
  final normalizedTag = tag?.trim().toLowerCase();

  return entries.where((entry) {
    final matchesFilter = switch (filter) {
      EntryTypeFilter.all => true,
      EntryTypeFilter.login => entry.itemType == 'login',
      EntryTypeFilter.note => entry.itemType == 'note',
      EntryTypeFilter.card => entry.itemType == 'card',
      EntryTypeFilter.totp => entry.totp.isNotEmpty,
      EntryTypeFilter.favorite => entry.favorite,
    };
    if (!matchesFilter) return false;

    if (normalizedTag != null &&
        !entry.tags.any((tag) => tag.toLowerCase() == normalizedTag)) {
      return false;
    }

    if (normalizedQuery.isEmpty) return true;

    final searchable = [
      entry.title,
      entry.username,
      entry.url,
      entry.notes,
      ...entry.tags,
      ...entry.customFields.map((field) => field.label),
    ].join(' ').toLowerCase();

    return searchable.contains(normalizedQuery);
  }).toList();
}

List<EntryDto> sortEntries(List<EntryDto> entries, EntrySortMode mode) {
  final sorted = [...entries];
  sorted.sort((a, b) {
    return switch (mode) {
      EntrySortMode.updatedDesc => b.updatedAt.compareTo(a.updatedAt),
      EntrySortMode.titleAsc => a.title.toLowerCase().compareTo(
        b.title.toLowerCase(),
      ),
      EntrySortMode.createdDesc => b.createdAt.compareTo(a.createdAt),
    };
  });
  return sorted;
}

List<String> collectTags(List<EntryDto> entries) {
  final tags = entries.expand((entry) => entry.tags).map((tag) => tag.trim());
  final unique = {
    for (final tag in tags)
      if (tag.isNotEmpty) tag,
  }.toList();
  unique.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return unique;
}

EntryDraftValidation validateEntryDraft({
  required String title,
  required String itemType,
  required String url,
  required String totp,
}) {
  if (title.trim().isEmpty) {
    return const EntryDraftValidation(isValid: false, message: '제목을 입력하세요.');
  }

  if (itemType == 'login' && url.trim().isNotEmpty) {
    if (RegExp(r'\s').hasMatch(url.trim())) {
      return const EntryDraftValidation(
        isValid: false,
        message: 'URL은 올바른 웹 주소여야 합니다.',
      );
    }
    final normalizedUrl = normalizeUrl(url);
    final uri = Uri.tryParse(normalizedUrl);
    final isWebUrl =
        uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
    if (!isWebUrl || uri.host.isEmpty) {
      return const EntryDraftValidation(
        isValid: false,
        message: 'URL은 올바른 웹 주소여야 합니다.',
      );
    }
  }

  if (itemType == 'login' && totp.trim().isNotEmpty) {
    final value = totp.trim();
    final looksLikeTotp =
        value.startsWith('otpauth://') ||
        RegExp(r'^[A-Z2-7=\s]+$', caseSensitive: false).hasMatch(value);
    if (!looksLikeTotp) {
      return const EntryDraftValidation(
        isValid: false,
        message: 'TOTP 값은 base32 secret 또는 otpauth:// URI여야 합니다.',
      );
    }
  }

  return const EntryDraftValidation(isValid: true);
}

String normalizeUrl(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '';
  final uri = Uri.tryParse(trimmed);
  if (uri != null && uri.hasScheme) return trimmed;
  return 'https://$trimmed';
}

String itemTypeLabel(String itemType) {
  return switch (itemType) {
    'note' => '보안 메모',
    'card' => '카드',
    _ => '로그인',
  };
}
