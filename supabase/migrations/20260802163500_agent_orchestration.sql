create extension if not exists pgmq;

create type public.agent_run_status as enum (
  'queued',
  'leased',
  'running',
  'waiting_for_approval',
  'retry_scheduled',
  'succeeded',
  'failed',
  'cancelled',
  'expired'
);

create type public.publication_status as enum (
  'pending_review',
  'approved',
  'scheduled',
  'publishing',
  'published',
  'failed',
  'cancelled'
);

create type public.lead_lawful_basis as enum (
  'not_assessed',
  'consent',
  'contract',
  'legal_obligation',
  'legitimate_interest',
  'credit_protection',
  'exercise_of_rights'
);

alter table public.agent_runs
  drop constraint if exists agent_runs_status_check;

alter table public.agent_runs
  alter column status drop default,
  alter column status type public.agent_run_status
    using status::public.agent_run_status,
  alter column status set default 'queued';

alter table public.agent_runs
  add column run_type text not null default 'unspecified',
  add column entity_type text,
  add column entity_id text,
  add column parent_run_id uuid references public.agent_runs(id) on delete set null,
  add column trace_id uuid not null default gen_random_uuid(),
  add column idempotency_key text,
  add column priority smallint not null default 100
    check (priority between 0 and 1000),
  add column attempt_count integer not null default 0
    check (attempt_count >= 0),
  add column max_attempts integer not null default 3
    check (max_attempts between 1 and 10),
  add column requested_by uuid references auth.users(id) on delete set null,
  add column locked_at timestamptz,
  add column locked_by text,
  add column lease_expires_at timestamptz,
  add column next_attempt_at timestamptz,
  add column approval_required boolean not null default false,
  add column approved_by uuid references auth.users(id) on delete set null,
  add column approved_at timestamptz,
  add column model_name text,
  add column input_tokens bigint not null default 0
    check (input_tokens >= 0),
  add column output_tokens bigint not null default 0
    check (output_tokens >= 0),
  add column estimated_cost numeric(14, 6)
    check (estimated_cost is null or estimated_cost >= 0),
  add column actual_cost numeric(14, 6)
    check (actual_cost is null or actual_cost >= 0),
  add column error_code text,
  add column updated_at timestamptz not null default now();

create unique index agent_runs_org_idempotency_uidx
  on public.agent_runs (organization_id, idempotency_key)
  where idempotency_key is not null;

create index agent_runs_dispatch_idx
  on public.agent_runs (
    status,
    next_attempt_at,
    priority,
    created_at
  )
  where status in ('queued', 'retry_scheduled');

create index agent_runs_trace_idx
  on public.agent_runs (trace_id, created_at);

alter table public.leads
  add column lawful_basis public.lead_lawful_basis
    not null default 'not_assessed',
  add column collection_source text,
  add column collection_method text,
  add column processing_purpose text,
  add column source_url text,
  add column collected_at timestamptz not null default now(),
  add column consent_granted_at timestamptz,
  add column consent_revoked_at timestamptz,
  add column privacy_notice_version text,
  add column legitimate_interest_assessment_id text,
  add column do_not_contact boolean not null default false,
  add column opt_out_at timestamptz,
  add column retention_expires_at timestamptz;

alter table public.leads
  add constraint leads_id_organization_unique
  unique (id, organization_id);

alter table public.lead_events
  drop constraint if exists lead_events_lead_id_fkey;

alter table public.lead_events
  add constraint lead_events_lead_organization_fkey
  foreign key (lead_id, organization_id)
  references public.leads (id, organization_id)
  on delete cascade;

create table public.agent_run_events (
  id bigint generated always as identity primary key,
  organization_id uuid not null
    references public.organizations(id) on delete cascade,
  run_id uuid not null
    references public.agent_runs(id) on delete cascade,
  from_status public.agent_run_status,
  to_status public.agent_run_status not null,
  event_type text not null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index agent_run_events_run_created_idx
  on public.agent_run_events (run_id, created_at);

create table public.publication_targets (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null
    references public.organizations(id) on delete cascade,
  content_item_id uuid not null
    references public.content_items(id) on delete cascade,
  provider text not null,
  external_account_id text,
  status public.publication_status not null default 'pending_review',
  idempotency_key text not null,
  scheduled_for timestamptz,
  published_at timestamptz,
  external_post_id text,
  attempt_count integer not null default 0
    check (attempt_count >= 0),
  last_error text,
  created_by uuid not null
    references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, idempotency_key)
);

create index publication_targets_status_schedule_idx
  on public.publication_targets (
    organization_id,
    status,
    scheduled_for
  );

alter table public.agent_run_events enable row level security;
alter table public.publication_targets enable row level security;

drop policy if exists "admins can manage agent runs"
  on public.agent_runs;

revoke insert, update, delete
  on public.agent_runs
  from authenticated;

create policy "members can read agent run events"
on public.agent_run_events for select
to authenticated
using (
  exists (
    select 1
    from public.organization_members member
    where member.organization_id = agent_run_events.organization_id
      and member.user_id = (select auth.uid())
  )
);

revoke insert, update, delete
  on public.agent_run_events
  from authenticated;

create policy "members can read publication targets"
on public.publication_targets for select
to authenticated
using (
  exists (
    select 1
    from public.organization_members member
    where member.organization_id = publication_targets.organization_id
      and member.user_id = (select auth.uid())
  )
);

create policy "editors can create publication targets"
on public.publication_targets for insert
to authenticated
with check (
  created_by = (select auth.uid())
  and exists (
    select 1
    from public.organization_members member
    where member.organization_id = publication_targets.organization_id
      and member.user_id = (select auth.uid())
      and member.role in ('owner', 'admin', 'editor')
  )
);

create policy "editors can update publication targets"
on public.publication_targets for update
to authenticated
using (
  exists (
    select 1
    from public.organization_members member
    where member.organization_id = publication_targets.organization_id
      and member.user_id = (select auth.uid())
      and member.role in ('owner', 'admin', 'editor')
  )
)
with check (
  exists (
    select 1
    from public.organization_members member
    where member.organization_id = publication_targets.organization_id
      and member.user_id = (select auth.uid())
      and member.role in ('owner', 'admin', 'editor')
  )
);

create policy "editors can delete publication targets"
on public.publication_targets for delete
to authenticated
using (
  exists (
    select 1
    from public.organization_members member
    where member.organization_id = publication_targets.organization_id
      and member.user_id = (select auth.uid())
      and member.role in ('owner', 'admin', 'editor')
  )
);

drop policy if exists "members can read their memberships"
  on public.organization_members;

create policy "members and owners can read organization members"
on public.organization_members for select
to authenticated
using (
  user_id = (select auth.uid())
  or exists (
    select 1
    from public.organizations organization
    where organization.id = organization_members.organization_id
      and organization.owner_id = (select auth.uid())
  )
);

insert into public.organization_members (
  organization_id,
  user_id,
  role
)
select
  organization.id,
  organization.owner_id,
  'owner'
from public.organizations organization
on conflict (organization_id, user_id)
do update set role = 'owner';

create schema if not exists internal;
revoke all on schema internal from public;
revoke all on schema internal from anon;
revoke all on schema internal from authenticated;

create or replace function internal.add_owner_membership()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.organization_members (
    organization_id,
    user_id,
    role
  )
  values (
    new.id,
    new.owner_id,
    'owner'
  )
  on conflict (organization_id, user_id)
  do update set role = 'owner';

  return new;
end;
$$;

drop trigger if exists organizations_add_owner_membership
  on public.organizations;

create trigger organizations_add_owner_membership
after insert on public.organizations
for each row
execute function internal.add_owner_membership();

create or replace function internal.preserve_content_creator()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.created_by is distinct from old.created_by then
    raise exception 'created_by is immutable';
  end if;

  return new;
end;
$$;

drop trigger if exists content_items_preserve_creator
  on public.content_items;

create trigger content_items_preserve_creator
before update on public.content_items
for each row
execute function internal.preserve_content_creator();

create trigger publication_targets_preserve_creator
before update on public.publication_targets
for each row
execute function internal.preserve_content_creator();

create or replace function internal.touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger agent_runs_touch_updated_at
before update on public.agent_runs
for each row
execute function internal.touch_updated_at();

create trigger publication_targets_touch_updated_at
before update on public.publication_targets
for each row
execute function internal.touch_updated_at();

create or replace function internal.capture_agent_run_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.agent_run_events (
      organization_id,
      run_id,
      from_status,
      to_status,
      event_type,
      details
    )
    values (
      new.organization_id,
      new.id,
      null,
      new.status,
      'created',
      jsonb_build_object(
        'agent_name', new.agent_name,
        'run_type', new.run_type,
        'trace_id', new.trace_id
      )
    );
  elsif new.status is distinct from old.status then
    insert into public.agent_run_events (
      organization_id,
      run_id,
      from_status,
      to_status,
      event_type,
      details
    )
    values (
      new.organization_id,
      new.id,
      old.status,
      new.status,
      'status_changed',
      jsonb_build_object(
        'attempt_count', new.attempt_count,
        'locked_by', new.locked_by,
        'error_code', new.error_code
      )
    );
  end if;

  return new;
end;
$$;

drop trigger if exists agent_runs_capture_event
  on public.agent_runs;

create trigger agent_runs_capture_event
after insert or update of status on public.agent_runs
for each row
execute function internal.capture_agent_run_event();

select pgmq.create('agent_jobs');

create or replace function public.enqueue_agent_run(
  p_organization_id uuid,
  p_agent_name text,
  p_run_type text,
  p_input jsonb default '{}'::jsonb,
  p_entity_type text default null,
  p_entity_id text default null,
  p_parent_run_id uuid default null,
  p_idempotency_key text default null,
  p_priority smallint default 100,
  p_max_attempts integer default 3
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_run_id uuid;
begin
  if v_user_id is null then
    raise exception 'authentication required'
      using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.organization_members member
    where member.organization_id = p_organization_id
      and member.user_id = v_user_id
      and member.role in ('owner', 'admin', 'editor', 'sales')
  ) then
    raise exception 'organization access denied'
      using errcode = '42501';
  end if;

  if p_idempotency_key is not null then
    select run.id
    into v_run_id
    from public.agent_runs run
    where run.organization_id = p_organization_id
      and run.idempotency_key = p_idempotency_key;

    if v_run_id is not null then
      return v_run_id;
    end if;
  end if;

  begin
    insert into public.agent_runs (
      organization_id,
      agent_name,
      run_type,
      status,
      input,
      entity_type,
      entity_id,
      parent_run_id,
      idempotency_key,
      priority,
      max_attempts,
      requested_by
    )
    values (
      p_organization_id,
      p_agent_name,
      p_run_type,
      'queued',
      coalesce(p_input, '{}'::jsonb),
      p_entity_type,
      p_entity_id,
      p_parent_run_id,
      p_idempotency_key,
      p_priority,
      p_max_attempts,
      v_user_id
    )
    returning id into v_run_id;
  exception
    when unique_violation then
      select run.id
      into v_run_id
      from public.agent_runs run
      where run.organization_id = p_organization_id
        and run.idempotency_key = p_idempotency_key;
  end;

  if v_run_id is null then
    raise exception 'agent run could not be created';
  end if;

  perform pgmq.send(
    queue_name => 'agent_jobs',
    msg => jsonb_build_object(
      'run_id', v_run_id,
      'organization_id', p_organization_id,
      'trace_version', 1
    ),
    delay => 0
  );

  insert into public.audit_logs (
    organization_id,
    actor_user_id,
    action,
    entity_type,
    entity_id,
    details
  )
  values (
    p_organization_id,
    v_user_id,
    'agent_run.enqueued',
    'agent_run',
    v_run_id::text,
    jsonb_build_object(
      'agent_name', p_agent_name,
      'run_type', p_run_type
    )
  );

  return v_run_id;
end;
$$;

revoke all on function public.enqueue_agent_run(
  uuid,
  text,
  text,
  jsonb,
  text,
  text,
  uuid,
  text,
  smallint,
  integer
) from public;

grant execute on function public.enqueue_agent_run(
  uuid,
  text,
  text,
  jsonb,
  text,
  text,
  uuid,
  text,
  smallint,
  integer
) to authenticated;

create or replace function public.read_agent_queue(
  p_batch_size integer default 5,
  p_visibility_timeout integer default 120
)
returns table (
  msg_id bigint,
  read_ct bigint,
  enqueued_at timestamptz,
  vt timestamptz,
  message jsonb
)
language sql
security definer
set search_path = ''
as $$
  select *
  from pgmq.read(
    queue_name => 'agent_jobs',
    vt => greatest(30, least(p_visibility_timeout, 900)),
    qty => greatest(1, least(p_batch_size, 20))
  );
$$;

revoke all on function public.read_agent_queue(integer, integer)
  from public;
grant execute on function public.read_agent_queue(integer, integer)
  to service_role;

create or replace function public.claim_agent_run(
  p_run_id uuid,
  p_worker_id text,
  p_lease_seconds integer default 120
)
returns setof public.agent_runs
language sql
security definer
set search_path = ''
as $$
  update public.agent_runs run
  set
    status = 'leased',
    attempt_count = run.attempt_count + 1,
    locked_at = now(),
    locked_by = p_worker_id,
    lease_expires_at = now()
      + make_interval(
          secs => greatest(30, least(p_lease_seconds, 900))
        ),
    next_attempt_at = null,
    error_code = null,
    error_message = null
  where run.id = p_run_id
    and run.status in ('queued', 'retry_scheduled')
    and (
      run.next_attempt_at is null
      or run.next_attempt_at <= now()
    )
    and (
      run.lease_expires_at is null
      or run.lease_expires_at <= now()
    )
  returning run.*;
$$;

revoke all on function public.claim_agent_run(uuid, text, integer)
  from public;
grant execute on function public.claim_agent_run(uuid, text, integer)
  to service_role;

create or replace function public.transition_agent_run(
  p_run_id uuid,
  p_worker_id text,
  p_to_status public.agent_run_status,
  p_output jsonb default null
)
returns public.agent_runs
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_current public.agent_runs;
  v_updated public.agent_runs;
  v_allowed boolean := false;
begin
  select *
  into v_current
  from public.agent_runs
  where id = p_run_id
  for update;

  if not found then
    raise exception 'agent run not found';
  end if;

  if v_current.locked_by is not null
     and v_current.locked_by <> p_worker_id then
    raise exception 'agent run lease is owned by another worker';
  end if;

  v_allowed := case
    when v_current.status = 'leased'
      and p_to_status in ('running', 'cancelled', 'expired')
      then true
    when v_current.status = 'running'
      and p_to_status in (
        'waiting_for_approval',
        'succeeded',
        'failed',
        'cancelled',
        'expired'
      )
      then true
    else false
  end;

  if not v_allowed then
    raise exception 'invalid agent run transition: % -> %',
      v_current.status,
      p_to_status;
  end if;

  update public.agent_runs
  set
    status = p_to_status,
    output = coalesce(p_output, output),
    started_at = case
      when p_to_status = 'running'
        then coalesce(started_at, now())
      else started_at
    end,
    finished_at = case
      when p_to_status in (
        'succeeded',
        'failed',
        'cancelled',
        'expired'
      )
        then now()
      else null
    end,
    approval_required = p_to_status = 'waiting_for_approval',
    locked_at = case
      when p_to_status = 'running' then locked_at
      else null
    end,
    locked_by = case
      when p_to_status = 'running' then locked_by
      else null
    end,
    lease_expires_at = case
      when p_to_status = 'running' then lease_expires_at
      else null
    end
  where id = p_run_id
  returning * into v_updated;

  return v_updated;
end;
$$;

revoke all on function public.transition_agent_run(
  uuid,
  text,
  public.agent_run_status,
  jsonb
) from public;

grant execute on function public.transition_agent_run(
  uuid,
  text,
  public.agent_run_status,
  jsonb
) to service_role;

create or replace function public.fail_agent_run(
  p_run_id uuid,
  p_worker_id text,
  p_error_code text,
  p_error_message text,
  p_retry_delay_seconds integer default 60
)
returns public.agent_runs
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_current public.agent_runs;
  v_updated public.agent_runs;
  v_should_retry boolean;
begin
  select *
  into v_current
  from public.agent_runs
  where id = p_run_id
  for update;

  if not found then
    raise exception 'agent run not found';
  end if;

  if v_current.locked_by is not null
     and v_current.locked_by <> p_worker_id then
    raise exception 'agent run lease is owned by another worker';
  end if;

  if v_current.status not in ('leased', 'running') then
    raise exception 'agent run is not active';
  end if;

  v_should_retry := v_current.attempt_count < v_current.max_attempts;

  update public.agent_runs
  set
    status = case
      when v_should_retry then 'retry_scheduled'::public.agent_run_status
      else 'failed'::public.agent_run_status
    end,
    error_code = p_error_code,
    error_message = p_error_message,
    next_attempt_at = case
      when v_should_retry
        then now()
          + make_interval(
              secs => greatest(
                15,
                least(p_retry_delay_seconds, 86400)
              )
            )
      else null
    end,
    finished_at = case
      when v_should_retry then null
      else now()
    end,
    locked_at = null,
    locked_by = null,
    lease_expires_at = null
  where id = p_run_id
  returning * into v_updated;

  if v_should_retry then
    perform pgmq.send(
      queue_name => 'agent_jobs',
      msg => jsonb_build_object(
        'run_id', v_updated.id,
        'organization_id', v_updated.organization_id,
        'trace_version', 1
      ),
      delay => greatest(
        15,
        least(p_retry_delay_seconds, 86400)
      )
    );
  end if;

  return v_updated;
end;
$$;

revoke all on function public.fail_agent_run(
  uuid,
  text,
  text,
  text,
  integer
) from public;

grant execute on function public.fail_agent_run(
  uuid,
  text,
  text,
  text,
  integer
) to service_role;

create or replace function public.approve_agent_run(
  p_run_id uuid,
  p_approved boolean,
  p_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_current public.agent_runs;
begin
  if v_user_id is null then
    raise exception 'authentication required'
      using errcode = '42501';
  end if;

  select *
  into v_current
  from public.agent_runs
  where id = p_run_id
  for update;

  if not found then
    raise exception 'agent run not found';
  end if;

  if not exists (
    select 1
    from public.organization_members member
    where member.organization_id = v_current.organization_id
      and member.user_id = v_user_id
      and member.role in ('owner', 'admin', 'editor', 'sales')
  ) then
    raise exception 'organization access denied'
      using errcode = '42501';
  end if;

  if v_current.status <> 'waiting_for_approval' then
    raise exception 'agent run is not waiting for approval';
  end if;

  if p_approved then
    update public.agent_runs
    set
      status = 'queued',
      approval_required = false,
      approved_by = v_user_id,
      approved_at = now(),
      output = coalesce(output, '{}'::jsonb)
        || jsonb_build_object('approval_note', p_note)
    where id = p_run_id;

    perform pgmq.send(
      queue_name => 'agent_jobs',
      msg => jsonb_build_object(
        'run_id', p_run_id,
        'organization_id', v_current.organization_id,
        'trace_version', 1
      ),
      delay => 0
    );
  else
    update public.agent_runs
    set
      status = 'cancelled',
      approval_required = false,
      approved_by = v_user_id,
      approved_at = now(),
      finished_at = now(),
      output = coalesce(output, '{}'::jsonb)
        || jsonb_build_object('rejection_note', p_note)
    where id = p_run_id;
  end if;

  insert into public.audit_logs (
    organization_id,
    actor_user_id,
    action,
    entity_type,
    entity_id,
    details
  )
  values (
    v_current.organization_id,
    v_user_id,
    case
      when p_approved then 'agent_run.approved'
      else 'agent_run.rejected'
    end,
    'agent_run',
    p_run_id::text,
    jsonb_build_object('note', p_note)
  );

  return p_run_id;
end;
$$;

revoke all on function public.approve_agent_run(uuid, boolean, text)
  from public;
grant execute on function public.approve_agent_run(uuid, boolean, text)
  to authenticated;

create or replace function public.archive_agent_queue_message(
  p_msg_id bigint
)
returns boolean
language sql
security definer
set search_path = ''
as $$
  select pgmq.archive('agent_jobs', p_msg_id);
$$;

revoke all on function public.archive_agent_queue_message(bigint)
  from public;
grant execute on function public.archive_agent_queue_message(bigint)
  to service_role;

create or replace function public.delete_agent_queue_message(
  p_msg_id bigint
)
returns boolean
language sql
security definer
set search_path = ''
as $$
  select pgmq.delete('agent_jobs', p_msg_id);
$$;

revoke all on function public.delete_agent_queue_message(bigint)
  from public;
grant execute on function public.delete_agent_queue_message(bigint)
  to service_role;
