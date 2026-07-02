import 'package:flutter/material.dart';

import '../src/rust/api/vault.dart';
import '../theme.dart';
import '../widgets.dart';

/// 비밀번호 생성기. pickMode면 "사용" 버튼으로 결과를 pop해서 돌려준다.
class GeneratorPage extends StatefulWidget {
  const GeneratorPage({super.key, this.pickMode = false});

  final bool pickMode;

  @override
  State<GeneratorPage> createState() => _GeneratorPageState();
}

class _GeneratorPageState extends State<GeneratorPage> {
  bool _passphraseMode = false;

  // 문자 비밀번호 옵션
  double _length = 20;
  bool _lower = true;
  bool _upper = true;
  bool _digits = true;
  bool _symbols = true;
  bool _excludeAmbiguous = false;

  // 패스프레이즈 옵션
  double _wordCount = 5;
  bool _capitalize = true;
  bool _addNumber = true;
  String _separator = '-';

  String _password = '';

  @override
  void initState() {
    super.initState();
    _regenerate();
  }

  Future<void> _regenerate() async {
    try {
      final p = _passphraseMode
          ? await generatePassphrase(
              opts: PassphraseOptionsDto(
              wordCount: _wordCount.round(),
              separator: _separator,
              capitalize: _capitalize,
              addNumber: _addNumber,
            ))
          : await generatePassword(
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
      // 잘못된 옵션 — 마지막 값 유지
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('비밀번호 생성기')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 모드 전환
          _modeSelector(),
          const SizedBox(height: 16),
          // 결과 카드
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: G.mint.withValues(alpha: 0.30)),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [G.mint.withValues(alpha: 0.07), G.surface],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                SelectableText(
                  _password,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: G.mint,
                    height: 1.5,
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
              child: _passphraseMode ? _passphraseOptions() : _passwordOptions(),
            ),
          ),
          if (widget.pickMode) ...[
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.check_rounded),
              onPressed: () => Navigator.of(context).pop(_password),
              label: const Text('이 비밀번호 사용'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _modeSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: G.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: G.border),
      ),
      child: Row(children: [
        _modeTab('비밀번호', !_passphraseMode, () {
          setState(() => _passphraseMode = false);
          _regenerate();
        }),
        _modeTab('패스프레이즈', _passphraseMode, () {
          setState(() => _passphraseMode = true);
          _regenerate();
        }),
      ]),
    );
  }

  Widget _modeTab(String label, bool active, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? G.mint : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: active ? G.onMint : G.sub,
              )),
        ),
      ),
    );
  }

  Widget _passwordOptions() {
    return Column(children: [
      _sliderRow('길이', _length, 8, 64, 56, (v) => setState(() => _length = v)),
      _toggle('소문자 (a-z)', _lower, (v) => _lower = v),
      _toggle('대문자 (A-Z)', _upper, (v) => _upper = v),
      _toggle('숫자 (0-9)', _digits, (v) => _digits = v),
      _toggle('기호 (!@#\$...)', _symbols, (v) => _symbols = v),
      _toggle('헷갈리는 문자 제외 (l, 1, O, 0...)', _excludeAmbiguous,
          (v) => _excludeAmbiguous = v),
    ]);
  }

  Widget _passphraseOptions() {
    return Column(children: [
      _sliderRow('단어 수', _wordCount, 3, 10, 7,
          (v) => setState(() => _wordCount = v)),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          const Text('구분자'),
          const Spacer(),
          ...['-', '.', '_', ' '].map((s) => Padding(
                padding: const EdgeInsets.only(left: 8),
                child: ChoiceChip(
                  label: Text(s == ' ' ? '공백' : s),
                  selected: _separator == s,
                  onSelected: (_) {
                    setState(() => _separator = s);
                    _regenerate();
                  },
                ),
              )),
        ]),
      ),
      _toggle('첫 글자 대문자', _capitalize, (v) => _capitalize = v),
      _toggle('끝에 숫자 추가', _addNumber, (v) => _addNumber = v),
    ]);
  }

  Widget _sliderRow(String label, double value, double min, double max,
      int divisions, void Function(double) onChanged) {
    return Row(children: [
      SizedBox(width: 56, child: Text(label)),
      Expanded(
        child: Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          label: '${value.round()}',
          onChanged: onChanged,
          onChangeEnd: (_) => _regenerate(),
        ),
      ),
      SizedBox(
          width: 32,
          child: Text('${value.round()}',
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w700))),
    ]);
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
