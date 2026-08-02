create extension if not exists pgcrypto;

create type public.content_status as enum (
  'idea',
  'draft',
  'review',
  'approved',
  'scheduled',
  'published',
  'rejected'
);

create type public.lead_stage as enum (
  'discovered',
  'qualified',
  'engaged',
  'meeting',
  'opportunity',
  'won',
  'lost'
);

create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  owner_id uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.organization_members (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner', 'admin', 'editor', 'sales', 'viewer')),
  created_at timestamptz not null default now(),
  primary key (organization_id, user_id)
);

create table public.integrations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  provider text not null,
  status text not null default 'disconnected',
  external_account_id text,
  configuration jsonb not null default '{}'::jsonb,
  last_synced_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, provider, external_account_id)
);

comment on column public.integrations.configuration is
  'Non-secret metadata only. OAuth tokens and secret material must use a secure secret store.';

create table public.content_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  title text not null,
  body text not null default '',
  language text not null default 'pt-BR',
  channel text,
  status public.content_status not null default 'idea',
  source_url text,
  drive_file_id text,
  scheduled_for timestamptz,
  published_at timestamptz,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.leads (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  full_name text not null,
  company_name text,
  role_title text,
  profile_url text,
  source_channel text,
  language text,
  country_code text,
  score smallint not null default 0 check (score between 0 and 100),
  stage public.lead_stage not null default 'discovered',
  owner_id uuid references auth.users(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.lead_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  lead_id uuid not null references public.leads(id) on delete cascade,
  event_type text not null,
  channel text,
  summary text not null,
  payload jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null
);

create table public.agent_runs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  agent_name text not null,
  status text not null check (status in ('queued', 'running', 'succeeded', 'failed', 'cancelled')),
  input jsonb not null default '{}'::jsonb,
  output jsonb,
  error_message text,
  started_at timestamptz,
  finished_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.audit_logs (
  id bigint generated always as identity primary key,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  actor_user_id uuid references auth.users(id) on delete set null,
  action text not null,
  entity_type text not null,
  entity_id text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index content_items_org_status_idx
  on public.content_items (organization_id, status, created_at desc);
create index leads_org_stage_score_idx
  on public.leads (organization_id, stage, score desc);
create index lead_events_lead_time_idx
  on public.lead_events (lead_id, occurred_at desc);
create index agent_runs_org_created_idx
  on public.agent_runs (organization_id, created_at desc);
create index audit_logs_org_created_idx
  on public.audit_logs (organization_id, created_at desc);

alter table public.organizations enable row level security;
alter table public.organization_members enable row level security;
alter table public.integrations enable row level security;
alter table public.content_items enable row level security;
alter table public.leads enable row level security;
alter table public.lead_events enable row level security;
alter table public.agent_runs enable row level security;
alter table public.audit_logs enable row level security;

create policy "organization owners can read organizations"
on public.organizations for select
to authenticated
using (
  owner_id = (select auth.uid())
  or exists (
    select 1
    from public.organization_members member
    where member.organization_id = organizations.id
      and member.user_id = (select auth.uid())
  )
);

create policy "authenticated users can create owned organizations"
on public.organizations for insert
to authenticated
with check (owner_id = (select auth.uid()));

create policy "owners can update organizations"
on public.organizations for update
to authenticated
using (owner_id = (select auth.uid()))
with check (owner_id = (select auth.uid()));

create policy "members can read their memberships"
on public.organization_members for select
to authenticated
using (user_id = (select auth.uid()));

create policy "owners can add organization members"
on public.organization_members for insert
to authenticated
with check (
  exists (
    select 1
    from public.organizations organization
    where organization.id = organization_id
      and organization.owner_id = (select auth.uid())
  )
);

create policy "owners can update organization members"
on public.organization_members for update
to authenticated
using (
  exists (
    select 1
    from public.organizations organization
    where organization.id = organization_id
      and organization.owner_id = (select auth.uid())
  )
)
with check (
  exists (
    select 1
    from public.organizations organization
    where organization.id = organization_id
      and organization.owner_id = (select auth.uid())
  )
);

create policy "owners can remove organization members"
on public.organization_members for delete
to authenticated
using (
  exists (
    select 1
    from public.organizations organization
    where organization.id = organization_id
      and organization.owner_id = (select auth.uid())
  )
);

create policy "members can read integrations"
on public.integrations for select
to authenticated
using (
  exists (
    select 1 from public.organization_members member
    where member.organization_id = integrations.organization_id
      and member.user_id = (select auth.uid())
  )
);

create policy "admins can manage integrations"
on public.integrations for all
to authenticated
using (
  exists (
    select 1 from public.organization_members member
    where member.organization_id = integrations.organization_id
      and member.user_id = (select auth.uid())
      and member.role in ('owner', 'admin')
  )
)
with check (
  exists (
    select 1 from public.organization_members member
    where member.organization_id = integrations.organization_id
      and member.user_id = (select auth.uid())
      and member.role in ('owner', 'admin')
  )
);

create policy "members can read content"
on public.content_items for select
to authenticated
using (
  exists (
    select 1 from public.organization_members member
    where member.organization_id = content_items.organization_id
      and member.user_id = (select auth.uid())
  )
);

create policy "editors can create content"
on public.content_items for insert
to authenticated
with check (
  created_by = (select auth.uid())
  and exists (
    select 1 from public.organization_members member
    where member.organization_id = content_items.organization_id
      and member.user_id = (select auth.uid())
      and member.role in ('owner', 'admin', 'editor')
  )
);

create policy "editors can update content"
on public.content_items for update
to authenticated
using (
  exists (
    select 1 from public.organization_members member
    where member.organization_id = content_items.organization_id
      and member.user_id = (select auth.uid())
      and member.role in ('owner', 'admin', 'editor')
  )
)
with check (
  exists (
    select 1 from public.organization_members member
    where member.organization_id = content_items.organization_id
      and member.user_id = (select auth.uid())
      and member.role in ('owner', 'admin', 'editor')
  )
);

create policy "editors can delete content"
on public.content_items for delete
to authenticated
using (
  exists (
    select 1 from public.organization_members member
    where member.organization_id = content_items.organization_id
      and member.user_id = (select auth.uid())
      and member.role in ('owner', 'admin', 'editor')
  )
);

create policy "members can read leads"
on public.leads for select
to authenticated
using (
  exists (
    select 1 from public.organization_members member
    where member.organization_id = leads.organization_id
      and member.user_id = (select auth.uid())
  )
);

create policy "sales can manage leads"
on public.leads for all
to authenticated
using (
  exists (
    select 1 from public.organization_members member
    where member.organization_id = leads.organization_id
      and member.user_id = (select auth.uid())
      and member.role in ('owner', 'admin', 'sales')
  )
)
with check (
  exists (
    select 1 from public.organization_members member
    where member.organization_id = leads.organization_id
      and member.user_id = (select auth.uid())
      and member.role in ('owner', 'admin', 'sales')
  )
);

create policy "members can read lead events"
on public.lead_events for select
to authenticated
using (
  exists (
    select 1 from public.organization_members member
    where member.organization_id = lead_events.organization_id
      and member.user_id = (select auth.uid())
  )
);

create policy "sales can create lead events"
on public.lead_events for insert
to authenticated
with check (
  created_by = (select auth.uid())
  and exists (
    select 1 from public.organization_members member
    where member.organization_id = lead_events.organization_id
      and member.user_id = (select auth.uid())
      and member.role in ('owner', 'admin', 'sales')
  )
);

create policy "members can read agent runs"
on public.agent_runs for select
to authenticated
using (
  exists (
    select 1 from public.organization_members member
    where member.organization_id = agent_runs.organization_id
      and member.user_id = (select auth.uid())
  )
);

create policy "admins can manage agent runs"
on public.agent_runs for all
to authenticated
using (
  exists (
    select 1 from public.organization_members member
    where member.organization_id = agent_runs.organization_id
      and member.user_id = (select auth.uid())
      and member.role in ('owner', 'admin')
  )
)
with check (
  exists (
    select 1 from public.organization_members member
    where member.organization_id = agent_runs.organization_id
      and member.user_id = (select auth.uid())
      and member.role in ('owner', 'admin')
  )
);

create policy "members can read audit logs"
on public.audit_logs for select
to authenticated
using (
  exists (
    select 1 from public.organization_members member
    where member.organization_id = audit_logs.organization_id
      and member.user_id = (select auth.uid())
  )
);

revoke insert, update, delete on public.audit_logs from authenticated;
