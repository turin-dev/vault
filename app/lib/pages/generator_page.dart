import 'package:flutter/material.dart';

import '../src/rust/api/vault.dart';
import '../widgets.dart';

/// 비밀번호 생성기. pickMode면 "사용" 버튼으로 결과를 pop해서 돌려준다.
class GeneratorPage extends StatefulWidget {
  const GeneratorPage({super.key, this.pickMode = false});

  final bool pickMode;

  @override
  State<GeneratorPage> createState() => _GeneratorPageState();
}

class _GeneratorPageState extends State<GeneratorPage> {
  double _length = 20;
  bool _lower = true;
  bool _upper = true;
  bool _digits = true;
  bool _symbols = true;
  bool _excludeAmbiguous = false;
  String _password = '';

  @override
  void initState() {
    super.initState();
    _regenerate();
  }

  Future<void> _regenerate() async {
    try {
      final p = await generatePassword(
          opts: GenOptionsDto(
        length: _length.round(),
        lower: _lower,
        upper: _upper,
        digits: _digits,
        symbols: _symbols,
        excludeAmbiguous: _excludeAmbiguous,
      ));
      if (mounted) setState(() => _password = p);
    } catch (_) {
      // 모든 클래스가 꺼진 경우 — 마지막 값 유지
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('비밀번호 생성기')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: scheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                SelectableText(
                  _password,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton.filledTonal(
                      icon: const Icon(Icons.refresh_rounded),
                      tooltip: '다시 생성',
                      onPressed: _regenerate,
                    ),
                    const SizedBox(width: 12),
                    IconButton.filledTonal(
                      icon: const Icon(Icons.copy_rounded),
                      tooltip: '복사',
                      onPressed: () =>
                          copySensitive(context, '비밀번호', _password),
                    ),
                  ],
                ),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          StrengthBar(password: _password),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(children: [
                Row(children: [
                  const Text('길이'),
                  Expanded(
                    child: Slider(
                      value: _length,
                      min: 8,
                      max: 64,
                      divisions: 56,
                      label: '${_length.round()}',
                      onChanged: (v) => setState(() => _length = v),
                      onChangeEnd: (_) => _regenerate(),
                    ),
                  ),
                  SizedBox(
                      width: 32,
                      child: Text('${_length.round()}',
                          textAlign: TextAlign.right,
                          style:
                              const TextStyle(fontWeight: FontWeight.w700))),
                ]),
                _toggle('소문자 (a-z)', _lower, (v) => _lower = v),
                _toggle('대문자 (A-Z)', _upper, (v) => _upper = v),
                _toggle('숫자 (0-9)', _digits, (v) => _digits = v),
                _toggle('기호 (!@#\$...)', _symbols, (v) => _symbols = v),
                _toggle('헷갈리는 문자 제외 (l, 1, O, 0...)', _excludeAmbiguous,
                    (v) => _excludeAmbiguous = v),
              ]),
            ),
          ),
          if (widget.pickMode) ...[
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.check_rounded),
              onPressed: () => Navigator.of(context).pop(_password),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('이 비밀번호 사용', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _toggle(String label, bool value, void Function(bool) set) {
    return SwitchListTile(
      title: Text(label),
      value: value,
      contentPadding: EdgeInsets.zero,
      onChanged: (v) {
        setState(() => set(v));
        _regenerate();
      },
    );
  }
}
