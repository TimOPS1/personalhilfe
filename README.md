# Personalhilfe

Kleine Web-App für die kurzfristige Personalkoordination zwischen Klassen einer Förderschule.
Läuft als statische Seite über GitHub Pages und lässt sich auf dem Handy als Icon auf den Homescreen legen.

## Was die App kann

- Eine Klasse meldet Bedarf an Erwachsenen, für einen oder mehrere Zeiträume (1. Block, 2. Block, Mittagessen, 3. Block oder ganzer Tag).
- Andere Klassen sehen offene Zeiträume und schicken jemanden für einen oder mehrere davon.
- Bei Bedarf von mehreren Personen bleibt der Zeitraum offen, bis genug zugesagt haben.
- Die Schulübersicht zeigt alle Klassen auf einen Blick, die Schulleitung hat zusätzlich eine Master-Ansicht (Bedarfe schließen, Personal von Klasse zu Klasse zuweisen, Block beenden).
- Die gewählte Klasse wird auf dem Gerät gemerkt. "Neu wählen" für Vertretungstage.
- Es werden keine Namen von Kindern oder Mitarbeitenden gespeichert, nur Klassen und Zeiträume.

## Anpassen (ohne Programmieren)

Alles Wichtige steht in `config.js`:

- **Klassennamen:** unter `classes` eintragen, z. B. `"G2a"`, `"G2b"` oder `"H1"` bis `"H6"`.
- **Schulleitungs-Passwort:** In `config.js` steht nur der Hash, nicht das Passwort. Einen neuen Hash erzeugt man mit dem Befehl, der als Kommentar in der Datei steht.
- **Beispieldaten:** `demoData: true` zeigt zum Ausprobieren ein paar Bedarfe.

Auf GitHub: Datei öffnen, Stift-Symbol, ändern, "Commit changes". Nach ca. einer Minute ist die Änderung live.

## Wichtig: aktueller Stand

Die Seite hat **kein Backend**. Alle Eingaben bleiben im Browser des jeweiligen Handys und gelten nur für den heutigen Tag. Ein anderes Handy sieht sie nicht. Deshalb zeigt die App einen entsprechenden Hinweis, solange `localOnlyNotice: true` gesetzt ist.

Der Passwortschutz der Schulleitungs-Ansicht ist nur eine Bequemlichkeit, kein echter Schutz: Auf einer statischen Seite kann jeder technisch Versierte den Code ansehen und ändern. Es liegen hier aber auch keine geheimen Daten.

Für den echten gemeinsamen Betrieb fehlen:

- ein Backend mit Echtzeit-Abgleich (geplant: Supabase, EU-Region)
- echte Anmeldung (ggf. über IServ-Single-Sign-On)
- Web Push für Benachrichtigungen auf allen Handys

## Technik

Reines HTML, CSS und JavaScript ohne Build-Schritt. Dateien: `index.html` (App), `config.js` (Einstellungen), `manifest.webmanifest` und Icons (Homescreen).
