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
