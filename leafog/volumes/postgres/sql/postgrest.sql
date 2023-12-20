\c postgres;

create schema postgrest;

create table postgrest.conf
(
    key   text primary key not null,
    value text             not null
);
insert into  postgrest.conf values ('pgrst.db_schemas','public,auth');


create or replace function postgrest.pre_config()
    returns void as
$$
declare
    conf_row record;
begin
    -- Iterate over rows in postgrest.conf and set configurations
    for conf_row in select * from postgrest.conf
        loop
            execute format('select set_config(%L, %L, true)', conf_row.key, conf_row.value);
        end loop;
end;
$$ language plpgsql;

create or replace function postgrest.reload()
    returns trigger as
$$
begin
    notify pgrst, 'reload config';
    return new;
end ;
$$ language plpgsql;

---
create or replace function postgrest.change_grant()
    returns trigger as
$$
declare
    old_value_length int;
    new_value_length int;
begin

    if new.key = 'pgrst.db_schemas' THEN
        old_value_length := char_length(old.value);
        if old_value_length > 0 then
            execute 'revoke usage on schema  ' || old.value || ' from account,anon;';
            execute 'revoke all on all tables in schema ' || old.value || ' from account,anon;';
            execute 'revoke all on all routines in schema ' || old.value || ' FROM account, anon;';
            execute 'revoke all on all sequences in schema ' || old.value || ' FROM account, anon;';
            execute 'alter default privileges for role postgres in schema ' || old.value ||
                    ' revoke all on tables from anon,account;';
            execute 'alter default privileges for role postgres in schema ' || old.value ||
                    ' revoke all on routines from anon,account;';
            execute 'alter default privileges for role postgres in schema ' || old.value ||
                    ' revoke all on sequences from anon,account;';
        end if;
        new_value_length := char_length(new.value);
        if new_value_length > 0 then
            execute 'grant usage on schema ' || new.value || ' to account,anon;';
            execute 'grant all on all tables in schema ' || new.value || ' to account,anon;';
            execute 'grant all on all routines in schema ' || new.value || ' to account, anon;';
            execute 'grant all on all sequences in schema ' || new.value || ' to account, anon;';
            execute 'alter default privileges for role postgres in schema ' || new.value ||
                    ' grant all on tables to anon,account;';
            execute 'alter default privileges for role postgres in schema ' || new.value ||
                    ' grant all on routines to anon,account;';
            execute 'alter default privileges for role postgres in schema ' || new.value ||
                    ' grant all on sequences to anon,account;';
        end if;

    end if;
    return new;
end;
$$ language plpgsql;
---

--- check schemas
create or replace function postgrest.check_schemas()
    returns trigger as
$$
declare
    schema_names  text[];
    valid_schemas text[] := '{}';
    schema_item   text;
begin
    if new.key = 'pgrst.db_schemas' THEN
        schema_names := string_to_array(new.value, ',');

        foreach schema_item IN ARRAY schema_names
            loop
                if exists (select 1 from information_schema.schemata where schema_name = schema_item) then
                    valid_schemas := valid_schemas || schema_item;
                end if;
            end loop;
        new.value := array_to_string(valid_schemas, ',');
    end if;
    return new;
end;
$$ language plpgsql;
---

create trigger change_grant
    after insert or update or delete
    on postgrest.conf
    for each row
execute function postgrest.change_grant();


create trigger reload_conf
    after insert or update or delete
    on postgrest.conf
    for each row
execute function postgrest.reload();

create trigger check_schemas
    before insert or update
    on postgrest.conf
    for each row
execute function postgrest.check_schemas();

