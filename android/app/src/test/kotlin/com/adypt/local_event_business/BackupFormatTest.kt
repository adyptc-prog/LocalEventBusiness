package com.adypt.local_event_business

import org.json.JSONObject
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class BackupFormatTest {

    private val prefs: Map<String, Any?> = mapOf(
        "flutter.menu_store_v1" to """{"categories":[],"items":[],"currency":"lei"}""",
        "flutter.table_count_v1" to 12L,
        "flutter.leaderboard_history_v1" to "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIGxpc3Qu![\"a\",\"b\"]",
        "flutter.some_flag" to true,
        "flutter.app_language_v1" to "en",
        "flutter.install_activated_v1" to true,
        "flutter.menu_cart_v1" to "{}",
        "not_flutter_key" to "x",
    )
    private val photos = mapOf(
        "1700000000000-12.jpg" to byteArrayOf(-1, -40, -1, 0, 1, 2),
        "1700000000001-7.jpg" to byteArrayOf(9, 8, 7),
    )

    @Test
    fun `encode si decode pastreaza datele, tipurile si pozele`() {
        val backup = BackupFormat.decode(BackupFormat.encode(prefs, photos, 1234L))
        assertEquals(1234L, backup.createdAt)
        assertEquals("""{"categories":[],"items":[],"currency":"lei"}""", backup.prefs["flutter.menu_store_v1"])
        assertEquals(12L, backup.prefs["flutter.table_count_v1"])
        assertEquals(true, backup.prefs["flutter.some_flag"])
        assertEquals(2, backup.photos.size)
        assertArrayEquals(byteArrayOf(-1, -40, -1, 0, 1, 2), backup.photos["1700000000000-12.jpg"])
    }

    @Test
    fun `cheile care tin de telefon nu intra in backup`() {
        val backup = BackupFormat.decode(BackupFormat.encode(prefs, photos, 0L))
        assertFalse(backup.prefs.containsKey("flutter.app_language_v1"))
        assertFalse(backup.prefs.containsKey("flutter.install_activated_v1"))
        assertFalse(backup.prefs.containsKey("flutter.menu_cart_v1"))
        assertFalse(backup.prefs.containsKey("not_flutter_key"))
    }

    @Test
    fun `restore pastreaza limba si activarea telefonului si sterge restul`() {
        val current = mapOf(
            "flutter.app_language_v1" to "ro",
            "flutter.install_activated_v1" to true,
            "flutter.table_count_v1" to 3L,
            "flutter.only_on_this_phone" to "x",
        )
        val merged = BackupFormat.mergeForRestore(current, mapOf("flutter.table_count_v1" to 12L))
        assertEquals("ro", merged["flutter.app_language_v1"])
        assertEquals(true, merged["flutter.install_activated_v1"])
        assertEquals(12L, merged["flutter.table_count_v1"])
        assertNull(merged["flutter.only_on_this_phone"])
    }

    @Test
    fun `numele de poza care ar iesi din folder sunt respinse`() {
        assertTrue(BackupFormat.isValidPhotoName("1700000000000-12.jpg"))
        assertFalse(BackupFormat.isValidPhotoName("../shared_prefs/x.xml"))
        assertFalse(BackupFormat.isValidPhotoName("a/b.jpg"))
        assertFalse(BackupFormat.isValidPhotoName(".hidden"))
        assertFalse(BackupFormat.isValidPhotoName("a..b.jpg"))
        assertFalse(BackupFormat.isValidPhotoName(""))
    }

    @Test
    fun `o poza cu nume periculos dintr-un fisier modificat e ignorata`() {
        val root = JSONObject(BackupFormat.encode(prefs, photos, 0L))
        val data = JSONObject(root.getString("data"))
        data.getJSONObject("photos").put("../../evil", "AAAA")
        val dataText = data.toString()
        root.put("data", dataText).put("checksum", BackupFormat.sha256(dataText))
        val backup = BackupFormat.decode(root.toString())
        assertFalse(backup.photos.containsKey("../../evil"))
        assertEquals(2, backup.photos.size)
    }

    @Test
    fun `checksum gresit e respins`() {
        val root = JSONObject(BackupFormat.encode(prefs, photos, 0L))
        root.put("checksum", "0".repeat(64))
        assertThrows(BackupFormat.InvalidBackupException::class.java) {
            BackupFormat.decode(root.toString())
        }
    }

    @Test
    fun `backup-ul altei aplicatii sau dintr-o versiune mai noua e respins`() {
        assertThrows(BackupFormat.InvalidBackupException::class.java) {
            BackupFormat.decode("""{"app":"organizator","formatVersion":1}""")
        }
        assertThrows(BackupFormat.InvalidBackupException::class.java) {
            BackupFormat.decode("""{"app":"localeventbusiness","formatVersion":99}""")
        }
        assertThrows(BackupFormat.InvalidBackupException::class.java) {
            BackupFormat.decode("nu e json")
        }
    }

    @Test
    fun `se pastreaza ultimele backup-uri automate, cele manuale niciodata nu se sterg`() {
        val names = (1..16).map { "localevent_auto_202610%02d_000000.lebbackup".format(it) } +
            "localevent_20261001_120000.lebbackup"
        val toDelete = BackupFormat.autoBackupsToDelete(names, keep = 14)
        assertEquals(
            listOf("localevent_auto_20261002_000000.lebbackup", "localevent_auto_20261001_000000.lebbackup"),
            toDelete,
        )
    }
}
