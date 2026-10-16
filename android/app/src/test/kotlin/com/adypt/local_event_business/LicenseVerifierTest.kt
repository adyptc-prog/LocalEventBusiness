package com.adypt.local_event_business

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.util.Base64

/**
 * Fixture-ul license_fixtures.json e semnat cu o cheie de test:
 *  - timed / lifetime / otherInstall — cu signLicense() din
 *    voltacademy_web/lib/licenseSigner.js (licențele cumpărate pe site);
 *  - manualTimed / manualLifetime — cu generate_license.ps1 din
 *    volt-academy-license-tools/localeventbusiness (licențele emise de pe PC).
 * Deci testele verifică și compatibilitatea byte-cu-byte a ambelor emitente
 * cu aplicația.
 */
class LicenseVerifierTest {

    private val fixtures = JSONObject(
        javaClass.classLoader!!.getResource("license_fixtures.json")!!.readText()
    )
    private val decoder: (String) -> ByteArray = { Base64.getMimeDecoder().decode(it) }
    private val verifier = LicenseVerifier(
        decoder(fixtures.getString("publicKeyDerB64")), decoder
    )

    private val ownId = "localeventbusiness-1700000000000"
    private val now = LicenseVerifier.parseIso8601Utc("2027-01-01T00:00:00Z")!!

    @Before
    fun romana() = AppLang.setForTest(false)

    private fun license(name: String): String = fixtures.getJSONObject(name).toString()

    private fun tampered(name: String, field: String, value: Any): String {
        val copy = JSONObject(fixtures.getJSONObject(name).toString())
        copy.getJSONObject("payload").put(field, value)
        return copy.toString()
    }

    @Test
    fun `licenta cumparata pe site e activa`() {
        val r = verifier.evaluate(license("timed"), ownId, now)
        assertTrue(r.message, r.isActive)
        assertEquals(ownId, r.businessId)
        assertFalse(r.isLifetime)
        assertEquals("2030-01-01T00:00:00Z", r.validUntil)
        assertEquals(1096, r.daysUntilExpiry)
    }

    @Test
    fun `licenta pe viata e activa`() {
        val r = verifier.evaluate(license("lifetime"), ownId, now)
        assertTrue(r.isActive)
        assertTrue(r.isLifetime)
        assertEquals("Licență pe viață activă.", r.message)
    }

    @Test
    fun `licentele emise manual de pe PC sunt active`() {
        val timed = verifier.evaluate(license("manualTimed"), ownId, now)
        assertTrue(timed.message, timed.isActive)
        assertFalse(timed.isLifetime)
        val lifetime = verifier.evaluate(license("manualLifetime"), ownId, now)
        assertTrue(lifetime.message, lifetime.isActive)
        assertTrue(lifetime.isLifetime)
    }

    @Test
    fun `alt cod de instalare e respins`() {
        val r = verifier.evaluate(license("otherInstall"), ownId, now)
        assertEquals("invalid", r.status)
        assertEquals("Licența aparține altei instalări.", r.message)
    }

    @Test
    fun `licenta expirata e respinsa`() {
        val later = LicenseVerifier.parseIso8601Utc("2030-01-01T00:00:00Z")!!
        val r = verifier.evaluate(license("timed"), ownId, later)
        assertEquals("Licența a expirat.", r.message)
    }

    @Test
    fun `ceas dat inapoi inainte de emitere e respins`() {
        val before = LicenseVerifier.parseIso8601Utc("2020-01-01T00:00:00Z")!!
        val r = verifier.evaluate(license("timed"), ownId, before)
        assertEquals("Ceasul telefonului e setat înaintea datei de emitere a licenței.", r.message)
    }

    @Test
    fun `data de expirare modificata invalideaza semnatura`() {
        val r = verifier.evaluate(tampered("timed", "validUntil", "2099-01-01T00:00:00Z"), ownId, now)
        assertEquals("Semnătura licenței nu este validă.", r.message)
    }

    @Test
    fun `transformarea in licenta pe viata invalideaza semnatura`() {
        val r = verifier.evaluate(tampered("manualTimed", "isLifetime", true), ownId, now)
        assertEquals("Semnătura licenței nu este validă.", r.message)
    }

    @Test
    fun `codul de instalare modificat invalideaza semnatura`() {
        val r = verifier.evaluate(tampered("otherInstall", "businessId", ownId), ownId, now)
        assertEquals("Semnătura licenței nu este validă.", r.message)
    }

    @Test
    fun `o licenta semnata cu alta cheie e respinsa`() {
        val other = LicenseVerifier(decoder(LicenseStore.PUBLIC_KEY_B64), decoder)
        assertEquals("Semnătura licenței nu este validă.", other.evaluate(license("timed"), ownId, now).message)
    }

    @Test
    fun `JSON invalid nu arunca exceptie`() {
        assertEquals("invalid", verifier.evaluate("nu e json", ownId, now).status)
        assertEquals("invalid", verifier.evaluate("{}", ownId, now).status)
    }

    @Test
    fun `JSON compactat si reformatat ramane valid`() {
        val pretty = fixtures.getJSONObject("timed").toString(2)
        assertTrue(verifier.evaluate(pretty, ownId, now).isActive)
    }

    // ── Perioada de probă ───────────────────────────────────────────────────────

    private val day = LicenseVerifier.DAY_MS

    @Test
    fun `proba dureaza 30 de zile`() {
        assertTrue(Trial.isActive(0L, 0L))
        assertTrue(Trial.isActive(0L, 30 * day - 1))
        assertFalse(Trial.isActive(0L, 30 * day))
        assertEquals(30, Trial.daysLeft(0L, 0L))
        assertEquals(30, Trial.daysLeft(0L, day / 2))
        assertEquals(10, Trial.daysLeft(0L, 20 * day))
        assertEquals(1, Trial.daysLeft(0L, 30 * day - 1))
        assertEquals(0, Trial.daysLeft(0L, 40 * day))
    }

    @Test
    fun `restore-ul nu prelungeste proba`() {
        assertEquals(5L, Trial.earlierStart(5L, 9L))
        assertEquals(5L, Trial.earlierStart(9L, 5L))
        assertEquals(9L, Trial.earlierStart(null, 9L))
        assertEquals(9L, Trial.earlierStart(9L, null))
        assertNull(Trial.earlierStart(null, null))
    }
}
