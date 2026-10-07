# DOT — projectconcept (werknaam)

DOT is een minimalistische app voor Android en macOS die beide apparaten met elkaar verbindt. Samen vormen ze één persoonlijke werkruimte: wat je op je telefoon toevoegt, verschijnt op je MacBook, en andersom. Grote, ruimtelijke dots maken de verbinding zichtbaar.

Android: installeerbare APK via GitHub Releases. macOS: zelfstandige desktopapp met eigen venster, dockicoon en optionele menubalkfunctie.

## Doel
Tekst, links, bestanden en korte notities tussen apparaten delen, bewaren en terugvinden. Eén centrale werkruimte, duidelijke verbindingsstatus, alleen relevante functies.

## Uitgangspunten
- Eén herkenbare app op twee platforms.
- Eenmalig koppelen, daarna automatisch opnieuw verbinden wanneer beide apps bereikbaar zijn.
- Geen verplichte account in v1.
- Lokaal bewaren; werkruimte blijft bruikbaar zonder verbinding.
- Minimalistische interface met speelse, snelle animaties.
- Duidelijke controle over gekoppelde apparaten en gedeelde gegevens.

## Werkruimte
Overzicht van gedeelde items als compacte kaarten (titel, type, herkomst, status).
Types: Tekst, Link (titel + waar mogelijk preview), Bestand, Notitie (bewerkbaar op beide apparaten).
Acties: openen, kopiëren, delen, vastzetten, verwijderen. Zoekveld + filters (tekst, links, bestanden, notities).
Android: nadruk op snel toevoegen/delen. macOS: overzicht, drag-and-drop, sneltoetsen.

## Koppelen
Eerste start: "Apparaat koppelen". macOS toont een QR-code, Android scant en vraagt bevestiging. Beide tonen welke verbinding wordt aangemaakt. Daarna onthouden ze elkaar en verbinden automatisch opnieuw. v1: zelfde lokale netwerk. Fallback: handmatige verbindingsroute (IP + poort + code).

## Verbindingsstatus
| Status | Tekst | Visueel |
|---|---|---|
| Geen gekoppeld apparaat | Koppel je apparaat | Eén rustige dot |
| Zoeken | Je MacBook zoeken… | Twee dots bewegen subtiel |
| Koppelen | Bevestig de verbinding | Dots bewegen naar elkaar toe |
| Verbonden | Verbonden met MacBook | Twee dots vormen één compositie |
| Synchroniseren | Wijzigingen synchroniseren… | Korte beweging tussen de dots |
| Offline | Je apparaat is offline | Dots iets verder uit elkaar |
| Mislukt | Verbinden lukt nog niet | Animatie stopt, herstelactie verschijnt |

Status altijd met tekst naast kleur en beweging.

## Functies
- **Snel delen**: tekst/link/bestand toevoegen → Versturen. Android-deelmenu → DOT. macOS: bestanden naar venster slepen.
- **Klembord**: "Plakken en versturen" deelt bewust het klembord. Ontvangen tekst → "Kopiëren". Automatisch klembord lezen staat uit.
- **Gedeelde notities**: lokaal opgeslagen, sync bij verbinding. Offline aan beide kanten bewerkt → beide versies blijven bestaan tot opgelost.
- **Bestanden**: voortgang, grootte, annuleren. Onderbroken → herstelactie. Status "Ontvangen" pas na bevestiging door ontvanger.
- **Offline**: items blijven lokaal, status "Wacht op verbinding", wachtrij verwerkt zonder dubbele items.
- **Geschiedenis/favorieten**: vastzetten houdt items bovenaan; geschiedenis apart op te schonen.

## Schermen
1. Welkom: grote 3D-dot, "Je telefoon en MacBook, verbonden." Knoppen: Apparaat koppelen, Eerst bekijken.
2. Koppelen: macOS QR-code; Android scanner + handmatig. Knoppen: Scan QR-code, Handmatig verbinden, Bevestig koppeling, Annuleren.
3. Werkruimte: status, items, opvallende toevoegknop. Acties: Toevoegen, Plakken en versturen, Bestand kiezen, Nieuwe notitie, Zoeken, Filteren.
4. Itemdetails: inhoud, herkomst, overdrachtsstatus. Kopiëren, Openen, Bewaren, Opnieuw versturen, Vastzetten, Verwijderen (alleen relevante; link → Open link; bestand → Toon in map op macOS).
5. Apparaten: naam, bereikbaarheid, laatste verbinding. Apparaat toevoegen, Naam wijzigen, Opnieuw verbinden, Koppeling verwijderen.
6. Instellingen: thema (systeem/licht/donker), animaties (volledig/verminderd), meldingen, automatisch opnieuw verbinden, starten bij inloggen (macOS), downloadlocatie (macOS), geschiedenis beheren, updates controleren, privacy en gekoppelde apparaten.

## macOS
Aanpasbaar venster, drag-and-drop, optioneel menubalkicoon met status, compact snel-deel-venster, sneltoetsen (toevoegen, zoeken, versturen), meldingen, openen/tonen in Finder, optioneel starten bij inloggen. Venster sluiten ≠ app afsluiten; actieve menubalk is zichtbaar.

## Android
APK via GitHub Releases, deelmenu, QR-scanner, systeembestandskiezer, meldingen (indien toegestaan), overdrachtsvoortgang, grote aanraakvlakken. Geen belofte van permanente achtergrondverbinding.

## Visuele richting
Paper #F5F0E8 en ink #1A1A1A. Coral #FF4F81 primair accent. Lime #CCFF00 voor succesvolle verbinding. Koppen Archivo Black, tekst/bediening Space Grotesk. Afgeronde hoeken, duidelijke borders, harde offsetschaduwen, subtiele noise. Eén centrale handeling per scherm.

## Dots en animaties
Grote zachte 3D-bollen met gecontroleerde belichting. Start: schaal-in. Zoeken: klein rustig patroon. Verbinden: naar elkaar toe. Verbonden: korte bounce. Versturen: kleine dot reist van apparaat naar apparaat. Ontvangen: korte puls. Verbreken: uit elkaar, tot rust. Interacties 0,2–0,5 s; doorlopende animaties subtiel en stoppen als het scherm niet actief is. Verminderde beweging: korte fades. App blijft zonder animatie begrijpelijk.

## Techniek
Flutter/Dart, één codebase. SQLite, lokale instellingen, beveiligde opslag, Bonjour/NSD, versleutelde lokale verbinding (WebSocket over TLS), GitHub + Actions.

## Sync & betrouwbaarheid
Unieke ID per item; wijzigingen bijgehouden tot bevestigd. Rekening houden met: wegvallen verbinding, dubbele verzendpogingen, offline wijzigingen, onderbroken bestandsoverdrachten, verschillende appversies, verwijderde items die niet terug mogen komen. UI onderscheidt Lokaal opgeslagen, Wacht op verbinding, Versturen, Ontvangen.

## Privacy
Geen cloud. Nieuw apparaat pas toegang na bevestiging. Koppeling met tijdelijk eenmalig geheim, daarna identiteit vastgelegd en bij elke verbinding gecontroleerd. Versleuteld transport, sleutels in beveiligde opslag, QR zonder blijvende sleutels, onbekende apparaten geen toegang, koppeling intrekbaar, klembord alleen na bewuste actie, logs zonder inhoud.

## Releases
Ondertekende APK, macOS DMG, versienummer, release notes, checksums. Zelfde Android-releasesleutel. Updatemelding in de app; installatie blijft een bewuste actie.

## Acceptatiecriteria v1
Installeerbaar op echte apparaten; koppelen zonder technische kennis; automatisch opnieuw verbinden; tekst/links/bestanden beide kanten op; offline items na herstel correct verwerkt; gelijktijdige notitiewijzigingen zonder stil verlies; onderbroken overdracht heeft herstelactie; niet-gekoppelde apparaten geen toegang; intrekken blokkeert toegang; bruikbaar zonder animaties; soepel tijdens sync; updates behouden data en koppelingen.
