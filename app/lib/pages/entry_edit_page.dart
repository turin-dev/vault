import 'package:flutter/material.dart';

import '../src/rust/api/vault.dart';
import '../widgets.dart';
import 'generator_page.dart';

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
  }

  @override
  void dispose() {
    for (final c in [_title, _username, _password, _url, _notes, _totp, _tags]) {
      c.dispose();
    }
    super.dispose();
  }

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
          TextField(
            controller: _title,
            autofocus: isNew,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
                labelText: '제목 *', prefixIcon: Icon(Icons.badge_rounded)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _username,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
                labelText: '아이디 / 이메일',
                prefixIcon: Icon(Icons.person_rounded)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: _obscure,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: '비밀번호',
              prefixIcon: const Icon(Icons.key_rounded),
              suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
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
          const SizedBox(height: 8),
          StrengthBar(password: _password.text),
          const SizedBox(height: 8),
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
            maxLines: 4,
            decoration: const InputDecoration(
                labelText: '메모', alignLabelWithHint: true),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: const Icon(Icons.save_rounded),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text('저장', style: TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }
}
