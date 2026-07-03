import 'src/rust/api/vault.dart';

enum EntryTypeFilter { all, login, note, card, totp, favorite }

enum EntrySortMode { updatedDesc, titleAsc, createdDesc }

class EntryDraftValidation {
  const EntryDraftValidation({required this.isValid, this.message});

  final bool isValid;
  final String? message;
}

class _SearchSpec {
  const _SearchSpec({
    required this.terms,
    required this.tags,
    required this.type,
    required this.hasTotp,
    required this.hasPassword,
    required this.hasUrl,
    required this.favorite,
  });

  final List<String> terms;
  final List<String> tags;
  final String? type;
  final bool? hasTotp;
  final bool? hasPassword;
  final bool? hasUrl;
  final bool? favorite;
}

List<EntryDto> filterEntries({
  required List<EntryDto> entries,
  required String query,
  required EntryTypeFilter filter,
  String? tag,
}) {
  final search = _parseSearch(query);
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

    if (search.type != null && entry.itemType != search.type) return false;
    if (search.favorite != null && entry.favorite != search.favorite) {
      return false;
    }
    if (search.hasTotp != null && entry.totp.isNotEmpty != search.hasTotp) {
      return false;
    }
    if (search.hasPassword != null &&
        entry.password.isNotEmpty != search.hasPassword) {
      return false;
    }
    if (search.hasUrl != null && entry.url.isNotEmpty != search.hasUrl) {
      return false;
    }

    if (normalizedTag != null &&
        !entry.tags.any((tag) => tag.toLowerCase() == normalizedTag)) {
      return false;
    }

    if (search.tags.isNotEmpty) {
      final entryTags = entry.tags.map((tag) => tag.toLowerCase()).toSet();
      if (!search.tags.every(entryTags.contains)) return false;
    }

    final searchable = [
      entry.title,
      entry.username,
      entry.url,
      entry.notes,
      ...entry.tags,
      ...entry.customFields.map((field) => field.label),
    ].join(' ').toLowerCase();

    return search.terms.every(searchable.contains);
  }).toList();
}

_SearchSpec _parseSearch(String query) {
  final terms = <String>[];
  final tags = <String>[];
  String? type;
  bool? hasTotp;
  bool? hasPassword;
  bool? hasUrl;
  bool? favorite;

  for (final rawToken in query.trim().split(RegExp(r'\s+'))) {
    if (rawToken.isEmpty) continue;
    final token = rawToken.toLowerCase();
    final value = _tokenValue(token);
    if (token.startsWith('tag:') && value.isNotEmpty) {
      tags.add(value);
    } else if (token.startsWith('type:') && _isKnownType(value)) {
      type = value;
    } else if (token.startsWith('has:')) {
      switch (value) {
        case '2fa':
        case 'totp':
          hasTotp = true;
        case 'password':
        case 'pass':
          hasPassword = true;
        case 'url':
        case 'site':
          hasUrl = true;
        default:
          terms.add(token);
      }
    } else if (token.startsWith('fav:') || token.startsWith('favorite:')) {
      favorite = _parseBoolToken(value);
    } else {
      terms.add(token);
    }
  }

  return _SearchSpec(
    terms: terms,
    tags: tags,
    type: type,
    hasTotp: hasTotp,
    hasPassword: hasPassword,
    hasUrl: hasUrl,
    favorite: favorite,
  );
}

String _tokenValue(String token) {
  final index = token.indexOf(':');
  if (index < 0 || index == token.length - 1) return '';
  return token.substring(index + 1).trim();
}

bool _isKnownType(String value) {
  return value == 'login' || value == 'note' || value == 'card';
}

bool? _parseBoolToken(String value) {
  return switch (value) {
    'true' || 'yes' || '1' || 'on' => true,
    'false' || 'no' || '0' || 'off' => false,
    _ => null,
  };
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

List<String> mergeTags(List<String> current, Iterable<String> additions) {
  final merged = <String>[];
  final seen = <String>{};
  for (final tag in [...current, ...additions]) {
    final trimmed = tag.trim();
    final key = trimmed.toLowerCase();
    if (trimmed.isEmpty || seen.contains(key)) continue;
    seen.add(key);
    merged.add(trimmed);
  }
  return merged;
}

EntryDto copyEntryWith({
  required EntryDto entry,
  bool? favorite,
  List<String>? tags,
}) {
  return EntryDto(
    id: entry.id,
    title: entry.title,
    username: entry.username,
    password: entry.password,
    url: entry.url,
    notes: entry.notes,
    totp: entry.totp,
    tags: tags ?? entry.tags,
    favorite: favorite ?? entry.favorite,
    createdAt: entry.createdAt,
    updatedAt: entry.updatedAt,
    itemType: entry.itemType,
    customFields: entry.customFields,
    passwordHistory: entry.passwordHistory,
    archived: entry.archived,
  );
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
