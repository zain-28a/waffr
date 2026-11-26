// Encrypted backup file: save everything on this phone to a file sealed with
// a passphrase, or restore one. Opened from Privacy and security.
//
// Restoring only adds and updates rows (LedgerBackupService.restore), so it
// is safe to run on a phone that already has data.

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:waffr/core/security/ledger_backup_codec.dart';
import 'package:waffr/core/sync/auth_session.dart';
import 'package:waffr/core/theme/app_icons.dart';
import 'package:waffr/core/theme/app_palette.dart';
import 'package:waffr/core/utils/app_feedback.dart';
import 'package:waffr/data/services/ledger_backup_service.dart';
import 'package:waffr/screens/offline/login/auth_fields.dart';
import 'package:waffr/widgets/brand/waffr_page_header.dart';
import 'package:waffr/widgets/button/app_primary_button.dart';
import 'package:waffr/widgets/containers/app_list_tile.dart';
import 'package:waffr/widgets/glass/aurora_backdrop.dart';

/// Save or restore an encrypted backup file.
class BackupScreen extends StatefulWidget {
  /// Creates a [BackupScreen].
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  final _passphrase = TextEditingController();
  final _confirm = TextEditingController();
  final _restorePassphrase = TextEditingController();

  bool _obscure = true;
  bool _busy = false;
  bool? _guest;
  String? _message;
  AppFeedbackKind _messageKind = AppFeedbackKind.error;

  /// The picked file waiting for its passphrase.
  Uint8List? _picked;
  String? _pickedName;

  @override
  void initState() {
    super.initState();
    AuthSession.instance.isLoggedIn().then((signedIn) {
      if (mounted) setState(() => _guest = !signedIn);
    });
  }

  @override
  void dispose() {
    _passphrase.dispose();
    _confirm.dispose();
    _restorePassphrase.dispose();
    super.dispose();
  }

  void _show(String? message, {AppFeedbackKind kind = AppFeedbackKind.error}) {
    setState(() {
      _message = message;
      _messageKind = kind;
    });
  }

  String? get _saveProblem {
    final value = _passphrase.text;
    if (value.length < LedgerBackupCodec.minPassphraseLength) {
      return 'اختر كلمة مرور للنسخة من ${LedgerBackupCodec.minPassphraseLength} أحرف على الأقل';
    }
    if (value != _confirm.text) return 'كلمتا المرور غير متطابقتين';
    return null;
  }

  Future<void> _save() async {
    final problem = _saveProblem;
    if (problem != null) return _show(problem);
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final bytes = await LedgerBackupService.instance.export(_passphrase.text);
      final saved = await FilePicker.saveFile(
        fileName: LedgerBackupService.fileName(DateTime.now()),
        bytes: bytes,
        dialogTitle: 'حفظ النسخة الاحتياطية',
      );
      if (!mounted) return;
      if (saved == null) {
        setState(() => _busy = false);
        return;
      }
      _passphrase.clear();
      _confirm.clear();
      setState(() => _busy = false);
      _show(
        'حُفظت النسخة. احتفظ بكلمة مرورها: لا يمكن فتح النسخة بدونها.',
        kind: AppFeedbackKind.success,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _show('تعذّر حفظ النسخة الاحتياطية. حاول مرة أخرى');
    }
  }

  Future<void> _pick() async {
    setState(() => _message = null);
    try {
      final file = await FilePicker.pickFile(dialogTitle: 'اختر ملف النسخة');
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      try {
        LedgerBackupCodec.parseHeader(bytes);
      } on BackupFormatException catch (error) {
        _show(
          error.reason == 'newer version'
              ? 'هذه النسخة من إصدار أحدث من التطبيق. حدّث التطبيق أولاً'
              : 'هذا الملف ليس نسخة احتياطية من وفّر',
        );
        return;
      }
      setState(() {
        _picked = bytes;
        _pickedName = file.name;
      });
    } catch (_) {
      if (mounted) _show('تعذّر فتح الملف');
    } finally {
      await FilePicker.clearTemporaryFiles().catchError((_) {});
    }
  }

  Future<void> _restore() async {
    final file = _picked;
    if (file == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    final LedgerBackupPreview preview;
    try {
      preview = await LedgerBackupService.instance.open(
        file,
        _restorePassphrase.text,
      );
    } on BackupPassphraseException {
      if (!mounted) return;
      setState(() => _busy = false);
      return _show('كلمة مرور النسخة غير صحيحة، أو الملف تغيّر بعد حفظه');
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      return _show('تعذّر قراءة النسخة الاحتياطية');
    }
    if (!mounted) return;

    final created = preview.createdAt;
    final owner = preview.accountEmail;
    final confirm = await showAppConfirmDialog(
      context,
      title: 'استعادة النسخة الاحتياطية',
      message:
          'نسخة بتاريخ ${created.year}/${created.month}/${created.day}'
          '${owner == null ? '' : ' من الحساب $owner'}، '
          'فيها ${preview.ledgerEntries} عملية.\n'
          'ستُضاف إلى بياناتك الحالية، ولن يُحذف منها شيء.',
      confirmLabel: 'استعادة',
      kind: AppFeedbackKind.info,
    );
    if (!mounted) return;
    if (!confirm) {
      setState(() => _busy = false);
      return;
    }

    final ok = await LedgerBackupService.instance.restore(preview);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) {
        _picked = null;
        _pickedName = null;
        _restorePassphrase.clear();
      }
    });
    _show(
      ok
          ? 'تمت استعادة النسخة الاحتياطية'
          : 'تعذّرت الاستعادة؛ بقيت بياناتك كما هي',
      kind: ok ? AppFeedbackKind.success : AppFeedbackKind.error,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final textPrimary = palette.textPrimary;
    final textSecondary = palette.textSecondary;

    Widget field(
      String label,
      TextEditingController controller,
      String hint, {
      Widget? suffix,
    }) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthFieldLabel(text: label, color: textPrimary),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            enabled: !_busy,
            obscureText: _obscure,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (_) => setState(() => _message = null),
            style: TextStyle(color: textPrimary, fontSize: 16),
            decoration: authFieldDecoration(
              hint: hint,
              fillColor: palette.surface,
              textSecondary: textSecondary,
              suffixIcon: suffix,
            ),
          ),
          const SizedBox(height: 16),
        ],
      );
    }

    final eye = IconButton(
      onPressed: () => setState(() => _obscure = !_obscure),
      icon: Icon(
        _obscure ? AppIcons.eye : AppIcons.eyeOff,
        color: textSecondary,
      ),
    );
    final note = TextStyle(color: textSecondary, fontSize: 13, height: 1.5);

    return Scaffold(
      backgroundColor: palette.background,
      appBar: WaffrBackHeader(enabled: !_busy, title: 'النسخة الاحتياطية'),
      body: AuroraPage(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_guest == true) ...[
              Text(
                'أنت تستخدم وفّر دون حساب، فبياناتك محفوظة على هذا الهاتف فقط. '
                'احفظ نسخة احتياطية لتستعيدها إن فقدت الهاتف أو غيّرته.',
                style: note,
              ),
              const SizedBox(height: 18),
            ],
            const AppSectionTitle(title: 'حفظ نسخة مشفّرة'),
            field(
              'كلمة مرور النسخة',
              _passphrase,
              '10 أحرف على الأقل',
              suffix: eye,
            ),
            field('تأكيد كلمة المرور', _confirm, 'أعد كتابتها'),
            Text(
              'تُشفَّر النسخة بهذه الكلمة. احفظها في مكان آمن: '
              'لا يمكن لأحد، ولا لنا، فتح النسخة بدونها.',
              style: note,
            ),
            const SizedBox(height: 16),
            AppPrimaryButton(
              label: 'حفظ النسخة',
              icon: AppIcons.shieldCheck,
              enabled: !_busy && _picked == null,
              busy: _busy && _picked == null,
              onTap: _save,
            ),
            const SizedBox(height: 28),
            const AppSectionTitle(title: 'استعادة من نسخة'),
            if (_picked == null)
              AppListTile(
                icon: AppIcons.fileText,
                title: 'اختيار ملف النسخة',
                onTap: _busy ? null : _pick,
              )
            else ...[
              Text(_pickedName ?? '', style: note),
              const SizedBox(height: 12),
              field(
                'كلمة مرور النسخة',
                _restorePassphrase,
                '••••••••••',
                suffix: eye,
              ),
              AppPrimaryButton(
                label: 'استعادة',
                icon: AppIcons.history,
                enabled: !_busy && _restorePassphrase.text.isNotEmpty,
                busy: _busy,
                onTap: _restore,
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _picked = null;
                        _pickedName = null;
                        _restorePassphrase.clear();
                      }),
                child: Text('إلغاء', style: TextStyle(color: textSecondary)),
              ),
            ],
            const SizedBox(height: 16),
            AppInlineMessage(message: _message, kind: _messageKind),
          ],
        ),
      ),
    );
  }
}
