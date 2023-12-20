create role account;
create role anon;

grant usage on schema public to account,anon;
grant all on all tables in schema public to account,anon;
grant all on all routines in schema public to account,anon;
grant all on all sequences in schema public to account,anon;

alter default privileges for role postgres in schema public grant all on tables to anon,account;
alter default privileges for role postgres in schema public grant all on routines to anon,account;
alter default privileges for role postgres in schema public grant all on sequences to anon,account;



create schema keycloak;
create schema storage;
create schema auth;

grant usage on schema auth to account,anon;
grant all on all tables in schema auth to account,anon;
grant all on all routines in schema auth to account,anon;
grant all on all sequences in schema auth to account,anon;

alter default privileges for role postgres in schema auth grant all on tables to anon,account;
alter default privileges for role postgres in schema auth grant all on routines to anon,account;
alter default privileges for role postgres in schema auth grant all on sequences to anon,account;



create or replace function auth.uid() returns uuid
    language plpgsql
as
$$
DECLARE
    uid uuid;
BEGIN
    uid := ((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text)::uuid;
    RETURN uid;
END
$$;



create or replace function auth.roles() returns json
    language plpgsql
as
$$
DECLARE
    roles json;
BEGIN
    roles := (((((current_setting('request.jwt.claims'::text, true))::json ->> 'realm_access'::text))::json ->>
               'roles'::text))::json;
    RETURN roles;
END
$$;


CREATE OR REPLACE FUNCTION auth.email() RETURNS text
    LANGUAGE plpgsql
AS
$$
DECLARE
    email          text;
    email_verified bool;
BEGIN
    email_verified := ((current_setting('request.jwt.claims'::text, true))::json ->> 'email_verified'::text)::bool;

    IF email_verified THEN
        email := ((current_setting('request.jwt.claims'::text, true))::json ->> 'email'::text);
        RETURN email;
    ELSE
        RETURN NULL;
    END IF;
END
$$;

CREATE OR REPLACE FUNCTION auth.jwt() RETURNS jsonb
    LANGUAGE plpgsql
AS
$$
DECLARE
    jwt jsonb;
BEGIN
    jwt := (current_setting('request.jwt.claims'::text, true))::json;
    return jwt;
END
$$;

