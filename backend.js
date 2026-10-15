// Verbindung zu Supabase. Wird nur aktiv, wenn in config.js url und anonKey eingetragen sind.
// Ohne Eintrag bleibt window.PH_BACKEND leer und die App arbeitet lokal.
(function(){
  var cfg = (window.PERSONALHILFE_CONFIG || {}).supabase || {};
  if(!cfg.url || !cfg.anonKey || !window.supabase || !window.supabase.createClient){
    window.PH_BACKEND = null;
    return;
  }
  var client = window.supabase.createClient(cfg.url, cfg.anonKey, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false }
  });

  // Lesen und Schreiben laufen nur über Datenbank-Funktionen (siehe supabase/schema.sql).
  // Alle prüfen den Schulcode, ohne Code gibt die Datenbank nichts heraus.
  async function rpc(name, args){
    var res;
    try{ res = await client.rpc(name, args); }
    catch(e){ return {ok: false, error: 'netz'}; }
    if(!res || res.error || !res.data) return {ok: false, error: 'netz'};
    return res.data;
  }

  function fetchDay(code){
    return rpc('ph_fetch_day', {p_code: code});
  }

  // Die Datenbank meldet nur "es hat sich etwas geändert", ohne Inhalt.
  // Die Daten holt die App danach selbst mit dem Schulcode ab.
  function subscribe(onChange){
    var ch = client.channel('personalhilfe');
    ch.on('broadcast', {event: 'changed'}, function(){ onChange(); });
    ch.subscribe(function(status){ if(status === 'SUBSCRIBED') onChange(); });
    return ch;
  }

  window.PH_BACKEND = {rpc: rpc, fetchDay: fetchDay, subscribe: subscribe};
})();
