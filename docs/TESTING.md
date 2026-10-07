# Handmatig testplan

Voer dit plan uit op een echte Android-telefoon en een echte MacBook. Noteer
per scenario de appversie, het netwerk en de uitkomst. Gebruik voor bestanden
zowel een klein bestand als een bestand van enkele honderden megabytes wanneer
dat praktisch is.

## 1. Installeren op echte apparaten

**Stappen**

1. Installeer de APK uit GitHub Releases op Android.
2. Open de DMG op macOS en sleep DOT naar Programma's.
3. Start DOT op beide apparaten.

**Verwacht resultaat:** beide apps starten zonder debugscherm, tonen de
welkomstpagina en bewaren lokale gegevens na herstart.

## 2. Koppelen zonder technische kennis

**Stappen**

1. Zet beide apparaten op hetzelfde gewone wifi-netwerk.
2. Kies op macOS **Apparaat koppelen**.
3. Scan de QR-code op Android en bevestig de getoonde apparaatnamen op beide
   apparaten.

**Verwacht resultaat:** de koppeling lukt zonder IP-adres in te voeren, beide
   apps tonen de verbonden status en het apparaat verschijnt in Apparaten.

## 3. Automatisch opnieuw verbinden

**Stappen**

1. Koppel de apparaten en zet automatisch opnieuw verbinden aan.
2. Zet wifi op één apparaat kort uit en weer aan.
3. Wacht tot de verbinding opnieuw wordt opgebouwd.

**Verwacht resultaat:** de status gaat tijdelijk naar offline of zoeken en
  daarna terug naar verbonden. Er is geen nieuwe koppeling nodig.

## 4. Tekst, links en bestanden in beide richtingen

**Stappen**

1. Voeg op Android tekst, een link en een bestand toe.
2. Controleer de drie items op macOS en gebruik kopiëren, openen of bewaren.
3. Herhaal dit vanaf macOS, inclusief een bestand slepen naar het venster.

**Verwacht resultaat:** ieder item verschijnt één keer met het juiste type,
  inhoud en herkomst. Een ontvangen bestand is pas ontvangen nadat de
  overdracht en checksum klaar zijn.

## 5. Offline items na herstel

**Stappen**

1. Verbreek de verbinding.
2. Voeg op beide apparaten meerdere items toe en bewerk een bestaand item.
3. Herstel de verbinding en kies zo nodig **Opnieuw verbinden**.

**Verwacht resultaat:** items tonen tijdens offline werken **Wacht op
verbinding**, worden na herstel verwerkt en verschijnen niet dubbel.

## 6. Gelijktijdige notitiewijzigingen

**Stappen**

1. Maak een notitie en laat die naar beide apparaten synchroniseren.
2. Verbreek de verbinding.
3. Bewerk dezelfde notitie op beide apparaten en verbind opnieuw.

**Verwacht resultaat:** geen van beide versies verdwijnt stil. De oorspronkelijke
notitie en een herkenbare andere versie blijven beschikbaar.

## 7. Onderbroken bestandsoverdracht

**Stappen**

1. Start een groot bestand vanaf Android.
2. Verbreek tijdens de overdracht de wifi of sluit een van de apps.
3. Herstel de verbinding en kies zo nodig **Opnieuw proberen**.

**Verwacht resultaat:** de overdracht toont een herstelactie, gaat verder vanaf
een geldig punt en het uiteindelijke bestand is compleet en onbeschadigd.

## 8. Niet-gekoppeld apparaat

**Stappen**

1. Laat een derde apparaat op hetzelfde netwerk zoeken naar DOT.
2. Probeer zonder bevestigde koppeling itemverkeer te starten.

**Verwacht resultaat:** het derde apparaat krijgt geen toegang tot items of
bestanden. De bestaande koppeling blijft bruikbaar.

## 9. Koppeling intrekken

**Stappen**

1. Verwijder de gekoppelde telefoon in het scherm Apparaten op macOS.
2. Probeer vanaf de telefoon opnieuw te verbinden.
3. Koppel de telefoon daarna opnieuw via een nieuwe QR-code.

**Verwacht resultaat:** de oude identiteit wordt geweigerd. Een nieuwe,
bevestigde koppeling werkt wel.

## 10. Werken zonder animaties

**Stappen**

1. Zet in Instellingen de animaties op verminderd.
2. Herhaal koppelen, toevoegen, synchroniseren en een foutscenario.

**Verwacht resultaat:** de app blijft begrijpelijk en bedienbaar. Belangrijke
  statusteksten en acties zijn zichtbaar zonder bewegende elementen.

## 11. Soepele synchronisatie

**Stappen**

1. Zet beide apps naast elkaar open.
2. Verstuur achter elkaar tekst, links en meerdere bestanden.
3. Observeer status, voortgang en bediening tijdens de overdracht.

**Verwacht resultaat:** de interface blijft bruikbaar, de status blijft
duidelijk en geen item raakt zoek of wordt dubbel aangemaakt.

## 12. Update met behoud van gegevens en koppeling

**Stappen**

1. Maak items en een werkende koppeling met een vorige versie.
2. Installeer de nieuwe APK of DMG zonder appgegevens te verwijderen.
3. Start de nieuwe versie en synchroniseer een nieuw item.

**Verwacht resultaat:** bestaande items, favorieten en de koppeling blijven
bestaan. Nieuwe items synchroniseren normaal.

## 13. Gastnetwerk met client isolation

**Stappen**

1. Verbind beide apparaten met een gastnetwerk waarvan client isolation aan
   staat.
2. Probeer te koppelen via QR en daarna via de handmatige route.

**Verwacht resultaat:** de beperking wordt zichtbaar als niet verbonden of
  zoeken. Na overstappen op een normaal netwerk kan koppelen wel.

## 14. MacBook in slaapstand

**Stappen**

1. Laat beide apps gekoppeld en verbonden.
2. Laat de MacBook slapen en stuur vanaf Android een item.
3. Maak de MacBook wakker.

**Verwacht resultaat:** tijdens slaap is de MacBook offline en blijft het item
  in de wachtrij. Na wakker worden kan de verbinding herstellen en wordt het
  item één keer afgeleverd.

## 15. App opnieuw starten

**Stappen**

1. Sluit DOT volledig op beide apparaten.
2. Start eerst macOS en daarna Android.
3. Voeg na het opstarten een item toe vanaf beide kanten.

**Verwacht resultaat:** de opgeslagen koppeling wordt herkend, de apps
  verbinden opnieuw en beide nieuwe items komen aan.

## 16. Camera- en notificatiepermission geweigerd

**Stappen**

1. Weiger cameratoegang wanneer Android daarom vraagt en probeer QR-scannen.
2. Gebruik daarna de handmatige route.
3. Weiger notificaties op Android en ontvang een item.

**Verwacht resultaat:** DOT crasht niet en legt uit welke route nog werkt.
Handmatig koppelen blijft beschikbaar. De synchronisatie werkt zonder
notificaties, maar toont de ontvangst in de app.

## 17. Weinig opslagruimte

**Stappen**

1. Maak op het ontvangende apparaat minder vrije ruimte dan nodig is voor een
   testbestand.
2. Start de overdracht.

**Verwacht resultaat:** de overdracht faalt zichtbaar, het lokale bestand blijft
  niet half als voltooid staan en **Opnieuw proberen** is beschikbaar nadat
  ruimte is vrijgemaakt.

## 18. Verschillende appversies

**Stappen**

1. Installeer op één apparaat de vorige release en op het andere de nieuwe
   release.
2. Koppel of herstel de bestaande koppeling.
3. Synchroniseer tekst, een notitie en een bestand.

**Verwacht resultaat:** ondersteunde protocolversies verbinden en wisselen
  bekende items uit. Een onbekend toekomstig itemtype wordt overgeslagen
  zonder crash. Bij een onverenigbare protocol-major verschijnt een duidelijke
  foutstatus.

## 19. Bediening op afstand

Voer deze controles uit met een gekoppelde Android-telefoon en Mac op hetzelfde wifi-netwerk.

### Toegankelijkheid geweigerd en toegestaan

**Stappen**

1. Zet op de Mac bij **Systeeminstellingen > Privacy en beveiliging > Toegankelijkheid** DOT uit.
2. Open **Bediening** op Android.
3. Zet DOT weer aan bij Toegankelijkheid en probeer de trackpad opnieuw.

**Verwacht resultaat:** bij geweigerde toestemming verschijnt een melding dat Toegankelijkheid nodig is en beweegt de Mac-cursor niet. Na toestemming beweegt de cursor mee met de vinger op het trackpad.

### Koppeling ingetrokken tijdens bediening

**Stappen**

1. Begin het trackpad te gebruiken vanaf de gekoppelde telefoon.
2. Verwijder de telefoon in **Apparaten** op de Mac.
3. Probeer opnieuw te bewegen, klikken en scrollen.

**Verwacht resultaat:** na het intrekken van de koppeling verwerkt de Mac geen invoer meer van die telefoon.

### Bediening uitgeschakeld op de Mac

**Stappen**

1. Zet **Bediening op afstand** uit in Instellingen op de Mac.
2. Probeer vanaf Android te bewegen, klikken en een toets te sturen.

**Verwacht resultaat:** de Mac verwerkt geen invoer zolang de instelling uitstaat. Zet de instelling weer aan en controleer dat bediening na herstel van de status weer werkt.

### Presentatieklikker verandert het systeemvolume niet

**Stappen**

1. Open een diavoorstelling en kies op Android **Bediening > Presentatie**.
2. Druk op de volumetoetsen van de telefoon om naar vorige en volgende dia te gaan.
3. Controleer het volume van de Mac.

**Verwacht resultaat:** de dia verandert; het systeemvolume van de Mac blijft gelijk.

### Scherm blijft aan tijdens presenteren

**Stappen**

1. Open op Android **Bediening > Presentatie**.
2. Laat de telefoon liggen tot de normale scherm-time-out zou verlopen.

**Verwacht resultaat:** het telefoonscherm blijft aan zolang de presentatieweergave actief is.

### Reactiesnelheid op hetzelfde wifi-netwerk

**Stappen**

1. Verbind de gekoppelde telefoon en Mac met hetzelfde wifi-netwerk.
2. Gebruik het trackpad om de cursor te bewegen en herhaal klikken en scrollen.
3. Gebruik **Vorige** en **Volgende** in een presentatie.

**Verwacht resultaat:** bewegingen en acties voelen vrijwel direct aan, zonder merkbare ophoping of achterblijvende invoer.
