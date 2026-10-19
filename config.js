// Einstellungen für Personalhilfe. Diese Datei darf angepasst werden.
// Bearbeiten auf GitHub: Datei öffnen, Stift-Symbol, ändern, "Commit changes".
window.PERSONALHILFE_CONFIG = {
  // Namen der Klassen, in dieser Reihenfolge. Hier lassen sich auch neutrale
  // Bezeichnungen wie "G2a", "G2b" oder "H1" bis "H6" eintragen.
  // Bitte keine Namen von Personen verwenden (z. B. nicht "Klasse Müller").
  // Wer eine Klasse später umbenennen will, ohne dass ihre Meldungen des Tages verloren
  // gehen, schreibt statt "Name" einen Eintrag wie { id: "klassea", name: "Neuer Name" }.
  classes: ["Klasse A", "Klasse B", "Klasse C", "Klasse D", "Klasse E", "Klasse F", "Klasse G", "Klasse H", "Klasse I", "Klasse J", "Klasse K", "Klasse L"],

  // Ende der Zeiträume (1. Block, 2. Block, Mittagessen, 3. Block). Die App schaltet danach
  // automatisch weiter. Gilt nur im lokalen Betrieb; im gemeinsamen Betrieb stehen die Zeiten
  // in supabase/schema.sql (Funktion ph_block_ends) und werden von dort übernommen.
  blockEnds: ["10:30", "11:45", "12:45", "14:25"],

  // Bewegliche Ferientage, festgelegt vom Staatlichen Schulamt Weilburg (Lahn-Dill-Kreis und
  // Landkreis Limburg-Weilburg). Quelle: https://schulaemter.hessen.de/schulbesuch/bewegliche-ferientage
  // Einmal im Jahr für das neue Schuljahr ergänzen. Sie erscheinen beim Knopf
  // "Ferien und Feiertage Hessen laden" in der Vorschau; vergangene Tage werden ausgelassen.
  beweglicheFerientage: [
    { day: "2026-10-02", label: "Beweglicher Ferientag" },   // Tag vor den Herbstferien
    { day: "2027-02-08", label: "Rosenmontag" },
    { day: "2027-05-07", label: "Beweglicher Ferientag" },   // Tag nach Christi Himmelfahrt
    { day: "2027-05-28", label: "Beweglicher Ferientag" }    // Tag nach Fronleichnam
  ],

  // Nur für den lokalen Betrieb ohne Supabase. Kein echter Schutz, weil dieser Hash öffentlich ist.
  // SHA-256-Hash des Schulleitungs-Passworts (das Passwort selbst steht nicht im Code).
  // Neuen Hash erzeugen: im Browser die Konsole öffnen und eingeben:
  //   crypto.subtle.digest('SHA-256', new TextEncoder().encode('NEUES-PASSWORT')).then(b=>console.log([...new Uint8Array(b)].map(x=>x.toString(16).padStart(2,'0')).join('')))
  adminPasswordHash: "",

  // Gemeinsamer Betrieb über Supabase. Solange url und anonKey leer sind, arbeitet die App
  // nur lokal auf dem jeweiligen Handy. Beide Werte stehen in Supabase unter
  // "Project Settings" -> "API". Der anon-Schlüssel ist für die Öffentlichkeit gedacht,
  // geschützt wird über die Regeln aus supabase/schema.sql. Den "service_role"-Schlüssel
  // darf man NIEMALS hier eintragen.
  supabase: {
    url: "https://surunzsxklrglcgqcnxv.supabase.co",
    anonKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InN1cnVuenN4a2xyZ2xjZ3Fjbnh2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTE4ODQxNTAsImV4cCI6MjEwNzQ2MDE1MH0.cvfR5Y5Zdqcw9eALIyZEUGS3gfN0RKcHZXYkxpYJtnM"
  },

  // Beispieldaten beim Start anzeigen (zum Ausprobieren). Für den Echtbetrieb: false.
  demoData: false,

  // Hinweis "Eingaben bleiben auf diesem Gerät" anzeigen. Erst abschalten, wenn die Daten
  // wirklich zwischen den Handys geteilt werden.
  localOnlyNotice: false,

  features: {
    // Benachrichtigungen funktionieren erst mit Server (Web Push). Bis dahin aus.
    notifications: false
  }
};
