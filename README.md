# LocalEventBusiness

Jocuri multiplayer, chat și comenzi la bar pe rețeaua Wi-Fi a unui local, fără internet.

## Arhitectură

- **Telefonul-server** (Android, „Server local”) rulează `EventServerService` într-un
  foreground service (`EventServerRunner`). Are un singur `HttpServer` pe portul **45034**
  care servește:
  - `/ws`: protocolul de joc (WebSocket, mesaje JSON, vezi `ClientService`);
  - `/menu/photos/<fișier>`: pozele produselor din meniu;
  - restul: clientul web (`assets/web_client.zip`), pentru iPhone și orice browser.
- Un beacon UDP pe portul **45033** anunță serverul, iar clienții Android îl găsesc automat.
- Fiecare cameră e un `RoomSession` cu propriul motor de reguli (`GameEngine`).
  Camera `MENU` (comenzi la bar) e creată de server la pornire.

## Identitate și securitate

- Fiecare telefon sau browser are un **id secret de profil** (`PlayerProfile.id`). Acesta
  pleacă doar spre server. Tot ce văd ceilalți folosește **id-ul public**
  `publicPlayerId(secret)` (SHA-256), așa că nimeni nu poate prelua locul altcuiva
  știind doar id-ul afișat.
- Reconectarea cu același secret preia locul existent și închide canalul vechi
  (mesajul `replaced`). Serverul trimite ping WebSocket la 10 s, ca să detecteze
  conexiunile moarte.
- Modul spectator (monitorizarea camerelor, chat ca „Organizator”) cere
  **cheia organizatorului** (`OrganizerKeyStore`), generată pe telefonul-server.
- Limite anti-abuz în `EventServerService`: conexiuni, camere, mesaje pe secundă,
  lungimi de text, miza mesei. Limitele comenzilor sunt în `MenuEngine`.
- Un jucător deconectat de peste 45 s nu mai blochează masa: serverul joacă în locul
  lui acțiunile cele mai pasive (`GameEngine.autoActionCandidates`).
- Comenzile la bar sunt persistate (`OrdersStore`) și supraviețuiesc unei reporniri
  a serverului.

## Limbi (română / engleză)

- Butonul **RO/EN** din bara de sus a fiecărui ecran schimbă limba imediat, fără să
  părăsească ecranul sau partida. Alegerea e salvată pe fiecare dispozitiv.
- Toate textele sunt în `lib/l10n/strings/`. Fiecare cheie are perechea
  `(română, engleză)`. În cod se folosește `tr('cheie', {'arg': valoare})`, iar
  șabloanele conțin `{arg}`.
- Textele generate de server (erori, rezumate de mână, evenimente de joc) circulă
  ca chei (`GameError`, `LocalizedText`), nu ca text. Fiecare client le traduce în
  limba lui, fiindcă serverul e comun pentru toți.
- **Adaugi o limbă nouă?** Extinde enum-ul `AppLanguage` și tuplurile din dicționar.
  **Adaugi un text?** Pune o cheie nouă în tabelul potrivit.
  `test/l10n_test.dart` pică dacă o cheie folosită în cod lipsește sau dacă
  placeholder-ele diferă între limbi.

## Licență (doar aplicația Android)

Același model ca în Organizator. Clientul web (meniul din QR) nu are licență.

- La prima pornire începe o **perioadă de probă de 30 de zile**, cu toate funcțiile.
  După ea, `LicenseGate` arată doar ecranul de licență (plus restaurarea unui backup),
  iar serverul localului se oprește.
- Licența e un fișier JSON semnat RSA-SHA256 (`{payload, signature}`), emis pe
  **codul de instalare** al telefonului (`localeventbusiness-<ms>`, ecranul Licență):
  30/60/180 de zile sau pe viață.
- Verificarea e nativă (`LicenseVerifier.kt`, `LicenseStore.kt`): semnătura, codul de
  instalare, expirarea și ceasul dat înapoi (un „acum” care nu scade niciodată, folosit
  și pentru probă). Cheia publică e în `LicenseStore.PUBLIC_KEY_B64`.
- Licența, codul de instalare și startul probei intră în backup: după reinstalare sau
  pe un telefon nou, restaurarea backup-ului aduce licența. Proba nu se prelungește prin
  restore.
- Emitere: automat de pe site (`voltacademy_web`, produsul `localeventbusiness`) sau
  manual de pe PC, cu `volt-academy-license-tools/localeventbusiness/generate_license.ps1`
  (`-BusinessId <cod> -Days 30`, `-ValidUntil 2027-12-31` sau `-Lifetime`).
- `android/app/src/test/resources/license_fixtures.json` e semnat cu o cheie de test, atât
  de semnatarul site-ului, cât și de scriptul manual, deci `LicenseVerifierTest` verifică
  compatibilitatea ambelor cu aplicația.

## Build

```powershell
.\build_web_client.ps1   # client web -> assets\web_client.zip, apoi APK-ul release
```

**Orice schimbare în codul de client trebuie urmată de această comandă.** APK-ul
servește browserelor clientul web împachetat în el.

### Semnarea release-ului

Creează `android/key.properties` (este ignorat de git):

```properties
storeFile=C:/cale/catre/upload-keystore.jks
storePassword=...
keyAlias=upload
keyPassword=...
```

Fără acest fișier, release-ul e semnat cu cheia de debug, care e bună doar pentru teste locale.

## Teste

```powershell
flutter analyze
flutter test
```

`test/support/` conține un canal WebSocket fals (`FakeChannel`) și utilitare care
testează serverul complet în memorie, fără rețea.
