-- =====================================================================
-- Personalhilfe: Datenbank-Schema für Supabase
--
-- Einrichtung: Im Supabase-Dashboard "SQL Editor" öffnen, diese Datei
-- einfügen und "Run" drücken. Das Skript kann gefahrlos mehrfach laufen
-- und bringt auch ältere Fassungen auf den aktuellen Stand.
--
-- Die Passwörter (Schulcode, Schulleitung) stehen NICHT in dieser Datei.
-- Sie werden danach einmalig mit einem eigenen Befehl gesetzt (siehe README):
--   select public.ph_set_secrets('DEIN-SCHULCODE', 'DEIN-ADMIN-PASSWORT');
--
-- Sicherheitsmodell:
--   * Die Tabellen sind von außen weder lesbar noch schreibbar.
--   * Gelesen und geschrieben wird ausschließlich über die ph_*-Funktionen unten.
--   * Jede Funktion prüft den Schulcode, Admin-Funktionen zusätzlich
--     eine Schulleitungs-Anmeldung. Ohne gesetzte Passwörter ist alles gesperrt.
--   * Fehlversuche werden pro Absender gezählt und bremsen das Durchprobieren.
--   * Der Live-Abgleich sendet nur ein inhaltsloses Signal "es hat sich etwas
--     geändert"; die Daten selbst holt jedes Handy mit dem Schulcode ab.
--   * Gespeichert wird nur der heutige Tag; ältere Tage werden automatisch gelöscht.
--   * Es werden nur Klassen-Kennungen, Zeiträume und Zahlen gespeichert,
--     keine Namen von Kindern oder Mitarbeitenden.
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

-- 1) Tabellen ---------------------------------------------------------

create table if not exists public.ph_needs (
  day        date        not null,
  class_id   text        not null check (char_length(class_id) between 1 and 40),
  need       int         not null default 0 check (need between 0 and 9),
  blocks     text[]      not null default '{}',
  updated_at timestamptz not null default now(),
  primary key (day, class_id)
);

create table if not exists public.ph_flows (
  id         bigint generated always as identity primary key,
  day        date        not null,
  from_class text        not null check (char_length(from_class) between 1 and 40),
  to_class   text        not null check (char_length(to_class) between 1 and 40),
  blocks     text[]      not null check (cardinality(blocks) > 0),
  active     boolean     not null default true,
  created_at timestamptz not null default now()
);
create index if not exists ph_flows_day_idx on public.ph_flows (day);

-- Manueller Eingriff der Schulleitung in den Zeitraum des Tages.
-- block_index: 0 = 1. Block ... 3 = 3. Block, 4 = Schultag beendet.
-- auto_at_set: welcher Zeitraum laut Uhr galt, als die Schulleitung umgeschaltet hat.
-- Sobald die Uhr danach den nächsten Wechsel erreicht, übernimmt wieder die Uhr.
create table if not exists public.ph_day (
  day         date primary key,
  block_index int  not null default 0 check (block_index between 0 and 4)
);
alter table public.ph_day add column if not exists auto_at_set int not null default 0;

-- Nur intern: gehashte Passwörter, Schulleitungs-Sitzungen, Fehlversuche
create table if not exists public.ph_secrets (k text primary key, v text not null);
create table if not exists public.ph_sessions (
  token_hash text primary key,
  expires_at timestamptz not null
);
create table if not exists public.ph_attempts (
  kind       text primary key,
  fails      int         not null default 0,
  first_fail timestamptz not null default now()
);

-- 2) Zugriffsschutz: keine direkten Lese- oder Schreibrechte von außen ----

alter table public.ph_needs    enable row level security;
alter table public.ph_flows    enable row level security;
alter table public.ph_day      enable row level security;
alter table public.ph_secrets  enable row level security;
alter table public.ph_sessions enable row level security;
alter table public.ph_attempts enable row level security;

-- Frühere Fassungen erlaubten allen das Lesen. Das wird hier zurückgenommen.
drop policy if exists ph_read_needs on public.ph_needs;
drop policy if exists ph_read_flows on public.ph_flows;
drop policy if exists ph_read_day   on public.ph_day;

revoke all on public.ph_needs, public.ph_flows, public.ph_day,
              public.ph_secrets, public.ph_sessions, public.ph_attempts
  from anon, authenticated;

-- Frühere Fassungen haben die Tabellen selbst live verteilt (mit Inhalt). Abschalten.
do $rt$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin alter publication supabase_realtime drop table public.ph_needs; exception when others then null; end;
    begin alter publication supabase_realtime drop table public.ph_flows; exception when others then null; end;
    begin alter publication supabase_realtime drop table public.ph_day;   exception when others then null; end;
  end if;
end
$rt$;

-- 3) Interne Hilfsfunktionen (von außen nicht aufrufbar) --------------

create or replace function public.ph_blocks() returns text[]
language sql immutable set search_path = '' as
$fn$ select array['1. Block','2. Block','Mittagessen','3. Block']::text[] $fn$;

-- Uhrzeit, zu der der jeweilige Zeitraum endet (deutsche Zeit, an allen Tagen gleich).
-- Reihenfolge wie ph_blocks(). Zum Ändern hier anpassen und die Datei erneut ausführen.
create or replace function public.ph_block_ends() returns time[]
language sql immutable set search_path = '' as
$fn$ select array['10:30','11:45','12:45','14:25']::time[] $fn$;

create or replace function public.ph_today() returns date
language sql stable set search_path = '' as
$fn$ select (now() at time zone 'Europe/Berlin')::date $fn$;

create or replace function public.ph_fail(p_error text) returns jsonb
language sql immutable set search_path = '' as
$fn$ select jsonb_build_object('ok', false, 'error', p_error) $fn$;

-- Zeitraum laut Uhr: Anzahl der heute schon erreichten Endzeiten (0 bis 4)
create or replace function public.ph_auto_block() returns int
language sql stable set search_path = public as
$fn$
  select count(*)::int from unnest(ph_block_ends()) as e
  where e <= (now() at time zone 'Europe/Berlin')::time
$fn$;

-- Tatsächlich geltender Zeitraum: Uhr, außer die Schulleitung hat seit dem
-- letzten Uhr-Wechsel manuell umgeschaltet.
create or replace function public.ph_current_block() returns int
language plpgsql stable security definer set search_path = public as
$fn$
declare
  v_auto int := ph_auto_block();
  v_row  ph_day%rowtype;
begin
  select * into v_row from ph_day where day = ph_today();
  if not found then return v_auto; end if;
  if v_auto > v_row.auto_at_set then return greatest(v_auto, v_row.block_index); end if;
  return v_row.block_index;
end
$fn$;

-- Absender einer Anfrage, für das Zählen von Fehlversuchen.
-- cf-connecting-ip setzt der Supabase-Eingang selbst, der Absender kann ihn nicht fälschen.
-- Ist gar kein Absender erkennbar, gibt es null zurück: dann wird nicht gesperrt, damit nicht
-- alle Handys in einem gemeinsamen Zähler landen und sich gegenseitig aussperren.
create or replace function public.ph_client_key() returns text
language plpgsql stable set search_path = '' as
$fn$
declare
  v_h json;
begin
  begin
    v_h := nullif(current_setting('request.headers', true), '')::json;
  exception when others then v_h := null;
  end;
  return nullif(trim(coalesce(v_h->>'cf-connecting-ip', v_h->>'x-real-ip',
                              split_part(v_h->>'x-forwarded-for', ',', 1))), '');
end
$fn$;

create or replace function public.ph_code_ok(p_code text) returns boolean
language sql stable security definer set search_path = public, extensions as
$fn$
  select exists (
    select 1 from ph_secrets
    where k = 'school_code' and v = crypt(coalesce(p_code, ''), v)
  )
$fn$;

-- Ist dieser Absender gerade wegen zu vieler Fehlversuche gesperrt?
create or replace function public.ph_is_locked(p_kind text, p_max int, p_window interval) returns boolean
language sql stable security definer set search_path = public as
$fn$
  select exists (
    select 1 from ph_attempts
    where kind = p_kind and fails >= p_max and now() - first_fail < p_window
  )
$fn$;

-- Fehlversuch zählen (Zähler beginnt nach Ablauf des Zeitfensters neu)
create or replace function public.ph_note_fail(p_kind text, p_window interval) returns void
language sql volatile security definer set search_path = public as
$fn$
  insert into ph_attempts (kind, fails, first_fail) values (p_kind, 1, now())
  on conflict (kind) do update set
    fails = case when now() - ph_attempts.first_fail >= p_window
                 then 1 else ph_attempts.fails + 1 end,
    first_fail = case when now() - ph_attempts.first_fail >= p_window
                      then now() else ph_attempts.first_fail end
$fn$;

-- Schulcode prüfen, mit Bremse: 30 Fehlversuche pro Absender in 15 Minuten.
-- Gibt null zurück, wenn alles stimmt, sonst den Fehlercode.
create or replace function public.ph_check_code(p_code text) returns text
language plpgsql volatile security definer set search_path = public as
$fn$
declare
  v_kind text := 'code:' || ph_client_key();   -- null, wenn kein Absender erkennbar
begin
  if v_kind is not null and ph_is_locked(v_kind, 30, interval '15 minutes') then return 'gesperrt'; end if;
  if ph_code_ok(p_code) then return null; end if;
  if v_kind is not null then perform ph_note_fail(v_kind, interval '15 minutes'); end if;
  return 'code';
end
$fn$;

create or replace function public.ph_admin_ok(p_token text) returns boolean
language sql stable security definer set search_path = public, extensions as
$fn$
  select exists (
    select 1 from ph_sessions
    where token_hash = encode(digest(coalesce(p_token, ''), 'sha256'), 'hex')
      and expires_at > now()
  )
$fn$;

-- Klassen-Kennungen wie in der App: Kleinbuchstaben, Ziffern, Bindestrich, Unterstrich
create or replace function public.ph_class_ok(p_class text) returns boolean
language sql immutable set search_path = '' as
$fn$ select coalesce(p_class ~ '^[a-z0-9_-]{1,40}$', false) $fn$;

-- Blöcke bereinigen: nur bekannte, ohne Doppelte, in Tagesreihenfolge
create or replace function public.ph_clean_blocks(p_blocks text[]) returns text[]
language sql immutable set search_path = public as
$fn$
  select coalesce(
    array_agg(b order by array_position(ph_blocks(), b)),
    '{}'::text[]
  )
  from (select distinct b from unnest(coalesce(p_blocks, '{}'::text[])) as b
        where b = any (ph_blocks())) s
$fn$;

-- Ältere Tage, abgelaufene Sitzungen und alte Fehlversuche löschen.
-- Läuft bei jeder Abfrage mit, löscht aber nur, wenn es wirklich Altes gibt.
create or replace function public.ph_cleanup() returns void
language plpgsql volatile security definer set search_path = public as
$fn$
declare
  v_day date := ph_today();
begin
  if exists (select 1 from ph_needs where day < v_day) then delete from ph_needs where day < v_day; end if;
  if exists (select 1 from ph_flows where day < v_day) then delete from ph_flows where day < v_day; end if;
  if exists (select 1 from ph_day   where day < v_day) then delete from ph_day   where day < v_day; end if;
  if exists (select 1 from ph_sessions where expires_at < now()) then
    delete from ph_sessions where expires_at < now();
  end if;
  if exists (select 1 from ph_attempts where first_fail < now() - interval '1 day') then
    delete from ph_attempts where first_fail < now() - interval '1 day';
  end if;
end
$fn$;

-- Live-Signal: meldet allen Handys "neu laden", ohne Inhalt.
create or replace function public.ph_notify() returns trigger
language plpgsql security definer set search_path = public as
$fn$
begin
  begin
    perform realtime.send('{}'::jsonb, 'changed', 'personalhilfe', false);
  exception when others then
    null; -- Ohne Live-Dienst laden die Handys trotzdem regelmäßig neu
  end;
  return null;
end
$fn$;

drop trigger if exists ph_needs_notify on public.ph_needs;
drop trigger if exists ph_flows_notify on public.ph_flows;
drop trigger if exists ph_day_notify   on public.ph_day;
create trigger ph_needs_notify after insert or update or delete on public.ph_needs
  for each row execute function public.ph_notify();
create trigger ph_flows_notify after insert or update or delete on public.ph_flows
  for each row execute function public.ph_notify();
create trigger ph_day_notify   after insert or update or delete on public.ph_day
  for each row execute function public.ph_notify();

-- 4) Öffentliche Funktionen (alle geben jsonb zurück: {ok:true,...} oder {ok:false,error:...})

-- Schulcode prüfen
create or replace function public.ph_login_code(p_code text) returns jsonb
language plpgsql volatile security definer set search_path = public, extensions as
$fn$
declare
  v_err text := ph_check_code(p_code);
begin
  if v_err is not null then return ph_fail(v_err); end if;
  return jsonb_build_object('ok', true);
end
$fn$;

-- Stand des heutigen Tages abholen (nur mit Schulcode)
create or replace function public.ph_fetch_day(p_code text) returns jsonb
language plpgsql volatile security definer set search_path = public, extensions as
$fn$
declare
  v_err text := ph_check_code(p_code);
  v_day date := ph_today();
begin
  if v_err is not null then return ph_fail(v_err); end if;
  perform ph_cleanup();
  return jsonb_build_object(
    'ok', true,
    'day', v_day,
    'block_index', ph_current_block(),
    'block_ends', (select jsonb_agg(to_char(e, 'HH24:MI')) from unnest(ph_block_ends()) as e),
    'needs', coalesce((select jsonb_agg(jsonb_build_object(
                'class_id', class_id, 'need', need, 'blocks', to_jsonb(blocks)))
              from ph_needs where day = v_day), '[]'::jsonb),
    'flows', coalesce((select jsonb_agg(jsonb_build_object(
                'id', id, 'from_class', from_class, 'to_class', to_class,
                'blocks', to_jsonb(blocks), 'active', active, 'created_at', created_at) order by id)
              from ph_flows where day = v_day), '[]'::jsonb)
  );
end
$fn$;

-- Schulleitung anmelden: gibt eine Sitzungs-Kennung zurück (14 Tage gültig).
-- Nach 5 Fehlversuchen ist die Anmeldung für diesen Absender 10 Minuten gesperrt.
create or replace function public.ph_admin_login(p_code text, p_password text) returns jsonb
language plpgsql volatile security definer set search_path = public, extensions as
$fn$
declare
  v_err   text := ph_check_code(p_code);
  v_kind  text := 'admin:' || ph_client_key();
  v_token text;
begin
  if v_err is not null then return ph_fail(v_err); end if;
  if v_kind is not null and ph_is_locked(v_kind, 5, interval '10 minutes') then return ph_fail('gesperrt'); end if;

  if exists (select 1 from ph_secrets
             where k = 'admin_password' and v = crypt(coalesce(p_password, ''), v)) then
    if v_kind is not null then delete from ph_attempts where kind = v_kind; end if;
    perform ph_cleanup();
    v_token := encode(gen_random_bytes(24), 'hex');
    insert into ph_sessions (token_hash, expires_at)
      values (encode(digest(v_token, 'sha256'), 'hex'), now() + interval '14 days');
    return jsonb_build_object('ok', true, 'token', v_token);
  end if;

  if v_kind is not null then perform ph_note_fail(v_kind, interval '10 minutes'); end if;
  return ph_fail('passwort');
end
$fn$;

-- Schulleitung abmelden: Sitzungs-Kennung sofort ungültig machen
create or replace function public.ph_admin_logout(p_token text) returns jsonb
language plpgsql volatile security definer set search_path = public, extensions as
$fn$
begin
  delete from ph_sessions where token_hash = encode(digest(coalesce(p_token, ''), 'sha256'), 'hex');
  return jsonb_build_object('ok', true);
end
$fn$;

-- Bedarf einer Klasse für heute setzen (0 = kein Bedarf).
-- Bei Bedarf > 0 muss mindestens ein Zeitraum gewählt sein; "leer" heißt nicht mehr "ganzer Tag".
create or replace function public.ph_set_need(
  p_code text, p_class text, p_need int, p_blocks text[]
) returns jsonb
language plpgsql volatile security definer set search_path = public, extensions as
$fn$
declare
  v_err    text := ph_check_code(p_code);
  v_blocks text[];
begin
  if v_err is not null then return ph_fail(v_err); end if;
  if not ph_class_ok(p_class) or p_need is null or p_need not between 0 and 9 then
    return ph_fail('ungueltig');
  end if;

  v_blocks := case when p_need = 0 then '{}'::text[] else ph_clean_blocks(p_blocks) end;
  if p_need > 0 and cardinality(v_blocks) = 0 then return ph_fail('zeitraum'); end if;

  perform ph_cleanup();
  insert into ph_needs (day, class_id, need, blocks)
    values (ph_today(), p_class, p_need, v_blocks)
  on conflict (day, class_id) do update
    set need = excluded.need, blocks = excluded.blocks, updated_at = now();
  return jsonb_build_object('ok', true);
end
$fn$;

-- Eine Klasse schickt jemanden. Die Funktion sperrt den Bedarf der Zielklasse,
-- dadurch können zwei gleichzeitige Zusagen nie denselben Zeitraum doppelt belegen.
-- Übernommen werden nur Zeiträume, die wirklich noch offen sind.
create or replace function public.ph_send(
  p_code text, p_from text, p_to text, p_blocks text[]
) returns jsonb
language plpgsql volatile security definer set search_path = public, extensions as
$fn$
declare
  v_err      text := ph_check_code(p_code);
  v_day      date := ph_today();
  v_need     ph_needs%rowtype;
  v_current  int;
  v_cand     text[];
  v_accept   text[] := '{}';
  v_past     int := 0;
  v_other    int := 0;
  v_idx      int;
  v_cnt      int;
  v_id       bigint;
  b          text;
begin
  if v_err is not null then return ph_fail(v_err); end if;
  if not ph_class_ok(p_from) or not ph_class_ok(p_to) or p_from = p_to then
    return ph_fail('ungueltig');
  end if;

  select * into v_need from ph_needs where day = v_day and class_id = p_to for update;
  if not found or v_need.need <= 0 then return ph_fail('kein_bedarf'); end if;

  v_current := ph_current_block();
  v_cand := ph_clean_blocks(p_blocks);

  foreach b in array v_cand loop
    v_idx := array_position(ph_blocks(), b) - 1;   -- 0-basiert wie block_index
    if v_idx < v_current then v_past := v_past + 1; continue; end if;
    if not (b = any (v_need.blocks)) then v_other := v_other + 1; continue; end if;

    select count(*) into v_cnt from ph_flows
      where day = v_day and to_class = p_to and active and b = any (blocks);
    if v_cnt >= v_need.need then v_other := v_other + 1; continue; end if;

    if exists (select 1 from ph_flows
               where day = v_day and to_class = p_to and from_class = p_from
                 and active and b = any (blocks)) then
      v_other := v_other + 1; continue;
    end if;

    v_accept := v_accept || b;
  end loop;

  if cardinality(v_accept) = 0 then
    return ph_fail(case when v_past > 0 and v_other = 0 then 'vergangen' else 'schon_gedeckt' end);
  end if;

  insert into ph_flows (day, from_class, to_class, blocks)
    values (v_day, p_from, p_to, v_accept) returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id, 'blocks', to_jsonb(v_accept));
end
$fn$;

-- Einsatz beenden. Nur durch eine beteiligte Klasse (schickend oder empfangend).
drop function if exists public.ph_end_flow(text, bigint);
create or replace function public.ph_end_flow(p_code text, p_class text, p_id bigint) returns jsonb
language plpgsql volatile security definer set search_path = public, extensions as
$fn$
declare
  v_err text := ph_check_code(p_code);
begin
  if v_err is not null then return ph_fail(v_err); end if;
  if not ph_class_ok(p_class) then return ph_fail('ungueltig'); end if;
  update ph_flows set active = false
    where id = p_id and day = ph_today() and active
      and (from_class = p_class or to_class = p_class);
  if not found then return ph_fail('nicht_gefunden'); end if;
  return jsonb_build_object('ok', true);
end
$fn$;

-- 5) Schulleitung (alle mit Sitzungs-Kennung aus ph_admin_login) ------

-- Personal von einer Klasse in eine andere schicken, unabhängig vom gemeldeten Bedarf
create or replace function public.ph_admin_assign(
  p_token text, p_from text, p_to text, p_blocks text[]
) returns jsonb
language plpgsql volatile security definer set search_path = public, extensions as
$fn$
declare
  v_day     date := ph_today();
  v_current int;
  v_blocks  text[];
  v_id      bigint;
begin
  if not ph_admin_ok(p_token) then return ph_fail('token'); end if;
  if not ph_class_ok(p_from) or not ph_class_ok(p_to) or p_from = p_to then
    return ph_fail('ungueltig');
  end if;

  v_current := ph_current_block();
  select coalesce(array_agg(b order by array_position(ph_blocks(), b)), '{}'::text[])
    into v_blocks
    from unnest(ph_clean_blocks(p_blocks)) as b
    where array_position(ph_blocks(), b) - 1 >= v_current;
  if cardinality(v_blocks) = 0 then return ph_fail('vergangen'); end if;

  insert into ph_flows (day, from_class, to_class, blocks)
    values (v_day, p_from, p_to, v_blocks) returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id, 'blocks', to_jsonb(v_blocks));
end
$fn$;

-- Beliebigen Einsatz beenden
create or replace function public.ph_admin_end_flow(p_token text, p_id bigint) returns jsonb
language plpgsql volatile security definer set search_path = public, extensions as
$fn$
begin
  if not ph_admin_ok(p_token) then return ph_fail('token'); end if;
  update ph_flows set active = false where id = p_id and day = ph_today() and active;
  if not found then return ph_fail('nicht_gefunden'); end if;
  return jsonb_build_object('ok', true);
end
$fn$;

-- Bedarf einer Klasse schließen
create or replace function public.ph_admin_clear_need(p_token text, p_class text) returns jsonb
language plpgsql volatile security definer set search_path = public, extensions as
$fn$
begin
  if not ph_admin_ok(p_token) then return ph_fail('token'); end if;
  if not ph_class_ok(p_class) then return ph_fail('ungueltig'); end if;
  insert into ph_needs (day, class_id, need, blocks) values (ph_today(), p_class, 0, '{}')
  on conflict (day, class_id) do update set need = 0, blocks = '{}', updated_at = now();
  return jsonb_build_object('ok', true);
end
$fn$;

-- Zeitraum manuell setzen (0 bis 3, 4 = Schultag beendet). Gilt, bis die Uhr
-- den nächsten Wechsel erreicht; danach übernimmt wieder die Uhr.
create or replace function public.ph_admin_set_block(p_token text, p_index int) returns jsonb
language plpgsql volatile security definer set search_path = public, extensions as
$fn$
declare
  v_auto int := ph_auto_block();
begin
  if not ph_admin_ok(p_token) then return ph_fail('token'); end if;
  if p_index is null or p_index not between 0 and 4 then return ph_fail('ungueltig'); end if;
  insert into ph_day (day, block_index, auto_at_set) values (ph_today(), p_index, v_auto)
  on conflict (day) do update set block_index = excluded.block_index, auto_at_set = excluded.auto_at_set;
  return jsonb_build_object('ok', true);
end
$fn$;

-- 6) Lebenszeichen für die GitHub Action, damit das Gratis-Projekt nicht pausiert.
-- Gibt keine Daten heraus, räumt nur Altes auf.
create or replace function public.ph_ping() returns jsonb
language plpgsql volatile security definer set search_path = public as
$fn$
begin
  perform ph_cleanup();
  return jsonb_build_object('ok', true);
end
$fn$;

-- 7) Passwörter setzen (nur im SQL Editor, von außen NICHT aufrufbar) --

create or replace function public.ph_set_secrets(p_school_code text, p_admin_password text) returns void
language plpgsql volatile security definer set search_path = public, extensions as
$fn$
begin
  if char_length(coalesce(p_school_code, '')) < 10 then
    raise exception 'Der Schulcode braucht mindestens 10 Zeichen';
  end if;
  if char_length(coalesce(p_admin_password, '')) < 12 then
    raise exception 'Das Admin-Passwort braucht mindestens 12 Zeichen';
  end if;
  if p_school_code = p_admin_password then
    raise exception 'Schulcode und Admin-Passwort müssen verschieden sein';
  end if;
  insert into ph_secrets (k, v) values ('school_code', crypt(p_school_code, gen_salt('bf', 10)))
    on conflict (k) do update set v = excluded.v;
  insert into ph_secrets (k, v) values ('admin_password', crypt(p_admin_password, gen_salt('bf', 10)))
    on conflict (k) do update set v = excluded.v;
  delete from ph_sessions;
  delete from ph_attempts;
end
$fn$;

-- 8) Berechtigungen: intern gesperrt, nur die API-Funktionen für die App freigeben

revoke all on function public.ph_blocks()                              from public, anon, authenticated;
revoke all on function public.ph_block_ends()                          from public, anon, authenticated;
revoke all on function public.ph_today()                               from public, anon, authenticated;
revoke all on function public.ph_fail(text)                            from public, anon, authenticated;
revoke all on function public.ph_auto_block()                          from public, anon, authenticated;
revoke all on function public.ph_current_block()                       from public, anon, authenticated;
revoke all on function public.ph_client_key()                          from public, anon, authenticated;
revoke all on function public.ph_code_ok(text)                         from public, anon, authenticated;
revoke all on function public.ph_is_locked(text, int, interval)        from public, anon, authenticated;
revoke all on function public.ph_note_fail(text, interval)             from public, anon, authenticated;
revoke all on function public.ph_check_code(text)                      from public, anon, authenticated;
revoke all on function public.ph_admin_ok(text)                        from public, anon, authenticated;
revoke all on function public.ph_class_ok(text)                        from public, anon, authenticated;
revoke all on function public.ph_clean_blocks(text[])                  from public, anon, authenticated;
revoke all on function public.ph_cleanup()                             from public, anon, authenticated;
revoke all on function public.ph_notify()                              from public, anon, authenticated;
revoke all on function public.ph_set_secrets(text, text)               from public, anon, authenticated;

revoke all on function public.ph_login_code(text)                         from public;
revoke all on function public.ph_fetch_day(text)                          from public;
revoke all on function public.ph_admin_login(text, text)                  from public;
revoke all on function public.ph_admin_logout(text)                       from public;
revoke all on function public.ph_set_need(text, text, int, text[])        from public;
revoke all on function public.ph_send(text, text, text, text[])           from public;
revoke all on function public.ph_end_flow(text, text, bigint)             from public;
revoke all on function public.ph_admin_assign(text, text, text, text[])   from public;
revoke all on function public.ph_admin_end_flow(text, bigint)             from public;
revoke all on function public.ph_admin_clear_need(text, text)             from public;
revoke all on function public.ph_admin_set_block(text, int)               from public;
revoke all on function public.ph_ping()                                   from public;

grant execute on function public.ph_login_code(text)                         to anon, authenticated;
grant execute on function public.ph_fetch_day(text)                          to anon, authenticated;
grant execute on function public.ph_admin_login(text, text)                  to anon, authenticated;
grant execute on function public.ph_admin_logout(text)                       to anon, authenticated;
grant execute on function public.ph_set_need(text, text, int, text[])        to anon, authenticated;
grant execute on function public.ph_send(text, text, text, text[])           to anon, authenticated;
grant execute on function public.ph_end_flow(text, text, bigint)             to anon, authenticated;
grant execute on function public.ph_admin_assign(text, text, text, text[])   to anon, authenticated;
grant execute on function public.ph_admin_end_flow(text, bigint)             to anon, authenticated;
grant execute on function public.ph_admin_clear_need(text, text)             to anon, authenticated;
grant execute on function public.ph_admin_set_block(text, int)               to anon, authenticated;
grant execute on function public.ph_ping()                                   to anon, authenticated;
