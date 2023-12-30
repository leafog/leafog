\c postgres;

create schema postgrest;

create table postgrest.conf
(
    key   text primary key not null,
    value text             not null
);



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
    schema_names     text[];
    schema_item      text;
    old_schema_names text[];
    ole_schema_item  text;
begin

    if new.key = 'pgrst.db_schemas' THEN
        old_value_length := char_length(old.value);
        if old_value_length > 0 then
            old_schema_names := string_to_array(old.value, ',');
            foreach ole_schema_item in array old_schema_names
                loop
                    execute 'drop function if exists ' || ole_schema_item || '.graphql;';
                end loop;

            execute 'revoke usage on schema  ' || old.value || ' from account,anon;';
            execute 'revoke all on all tables in schema ' || old.value || ' from account,anon;';
            execute 'revoke all on all functions in schema ' || old.value || ' FROM account, anon;';
            execute 'revoke all on all sequences in schema ' || old.value || ' FROM account, anon;';
            execute 'alter default privileges for role postgres in schema ' || old.value ||
                    ' revoke all on tables from anon,account;';
            execute 'alter default privileges for role postgres in schema ' || old.value ||
                    ' revoke all on functions from anon,account;';
            execute 'alter default privileges for role postgres in schema ' || old.value ||
                    ' revoke all on sequences from anon,account;';
        end if;
        new_value_length := char_length(new.value);
        if new_value_length > 0 then
            schema_names := string_to_array(new.value, ',');
            foreach schema_item IN ARRAY schema_names
                loop
                    execute '
                        create or replace function ' || schema_item || '.graphql(
                            "operationName" text default null,
                            query text default null,
                            variables jsonb default null,
                            extensions jsonb default null
                        )
                            returns jsonb
                            language sql
                        as
                        $BODY$
                        select graphql.resolve(
                                       query := query,
                                       variables := coalesce(variables, ''{}''),
                                       "operationName" := "operationName",
                                       extensions := extensions
                               );
                        $BODY$;
                        ';
                end loop;
            execute 'grant usage on schema ' || new.value || ' to account,anon;';
            execute 'grant all on all tables in schema ' || new.value || ' to account,anon;';
            execute 'grant all on all functions in schema ' || new.value || ' to account, anon;';
            execute 'grant all on all sequences in schema ' || new.value || ' to account, anon;';
            execute 'alter default privileges for role postgres in schema ' || new.value ||
                    ' grant all on tables to anon,account;';
            execute 'alter default privileges for role postgres in schema ' || new.value ||
                    ' grant all on functions to anon,account;';
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


-- watch CREATE and ALTER
create or replace function postgrest.pgrst_ddl_watch() returns event_trigger AS
$$
declare
    cmd record;
begin
    for cmd in select * from pg_event_trigger_ddl_commands()
        loop
            if cmd.command_tag IN (
                                   'CREATE SCHEMA', 'ALTER SCHEMA', 'CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO',
                                   'ALTER TABLE', 'CREATE FOREIGN TABLE', 'ALTER FOREIGN TABLE', 'CREATE VIEW',
                                   'ALTER VIEW', 'CREATE MATERIALIZED VIEW', 'ALTER MATERIALIZED VIEW',
                                   'CREATE FUNCTION', 'ALTER FUNCTION', 'CREATE TRIGGER', 'CREATE TYPE', 'ALTER TYPE',
                                   'CREATE RULE', 'COMMENT'
                )
                -- don't notify in case of CREATE TEMP table or other objects created on pg_temp
                and cmd.schema_name is distinct from 'pg_temp'
            then
                notify pgrst, 'reload schema';
            end if;
        end loop;
end;
$$ language plpgsql;

-- watch DROP
create or replace function postgrest.pgrst_drop_watch() returns event_trigger AS
$$
declare
    obj record;
begin
    for obj in
        select *
        from pg_event_trigger_dropped_objects()
        loop
            if obj.object_type in (
                                   'schema', 'table', 'foreign table', 'view', 'materialized view', 'function',
                                   'trigger', 'type', 'rule'
                )
                and obj.is_temporary is false -- no pg_temp objects
            then
                notify pgrst, 'reload schema';
            end if;
        end loop;
end;
$$ language plpgsql;


create event trigger pgrst_ddl_watch
    on ddl_command_end
execute procedure postgrest.pgrst_ddl_watch();

create event trigger pgrst_drop_watch
    on sql_drop
execute procedure postgrest.pgrst_drop_watch();


