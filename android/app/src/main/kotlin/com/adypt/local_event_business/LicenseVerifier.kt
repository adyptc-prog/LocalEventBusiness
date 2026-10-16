package com.adypt.local_event_business

import org.json.JSONObject
import java.security.KeyFactory
import java.security.Signature
import java.security.spec.X509EncodedKeySpec
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

/**
 * Rezultatul verificării unui fișier de licență (același format ca în
 * Organizator și Fidelio).
 */
data class LicenseCheck(
    val status: String,
    val message: String,
    val businessId: String? = null,
    val licenseId: String? = null,
    val isLifetime: Boolean = false,
    val validUntil: String? = null,
    val validUntilMs: Long? = null,
    val daysUntilExpiry: Int? = null,
) {
    val isActive: Boolean get() = status == "active"

    fun toMap(): HashMap<String, Any?> {
        val data = HashMap<String, Any?>()
        data["status"] = status
        data["message"] = message
        if (isActive) {
            data["licenseId"] = licenseId
            data["isLifetime"] = isLifetime
            data["validUntil"] = validUntil
            data["daysUntilExpiry"] = daysUntilExpiry
        }
        return data
    }
}

/**
 * Logică pură (fără Android) — testabilă pe JVM. Base64 e injectat pentru că
 * android.util.Base64 nu există în testele JVM.
 *
 * Licența e emisă de site (voltacademy_web/lib/licenseSigner.js) sau manual,
 * de pe PC (volt-academy-license-tools/localeventbusiness/generate_license.ps1).
 */
class LicenseVerifier(
    private val publicKeyDer: ByteArray,
    private val decodeBase64: (String) -> ByteArray,
) {

    fun evaluate(content: String, expectedBusinessId: String, nowMs: Long): LicenseCheck {
        return try {
            val root = JSONObject(content)
            val payload = root.getJSONObject("payload")
            val signature = root.optString("signature")
            val licenseBusinessId = payload.optString("businessId")
            val isLifetime = payload.optBoolean("isLifetime", false)
            val validUntilStr = if (payload.isNull("validUntil")) null
                                else payload.optString("validUntil").takeIf { it.isNotBlank() }
            val issuedAtStr = payload.optString("issuedAt")

            if (licenseBusinessId.isBlank()) {
                return LicenseCheck("invalid", tr("Licența nu are cod de instalare.", "License has no installation code."))
            }
            if (licenseBusinessId != expectedBusinessId) {
                return LicenseCheck("invalid", tr("Licența aparține altei instalări.", "License belongs to another installation."))
            }

            val issuedAtMs = parseIso8601Utc(issuedAtStr)
            if (issuedAtMs != null && nowMs < issuedAtMs) {
                return LicenseCheck("invalid", tr("Ceasul telefonului e setat înaintea datei de emitere a licenței.", "Device clock is set before the license issue date."))
            }

            var validUntilMs: Long? = null
            if (!isLifetime) {
                validUntilMs = parseIso8601Utc(validUntilStr)
                    ?: return LicenseCheck("invalid", tr("Licența nu are o dată de expirare validă.", "License has no valid expiry date."))
                if (nowMs >= validUntilMs) {
                    return LicenseCheck("invalid", tr("Licența a expirat.", "License has expired."))
                }
            }

            if (!verifySignature(payload, signature)) {
                return LicenseCheck("invalid", tr("Semnătura licenței nu este validă.", "License signature is invalid."))
            }

            if (isLifetime || validUntilMs == null) {
                LicenseCheck(
                    status = "active",
                    message = tr("Licență pe viață activă.", "Lifetime license active."),
                    businessId = licenseBusinessId,
                    licenseId = payload.optString("licenseId"),
                    isLifetime = true,
                )
            } else {
                val daysRemaining = ((validUntilMs - nowMs) / DAY_MS).toInt()
                LicenseCheck(
                    status = "active",
                    message = if (daysRemaining <= 1) tr("Licența expiră mâine.", "License expires tomorrow.")
                              else tr("Licență activă. $daysRemaining zile rămase.", "License active. $daysRemaining days remaining."),
                    businessId = licenseBusinessId,
                    licenseId = payload.optString("licenseId"),
                    isLifetime = false,
                    validUntil = validUntilStr,
                    validUntilMs = validUntilMs,
                    daysUntilExpiry = daysRemaining,
                )
            }
        } catch (error: Exception) {
            LicenseCheck("invalid", tr("Fișierul nu este o licență validă.", "The file is not a valid license."))
        }
    }

    // Trebuie să fie identic byte-cu-byte cu canonicalLicensePayload() din
    // voltacademy_web/lib/licenseSigner.js — nu schimba ordinea câmpurilor.
    fun canonicalLicensePayload(payload: JSONObject): String {
        return listOf(
            payload.optString("licenseId"),
            payload.optString("businessId"),
            payload.optString("stickId"),
            payload.optString("issuedAt"),
            payload.optBoolean("isLifetime", false).toString(),
            if (payload.isNull("validUntil")) "" else payload.optString("validUntil"),
        ).joinToString("|")
    }

    private fun verifySignature(payload: JSONObject, signatureBase64: String): Boolean {
        if (signatureBase64.isBlank()) return false
        val publicKey = KeyFactory.getInstance("RSA").generatePublic(X509EncodedKeySpec(publicKeyDer))
        val verifier = Signature.getInstance("SHA256withRSA")
        verifier.initVerify(publicKey)
        verifier.update(canonicalLicensePayload(payload).toByteArray(Charsets.UTF_8))
        return verifier.verify(decodeBase64(signatureBase64))
    }

    companion object {
        const val DAY_MS = 24L * 60L * 60L * 1000L

        fun parseIso8601Utc(dateStr: String?): Long? {
            if (dateStr.isNullOrBlank()) return null
            return try {
                SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply {
                    timeZone = TimeZone.getTimeZone("UTC")
                }.parse(dateStr)?.time
            } catch (_: Exception) {
                null
            }
        }
    }
}

/**
 * Perioada de probă: toate funcțiile, 30 de zile de la prima pornire.
 * Timpul folosit e cel „efectiv” al licenței (LicenseStore.effectiveNow):
 * ceasul dat înapoi nu prelungește proba.
 */
object Trial {
    const val DAYS = 30

    fun isActive(startMs: Long, nowMs: Long): Boolean =
        nowMs < startMs + DAYS * LicenseVerifier.DAY_MS

    fun daysLeft(startMs: Long, nowMs: Long): Int {
        val leftMs = startMs + DAYS * LicenseVerifier.DAY_MS - nowMs
        if (leftMs <= 0L) return 0
        // Zi începută = zi rămasă: în prima zi se afișează 30, nu 29.
        return ((leftMs + LicenseVerifier.DAY_MS - 1) / LicenseVerifier.DAY_MS).toInt()
    }

    /** La restore, proba nu se prelungește — rămâne cel mai vechi start. */
    fun earlierStart(current: Long?, backup: Long?): Long? = when {
        current == null -> backup
        backup == null -> current
        else -> minOf(current, backup)
    }
}
