-- Test helpers shared by every *_test.sql file. Run after auth_stub.sql and the migrations.

create schema tests;
grant usage on schema tests to anon, authenticated, service_role;

create table tests.vars (key text primary key, value text not null);
grant all on tests.vars to authenticated, service_role;

create function tests.var(p_key text) returns text language sql stable as $$
  select value from tests.vars where key = p_key;
$$;

create function tests.login(p_user uuid, p_session uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'session_id', p_session, 'role', 'authenticated')::text, false);
$$;

-- Runs p_sql and fails unless it raises an error whose message matches p_message_like.
create function tests.expect_error(p_sql text, p_message_like text) returns void language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlerrm not like p_message_like then
      raise exception 'Expected error like "%" but got "%"', p_message_like, sqlerrm;
    end if;
    return;
  end;
  raise exception 'Expected error like "%" but it succeeded: %', p_message_like, p_sql;
end;
$$;

grant execute on all functions in schema tests to anon, authenticated, service_role;
