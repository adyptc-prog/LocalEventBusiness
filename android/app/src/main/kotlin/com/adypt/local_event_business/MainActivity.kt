package com.adypt.local_event_business

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val INSTALL_SOURCE_CHANNEL = "local_event_business/install_source"
        private const val BACKUP_CHANNEL = "local_event_business/backup"
        private const val PICK_BACKUP_FOLDER_REQUEST_CODE = 8022
        private const val PICK_RESTORE_BACKUP_REQUEST_CODE = 8023
    }

    // Backup: selectoarele de folder / fișier așteaptă rezultatul activității
    private var pendingBackupFolderResult: MethodChannel.Result? = null
    private var pendingBackupDestination: String = "phone"
    private var pendingRestoreResult: MethodChannel.Result? = null
    @Volatile
    private var lastPickedRestoreUri: Uri? = null

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            PICK_BACKUP_FOLDER_REQUEST_CODE -> handleBackupFolderResult(resultCode, data)
            PICK_RESTORE_BACKUP_REQUEST_CODE -> handleRestoreResult(resultCode, data)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        AppLang.sync(applicationContext)
        LocalEventBackupWorker.schedule(applicationContext)

        // Cine a instalat aplicația — citit de `InstallActivation` (Dart) la
        // prima pornire, ca să decidă dacă telefonul e activat.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, INSTALL_SOURCE_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "getInstallSource") {
                    try {
                        result.success(installSource())
                    } catch (e: Exception) {
                        result.error("install_source", e.message, null)
                    }
                } else {
                    result.notImplemented()
                }
            }

        // Backup & restaurare (vezi BackupManager / lib/core/backup_service.dart)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BACKUP_CHANNEL)
            .setMethodCallHandler { call, result ->
                AppLang.sync(applicationContext)
                when (call.method) {
                    "getStatus" -> runInBackground(result, "BACKUP_STATUS_FAILED") {
                        BackupManager.status(this)
                    }
                    "pickFolder" -> pickBackupFolder(call.argument<String>("destination") ?: "phone", result)
                    "createBackup" -> runInBackground(result, "BACKUP_CREATE_FAILED") {
                        BackupManager.createBackup(this, auto = false)
                    }
                    "listBackups" -> runInBackground(result, "BACKUP_LIST_FAILED") {
                        BackupManager.listBackups(this)
                    }
                    "restoreBackup" -> {
                        val id = call.argument<String>("id")
                            ?: run { result.error("ARG", "missing id", null); return@setMethodCallHandler }
                        val password = call.argument<String>("password")
                        runInBackground(result, "BACKUP_RESTORE_FAILED") {
                            BackupManager.restoreFromDocumentId(this, id, password); null
                        }
                    }
                    "pickAndRestoreBackup" -> pickAndRestoreBackup(result)
                    // Fișierul ales anterior era criptat: reîncercăm cu parola,
                    // fără să-l mai cerem din nou utilizatorului.
                    "retryPickedRestore" -> {
                        val uri = lastPickedRestoreUri
                            ?: run { result.error("ARG", "no picked backup", null); return@setMethodCallHandler }
                        val password = call.argument<String>("password")
                        runInBackground(result, "BACKUP_RESTORE_FAILED") {
                            BackupManager.restoreFromUri(this, uri, password)
                            lastPickedRestoreUri = null
                            null
                        }
                    }
                    "setPassword" -> {
                        val password = call.argument<String>("password")
                            ?: run { result.error("ARG", "missing password", null); return@setMethodCallHandler }
                        runInBackground(result, "BACKUP_PASSWORD_INVALID") {
                            BackupPassword.set(this, password)
                            BackupManager.status(this)
                        }
                    }
                    "restartApp" -> {
                        result.success(null)
                        restartApp()
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun installSource(): Map<String, Any?> {
        val sdk = Build.VERSION.SDK_INT
        return if (sdk >= Build.VERSION_CODES.R) {
            val info = packageManager.getInstallSourceInfo(packageName)
            mapOf(
                "installer" to info.installingPackageName,
                "initiator" to info.initiatingPackageName,
                "sdk" to sdk,
            )
        } else {
            @Suppress("DEPRECATION")
            mapOf(
                "installer" to packageManager.getInstallerPackageName(packageName),
                "initiator" to null,
                "sdk" to sdk,
            )
        }
    }

    // ── Backup ───────────────────────────────────────────────────────────────────
    // Operațiile pe fișiere (stick USB) nu blochează interfața.
    private fun runInBackground(result: MethodChannel.Result, errorCode: String, work: () -> Any?) {
        Thread {
            try {
                val value = work()
                runOnUiThread { result.success(value) }
            } catch (e: BackupManager.PasswordException) {
                runOnUiThread { result.error(e.code, e.message, null) }
            } catch (e: Exception) {
                runOnUiThread { result.error(errorCode, e.message ?: e.toString(), null) }
            }
        }.start()
    }

    private fun pickBackupFolder(destination: String, result: MethodChannel.Result) {
        if (pendingBackupFolderResult != null) {
            result.error("BACKUP_PICK_BUSY", tr("Un selector de folder este deja deschis.", "A backup folder picker is already open."), null)
            return
        }
        pendingBackupFolderResult = result
        pendingBackupDestination = destination
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
            // Memoria telefonului: pornim din Documents, unde backup-ul
            // supraviețuiește dezinstalării aplicației.
            if (destination == "phone" && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                putExtra(
                    DocumentsContract.EXTRA_INITIAL_URI,
                    DocumentsContract.buildDocumentUri(
                        "com.android.externalstorage.documents", "primary:Documents"
                    )
                )
            }
        }
        startActivityForResult(intent, PICK_BACKUP_FOLDER_REQUEST_CODE)
    }

    private fun handleBackupFolderResult(resultCode: Int, data: Intent?) {
        val result = pendingBackupFolderResult ?: return
        pendingBackupFolderResult = null
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) {
            result.error("BACKUP_PICK_CANCELLED", tr("Nu a fost selectat niciun folder de backup.", "No backup folder was selected."), null)
            return
        }
        runInBackground(result, "BACKUP_PICK_FAILED") {
            BackupManager.setFolder(this, uri, pendingBackupDestination)
            BackupManager.status(this)
        }
    }

    private fun pickAndRestoreBackup(result: MethodChannel.Result) {
        if (pendingRestoreResult != null) {
            result.error("RESTORE_PICK_BUSY", tr("Un selector de backup este deja deschis.", "A backup picker is already open."), null)
            return
        }
        pendingRestoreResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivityForResult(intent, PICK_RESTORE_BACKUP_REQUEST_CODE)
    }

    private fun handleRestoreResult(resultCode: Int, data: Intent?) {
        val result = pendingRestoreResult ?: return
        pendingRestoreResult = null
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) {
            result.error("RESTORE_PICK_CANCELLED", tr("Nu a fost selectat niciun fișier de backup.", "No backup file was selected."), null)
            return
        }
        lastPickedRestoreUri = uri
        runInBackground(result, "BACKUP_RESTORE_FAILED") {
            BackupManager.restoreFromUri(this, uri)
            lastPickedRestoreUri = null
            null
        }
    }

    /**
     * Pornește aplicația din nou, de la zero — după un restore, datele din
     * memoria aplicației Flutter (meniu, comenzi, clasament) sunt vechi.
     */
    private fun restartApp() {
        val launch = packageManager.getLaunchIntentForPackage(packageName) ?: return
        val restart = Intent.makeRestartActivityTask(launch.component)
        window.decorView.postDelayed({
            startActivity(restart)
            Runtime.getRuntime().exit(0)
        }, 300)
    }
}
