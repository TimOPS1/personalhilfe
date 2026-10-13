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

  // Der Tag richtet sich nach deutscher Zeit, genau wie in der Datenbank
  function berlinDay(){
    return new Intl.DateTimeFormat('en-CA', {timeZone: 'Europe/Berlin', year: 'numeric', month: '2-digit', day: '2-digit'}).format(new Date());
  }

  // Schreibzugriffe laufen nur über Datenbank-Funktionen (siehe supabase/schema.sql)
  async function rpc(name, args){
    var res;
    try{ res = await client.rpc(name, args); }
    catch(e){ return {ok: false, error: 'netz'}; }
    if(!res || res.error || !res.data) return {ok: false, error: 'netz'};
    return res.data;
  }

  async function fetchDay(){
    var day = berlinDay();
    var out = await Promise.all([
      client.from('ph_needs').select('class_id,need,blocks').eq('day', day),
      client.from('ph_flows').select('id,from_class,to_class,blocks,active,created_at').eq('day', day).order('id', {ascending: true}),
      client.from('ph_day').select('block_index').eq('day', day)
    ]);
    out.forEach(function(r){ if(r.error) throw r.error; });
    return {needs: out[0].data || [], flows: out[1].data || [], day: out[2].data || []};
  }

  // Meldet jede Änderung an den drei Tabellen, damit alle Handys sofort aktuell sind
  function subscribe(onChange){
    var ch = client.channel('personalhilfe-live');
    ['ph_needs', 'ph_flows', 'ph_day'].forEach(function(t){
      ch.on('postgres_changes', {event: '*', schema: 'public', table: t}, function(){ onChange(); });
    });
    ch.subscribe(function(status){ if(status === 'SUBSCRIBED') onChange(); });
    return ch;
  }

  window.PH_BACKEND = {rpc: rpc, fetchDay: fetchDay, subscribe: subscribe, berlinDay: berlinDay};
})();
