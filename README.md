# DOT

DOT verbindt je Android-telefoon en MacBook, zodat je lokaal tekst, links,
bestanden en korte notities kunt delen.

<p align="center"><img src="docs/icon-preview.png" alt="DOT app-icoon" width="128"></p>

## Downloaden

Ga naar de [laatste release](https://github.com/BEMBOOMER/dot/releases/latest)
en download het bestand voor je apparaat:

- **Mac:** `DOT-<versie>.dmg`
- **Android:** `DOT-<versie>.apk`
- `checksums-sha256.txt` bevat de SHA-256-controlesommen van beide bestanden.

DOT heeft geen account of cloud nodig. Je gegevens blijven op je apparaten en
worden via je lokale netwerk gedeeld.

## Installeren op je Mac

### Via de Terminal (snelst)

Plak dit in **Terminal**:

```bash
curl -fsSL https://raw.githubusercontent.com/BEMBOOMER/dot/main/scripts/install-mac.sh | bash
```

Het script ([`scripts/install-mac.sh`](scripts/install-mac.sh)) haalt de
laatste release op, controleert de SHA-256-controlesom, zet DOT in
**Programma's**, haalt de downloadblokkade van macOS weg en start de app. Bij een
eerste installatie opent het ook **Toegankelijkheid**, zodat je DOT meteen kunt
aanzetten voor bediening op afstand. Die ene schakelaar moet je zelf omzetten;
macOS staat niet toe dat een script dat doet. Hetzelfde commando werkt ook om
DOT bij te werken.

### Handmatig

1. Open `DOT-<versie>.dmg`.
2. Sleep DOT naar **Programma's**.
3. Start DOT vanuit Programma's.

Bij de eerste start kan macOS de app blokkeren omdat DOT nog niet is
genotariseerd. Ga dan naar **Systeeminstellingen > Privacy en beveiliging**,
scroll naar beneden en klik op **Toch openen**. Op macOS 15 en nieuwer werkt
rechtsklik > **Open** hiervoor niet meer.

De huidige release-build werkt vanaf macOS 12. De optie **Starten bij
inloggen** werkt vanaf macOS 13.

## Installeren op Android

1. Download `DOT-<versie>.apk` op je telefoon.
2. Sta, als Android daarom vraagt, **Installeren uit deze bron** toe voor je
   browser of bestandsbeheerder.
3. Open de APK en rond de installatie af.

Heb je `adb` en staat USB-foutopsporing aan, dan kan het ook vanaf je Mac:

```bash
adb install -r DOT-<versie>.apk
```

DOT werkt op Android 6 en nieuwer.

## Koppelen

De Mac is het host-apparaat. Open DOT op beide apparaten, kies **Apparaat
koppelen** en scan op Android de QR-code die op de Mac verschijnt. Controleer
de apparaatnaam en bevestig de koppeling op beide apparaten.

Werkt scannen niet, kies dan **Handmatig verbinden** en gebruik het IP-adres, de
poort en de code van zes tekens van de Mac. Daarna onthouden beide apparaten
elkaar en verbinden ze automatisch opnieuw wanneer dat is ingeschakeld.

## Bediening op afstand

Je kunt Android ook gebruiken als trackpad, presentatieklikker of
media-afstandsbediening voor je Mac. Zet **Bediening op afstand** aan in de
instellingen van DOT op de Mac.

Geef DOT daarna toegang tot Toegankelijkheid:

1. Open **Systeeminstellingen > Privacy en beveiliging > Toegankelijkheid**.
2. Sleep DOT vanuit **Programma's** naar de lijst, of klik op de **+**-knop en
   voeg DOT toe.
3. Zet DOT aan in de lijst.

Vanaf v0.2.3 hoef je dit maar één keer te doen. Verplaats je van v0.2.2 of
ouder, geef DOT na deze update nog één laatste keer opnieuw toestemming.

Op Android vind je **Bediening** in de werkruimte. Daar kun je wisselen tussen
**Trackpad**, **Presentatie** en **Media**. Alleen een gekoppelde telefoon kan
invoer sturen. Zonder Toegankelijkheid kan DOT de Mac niet bedienen.

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

De releaseworkflow bouwt `DOT-<versie>.apk` en `DOT-<versie>.dmg`, maakt
`checksums-sha256.txt` en gebruikt de `[0.1.0]`-sectie uit `CHANGELOG.md` als
release notes. Zonder de Android-keystore wordt een niet-ondertekende APK met
debug-signing fallback gemaakt. Notarization van de DMG is optioneel en
gebruikt de Apple-secrets uit de workflow.

Na de CI-release vervangt de maker de Mac-download lokaal met de stabiel
ondertekende versie:

```sh
scripts/publish_signed_mac.sh <tag>
```

Deze ondertekening zorgt ervoor dat macOS de Toegankelijkheidstoestemming bij
updates behoudt.

## Licentie

MIT, zie [LICENSE](LICENSE). Gemaakt door Roelof Junior Haar
([@bemooks](https://instagram.com/bemooks)).
