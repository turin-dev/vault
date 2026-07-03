import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../src/rust/api/vault.dart';
import '../theme.dart';

/// 데이터 관리 — 가져오기(CSV) / 내보내기(CSV).
class DataPage extends StatefulWidget {
  const DataPage({super.key});

  @override
  State<DataPage> createState() => _DataPageState();
}

class _DataPageState extends State<DataPage> {
  bool _busy = false;
  String? _message;
  bool _error = false;

  void _report(String msg, {bool error = false}) {
    if (mounted) setState(() { _message = msg; _error = error; });
  }

  Future<void> _import() async {
    setState(() { _busy = true; _message = null; });
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true,
      );
      if (result == null) {
        setState(() => _busy = false);
        return;
      }
      final file = result.files.single;
      final bytes = file.bytes ?? await File(file.path!).readAsBytes();
      final text = String.fromCharCodes(bytes);
      final count = await importCsv(text: text);
      _report('$count개 항목을 가져왔습니다');
    } catch (e) {
      _report(
          '가져오기 실패: ${'$e'.replaceFirst('AnyhowException(', '').replaceFirst(RegExp(r'\)$'), '')}',
          error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('CSV로 내보내기'),
        content: const Text(
          '내보낸 CSV 파일은 암호화되지 않은 평문입니다.\n'
          '비밀번호가 그대로 담기므로 안전한 곳에만 저장하고,\n'
          '사용 후 삭제하세요. 계속할까요?',
          style: TextStyle(color: G.sub, height: 1.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('내보내기')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() { _busy = true; _message = null; });
    try {
      final csv = await exportCsv();
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/geumgo-export.csv';
      final f = File(path);
      await f.writeAsString(csv);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(path)], text: 'Vault 내보내기 (평문 CSV)'),
      );
      _report('내보내기 완료 — 공유 후 임시 파일을 삭제하세요');
    } catch (e) {
      _report('내보내기 실패: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('데이터 관리')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _actionCard(
            icon: Icons.file_download_rounded,
            color: G.mint,
            title: '가져오기',
            subtitle:
                'CSV 파일에서 항목을 가져옵니다.\nBitwarden, 1Password, Chrome, KeePass 등의\n내보낸 CSV를 자동 인식합니다.',
            button: 'CSV 파일 선택',
            onTap: _busy ? null : _import,
          ),
          const SizedBox(height: 12),
          _actionCard(
            icon: Icons.file_upload_rounded,
            color: G.amber,
            title: '내보내기',
            subtitle: '모든 항목을 CSV로 내보냅니다.\n주의: 평문이므로 비밀번호가 그대로 노출됩니다.',
            button: 'CSV로 내보내기',
            onTap: _busy ? null : _export,
          ),
          if (_message != null) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: (_error ? G.danger : G.mint).withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: (_error ? G.danger : G.mint).withValues(alpha: 0.35)),
              ),
              child: Row(children: [
                Icon(_error ? Icons.error_outline_rounded : Icons.check_circle_rounded,
                    size: 18, color: _error ? G.danger : G.mint),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(_message!,
                      style: TextStyle(
                          color: _error ? G.danger : G.mint, fontSize: 13)),
                ),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _actionCard({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required String button,
    required VoidCallback? onTap,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 14),
            Text(title,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 12),
          Text(subtitle,
              style: const TextStyle(fontSize: 13, color: G.sub, height: 1.5)),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                  backgroundColor: color, foregroundColor: G.bg),
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(button),
            ),
          ),
        ]),
      ),
    );
  }
}
