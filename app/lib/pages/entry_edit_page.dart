import 'package:flutter/material.dart';

import '../src/rust/api/vault.dart';
import '../theme.dart';
import '../widgets.dart';
import 'generator_page.dart';

/// 편집 가능한 커스텀 필드 상태.
class _EditableField {
  _EditableField({String label = '', String value = '', this.hidden = false})
      : label = TextEditingController(text: label),
        value = TextEditingController(text: value);
  final TextEditingController label;
  final TextEditingController value;
  bool hidden;
  void dispose() {
    label.dispose();
    value.dispose();
  }
}

/// entry == null이면 새 항목 추가, 아니면 편집.
class EntryEditPage extends StatefulWidget {
  const EntryEditPage({super.key, this.entry});

  final EntryDto? entry;

  @override
  State<EntryEditPage> createState() => _EntryEditPageState();
}

class _EntryEditPageState extends State<EntryEditPage> {
  late final TextEditingController _title;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late final TextEditingController _url;
  late final TextEditingController _notes;
  late final TextEditingController _totp;
  late final TextEditingController _tags;
  late String _itemType;
  final List<_EditableField> _fields = [];
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _title = TextEditingController(text: e?.title ?? '');
    _username = TextEditingController(text: e?.username ?? '');
    _password = TextEditingController(text: e?.password ?? '');
    _url = TextEditingController(text: e?.url ?? '');
    _notes = TextEditingController(text: e?.notes ?? '');
    _totp = TextEditingController(text: e?.totp ?? '');
    _tags = TextEditingController(text: e?.tags.join(', ') ?? '');
    _itemType = e?.itemType ?? 'login';
    for (final f in e?.customFields ?? <CustomFieldDto>[]) {
      _fields.add(_EditableField(
          label: f.label, value: f.value, hidden: f.hidden));
    }
  }

  @override
  void dispose() {
    for (final c in [_title, _username, _password, _url, _notes, _totp, _tags]) {
      c.dispose();
    }
    for (final f in _fields) {
      f.dispose();
    }
    super.dispose();
  }

  bool get _isLogin => _itemType == 'login' || _itemType == 'card';
  bool get _isCard => _itemType == 'card';

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = '제목을 입력하세요');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final tags = _tags.text
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    final customFields = _fields
        .where((f) => f.label.text.trim().isNotEmpty || f.value.text.isNotEmpty)
        .map((f) => CustomFieldDto(
              label: f.label.text.trim(),
              value: f.value.text,
              hidden: f.hidden,
            ))
        .toList();
    final dto = EntryDto(
      id: widget.entry?.id ?? '',
      title: _title.text.trim(),
      username: _username.text.trim(),
      password: _password.text,
      url: _url.text.trim(),
      notes: _notes.text,
      totp: _totp.text.trim(),
      tags: tags,
      favorite: widget.entry?.favorite ?? false,
      createdAt: widget.entry?.createdAt ?? 0,
      updatedAt: widget.entry?.updatedAt ?? 0,
      itemType: _itemType,
      customFields: customFields,
      passwordHistory: widget.entry?.passwordHistory ?? [],
      archived: widget.entry?.archived ?? false,
    );
    try {
      if (widget.entry == null) {
        await addEntry(entry: dto);
      } else {
        await updateEntry(entry: dto);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  Future<void> _generate() async {
    final generated = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => const GeneratorPage(pickMode: true)));
    if (generated != null && generated.isNotEmpty) {
      setState(() {
        _password.text = generated;
        _obscure = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.entry == null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? '새 항목' : '항목 편집'),
        actions: [
          TextButton.icon(
            onPressed: _busy ? null : _save,
            icon: const Icon(Icons.check_rounded),
            label: const Text('저장'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (isNew) ...[
            _typeSelector(),
            const SizedBox(height: 16),
          ],
          TextField(
            controller: _title,
            autofocus: isNew,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
                labelText: '제목 *',
                prefixIcon: Icon(_typeIcon(_itemType))),
          ),
          const SizedBox(height: 12),
          if (_isLogin) ...[
            TextField(
              controller: _username,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                  labelText: _isCard ? '카드 소유자 / 번호' : '아이디 / 이메일',
                  prefixIcon: Icon(
                      _isCard ? Icons.credit_card_rounded : Icons.person_rounded)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: _obscure,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: _isCard ? 'CVC / PIN' : '비밀번호',
                prefixIcon: const Icon(Icons.key_rounded),
                suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (!_isCard)
                    IconButton(
                      tooltip: '생성기',
                      icon: const Icon(Icons.auto_awesome_rounded),
                      onPressed: _generate,
                    ),
                  IconButton(
                    icon: Icon(_obscure
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ]),
              ),
            ),
            if (!_isCard) ...[
              const SizedBox(height: 8),
              StrengthBar(password: _password.text),
            ],
            const SizedBox(height: 12),
          ],
          if (_itemType == 'login') ...[
            TextField(
              controller: _url,
              textInputAction: TextInputAction.next,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                  labelText: 'URL', prefixIcon: Icon(Icons.link_rounded)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _totp,
              decoration: const InputDecoration(
                labelText: 'TOTP 시크릿 (base32 또는 otpauth:// URI)',
                prefixIcon: Icon(Icons.timer_rounded),
              ),
            ),
            const SizedBox(height: 12),
          ],
          // 커스텀 필드
          _customFieldsSection(),
          const SizedBox(height: 12),
          TextField(
            controller: _tags,
            decoration: const InputDecoration(
              labelText: '태그 (쉼표로 구분)',
              prefixIcon: Icon(Icons.sell_rounded),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            maxLines: _itemType == 'note' ? 10 : 4,
            decoration: const InputDecoration(
                labelText: '메모', alignLabelWithHint: true),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: G.danger)),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: const Icon(Icons.save_rounded),
            label: const Text('저장'),
          ),
        ],
      ),
    );
  }

  IconData _typeIcon(String t) => switch (t) {
        'note' => Icons.sticky_note_2_rounded,
        'card' => Icons.credit_card_rounded,
        _ => Icons.badge_rounded,
      };

  Widget _typeSelector() {
    Widget tab(String type, IconData icon, String label) {
      final active = _itemType == type;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _itemType = type),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: active ? G.mint.withValues(alpha: 0.12) : G.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: active ? G.mint : G.border,
                  width: active ? 1.4 : 1),
            ),
            child: Column(children: [
              Icon(icon, color: active ? G.mint : G.sub, size: 22),
              const SizedBox(height: 6),
              Text(label,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: active ? G.mint : G.sub)),
            ]),
          ),
        ),
      );
    }

    return Row(children: [
      tab('login', Icons.badge_rounded, '로그인'),
      tab('note', Icons.sticky_note_2_rounded, '보안 메모'),
      tab('card', Icons.credit_card_rounded, '카드'),
    ]);
  }

  Widget _customFieldsSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (var i = 0; i < _fields.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            Expanded(
              flex: 2,
              child: TextField(
                controller: _fields[i].label,
                decoration: const InputDecoration(
                    labelText: '필드명', isDense: true),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: TextField(
                controller: _fields[i].value,
                obscureText: _fields[i].hidden,
                decoration: InputDecoration(
                  labelText: '값',
                  isDense: true,
                  suffixIcon: IconButton(
                    icon: Icon(
                        _fields[i].hidden
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        size: 18),
                    onPressed: () =>
                        setState(() => _fields[i].hidden = !_fields[i].hidden),
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline_rounded,
                  color: G.faint),
              onPressed: () => setState(() {
                _fields[i].dispose();
                _fields.removeAt(i);
              }),
            ),
          ]),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => setState(() => _fields.add(_EditableField())),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('필드 추가'),
        ),
      ),
    ]);
  }
}
