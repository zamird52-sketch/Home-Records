create extension if not exists pgcrypto;

create type public.user_role as enum ('user','moderator','owner');
create type public.note_visibility as enum ('private','public','collaborative');
create type public.sanction_type as enum ('mute','suspend','ban');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique not null check (char_length(username) between 3 and 30),
  bio text not null default '' check (char_length(bio) <= 500),
  avatar_url text,
  role public.user_role not null default 'user',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.notes (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  title text not null default 'Sin título' check (char_length(title) between 1 and 120),
  content text not null default '',
  visibility public.note_visibility not null default 'private',
  pinned boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.note_collaborators (
  note_id uuid not null references public.notes(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  accepted boolean not null default false,
  invited_at timestamptz not null default now(),
  accepted_at timestamptz,
  primary key (note_id, user_id)
);

create table public.sanctions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  applied_by uuid not null references public.profiles(id),
  type public.sanction_type not null,
  reason text not null default '',
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  reported_user_id uuid references public.profiles(id) on delete set null,
  note_id uuid references public.notes(id) on delete set null,
  reason text not null,
  status text not null default 'open' check (status in ('open','reviewing','resolved','dismissed')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);

alter table public.profiles enable row level security;
alter table public.notes enable row level security;
alter table public.note_collaborators enable row level security;
alter table public.sanctions enable row level security;
alter table public.reports enable row level security;

create or replace function public.is_owner_or_moderator()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role in ('owner','moderator')
  );
$$;

create policy "profiles readable"
on public.profiles for select
using (true);

create policy "users update own profile"
on public.profiles for update
using (id = auth.uid())
with check (id = auth.uid());

create policy "users create own notes"
on public.notes for insert
with check (owner_id = auth.uid());

create policy "owners see own notes"
on public.notes for select
using (
  owner_id = auth.uid()
  or visibility = 'public'
  or exists (
    select 1 from public.note_collaborators c
    where c.note_id = id and c.user_id = auth.uid() and c.accepted = true
  )
  or public.is_owner_or_moderator()
);

create policy "owners and collaborators edit notes"
on public.notes for update
using (
  owner_id = auth.uid()
  or exists (
    select 1 from public.note_collaborators c
    where c.note_id = id and c.user_id = auth.uid() and c.accepted = true
  )
  or public.is_owner_or_moderator()
)
with check (
  owner_id = auth.uid()
  or public.is_owner_or_moderator()
);

create policy "owners delete notes"
on public.notes for delete
using (owner_id = auth.uid() or public.is_owner_or_moderator());

create policy "note collaboration access"
on public.note_collaborators for select
using (
  user_id = auth.uid()
  or exists (select 1 from public.notes n where n.id = note_id and n.owner_id = auth.uid())
  or public.is_owner_or_moderator()
);

create policy "note owners invite collaborators"
on public.note_collaborators for insert
with check (
  exists (select 1 from public.notes n where n.id = note_id and n.owner_id = auth.uid())
  or public.is_owner_or_moderator()
);

create policy "collaborators accept or owner manages"
on public.note_collaborators for update
using (
  user_id = auth.uid()
  or exists (select 1 from public.notes n where n.id = note_id and n.owner_id = auth.uid())
  or public.is_owner_or_moderator()
);

create policy "note owners remove collaborators"
on public.note_collaborators for delete
using (
  exists (select 1 from public.notes n where n.id = note_id and n.owner_id = auth.uid())
  or public.is_owner_or_moderator()
);

create policy "users create reports"
on public.reports for insert
with check (reporter_id = auth.uid());

create policy "users see own reports"
on public.reports for select
using (reporter_id = auth.uid() or public.is_owner_or_moderator());

create policy "moderators manage reports"
on public.reports for update
using (public.is_owner_or_moderator());

create policy "moderators see sanctions"
on public.sanctions for select
using (user_id = auth.uid() or public.is_owner_or_moderator());

create policy "moderators create sanctions"
on public.sanctions for insert
with check (public.is_owner_or_moderator());

create policy "moderators update sanctions"
on public.sanctions for update
using (public.is_owner_or_moderator());

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, username)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'username', 'usuario_' || substr(new.id::text,1,8))
  );
  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();

-- El primer usuario OWNER debe asignarse de forma segura desde el backend/SQL del proyecto.
-- Nunca debe confiarse en un selector de rol del frontend.
