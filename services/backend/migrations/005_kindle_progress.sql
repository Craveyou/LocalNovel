-- Extend the installed validator; keep 003/004 historical behavior byte-for-byte.
do $migration$
declare previous_check text;
begin
  select pg_get_expr(conbin, conrelid) into strict previous_check
    from pg_constraint where conrelid='document_progress'::regclass
      and conname='document_progress_locator_check';
  alter table document_progress drop constraint document_progress_locator_check;
  execute format($ddl$
    alter table document_progress add constraint document_progress_locator_check check (
      (%s) or coalesce(case
        when jsonb_typeof(locator)='object' and locator->>'format'='kindle'
          and jsonb_typeof(locator->'version')='number'
          and jsonb_typeof(locator->'profile')='string'
          and jsonb_typeof(locator->'textHash')='string'
          and jsonb_typeof(locator->'textOffset')='number'
          and jsonb_typeof(locator->'textLength')='number'
        then locator ?& array['format','version','profile','textHash','textOffset','textLength']
          and locator - array['format','version','profile','textHash','textOffset','textLength']='{}'::jsonb
          and (locator->>'version')::numeric=1
          and locator->>'profile'='kindle-text-v1'
          and locator->>'textHash' ~ '^[0-9a-f]{64}$'
          and (locator->>'textLength')::numeric between 1 and 2147483647
          and (locator->>'textLength')::numeric=trunc((locator->>'textLength')::numeric)
          and (locator->>'textOffset')::numeric between 0 and (locator->>'textLength')::numeric
          and (locator->>'textOffset')::numeric=trunc((locator->>'textOffset')::numeric)
        else false end,false))
    $ddl$,previous_check);
end $migration$;
