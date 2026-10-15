import 'package:flutter/material.dart';

import '../core/backup_service.dart';
import '../l10n/tr.dart';
import '../network/event_server_runner.dart';
import '../widgets/language_button.dart';

/// Backup & restaurare — același sistem ca în aplicația Organizator: un
/// folder ales (stick USB sau memoria telefonului), backup automat zilnic,
/// fișiere criptate cu parola de backup. Backup-ul cuprinde meniul (cu
/// pozele produselor), mesele, comenzile, activitățile și clasamentul.
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  BackupStatus _status = const BackupStatus();
  bool _busy = false;
  String? _message;
  bool _messageIsError = false;

  @override
  void initState() {
    super.initState();
    _run(_loadStatus);
  }

  Future<void> _loadStatus() async {
    _status = await BackupService.getStatus();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on BackupCancelled {
      // selector închis — nimic de raportat
    } catch (e) {
      _setMessage(e.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _setMessage(String text, {bool error = false}) {
    _message = text;
    _messageIsError = error;
  }

  static String _formatDate(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  Future<void> _pickFolder(String destination) => _run(() async {
        _status = await BackupService.pickFolder(destination);
        _setMessage(tr('backup.folderSet'));
      });

  Future<void> _create() => _run(() async {
        final b = await BackupService.createBackup();
        await _loadStatus();
        _setMessage(tr('backup.created', {'name': b.name}));
      });

  Future<bool> _confirmRestore(String source) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('backup.restore.confirmTitle')),
        content: Text(tr('backup.restore.confirmBody', {'source': source})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('common.cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('backup.restore.action'))),
        ],
      ),
    );
    return confirmed ?? false;
  }

  /// Parola de backup nouă (de două ori, ca să nu fie greșită la tastare).
  Future<void> _setPassword() async {
    final pw1 = TextEditingController();
    final pw2 = TextEditingController();
    String? error;
    final password = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDs) => AlertDialog(
          title: Text(_status.hasPassword ? tr('backup.password.changeTitle') : tr('backup.password.setTitle')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(tr('backup.password.explain'), style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 12),
              TextField(
                controller: pw1,
                obscureText: true,
                decoration: InputDecoration(labelText: tr('backup.password.label'), border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: pw2,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: tr('backup.password.repeat'),
                  errorText: error,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('common.cancel'))),
            FilledButton(
              onPressed: () {
                if (pw1.text.length < BackupService.minPasswordLength) {
                  setDs(() => error = tr('backup.password.tooShort', {'n': BackupService.minPasswordLength}));
                } else if (pw1.text != pw2.text) {
                  setDs(() => error = tr('backup.password.mismatch'));
                } else {
                  Navigator.pop(ctx, pw1.text);
                }
              },
              child: Text(tr('backup.password.save')),
            ),
          ],
        ),
      ),
    );
    if (password == null || !mounted) return;
    await _run(() async {
      _status = await BackupService.setPassword(password);
      _setMessage(tr('backup.password.saved'));
    });
  }

  /// Parola unui backup criptat (alt telefon, sau parolă schimbată între timp).
  Future<String?> _askBackupPassword({required bool wrong}) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('backup.password.askTitle')),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          autofocus: true,
          decoration: InputDecoration(
            labelText: tr('backup.password.label'),
            errorText: wrong ? tr('backup.password.wrong') : null,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('common.cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text(tr('backup.password.open'))),
        ],
      ),
    );
  }

  /// [restore] primește parola introdusă (null la prima încercare — se
  /// folosește parola salvată pe telefon). După reușită aplicația se
  /// repornește, ca să încarce datele restaurate.
  Future<void> _restore(String source, Future<void> Function(String? password) restore) async {
    // Serverul pornit ține meniul și comenzile în memorie și le-ar scrie
    // peste datele restaurate.
    if (await EventServerRunner.isRunning) {
      setState(() => _setMessage(tr('backup.restore.stopServer'), error: true));
      return;
    }
    if (!mounted || !await _confirmRestore(source) || !mounted) return;
    var restored = false;
    await _run(() async {
      String? password;
      while (true) {
        try {
          await restore(password);
          break;
        } on BackupPasswordNeeded catch (e) {
          if (!mounted) throw const BackupCancelled();
          // Fără indicator de lucru cât timp așteptăm parola.
          setState(() => _busy = false);
          password = await _askBackupPassword(wrong: e.wrong);
          if (password == null) throw const BackupCancelled();
          if (mounted) setState(() => _busy = true);
        }
      }
      restored = true;
    });
    if (!restored || !mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(tr('backup.restore.doneTitle')),
        content: Text(tr('backup.restore.doneBody')),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('backup.restore.restart'))),
        ],
      ),
    );
    await BackupService.restartApp();
  }

  Future<void> _restoreFromFolder() async {
    List<BackupEntry>? backups;
    await _run(() async => backups = await BackupService.listBackups());
    if (!mounted || backups == null) return; // eroarea e deja afișată
    if (backups!.isEmpty) {
      setState(() => _setMessage(tr('backup.restore.noneInFolder')));
      return;
    }
    final chosen = await showDialog<BackupEntry>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(tr('backup.restore.choose')),
        children: [
          for (final b in backups!)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, b),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(b.auto ? Icons.schedule : Icons.save_outlined),
                title: Text(_formatDate(b.modifiedAt)),
                subtitle: Text(tr(b.auto ? 'backup.entry.auto' : 'backup.entry.manual',
                    {'size': (b.size / (1024 * 1024)).toStringAsFixed(1)})),
              ),
            ),
        ],
      ),
    );
    if (chosen == null || !mounted) return;
    await _restore(
      tr('backup.restore.sourceFolder', {'date': _formatDate(chosen.modifiedAt)}),
      (password) => BackupService.restoreBackup(chosen.id, password: password),
    );
  }

  Future<void> _restoreFromFile() => _restore(
        tr('backup.restore.sourceFile'),
        (password) => password == null
            ? BackupService.pickAndRestoreBackup()
            : BackupService.retryPickedRestore(password: password),
      );

  @override
  Widget build(BuildContext context) {
    final s = _status;
    final folderOk = s.hasFolder && s.folderAccessible;
    const cardColor = Colors.white10;

    return Scaffold(
      backgroundColor: const Color(0xFF101418),
      appBar: AppBar(
        backgroundColor: Colors.black26,
        title: Text(tr('backup.title')),
        actions: const [LanguageButton()],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(tr('backup.destination'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'usb', icon: const Icon(Icons.usb), label: Text(tr('backup.destination.usb'))),
              ButtonSegment(
                  value: 'phone', icon: const Icon(Icons.phone_android), label: Text(tr('backup.destination.phone'))),
            ],
            emptySelectionAllowed: true,
            selected: {?s.destination},
            onSelectionChanged: _busy
                ? null
                : (sel) => sel.isEmpty ? _pickFolder(s.destination ?? 'phone') : _pickFolder(sel.first),
          ),
          const SizedBox(height: 8),
          Card(
            color: cardColor,
            child: ListTile(
              leading: Icon(
                folderOk ? Icons.folder : Icons.folder_off_outlined,
                color: folderOk ? Colors.lightGreenAccent : Colors.orangeAccent,
              ),
              title: Text(
                !s.hasFolder
                    ? tr('backup.folder.none')
                    : folderOk
                        ? s.folderName!
                        : tr('backup.folder.inaccessible'),
                style: const TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                !s.hasFolder
                    ? tr('backup.folder.noneHint')
                    : folderOk
                        ? tr('backup.folder.autoDaily')
                        : tr('backup.folder.inaccessibleHint'),
                style: const TextStyle(color: Colors.white60),
              ),
              trailing: s.hasFolder
                  ? IconButton(
                      tooltip: tr('backup.folder.change'),
                      icon: const Icon(Icons.edit_outlined, color: Colors.white70),
                      onPressed: _busy ? null : () => _pickFolder(s.destination ?? 'phone'),
                    )
                  : null,
            ),
          ),
          if (s.hasFolder)
            Card(
              color: cardColor,
              child: ListTile(
                leading: Icon(
                  s.lastAutoError != null ? Icons.error_outline : Icons.schedule,
                  color: s.lastAutoError != null ? Colors.redAccent : Colors.white70,
                ),
                title: Text(
                  s.lastAutoAt != null
                      ? tr('backup.lastAuto', {'date': _formatDate(s.lastAutoAt!)})
                      : tr('backup.lastAuto.none'),
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: s.lastAutoError != null
                    ? Text(tr('backup.lastAuto.failed', {'error': s.lastAutoError!}),
                        style: const TextStyle(color: Colors.redAccent))
                    : s.lastManualAt != null
                        ? Text(tr('backup.lastManual', {'date': _formatDate(s.lastManualAt!)}),
                            style: const TextStyle(color: Colors.white60))
                        : null,
              ),
            ),
          Card(
            color: s.hasPassword ? cardColor : Colors.orange.withValues(alpha: 0.15),
            child: ListTile(
              leading: Icon(
                s.hasPassword ? Icons.lock_outline : Icons.lock_open,
                color: s.hasPassword ? Colors.lightGreenAccent : Colors.orangeAccent,
              ),
              title: Text(s.hasPassword ? tr('backup.password.isSet') : tr('backup.password.notSet'),
                  style: const TextStyle(color: Colors.white)),
              subtitle: Text(s.hasPassword ? tr('backup.password.isSetHint') : tr('backup.password.notSetHint'),
                  style: const TextStyle(color: Colors.white60)),
              trailing: TextButton(
                onPressed: _busy ? null : _setPassword,
                child: Text(s.hasPassword ? tr('backup.password.change') : tr('backup.password.set')),
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.backup),
            label: Text(tr('backup.createNow')),
            onPressed: _busy || !folderOk || !s.hasPassword ? null : _create,
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.restore),
            label: Text(tr('backup.restore.fromFolder')),
            onPressed: _busy || !folderOk ? null : _restoreFromFolder,
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.file_open_outlined),
            label: Text(tr('backup.restore.fromFile')),
            onPressed: _busy ? null : _restoreFromFile,
          ),
          if (_busy) ...[
            const SizedBox(height: 16),
            const Center(child: CircularProgressIndicator()),
          ],
          if (_message != null) ...[
            const SizedBox(height: 16),
            Card(
              color: _messageIsError ? Colors.red.withValues(alpha: 0.15) : Colors.green.withValues(alpha: 0.15),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _message!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _messageIsError ? Colors.redAccent : Colors.lightGreenAccent),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Card(
            color: Colors.white.withValues(alpha: 0.05),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(tr('backup.info'), style: const TextStyle(color: Colors.white70, height: 1.4)),
            ),
          ),
        ],
      ),
    );
  }
}
