-- NOVA / Home Records — Sala de colaboradores
-- Ejecutar una sola vez en Supabase > SQL Editor > New query.
-- Requiere Supabase Auth: cada colaborador debe iniciar sesión.
create extension if not exists pgcrypto;

create table if not exists public.nova_projects (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  title text not null default 'Proyecto sin título',
  genre text not null default '',
  original_lyrics text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.nova_project_members (
  project_id uuid not null references public.nova_projects(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'editor' check (role in ('owner','editor','viewer')),
  joined_at timestamptz not null default now(),
  primary key (project_id, user_id)
);

create table if not exists public.nova_project_invites (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.nova_projects(id) on delete cascade,
  invite_code text not null unique default encode(gen_random_bytes(24), 'hex'),
  created_by uuid not null references auth.users(id) on delete cascade,
  expires_at timestamptz not null default (now() + interval '7 days'),
  max_uses integer not null default 10 check (max_uses between 1 and 100),
  uses integer not null default 0 check (uses >= 0),
  created_at timestamptz not null default now()
);

create table if not exists public.nova_project_comments (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.nova_projects(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  line_reference text not null default '',
  body text not null check (char_length(body) between 1 and 3000),
  created_at timestamptz not null default now()
);

create table if not exists public.nova_project_versions (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.nova_projects(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null default 'Versión',
  lyrics text not null,
  created_at timestamptz not null default now()
);

create index if not exists nova_projects_owner_idx on public.nova_projects(owner_id);
create index if not exists nova_members_user_idx on public.nova_project_members(user_id);
create index if not exists nova_comments_project_idx on public.nova_project_comments(project_id, created_at);
create index if not exists nova_versions_project_idx on public.nova_project_versions(project_id, created_at desc);

alter table public.nova_projects enable row level security;
alter table public.nova_project_members enable row level security;
alter table public.nova_project_invites enable row level security;
alter table public.nova_project_comments enable row level security;
alter table public.nova_project_versions enable row level security;

-- Evita que una persona lea un proyecto si no es su dueño ni miembro.
drop policy if exists "project members can read projects" on public.nova_projects;
create policy "project members can read projects" on public.nova_projects
for select to authenticated using (
  owner_id = (select auth.uid()) or exists (
    select 1 from public.nova_project_members m
    where m.project_id = id and m.user_id = (select auth.uid())
  )
);
drop policy if exists "authenticated users can create own projects" on public.nova_projects;
create policy "authenticated users can create own projects" on public.nova_projects
for insert to authenticated with check (owner_id = (select auth.uid()));
drop policy if exists "owners can update projects" on public.nova_projects;
create policy "owners can update projects" on public.nova_projects
for update to authenticated using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
drop policy if exists "owners can delete projects" on public.nova_projects;
create policy "owners can delete projects" on public.nova_projects
for delete to authenticated using (owner_id = (select auth.uid()));

drop policy if exists "members can read membership" on public.nova_project_members;
create policy "members can read membership" on public.nova_project_members
for select to authenticated using (
  user_id = (select auth.uid()) or exists (
    select 1 from public.nova_projects p
    where p.id = project_id and p.owner_id = (select auth.uid())
  )
);
drop policy if exists "owners can add members" on public.nova_project_members;
create policy "owners can add members" on public.nova_project_members
for insert to authenticated with check (exists (
  select 1 from public.nova_projects p
  where p.id = project_id and p.owner_id = (select auth.uid())
));
drop policy if exists "owners can remove members" on public.nova_project_members;
create policy "owners can remove members" on public.nova_project_members
for delete to authenticated using (exists (
  select 1 from public.nova_projects p
  where p.id = project_id and p.owner_id = (select auth.uid())
));

drop policy if exists "owners can manage invites" on public.nova_project_invites;
create policy "owners can manage invites" on public.nova_project_invites
for all to authenticated using (created_by = (select auth.uid())) with check (
  created_by = (select auth.uid()) and exists (
    select 1 from public.nova_projects p where p.id = project_id and p.owner_id = (select auth.uid())
  )
);

drop policy if exists "members can read comments" on public.nova_project_comments;
create policy "members can read comments" on public.nova_project_comments
for select to authenticated using (exists (
  select 1 from public.nova_project_members m
  where m.project_id = public.nova_project_comments.project_id and m.user_id = (select auth.uid())
) or exists (
  select 1 from public.nova_projects p where p.id = public.nova_project_comments.project_id and p.owner_id = (select auth.uid())
));
drop policy if exists "members can add comments" on public.nova_project_comments;
create policy "members can add comments" on public.nova_project_comments
for insert to authenticated with check (
  user_id = (select auth.uid()) and (
    exists (select 1 from public.nova_project_members m where m.project_id = nova_project_comments.project_id and m.user_id = (select auth.uid()))
    or exists (select 1 from public.nova_projects p where p.id = nova_project_comments.project_id and p.owner_id = (select auth.uid()))
  )
);
drop policy if exists "authors can delete own comments" on public.nova_project_comments;
create policy "authors can delete own comments" on public.nova_project_comments
for delete to authenticated using (user_id = (select auth.uid()));

drop policy if exists "members can read versions" on public.nova_project_versions;
create policy "members can read versions" on public.nova_project_versions
for select to authenticated using (exists (
  select 1 from public.nova_project_members m where m.project_id = nova_project_versions.project_id and m.user_id = (select auth.uid())
) or exists (
  select 1 from public.nova_projects p where p.id = nova_project_versions.project_id and p.owner_id = (select auth.uid())
));
drop policy if exists "members can add versions" on public.nova_project_versions;
create policy "members can add versions" on public.nova_project_versions
for insert to authenticated with check (
  user_id = (select auth.uid()) and (
    exists (select 1 from public.nova_project_members m where m.project_id = nova_project_versions.project_id and m.user_id = (select auth.uid()))
    or exists (select 1 from public.nova_projects p where p.id = nova_project_versions.project_id and p.owner_id = (select auth.uid()))
  )
);

-- La aceptación del enlace se hace mediante esta función; el código vence y tiene usos limitados.
create or replace function public.nova_accept_invite(p_invite_code text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_project_id uuid;
  v_invite_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Iniciá sesión para aceptar una invitación.';
  end if;

  select i.id, i.project_id into v_invite_id, v_project_id
  from public.nova_project_invites i
  where i.invite_code = p_invite_code
    and i.expires_at > now()
    and i.uses < i.max_uses
  for update;

  if v_invite_id is null then
    raise exception 'El enlace no existe, venció o alcanzó su límite de usos.';
  end if;

  insert into public.nova_project_members(project_id, user_id, role)
  values (v_project_id, auth.uid(), 'editor')
  on conflict (project_id, user_id) do nothing;

  update public.nova_project_invites
  set uses = uses + 1
  where id = v_invite_id;

  return v_project_id;
end;
$$;

revoke all on function public.nova_accept_invite(text) from public;
grant execute on function public.nova_accept_invite(text) to authenticated;

grant select, insert, update, delete on public.nova_projects to authenticated;
grant select, insert, delete on public.nova_project_members to authenticated;
grant select, insert, update, delete on public.nova_project_invites to authenticated;
grant select, insert, delete on public.nova_project_comments to authenticated;
grant select, insert on public.nova_project_versions to authenticated;
