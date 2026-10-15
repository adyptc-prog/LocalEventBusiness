package com.adypt.local_event_business

import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest
import kotlin.io.encoding.Base64

/**
 * Formatul fișierului de backup LocalEventBusiness (.lebbackup) — logică
 * pură, fără Android, testabilă pe JVM. Același model ca în Organizator
 * (management_app), plus pozele produselor din meniu.
 *
 * Datele aplicației stau în SharedPreferences, iar pozele produselor sunt
 * fișiere separate (`app_flutter/menu_photos`), deci backup-ul e un export
 * JSON al cheilor — cu tipul fiecărei valori păstrat — și al pozelor:
 *
 *   {
 *     "app": "localeventbusiness",
 *     "formatVersion": 1,
 *     "createdAt": <epoch ms>,
 *     "checksum": sha256(data),
 *     "data": "<JSON ca text: {prefs: {...}, photos: {nume: base64}}>"
 *   }
 *
 * "data" e păstrat ca text, nu ca obiect, ca checksum-ul să fie calculat pe
 * exact aceiași octeți la scriere și la citire (org.json nu garantează
 * ordinea cheilor la re-serializare). Pe disc fișierul e criptat
 * (BackupCrypto), iar acesta e textul din interior.
 */
object BackupFormat {

    const val APP_ID = "localeventbusiness"
    const val FORMAT_VERSION = 1
    const val EXTENSION = ".lebbackup"
    const val AUTO_PREFIX = "localevent_auto_"
    const val MANUAL_PREFIX = "localevent_"

    private const val FLUTTER_PREFIX = "flutter."

    // Chei care țin de acest telefon, nu de datele localului — nu se salvează
    // și nu se suprascriu la restore.
    private val EXCLUDED_KEYS = setOf(
        // Limba e a telefonului, nu a datelor: un backup restaurat nu o schimbă.
        "flutter.app_language_v1",
        // Activarea e a telefonului (cine a instalat aplicația pe el).
        "flutter.install_activated_v1",
        // Coșul netrimis al unui client — nu are ce căuta într-un backup.
        "flutter.menu_cart_v1",
    )

    // Numele pozelor sunt generate de aplicație (`<id>.jpg`); orice altceva
    // dintr-un fișier de backup e respins, ca un fișier modificat să nu poată
    // scrie în afara folderului de poze.
    private val PHOTO_NAME = Regex("""^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$""")

    fun isBackedUpKey(key: String): Boolean =
        key.startsWith(FLUTTER_PREFIX) && key !in EXCLUDED_KEYS

    fun isValidPhotoName(name: String): Boolean =
        PHOTO_NAME.matches(name) && !name.contains("..")

    data class Backup(
        val createdAt: Long,
        val prefs: Map<String, Any?>,
        val photos: Map<String, ByteArray>,
    )

    class InvalidBackupException(message: String) : Exception(message)

    private fun notOurs() = InvalidBackupException(
        tr("Fișierul nu este un backup LocalEventBusiness.", "The file is not a LocalEventBusiness backup."),
    )

    fun encode(prefs: Map<String, *>, photos: Map<String, ByteArray>, createdAt: Long): String {
        val prefsJson = JSONObject()
        for ((key, value) in prefs.toSortedMap()) {
            if (!isBackedUpKey(key)) continue
            encodeValue(value)?.let { prefsJson.put(key, it) }
        }
        val photosJson = JSONObject()
        for ((name, bytes) in photos.toSortedMap()) {
            if (!isValidPhotoName(name)) continue
            photosJson.put(name, Base64.encode(bytes))
        }

        val data = JSONObject()
            .put("prefs", prefsJson)
            .put("photos", photosJson)
            .toString()

        return JSONObject()
            .put("app", APP_ID)
            .put("formatVersion", FORMAT_VERSION)
            .put("createdAt", createdAt)
            .put("checksum", sha256(data))
            .put("data", data)
            .toString()
    }

    fun decode(content: String): Backup {
        val root = try {
            JSONObject(content)
        } catch (_: Exception) {
            throw notOurs()
        }
        if (root.optString("app") != APP_ID) throw notOurs()
        val version = root.optInt("formatVersion", -1)
        if (version < 1 || version > FORMAT_VERSION) {
            throw InvalidBackupException(
                tr(
                    "Backup creat de o versiune mai nouă a aplicației. Actualizează aplicația.",
                    "The backup was created by a newer version of the app. Update the app.",
                )
            )
        }
        val data = root.optString("data")
        if (data.isEmpty() || sha256(data) != root.optString("checksum")) {
            throw InvalidBackupException(tr("Backup-ul este corupt (checksum invalid).", "The backup is corrupted (invalid checksum)."))
        }

        val dataJson = JSONObject(data)
        val prefsJson = dataJson.getJSONObject("prefs")
        val prefs = LinkedHashMap<String, Any?>()
        for (key in prefsJson.keys()) {
            if (!isBackedUpKey(key)) continue
            prefs[key] = decodeValue(prefsJson.getJSONObject(key))
        }
        val photosJson = dataJson.optJSONObject("photos") ?: JSONObject()
        val photos = LinkedHashMap<String, ByteArray>()
        for (name in photosJson.keys()) {
            if (!isValidPhotoName(name)) continue
            photos[name] = try {
                Base64.decode(photosJson.getString(name))
            } catch (_: Exception) {
                throw InvalidBackupException(tr("Backup-ul este corupt (poză invalidă).", "The backup is corrupted (invalid photo)."))
            }
        }
        return Backup(
            createdAt = root.optLong("createdAt", 0L),
            prefs = prefs,
            photos = photos,
        )
    }

    /**
     * Cheile de scris la restore: cele din backup, plus cheile actuale care
     * țin de acest telefon ([EXCLUDED_KEYS]). Restul cheilor actuale care nu
     * sunt în backup se șterg (restore = stare identică cu cea din backup).
     */
    fun mergeForRestore(current: Map<String, *>, backup: Map<String, Any?>): Map<String, Any?> {
        val result = LinkedHashMap<String, Any?>()
        for ((key, value) in backup) {
            if (isBackedUpKey(key)) result[key] = value
        }
        for ((key, value) in current) {
            if (key in EXCLUDED_KEYS) result[key] = value
        }
        return result
    }

    /** Backup-urile automate de șters, păstrând cele mai noi [keep]. */
    fun autoBackupsToDelete(names: List<String>, keep: Int): List<String> =
        names.filter { it.startsWith(AUTO_PREFIX) && it.endsWith(EXTENSION) }
            .sortedDescending() // numele conțin yyyyMMdd_HHmmss
            .drop(keep)

    private fun encodeValue(value: Any?): JSONObject? = when (value) {
        is String -> JSONObject().put("t", "s").put("v", value)
        is Long -> JSONObject().put("t", "l").put("v", value.toString())
        is Int -> JSONObject().put("t", "i").put("v", value.toString())
        is Boolean -> JSONObject().put("t", "b").put("v", value.toString())
        is Float -> JSONObject().put("t", "f").put("v", value.toString())
        is Set<*> -> JSONObject().put("t", "set")
            .put("v", JSONArray(value.filterIsInstance<String>().sorted()))
        else -> null
    }

    private fun decodeValue(json: JSONObject): Any? {
        val v = json.opt("v")
        return when (json.optString("t")) {
            "s" -> v as? String
            "l" -> (v as? String)?.toLongOrNull()
            "i" -> (v as? String)?.toIntOrNull()
            "b" -> (v as? String)?.toBooleanStrictOrNull()
            "f" -> (v as? String)?.toFloatOrNull()
            "set" -> (v as? JSONArray)?.let { arr ->
                (0 until arr.length()).map { arr.getString(it) }.toSet()
            }
            else -> null
        }
    }

    fun sha256(text: String): String =
        MessageDigest.getInstance("SHA-256")
            .digest(text.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }
}
