# Personalhilfe

Kleine Web-App für die kurzfristige Personalkoordination zwischen Klassen einer Förderschule.
Läuft als statische Seite über GitHub Pages und lässt sich auf dem Handy als Icon auf den Homescreen legen.

## Was die App kann

- Eine Klasse meldet Bedarf an Erwachsenen: erst den Zeitraum wählen (1. Block, 2. Block, Mittagessen, 3. Block oder ganzer Tag), dann die Anzahl mit + melden.
- Andere Klassen sehen offene Zeiträume und schicken jemanden für einen oder mehrere davon.
- Bei Bedarf von mehreren Personen bleibt der Zeitraum offen, bis genug zugesagt haben.
- Die Zeiträume wechseln automatisch nach Uhrzeit (10:30, 11:45, 12:45, 14:25). Die Schulleitung kann manuell vor- oder zurückschalten; das gilt bis zur nächsten Uhrzeit.
- Die Schulübersicht zeigt alle Klassen auf einen Blick, die Schulleitung hat zusätzlich eine Master-Ansicht (Bedarfe schließen, Personal von Klasse zu Klasse zuweisen, Einsätze beenden).
- Schulleitung am PC: Matrix aus Klassen und Zeiträumen. Die Ansicht schaltet nach Bildschirmbreite automatisch zwischen Desktop und Mobil (ab 900 px Breite Desktop), der Umschalter Auto / Mobil / Desktop erzwingt eine der beiden. Ein Feld der Matrix anklicken wählt es unter "Zuweisen" vor.
- Schulleitung trägt Abwesende ein, für den ganzen Tag oder einzelne Zeiträume ("nur 3. Block", "kommt später" = die frühen Zeiträume). Ist eine Klasse angegeben, fehlt dort automatisch 1 Person pro Abwesendem; meldet die Klasse selbst mehr Bedarf, gilt der höhere Wert.
- Schulleitung kann Vertretungen eintragen ("Frau X vertritt in Klasse A", ganzer Tag oder einzelne Zeiträume). Eine Vertretung zählt wie ein Einsatz und deckt den Bedarf der Klasse. In der Matrix sind Vertretungen blau-grau, Hilfe aus einer anderen Klasse grün.
- **Planung im Voraus (bis 6 Monate):** Klassen melden Abwesenheiten für ihre eigene Klasse über einen Zeitraum ("Frau X, 26.10.–6.11."), die Schulleitung trägt Abwesenheiten, Vertretungen und unterrichtsfreie Tage (Ferien, Feiertage) ein. Wochenenden und freie Tage werden übersprungen. Ein mehrtägiger Eintrag lässt sich als Ganzes entfernen. Gründe werden nicht gespeichert.
- Schulleitung, Reiter "Planung": Wochenansicht Klassen × Mo–Fr mit "fehlt" / "gedeckt", blätterbar bis 26 Wochen voraus. Ein Feld anklicken zeigt die Einträge des Tages und übernimmt Datum und Klasse ins Formular.
- Klassen sehen ihre geplanten Meldungen und ob dafür schon eine Vertretung (mit Namen) geplant ist.
- Ferien und gesetzliche Feiertage Hessen: In der Karte "Unterrichtsfrei" holt "Ferien und Feiertage Hessen laden" die Termine der nächsten 12 Monate von OpenHolidays (openholidaysapi.org) und zeigt sie zur Kontrolle an, bevor sie übernommen werden. Die beweglichen Ferientage des Staatlichen Schulamts Weilburg (Lahn-Dill-Kreis und Limburg-Weilburg) stehen in `config.js` unter `beweglicheFerientage` und kommen automatisch mit in die Vorschau. Einmal pro Schuljahr von https://schulaemter.hessen.de/schulbesuch/bewegliche-ferientage übernehmen.
- Aula-Anzeige: eigene Seite für einen großen Bildschirm, nur lesend, aktualisiert sich selbst (siehe unten).
- Die gewählte Klasse wird auf dem Gerät gemerkt. "Neu wählen" für Vertretungstage.
- Es werden keine Namen von Kindern gespeichert. Namen von Mitarbeitenden stehen nur in der Abwesenheits- und Vertretungsliste. Abwesenheiten können Schulleitung und Klassen eintragen (jede Person mit Schulcode, nur für die gewählte Klasse), Vertretungen nur die Schulleitung. Vergangene Tage werden gelöscht; im Voraus Geplantes liegt höchstens 6 Monate vor.

## Anpassen (ohne Programmieren)

Alles Wichtige steht in `config.js`:

- **Klassennamen:** unter `classes` eintragen, z. B. `"G2a"`, `"G2b"` oder `"H1"` bis `"H6"`. Bitte keine Personennamen (nicht "Klasse Müller"), damit auch die Klassenliste keine personenbezogenen Daten enthält. Zwei Namen, die sich nur in Groß-/Kleinschreibung oder Sonderzeichen unterscheiden, meldet die App als Fehler.
- **Uhrzeiten der Zeiträume:** im gemeinsamen Betrieb in `supabase/schema.sql` (Funktion `ph_block_ends`), danach die Datei im SQL Editor erneut ausführen. `blockEnds` in `config.js` gilt nur im lokalen Betrieb.
- **Beispieldaten:** `demoData: true` zeigt zum Ausprobieren ein paar Bedarfe.

Auf GitHub: Datei öffnen, Stift-Symbol, ändern, "Commit changes". Nach ca. einer Minute ist die Änderung live.

## Zwei Betriebsarten

**Lokal:** Solange in `config.js` `supabase.url` und `supabase.anonKey` leer sind, bleiben alle Eingaben im Browser des jeweiligen Handys. Der Passwortschutz der Schulleitung ist dann nur Bequemlichkeit, kein echter Schutz.

**Gemeinsam (Supabase):** Alle Handys sehen denselben Stand in Echtzeit. Einrichtung:

1. Auf supabase.com ein kostenloses Projekt anlegen, Region **Frankfurt (eu-central-1)**.
2. Im SQL Editor den Inhalt von `supabase/schema.sql` ausführen. Das geht auch später gefahrlos erneut, z. B. nach einem Update.
3. Im SQL Editor die Zugangsdaten setzen (nicht ins Repository schreiben):
   `select public.ph_set_secrets('SCHULCODE', 'SCHULLEITUNGS-PASSWORT');`
   Schulcode mindestens 10 Zeichen, Passwort mindestens 12 Zeichen, beide verschieden. Am besten zufällige Wörter, z. B. `Tafel-Wolke-Birne-7`.
   **Niemals ein Passwort verwenden, das irgendwann in diesem Repository stand** (auch nicht als Hash): Die Historie ist öffentlich.
4. Unter Project Settings, API die Project URL und den `anon`-Key in `config.js` unter `supabase` eintragen. Den `service_role`-Key niemals.
5. Beim ersten Öffnen fragt die App einmalig nach dem Schulcode und merkt ihn sich.

### Was geschützt ist

- Ohne Schulcode gibt die Datenbank nichts heraus, auch nicht lesend. Der `anon`-Key in `config.js` ist öffentlich und darf das sein.
- Der Live-Abgleich sendet nur ein Signal "es hat sich etwas geändert", keine Inhalte.
- Fehlversuche werden pro Absender gebremst (Schulcode: 30 in 15 Minuten, Schulleitung: 5 in 10 Minuten).
- "Abmelden" beendet die Schulleitungs-Sitzung auch auf dem Server. Bei verlorenem Handy: `ph_set_secrets` mit neuen Werten ausführen, das beendet alle Sitzungen.
- Wer den Schulcode kennt, kann für jede Klasse melden. Der Code sollte daher nur an Mitarbeitende gehen und bei Personalwechsel geändert werden.

### Grenzen

- Das kostenlose Supabase-Projekt pausiert nach einer Woche ohne Aktivität. Die GitHub Action "Supabase wach halten" ruft es alle 3 Tage auf. GitHub schaltet solche geplanten Abläufe ab, wenn 60 Tage lang nichts am Repo geändert wurde; dann unter "Actions" wieder aktivieren. Notfalls lässt sich das Projekt im Supabase-Dashboard neu starten.
- Web Push für Benachrichtigungen ist noch nicht eingebaut.
- Vor echtem Einsatz Datenschutz der Schule klären.

## Aula-Anzeige

Die Seite `…/index.html#anzeige` zeigt im Vollbild die Matrix, die Abwesenden und die Vertretungen. Sie hat keine Knöpfe und aktualisiert sich selbst.

- Mit `#anzeige=SCHULCODE` im Link braucht der Bildschirm keine Eingabe. In der Schulleitungs-Ansicht erzeugt der Knopf "Link für Anzeige kopieren" diesen Link. Er enthält den Schulcode und sollte nur dort eingetragen werden, wo ihn die Schulleitung verwaltet (z. B. in den Einstellungen einer IServ-Infoanzeige).
- Namen von Abwesenden und Vertretungen liegen in Tabellen, die von außen nicht lesbar sind. Sie kommen nur mit Schulcode aus der Datenbank und werden, wie alles andere, nach dem Tag gelöscht.
- Ob eine IServ-Infoanzeige eine fremde Webseite einbinden kann, muss in IServ geprüft werden. Sonst den Aula-PC im Vollbild-Browser auf den Link stellen.

## Update einer bestehenden Datenbank

Nach Änderungen an `supabase/schema.sql` die Datei im SQL Editor einfach erneut ausführen. Sie ist wiederholbar und lässt die Passwörter unberührt.

## Technik

Reines HTML, CSS und JavaScript ohne Build-Schritt. Dateien: `index.html` (App), `config.js` (Einstellungen), `backend.js` (Verbindung zu Supabase), `supabase/schema.sql` (Datenbank), `manifest.webmanifest` und Icons (Homescreen).
