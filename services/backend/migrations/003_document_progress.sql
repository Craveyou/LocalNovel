-- v2 format locations are isolated from the TXT-only v1 table and wire format.
create table document_progress (
    user_id bigint not null references users(id) on delete cascade,
    book_hash bytea not null check(octet_length(book_hash)=32),
    file_size bigint not null check(file_size > 0 and file_size <= 9007199254740991),
    locator jsonb not null check(jsonb_typeof(locator)='object'
        and locator->>'format' in ('pdf','epub') and locator->>'version'='1'),
    read_at timestamptz not null check(read_at >= timestamptz '1970-01-01 00:00:00+00'
        and read_at <= timestamptz '9999-12-31 23:59:59.999+00'),
    device_id bigint not null,
    device_uid_order uuid not null,
    version bigint not null default 1 check(version > 0),
    primary key(user_id,book_hash,file_size),
    foreign key(device_id,user_id,device_uid_order) references devices(id,user_id,device_uid)
);
create index document_progress_device_idx on document_progress(device_id);
