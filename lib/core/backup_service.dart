import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Starea backup-ului, așa cum o raportează partea nativă
/// (`BackupManager.status`, Kotlin).
class BackupStatus {
  final String? folderName;
  final bool folderAccessible;
  final bool hasFolder;
  final String? destination; // 'usb' | 'phone'
  final DateTime? lastAutoAt;
  final String? lastAutoError;
  final DateTime? lastManualAt;

  /// Backup-urile sunt criptate cu parola de backup a telefonului — fără ea
  /// nu se poate crea niciun backup.
  final bool hasPassword;

  const BackupStatus({
    this.folderName,
    this.folderAccessible = false,
    this.hasFolder = false,
    this.destination,
    this.lastAutoAt,
    this.lastAutoError,
    this.lastManualAt,
    this.hasPassword = false,
  });

  static DateTime? _date(Object? ms) => ms is int ? DateTime.fromMillisecondsSinceEpoch(ms) : null;

  factory BackupStatus.fromMap(Map<Object?, Object?>? m) => BackupStatus(
        folderName: m?['folderName'] as String?,
        folderAccessible: (m?['folderAccessible'] as bool?) ?? false,
        hasFolder: m?['folderUri'] != null,
        destination: m?['destination'] as String?,
        lastAutoAt: _date(m?['lastAutoAt']),
        lastAutoError: m?['lastAutoError'] as String?,
        lastManualAt: _date(m?['lastManualAt']),
        hasPassword: (m?['hasPassword'] as bool?) ?? false,
      );
}

class BackupEntry {
  final String id;
  final String name;
  final DateTime modifiedAt;
  final int size;
  final bool auto;

  const BackupEntry({
    required this.id,
    required this.name,
    required this.modifiedAt,
    required this.size,
    required this.auto,
  });

  factory BackupEntry.fromMap(Map<Object?, Object?> m) => BackupEntry(
        id: m['id'] as String? ?? '',
        name: m['name'] as String? ?? '',
        modifiedAt: DateTime.fromMillisecondsSinceEpoch((m['modifiedAt'] as int?) ?? 0),
        size: (m['size'] as int?) ?? 0,
        auto: (m['auto'] as bool?) ?? false,
      );
}

/// Utilizatorul a închis selectorul fără să aleagă nimic.
class BackupCancelled implements Exception {
  const BackupCancelled();
}

/// Backup-ul e criptat: parola lipsește ([wrong] = false) sau e greșită.
class BackupPasswordNeeded implements Exception {
  final bool wrong;
  const BackupPasswordNeeded({required this.wrong});
}

/// Backup-ul (manual + automat zilnic) și restaurarea — implementate nativ
/// (`BackupManager.kt`), ca backup-ul automat să ruleze și cu aplicația
/// închisă. Același sistem ca în aplicația Organizator.
class BackupService {
  BackupService._();

  static const _ch = MethodChannel('local_event_business/backup');

  /// Doar aplicația Android are backup (clientul web nu ține date).
  static bool get isSupported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static const minPasswordLength = 8;

  static Future<T?> _call<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _ch.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      if (e.code.endsWith('_CANCELLED')) throw const BackupCancelled();
      if (e.code == 'BACKUP_PASSWORD_REQUIRED') throw const BackupPasswordNeeded(wrong: false);
      if (e.code == 'BACKUP_PASSWORD_WRONG') throw const BackupPasswordNeeded(wrong: true);
      throw Exception(e.message ?? e.code);
    }
  }

  static Future<BackupStatus> getStatus() async {
    if (!isSupported) return const BackupStatus();
    return BackupStatus.fromMap(await _call<Map<Object?, Object?>>('getStatus'));
  }

  /// [destination]: 'usb' sau 'phone' — un singur folder activ.
  static Future<BackupStatus> pickFolder(String destination) async =>
      BackupStatus.fromMap(await _call<Map<Object?, Object?>>('pickFolder', {'destination': destination}));

  static Future<BackupEntry> createBackup() async =>
      BackupEntry.fromMap((await _call<Map<Object?, Object?>>('createBackup'))!);

  static Future<List<BackupEntry>> listBackups() async {
    final r = await _call<List<Object?>>('listBackups') ?? const [];
    return r.whereType<Map<Object?, Object?>>().map(BackupEntry.fromMap).toList();
  }

  static Future<BackupStatus> setPassword(String password) async =>
      BackupStatus.fromMap(await _call<Map<Object?, Object?>>('setPassword', {'password': password}));

  static Future<void> restoreBackup(String id, {String? password}) =>
      _call<void>('restoreBackup', {'id': id, 'password': ?password});

  static Future<void> pickAndRestoreBackup() => _call<void>('pickAndRestoreBackup');

  /// Același fișier ales la [pickAndRestoreBackup], de data asta cu parola.
  static Future<void> retryPickedRestore({required String password}) =>
      _call<void>('retryPickedRestore', {'password': password});

  /// Repornește aplicația — după restaurare, datele din memorie sunt vechi.
  static Future<void> restartApp() => _call<void>('restartApp');
}
