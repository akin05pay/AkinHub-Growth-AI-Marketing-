-- Close cross-tenant relationship gaps left intentionally explicit in the
-- orchestration migration. These constraints ensure that related records share
-- the same organization_id.

alter table public.agent_runs
  add constraint agent_runs_id_organization_unique
  unique (id, organization_id);

alter table public.agent_runs
  add constraint agent_runs_parent_organization_fkey
  foreign key (parent_run_id, organization_id)
  references public.agent_runs (id, organization_id);

alter table public.agent_run_events
  add constraint agent_run_events_run_organization_fkey
  foreign key (run_id, organization_id)
  references public.agent_runs (id, organization_id)
  on delete cascade;

alter table public.content_items
  add constraint content_items_id_organization_unique
  unique (id, organization_id);

alter table public.publication_targets
  add constraint publication_targets_content_organization_fkey
  foreign key (content_item_id, organization_id)
  references public.content_items (id, organization_id)
  on delete cascade;

-- Avoid recursive RLS evaluation between organizations and
-- organization_members. The helper executes as the function owner and exposes
-- only whether the current authenticated user owns the supplied organization.
create or replace function public.is_organization_owner(
  p_organization_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.organizations organization
    where organization.id = p_organization_id
      and organization.owner_id = auth.uid()
  );
$$;

revoke all on function public.is_organization_owner(uuid)
  from public;
grant execute on function public.is_organization_owner(uuid)
  to authenticated;

drop policy if exists "members and owners can read organization members"
  on public.organization_members;

create policy "members and owners can read organization members"
on public.organization_members for select
to authenticated
using (
  user_id = (select auth.uid())
  or public.is_organization_owner(organization_id)
);
