-- Harden read access to public.profiles.
--
-- Before: two SELECT policies with USING (true) for role `public`, so anyone
-- holding the anon key (no login) could dump every profile: emails, phones,
-- addresses, roles. The username-login flow depended on that.
--
-- After:
--   * logged-in users keep full read access (chat, orders, riders, stations);
--   * anonymous guests can read station (owner) rows only, for guest browsing;
--   * username -> email resolution for login goes through a narrow
--     SECURITY DEFINER function instead of a table read.

create or replace function public.resolve_login_email(p_username text)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select p.email
  from public.profiles p
  where p.username is not null
    and lower(p.username) = lower(trim(p_username))
    and nullif(trim(p.email), '') is not null
  limit 1;
$$;

revoke all on function public.resolve_login_email(text) from public;
grant execute on function public.resolve_login_email(text) to anon, authenticated;

drop policy if exists "Public profiles are viewable by everyone for chat" on public.profiles;
drop policy if exists "Public profiles are viewable by everyone." on public.profiles;

drop policy if exists "profiles_select_authenticated" on public.profiles;
create policy "profiles_select_authenticated"
  on public.profiles for select
  to authenticated
  using (true);

drop policy if exists "profiles_select_anon_stations" on public.profiles;
create policy "profiles_select_anon_stations"
  on public.profiles for select
  to anon
  using (role = 'owner');
