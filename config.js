// Einstellungen für Personalhilfe. Diese Datei darf angepasst werden.
// Bearbeiten auf GitHub: Datei öffnen, Stift-Symbol, ändern, "Commit changes".
window.PERSONALHILFE_CONFIG = {
  // Namen der Klassen, in dieser Reihenfolge. Hier lassen sich auch neutrale
  // Bezeichnungen wie "G2a", "G2b" oder "H1" bis "H6" eintragen.
  classes: ["Klasse A", "Klasse B", "Klasse C", "Klasse D", "Klasse E", "Klasse F", "Klasse G", "Klasse H", "Klasse I", "Klasse J", "Klasse K", "Klasse L"],

  // SHA-256-Hash des Schulleitungs-Passworts (das Passwort selbst steht nicht im Code).
  // Neuen Hash erzeugen: im Browser die Konsole öffnen und eingeben:
  //   crypto.subtle.digest('SHA-256', new TextEncoder().encode('NEUES-PASSWORT')).then(b=>console.log([...new Uint8Array(b)].map(x=>x.toString(16).padStart(2,'0')).join('')))
  adminPasswordHash: "2c013a7e49a8ced055e2ee3f1abd6c84fecaa1cb73b3f39d5477fcdef798a46a",

  // Gemeinsamer Betrieb über Supabase. Solange url und anonKey leer sind, arbeitet die App
  // nur lokal auf dem jeweiligen Handy. Beide Werte stehen in Supabase unter
  // "Project Settings" -> "API". Der anon-Schlüssel ist für die Öffentlichkeit gedacht,
  // geschützt wird über die Regeln aus supabase/schema.sql. Den "service_role"-Schlüssel
  // darf man NIEMALS hier eintragen.
  supabase: { url: "", anonKey: "" },

  // Beispieldaten beim Start anzeigen (zum Ausprobieren). Für den Echtbetrieb: false.
  demoData: false,

  // Hinweis "Eingaben bleiben auf diesem Gerät" anzeigen. Erst abschalten, wenn die Daten
  // wirklich zwischen den Handys geteilt werden.
  localOnlyNotice: true,

  features: {
    // Benachrichtigungen funktionieren erst mit Server (Web Push). Bis dahin aus.
    notifications: false
  }
};
