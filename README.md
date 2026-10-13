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

## Zwei Betriebsarten

**Lokal (Standard):** Solange in `config.js` `supabase.url` und `supabase.anonKey` leer sind, bleiben alle Eingaben im Browser des jeweiligen Handys und gelten nur für den heutigen Tag. Der Passwortschutz der Schulleitung ist dann nur Bequemlichkeit, kein echter Schutz.

**Gemeinsam (Supabase):** Alle Handys sehen denselben Stand in Echtzeit. Einrichtung:

1. Auf supabase.com ein kostenloses Projekt anlegen, Region **Frankfurt (eu-central-1)**.
2. Im SQL Editor den Inhalt von `supabase/schema.sql` ausführen.
3. Im SQL Editor die Zugangsdaten setzen (nicht ins Repository schreiben):
   `select public.ph_set_secrets('SCHULCODE', 'SCHULLEITUNGS-PASSWORT');` (jeweils mindestens 8 Zeichen)
4. Unter Project Settings, API die Project URL und den `anon`-Key in `config.js` unter `supabase` eintragen. Den `service_role`-Key niemals.
5. In `config.js` `adminPasswordHash` leeren und `localOnlyNotice: false` setzen.
6. Beim ersten Öffnen fragt die App einmalig nach dem Schulcode und merkt ihn sich.

Grenzen: Das kostenlose Supabase-Projekt pausiert nach einer Woche ohne Aktivität (Ferien), im Dashboard lässt es sich wieder starten. Web Push für Benachrichtigungen ist noch nicht eingebaut. Vor echtem Einsatz Datenschutz der Schule klären.

## Technik

Reines HTML, CSS und JavaScript ohne Build-Schritt. Dateien: `index.html` (App), `config.js` (Einstellungen), `manifest.webmanifest` und Icons (Homescreen).
