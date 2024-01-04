create role account;
create role anon;

grant usage on schema public to account,anon;
grant all on all tables in schema public to account,anon;
grant all on all functions in schema public to account,anon;
grant all on all sequences in schema public to account,anon;

alter default privileges for role postgres in schema public grant all on tables to anon,account;
alter default privileges for role postgres in schema public grant all on functions to anon,account;
alter default privileges for role postgres in schema public grant all on sequences to anon,account;



create schema keycloak;
create schema storage;
create schema auth;

grant usage on schema auth to account,anon;
grant all on all tables in schema auth to account,anon;
grant all on all functions in schema auth to account,anon;
grant all on all sequences in schema auth to account,anon;

alter default privileges for role postgres in schema auth grant all on tables to anon,account;
alter default privileges for role postgres in schema auth grant all on functions to anon,account;
alter default privileges for role postgres in schema auth grant all on sequences to anon,account;



create or replace function auth.uid() returns uuid
    language plpgsql
as
$$
declare
    uid uuid;
begin
    uid := ((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text)::uuid;
    return uid;
end
$$;



create or replace function auth.roles() returns jsonb
    language plpgsql
as
$$
declare
    roles jsonb;
begin
    roles := (((((current_setting('request.jwt.claims'::text, true))::json ->> 'realm_access'::text))::json ->>
               'roles'::text))::json;
    return roles;
end
$$;


create or replace function auth.email() returns text
    language plpgsql
as
$$
declare
    email          text;
    email_verified bool;
begin
    email_verified := ((current_setting('request.jwt.claims'::text, true))::json ->> 'email_verified'::text)::bool;

    if email_verified then
        email := ((current_setting('request.jwt.claims'::text, true))::json ->> 'email'::text);
        return email;
    else
        return null;
    end if;
end
$$;

create or replace function auth.jwt() returns jsonb
    language plpgsql
as
$$
declare
    jwt jsonb;
begin
    jwt := (current_setting('request.jwt.claims'::text, true))::json;
    return jwt;
end
$$;

-- graphql --
create extension pg_graphql;
grant usage on schema graphql to anon,account;
grant all on function graphql.resolve to anon,account;

-- init schemas --
insert into postgrest.conf
values ('pgrst.db_schemas', 'public,auth');

