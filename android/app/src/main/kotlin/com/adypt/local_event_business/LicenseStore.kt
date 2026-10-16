package com.adypt.local_event_business

import android.content.Context
import android.content.SharedPreferences
import android.util.Base64

/**
 * Starea licenței (același model ca în Organizator), păstrată în
 * "LicensePrefs", separat de datele Flutter:
 *  - business_id    — codul de instalare pe care se emite licența;
 *  - license_json   — conținutul semnat al licenței, copiat intern la import,
 *                     ca să nu depindă de fișierul original și să intre în backup;
 *  - trial_start_ms — prima pornire: începutul perioadei de probă.
 */
object LicenseStore {

    const val PREFS_NAME = "LicensePrefs"
    const val KEY_BUSINESS_ID = "business_id"
    const val KEY_LICENSE_JSON = "license_json"
    const val KEY_TRIAL_START = "trial_start_ms"
    private const val KEY_LAST_CHECK = "last_license_check"

    // Cheia publică RSA-2048 (DER/X.509, base64) — perechea cheii private din
    // volt-academy-license-tools/localeventbusiness/private.pem.
    const val PUBLIC_KEY_B64 =
        "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEApV30/DhHqAlsW68lkd6W" +
        "HIlx/6hk4EU9rY8UBE32w9jgK33vES4zXb75iQHP5x7h19SakokhfnlpEnO/Vfbv" +
        "Wyr0BYSodrBxnT92LS+IfN9/yFktm2QSOFZTeQ2XM8MRGLsfa9FFDjnUyQ9DQanc" +
        "kDT0YxfRleT/MYA+jDF+DnLVTkoHFpfwI99y5SOTQp+QRRZYn2xWMiWqO9nw3QTy" +
        "jCBfzpPHHpnnyt2/fdQdpuiEigl6RmXctVczXjY5a1ogo73WpEa/ELWyLX/CDUtS" +
        "1aDItnjHWVSIHq1YROon49XglrlsYlAwJ+An9250fnIreBGZmB8okupbhpV7KVuh" +
        "dwIDAQAB"

    private val verifier by lazy {
        LicenseVerifier(Base64.decode(PUBLIC_KEY_B64, Base64.DEFAULT)) {
            Base64.decode(it, Base64.DEFAULT)
        }
    }

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun getOrCreateBusinessId(context: Context): String {
        val prefs = prefs(context)
        prefs.getString(KEY_BUSINESS_ID, null)?.let { return it }
        val fresh = "localeventbusiness-${System.currentTimeMillis()}"
        prefs.edit().putString(KEY_BUSINESS_ID, fresh).commit()
        return fresh
    }

    // Anti-manipularea ceasului: un „acum” care nu scade niciodată — aceeași
    // logică ca getEffectiveNow() din Fidelio / Organizator.
    fun effectiveNow(context: Context): Long {
        val prefs = prefs(context)
        val lastMs = prefs.getLong(KEY_LAST_CHECK, 0L)
        val deviceNow = System.currentTimeMillis()
        val effectiveNow = if (deviceNow < lastMs - 60_000L) lastMs else maxOf(deviceNow, lastMs)
        prefs.edit().putLong(KEY_LAST_CHECK, effectiveNow).apply()
        return effectiveNow
    }

    private fun trialStartMs(context: Context, now: Long): Long {
        val prefs = prefs(context)
        if (prefs.contains(KEY_TRIAL_START)) return prefs.getLong(KEY_TRIAL_START, now)
        prefs.edit().putLong(KEY_TRIAL_START, now).commit()
        return now
    }

    private fun storedLicense(context: Context): String? =
        prefs(context).getString(KEY_LICENSE_JSON, null)

    fun check(context: Context): LicenseCheck {
        val content = storedLicense(context)
            ?: return LicenseCheck("missing", tr("Nicio licență importată.", "No license imported."))
        return verifier.evaluate(content, getOrCreateBusinessId(context), effectiveNow(context))
    }

    /** Licența, plus starea perioadei de probă — tot ce afișează Flutter. */
    fun status(context: Context): HashMap<String, Any?> {
        val map = check(context).toMap()
        val now = effectiveNow(context)
        val start = trialStartMs(context, now)
        map["trialActive"] = Trial.isActive(start, now)
        map["trialDaysLeft"] = Trial.daysLeft(start, now)
        return map
    }

    /**
     * Import din fișierul ales de utilizator. O licență invalidă NU înlocuiește
     * licența stocată — altfel alegerea greșită a unui fișier ar dezactiva o
     * licență bună.
     */
    fun importLicense(context: Context, fileContent: String): LicenseCheck {
        // Editoarele de text din Windows pot adăuga un BOM la începutul fișierului.
        val content = fileContent.removePrefix("\uFEFF").trim()
        val result = verifier.evaluate(content, getOrCreateBusinessId(context), effectiveNow(context))
        if (result.isActive) {
            prefs(context).edit().putString(KEY_LICENSE_JSON, content).commit()
        }
        return result
    }

    // ── Backup / restore ─────────────────────────────────────────────────────────
    fun identity(context: Context): BackupFormat.Identity {
        val prefs = prefs(context)
        return BackupFormat.Identity(
            businessId = getOrCreateBusinessId(context),
            licenseJson = storedLicense(context),
            trialStartMs = if (prefs.contains(KEY_TRIAL_START)) prefs.getLong(KEY_TRIAL_START, 0L) else null,
        )
    }

    private fun isActiveFor(context: Context, licenseJson: String?, businessId: String): Boolean {
        if (licenseJson == null) return false
        return verifier.evaluate(licenseJson, businessId, effectiveNow(context)).isActive
    }

    /**
     * Restaurează codul de instalare (și licența) din backup — licența
     * cumpărată continuă să funcționeze după reinstalare sau pe telefon nou.
     * Nu înlocuiește o licență activă cu o identitate fără licență validă.
     * Proba nu se prelungește: rămâne cel mai vechi start.
     */
    fun restoreIdentity(context: Context, identity: BackupFormat.Identity) {
        val prefs = prefs(context)
        val editor = prefs.edit()
        val currentTrial = if (prefs.contains(KEY_TRIAL_START)) prefs.getLong(KEY_TRIAL_START, 0L) else null
        Trial.earlierStart(currentTrial, identity.trialStartMs)?.let { editor.putLong(KEY_TRIAL_START, it) }

        val businessId = identity.businessId
        if (businessId != null && BackupFormat.shouldRestoreIdentity(
                currentLicenseActive = check(context).isActive,
                backupLicenseActive = isActiveFor(context, identity.licenseJson, businessId),
            )
        ) {
            editor.putString(KEY_BUSINESS_ID, businessId)
            if (identity.licenseJson != null) {
                editor.putString(KEY_LICENSE_JSON, identity.licenseJson)
            } else {
                editor.remove(KEY_LICENSE_JSON)
            }
        }
        editor.commit()
    }
}
