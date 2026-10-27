create table public.secret_code_redemptions (
  user_id uuid not null references auth.users(id) on delete cascade,
  code text not null check (code = 'dev'),
  reward_vc integer not null check (reward_vc = 3000),
  redeemed_at timestamptz not null default now(),
  primary key (user_id, code)
);

alter table public.secret_code_redemptions enable row level security;
revoke all on public.secret_code_redemptions from anon, authenticated;

create or replace function public.redeem_secret_code(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_balance integer;
begin
  if v_user_id is null then
    return jsonb_build_object('ok', false, 'reason', 'not_authenticated');
  end if;

  if p_code is distinct from 'dev' then
    return jsonb_build_object('ok', false, 'reason', 'invalid_code');
  end if;

  insert into public.secret_code_redemptions (user_id, code, reward_vc)
  values (v_user_id, 'dev', 3000)
  on conflict (user_id, code) do nothing;

  if not found then
    return jsonb_build_object('ok', false, 'reason', 'already_redeemed');
  end if;

  update public.player_stats
  set vc = vc + 3000
  where user_id = v_user_id
  returning vc into v_balance;

  if not found then
    delete from public.secret_code_redemptions
    where user_id = v_user_id and code = 'dev';
    return jsonb_build_object('ok', false, 'reason', 'wallet_missing');
  end if;

  return jsonb_build_object('ok', true, 'reason', 'redeemed', 'balance', v_balance);
end;
$$;

revoke all on function public.redeem_secret_code(text) from public, anon, authenticated;
grant execute on function public.redeem_secret_code(text) to authenticated;
