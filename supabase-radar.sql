-- ═══════════════════════════════════════════════════════════════════
-- INBOUND RADAR — Supabase Edition
-- The whole "get-chased" engine inside Postgres. No server, no n8n,
-- no card, no new accounts. Uses pg_cron + pg_net (free tier).
--
-- Install: Supabase SQL editor → paste → replace PASTE_DISCORD_WEBHOOK_URL → Run.
-- Then: done. Digests land in Discord every 30 minutes.
-- Customize: edit the `kw` array in radar_process(), re-run the CREATE.
-- Tested live 2026-09-06: forum 200, digest delivered (Discord 204).
-- CC0.
-- ═══════════════════════════════════════════════════════════════════

create extension if not exists pg_cron;
create extension if not exists pg_net;

-- matches + their post state
create table if not exists radar_hits (
  id         text primary key,          -- 'f_<topicid>' | 'r_<postid>'
  source     text,
  title      text,
  url        text,
  matched    text,                      -- which keyword fired
  created_at timestamptz default now(),
  posted     boolean default false
);

create table if not exists radar_config (key text primary key, value text);
insert into radar_config(key, value)
values ('discord_webhook', 'PASTE_DISCORD_WEBHOOK_URL')
on conflict (key) do update set value = excluded.value;

-- safe text→jsonb cast (pg_net stores content as text)
create or replace function radar_json(txt text) returns jsonb
language plpgsql immutable as $h$
begin
  return txt::jsonb;
exception when others then return null;
end $h$;

-- fetch both sources (async via pg_net; responses land in net._http_response)
create or replace function radar_fetch() returns void language plpgsql as $f$
begin
  delete from net._http_response;  -- drop last cycle's leftovers
  perform net.http_get('https://community.n8n.io/latest.json', '{}'::jsonb,
    jsonb_build_object('User-Agent','inbound-radar/1.0'), 8000);
  perform net.http_get('https://api.pullpush.io/reddit/search/submission/?subreddit=n8n&sort=desc&size=25','{}'::jsonb,
    jsonb_build_object('User-Agent','inbound-radar/1.0'), 8000);
end $f$;

-- match + dedupe + digest to Discord
create or replace function radar_process() returns void language plpgsql as $f$
declare
  kw text[] := array['zapier','make.com','alternativ','invoice','reminder','follow up','follow-up',
    'scrap','cold email','lead gen','leads','code node','self-host','self host','selfhost',
    'supabase','webhook','google sheet','openai','telegram','gmail','smtp','crm'];
  r record; h record; t text; mk text; i int; cnt int; lines text; digest text; wh text; cj jsonb;
begin
  select value into wh from radar_config where key='discord_webhook';

  for r in select * from net._http_response loop
    cj := radar_json(r.content);
    continue when cj is null;

    if cj ? 'topic_list' then  -- n8n forum (Discourse)
      for h in select e->>'id' as id, e->>'slug' as slug, e->>'title' as title
               from jsonb_array_elements(cj->'topic_list'->'topics') e
               where not coalesce((e->>'pinned')::boolean, false) loop
        t := lower(coalesce(h.title,'')); mk := null;
        for i in 1..coalesce(array_length(kw,1),0) loop
          if strpos(t, kw[i]) > 0 then mk := kw[i]; exit; end if;
        end loop;
        continue when mk is null;
        begin
          insert into radar_hits(id,source,title,url,matched)
          values ('f_'||h.id,'n8n forum',h.title,
                  'https://community.n8n.io/t/'||h.slug||'/'||h.id, mk);
        exception when unique_violation then null; end;
      end loop;
    end if;

    if jsonb_typeof(cj->'data') = 'array' then  -- reddit via PullPush
      for h in select e->>'id' as id, e->>'title' as title, e->>'permalink' as permalink
               from jsonb_array_elements(cj->'data') e loop
        t := lower(coalesce(h.title,'')); mk := null;
        for i in 1..coalesce(array_length(kw,1),0) loop
          if strpos(t, kw[i]) > 0 then mk := kw[i]; exit; end if;
        end loop;
        continue when mk is null;
        begin
          insert into radar_hits(id,source,title,url,matched)
          values ('r_'||h.id,'r/n8n',h.title,'https://www.reddit.com'||h.permalink, mk);
        exception when unique_violation then null; end;
      end loop;
    end if;
  end loop;

  -- digest unposted hits → Discord
  select count(*) into cnt from radar_hits where not posted;
  if cnt > 0 and wh is not null then
    select string_agg('• ['||source||'] '||title||E'\n  '||url||'  ("'||matched||'")', E'\n\n')
      into lines
      from (select * from radar_hits where not posted order by created_at desc limit 10) x;
    digest := '📬 '||cnt::text||' question(s) you can answer today:'||E'\n\n'||lines
      || (case when cnt > 10 then E'\n\n(+'||(cnt-10)::text||' more in the DB)' else '' end)
      || E'\n\nAnswer help-first — the repo link does the pitching.';
    perform net.http_post(url := wh,
      headers := jsonb_build_object('Content-Type','application/json'),
      body    := jsonb_build_object('username','Inbound Radar','content', digest));
    update radar_hits set posted = true where not posted;
  end if;

  delete from net._http_response where radar_json(content) ? 'topic_list'
      or radar_json(content) ? 'data'
      or (jsonb_typeof(radar_json(content))='object' and radar_json(content) ? 'error');
end $f$;

-- schedules (fetch at :00/:30, process 5 min later so responses have landed)
select cron.unschedule(jobid) from cron.job where jobname in ('radar-fetch','radar-process');
select cron.schedule('radar-fetch',   '*/30 * * * *', 'select radar_fetch()');
select cron.schedule('radar-process', '5,35 * * * *', 'select radar_process()');

-- quick manual test:
-- select radar_fetch();  -- wait ~10s, then:
-- select radar_process();
-- select status_code from net._http_response where radar_json(content) is null;  -- 204 = Discord delivered
-- select * from radar_hits order by created_at desc limit 10;
