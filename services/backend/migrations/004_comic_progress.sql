-- Extend, never rewrite, 003. Preserve validation of historical PDF/EPUB rows.
alter table document_progress drop constraint document_progress_locator_check;
alter table document_progress add constraint document_progress_locator_check check (
  coalesce(case
    when jsonb_typeof(locator) <> 'object' then false
    when locator->>'format' in ('pdf','epub') then locator->>'version' = '1'
    when locator->>'format' in ('cbz','cbr') then
      case when jsonb_typeof(locator->'version') = 'number'
        and jsonb_typeof(locator->'profile') = 'string'
        and jsonb_typeof(locator->'manifestHash') = 'string'
        and jsonb_typeof(locator->'pageKey') = 'string'
        and jsonb_typeof(locator->'page') = 'number'
        and jsonb_typeof(locator->'pageCount') = 'number'
        and jsonb_typeof(locator->'y') = 'number'
      then
        locator ?& array['format','version','profile','manifestHash','pageKey','page','pageCount','y']
        and locator - array['format','version','profile','manifestHash','pageKey','page','pageCount','y'] = '{}'::jsonb
        and (locator->>'version')::numeric = 1
        and locator->>'profile' = 'comic-order-v1'
        and locator->>'manifestHash' ~ '^[0-9a-f]{64}$'
        and locator->>'pageKey' ~ '^[0-9a-f]{64}$'
        and (locator->>'page')::numeric = trunc((locator->>'page')::numeric)
        and (locator->>'pageCount')::numeric = trunc((locator->>'pageCount')::numeric)
        and (locator->>'pageCount')::numeric between 1 and 10000
        and (locator->>'page')::numeric >= 0
        and (locator->>'page')::numeric < (locator->>'pageCount')::numeric
        and (locator->>'y')::numeric between 0 and 1
        and (locator->>'y')::numeric = round((locator->>'y')::numeric, 6)
      else false end
    else false
  end, false)
);
