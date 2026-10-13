-- =====================================================================
-- Personalhilfe: Datenbank-Schema für Supabase
--
-- Einrichtung: Im Supabase-Dashboard "SQL Editor" öffnen, diese Datei
-- einfügen und "Run" drücken. Das Skript kann gefahrlos mehrfach laufen.
--
-- Die Passwörter (Schulcode, Schulleitung) stehen NICHT in dieser Datei.
-- Sie werden danach einmalig mit einem eigenen Befehl gesetzt (siehe README):
--   select public.ph_set_secrets('DEIN-SCHULCODE', 'DEIN-ADMIN-PASSWORT');
--
-- Sicherheitsmodell:
--   * Die Tabellen sind für die Öffentlichkeit nur LESBAR (Row Level Security).
--   * Geschrieben wird ausschließlich über die ph_*-Funktionen unten.
--   * Jede Schreib-Funktion prüft den Schulcode, Admin-Funktionen zusätzlich
--     eine Schulleitungs-Anmeldung. Ohne gesetzte Passwörter ist alles gesperrt.
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

-- Aktueller Zeitraum des Tages: 0 = 1. Block ... 3 = 3. Block, 4 = Schultag beendet
create table if not exists public.ph_day (
  day         date primary key,
  block_index int  not null default 0 check (block_index between 0 and 4)
);

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

-- 2) Zugriffsschutz (Row Level Security) ------------------------------

alter table public.ph_needs    enable row level security;
alter table public.ph_flows    enable row level security;
alter table public.ph_day      enable row level security;
alter table public.ph_secrets  enable row level security;
alter table public.ph_sessions enable row level security;
alter table public.ph_attempts enable row level security;

drop policy if exists ph_read_needs on public.ph_needs;
drop policy if exists ph_read_flows on public.ph_flows;
drop policy if exists ph_read_day   on public.ph_day;
create policy ph_read_needs on public.ph_needs for select to anon, authenticated using (true);
create policy ph_read_flows on public.ph_flows for select to anon, authenticated using (true);
create policy ph_read_day   on public.ph_day   for select to anon, authenticated using (true);

revoke all on public.ph_needs, public.ph_flows, public.ph_day,
              public.ph_secrets, public.ph_sessions, public.ph_attempts
  from anon, authenticated;
grant select on public.ph_needs, public.ph_flows, public.ph_day to anon, authenticated;

-- Live-Abgleich: Änderungen an den drei lesbaren Tabellen an alle Handys melden
do $rt$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin alter publication supabase_realtime add table public.ph_needs; exception when duplicate_object then null; end;
    begin alter publication supabase_realtime add table public.ph_flows; exception when duplicate_object then null; end;
    begin alter publication supabase_realtime add table public.ph_day;   exception when duplicate_object then null; end;
  end if;
end
$rt$;

-- 3) Interne Hilfsfunktionen (von außen nicht aufrufbar) --------------

create or replace function public.ph_blocks() returns text[]
language sql immutable set search_path = '' as
$fn$ select array['1. Block','2. Block','Mittagessen','3. Block']::text[] $fn$;

create or replace function public.ph_today() returns date
language sql stable set search_path = '' as
$fn$ select (now() at time zone 'Europe/Berlin')::date $fn$;

create or replace function public.ph_fail(p_error text) returns jsonb
language sql immutable set search_path = '' as
$fn$ select jsonb_build_object('ok', false, 'error', p_error) $fn$;

create or replace function public.ph_code_ok(p_code text) returns boolean
language sql stable security definer set search_path = public, extensions as
$fn$
  select exists (
    select 1 from ph_secrets
    where k = 'school_code' and v = crypt(coalesce(p_code, ''), v)
  )
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

-- 4) Öffentliche Funktionen (alle geben jsonb zurück: {ok:true,...} oder {ok:false,error:...})

-- Schulcode prüfen
create or replace function public.ph_login_code(p_code text) returns jsonb
language plpgsql stable security definer set search_path = public, extensions as
$fn$
begin
  if ph_code_ok(p_code) then return jsonb_build_object('ok', true); end if;
  return ph_fail('code');
end
$fn$;

-- Schulleitung anmelden: gibt eine Sitzungs-Kennung zurück (14 Tage gültig).
-- Nach 5 Fehlversuchen ist die Anmeldung 10 Minuten gesperrt.
create or replace function public.ph_admin_login(p_code text, p_password text) returns jsonb
language plpgsql volatile security definer set search_path = public, extensions as
$fn$
declare
  v_fails int;
  v_first timestamptz;
  v_token text;
begin
  if not ph_code_ok(p_code) then return ph_fail('code'); end if;

  select fails, first_fail into v_fails, v_first from ph_attempts where kind = 'admin' for update;
  if found and v_fails >= 5 and now() - v_first < interval '10 minutes' then
    return ph_fail('gesperrt');
  end if;

  if exists (select 1 from ph_secrets
             where k = 'admin_password' and v = crypt(coalesce(p_password, ''), v)) then
    delete from ph_attempts where kind = 'admin';
    delete from ph_sessions where expires_at < now();
    v_token := encode(gen_random_bytes(24), 'hex');
    insert into ph_sessions (token_hash, expires_at)
      values (encode(digest(v_token, 'sha256'), 'hex'), now() + interval '14 days');
    return jsonb_build_object('ok', true, 'token', v_token);
  end if;

  insert into ph_attempts (kind, fails, first_fail) values ('admin', 1, now())
  on conflict (kind) do update set
    fails = case when now() - ph_attempts.first_fail >= interval '10 minutes'
                 then 1 else ph_attempts.fails + 1 end,
    first_fail = case when now() - ph_attempts.first_fail >= interval '10 minutes'
                      then now() else ph_attempts.first_fail end;
  return ph_fail('passwort');
end
$fn$;

-- Bedarf einer Klasse für heute setzen (0 = kein Bedarf)
create or replace function public.ph_set_need(
  p_code text, p_class text, p_need int, p_blocks text[]
) returns jsonb
language plpgsql volatile security definer set search_path = public, extensions as
$fn$
declare
  v_blocks text[];
begin
  if not ph_code_ok(p_code) then return ph_fail('code'); end if;
  if p_class is null or char_length(p_class) not between 1 and 40
     or p_need is null or p_need not between 0 and 9 then
    return ph_fail('ungueltig');
  end if;

  v_blocks := case when p_need = 0 then '{}'::text[] else ph_clean_blocks(p_blocks) end;

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
  v_day      date := ph_today();
  v_need     ph_needs%rowtype;
  v_required text[];
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
  if not ph_code_ok(p_code) then return ph_fail('code'); end if;
  if p_from is null or p_to is null or p_from = p_to
     or char_length(p_from) not between 1 and 40
     or char_length(p_to)   not between 1 and 40 then
    return ph_fail('ungueltig');
  end if;

  select * into v_need from ph_needs where day = v_day and class_id = p_to for update;
  if not found or v_need.need <= 0 then return ph_fail('kein_bedarf'); end if;

  v_required := case when cardinality(v_need.blocks) = 0 then ph_blocks() else v_need.blocks end;
  select coalesce((select block_index from ph_day where day = v_day), 0) into v_current;
  v_cand := ph_clean_blocks(p_blocks);

  foreach b in array v_cand loop
    v_idx := array_position(ph_blocks(), b) - 1;   -- 0-basiert wie block_index
    if v_idx < v_current then v_past := v_past + 1; continue; end if;
    if not (b = any (v_required)) then v_other := v_other + 1; continue; end if;

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

-- Einsatz beenden
create or replace function public.ph_end_flow(p_code text, p_id bigint) returns jsonb
language plpgsql volatile security definer set search_path = public, extensions as
$fn$
begin
  if not ph_code_ok(p_code) then return ph_fail('code'); end if;
  update ph_flows set active = false where id = p_id and active;
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
  if p_from is null or p_to is null or p_from = p_to
     or char_length(p_from) not between 1 and 40
     or char_length(p_to)   not between 1 and 40 then
    return ph_fail('ungueltig');
  end if;

  select coalesce((select block_index from ph_day where day = v_day), 0) into v_current;
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

-- Bedarf einer Klasse schließen
create or replace function public.ph_admin_clear_need(p_token text, p_class text) returns jsonb
language plpgsql volatile security definer set search_path = public, extensions as
$fn$
begin
  if not ph_admin_ok(p_token) then return ph_fail('token'); end if;
  if p_class is null or char_length(p_class) not between 1 and 40 then return ph_fail('ungueltig'); end if;
  insert into ph_needs (day, class_id, need, blocks) values (ph_today(), p_class, 0, '{}')
  on conflict (day, class_id) do update set need = 0, blocks = '{}', updated_at = now();
  return jsonb_build_object('ok', true);
end
$fn$;

-- Aktuellen Zeitraum des Tages setzen (0 bis 3, 4 = Schultag beendet)
create or replace function public.ph_admin_set_block(p_token text, p_index int) returns jsonb
language plpgsql volatile security definer set search_path = public, extensions as
$fn$
begin
  if not ph_admin_ok(p_token) then return ph_fail('token'); end if;
  if p_index is null or p_index not between 0 and 4 then return ph_fail('ungueltig'); end if;
  insert into ph_day (day, block_index) values (ph_today(), p_index)
  on conflict (day) do update set block_index = excluded.block_index;
  return jsonb_build_object('ok', true);
end
$fn$;

-- 6) Passwörter setzen (nur im SQL Editor, von außen NICHT aufrufbar) --

create or replace function public.ph_set_secrets(p_school_code text, p_admin_password text) returns void
language plpgsql volatile security definer set search_path = public, extensions as
$fn$
begin
  if char_length(coalesce(p_school_code, '')) < 8 then
    raise exception 'Der Schulcode braucht mindestens 8 Zeichen';
  end if;
  if char_length(coalesce(p_admin_password, '')) < 8 then
    raise exception 'Das Admin-Passwort braucht mindestens 8 Zeichen';
  end if;
  insert into ph_secrets (k, v) values ('school_code', crypt(p_school_code, gen_salt('bf', 10)))
    on conflict (k) do update set v = excluded.v;
  insert into ph_secrets (k, v) values ('admin_password', crypt(p_admin_password, gen_salt('bf', 10)))
    on conflict (k) do update set v = excluded.v;
  delete from ph_sessions;
  delete from ph_attempts;
end
$fn$;

-- 7) Berechtigungen: intern gesperrt, nur die API-Funktionen für die App freigeben

revoke all on function public.ph_blocks()                              from public, anon, authenticated;
revoke all on function public.ph_today()                               from public, anon, authenticated;
revoke all on function public.ph_fail(text)                            from public, anon, authenticated;
revoke all on function public.ph_code_ok(text)                         from public, anon, authenticated;
revoke all on function public.ph_admin_ok(text)                        from public, anon, authenticated;
revoke all on function public.ph_clean_blocks(text[])                  from public, anon, authenticated;
revoke all on function public.ph_set_secrets(text, text)               from public, anon, authenticated;

revoke all on function public.ph_login_code(text)                      from public;
revoke all on function public.ph_admin_login(text, text)               from public;
revoke all on function public.ph_set_need(text, text, int, text[])     from public;
revoke all on function public.ph_send(text, text, text, text[])        from public;
revoke all on function public.ph_end_flow(text, bigint)                from public;
revoke all on function public.ph_admin_assign(text, text, text, text[]) from public;
revoke all on function public.ph_admin_clear_need(text, text)          from public;
revoke all on function public.ph_admin_set_block(text, int)            from public;

grant execute on function public.ph_login_code(text)                      to anon, authenticated;
grant execute on function public.ph_admin_login(text, text)               to anon, authenticated;
grant execute on function public.ph_set_need(text, text, int, text[])     to anon, authenticated;
grant execute on function public.ph_send(text, text, text, text[])        to anon, authenticated;
grant execute on function public.ph_end_flow(text, bigint)                to anon, authenticated;
grant execute on function public.ph_admin_assign(text, text, text, text[]) to anon, authenticated;
grant execute on function public.ph_admin_clear_need(text, text)          to anon, authenticated;
grant execute on function public.ph_admin_set_block(text, int)            to anon, authenticated;
