# DOT

<p align="center"><img src="docs/icon-preview.png" alt="DOT app icon" width="128"></p>

DOT maakt van je Android-telefoon en MacBook één kleine, persoonlijke
werkruimte. Deel tekst, links, bestanden en korte notities over je lokale
netwerk. DOT bewaart alles lokaal en vraagt geen account.

## Installeren

### Android

1. Download de APK uit [GitHub Releases](https://github.com/BEMBOOMER/dot/releases/latest).
2. Open de APK op je telefoon.
3. Sta, als Android daarom vraagt, **Installeren uit onbekende bron** toe voor
   je browser of bestandsbeheerder.

### macOS

1. Download `DOT.dmg` uit GitHub Releases en open het bestand.
2. Sleep DOT naar **Programma's**.
3. Open DOT de eerste keer met rechtsklik > **Open**, omdat de app niet
   genotariseerd is.

## Eerste koppeling

De MacBook is het host-apparaat en de Android-telefoon maakt verbinding.

1. Open DOT op de MacBook en kies **Apparaat koppelen**.
2. Open DOT op Android en kies **Apparaat koppelen**.
3. Scan op Android de QR-code die op de MacBook verschijnt.
4. Controleer op beide schermen de apparaatnaam en bevestig de koppeling.
5. Staat scannen niet klaar, kies dan **Handmatig verbinden** en gebruik het
   IP-adres, de poort en de zescijferige code van de MacBook.

Daarna onthouden beide apparaten elkaar en proberen ze automatisch opnieuw te
verbinden wanneer dat is ingeschakeld.

## Privacy

Je werkruimte staat lokaal op je apparaten. DOT gebruikt geen cloud en geen
account. De verbinding loopt versleuteld over TLS, apparaten bewijzen hun
identiteit bij elke verbinding en een onbekend apparaat krijgt geen toegang.
Klembordinhoud wordt alleen gedeeld wanneer je bewust **Plakken en versturen**
kiest. Logs bevatten geen iteminhoud.

## Bekende beperkingen

- Beide apparaten moeten op hetzelfde lokale netwerk zitten.
- Gastnetwerken met client isolation laten apparaten vaak niet met elkaar
  praten.
- Android kan een verbinding stoppen wanneer DOT naar de achtergrond gaat.
- Een MacBook in slaapstand is niet bereikbaar.
- De eerste versie belooft geen permanente achtergrondverbinding op Android.

## Ontwikkelen

Installeer Flutter en haal daarna de dependencies op:

```sh
flutter pub get
flutter run -d macos
flutter run -d <android-id>
flutter test
```

Bekijk aangesloten apparaten met `flutter devices`. De sync-tests gebruiken
een lokale loopbackverbinding en een SQLite-testdatabase.

## Release maken

Voor een ondertekende Android-release heb je eerst een keystore en de
bijbehorende secrets in GitHub Actions nodig:

```sh
./scripts/make_keystore.sh
git tag v0.1.0
git push --tags
```

De releaseworkflow bouwt de APK en DMG, maakt checksums en gebruikt de
`[0.1.0]`-sectie uit `CHANGELOG.md` als release notes. Zonder de Android
keystore wordt een niet-ondertekende APK met debug-signing fallback gemaakt.
Notarization van de DMG is optioneel en gebruikt de Apple-secrets uit de
workflow.

## Licentie

MIT, zie [LICENSE](LICENSE). Gemaakt door Roelof Junior Haar ([@bemooks](https://instagram.com/bemooks)).
