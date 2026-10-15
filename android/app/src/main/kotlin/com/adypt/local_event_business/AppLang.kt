package com.adypt.local_event_business

import android.content.Context

/**
 * Limba aplicației pentru mesajele generate nativ (backup): aceeași alegere
 * ca în `LanguageController` (Dart) — salvată ca `app_language_v1`, română
 * până când utilizatorul alege altceva.
 *
 * Fiecare punct de intrare nativ (activitate, worker) apelează [sync]
 * înainte să genereze mesaje, ca alegerea făcută între timp să fie respectată.
 */
object AppLang {
    private const val FLUTTER_PREFS = "FlutterSharedPreferences"
    const val PREF_KEY = "flutter.app_language_v1"

    @Volatile
    var isEn: Boolean = false
        private set

    fun sync(context: Context) {
        val saved = context.applicationContext
            .getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
            .getString(PREF_KEY, null)
        isEn = saved == "en"
    }

    /** Doar pentru teste. */
    fun setForTest(en: Boolean) {
        isEn = en
    }
}

/** Textul în limba aplicației. Ambele variante stau una lângă alta în cod. */
fun tr(ro: String, en: String): String = if (AppLang.isEn) en else ro
