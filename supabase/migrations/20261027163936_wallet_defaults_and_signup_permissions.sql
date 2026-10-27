alter table public.player_stats
  alter column vc set default 0;

revoke execute on function public.handle_new_vexa_user()
  from public, anon, authenticated;
