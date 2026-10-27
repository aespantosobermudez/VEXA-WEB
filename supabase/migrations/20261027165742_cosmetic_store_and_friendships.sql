create table public.store_items (
  id text primary key,
  name text not null,
  category text not null check (category in ('frame', 'banner')),
  rarity text not null check (rarity in ('common', 'rare', 'epic', 'legendary')),
  price integer not null check (price between 150 and 2500),
  asset_path text not null,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.store_items enable row level security;
revoke all on public.store_items from anon, authenticated;
grant select on public.store_items to authenticated;
create policy "Signed-in players can view active cosmetics"
  on public.store_items for select to authenticated using (is_active);

create table public.user_inventory (
  user_id uuid not null references auth.users(id) on delete cascade,
  item_id text not null references public.store_items(id) on delete restrict,
  purchased_at timestamptz not null default now(),
  equipped boolean not null default false,
  primary key (user_id, item_id)
);
alter table public.user_inventory enable row level security;
revoke all on public.user_inventory from anon, authenticated;
grant select on public.user_inventory to authenticated;
create policy "Players can view their own cosmetics"
  on public.user_inventory for select to authenticated using ((select auth.uid()) = user_id);

create table public.friendships (
  user_id uuid not null references auth.users(id) on delete cascade,
  friend_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, friend_id),
  check (user_id <> friend_id)
);
alter table public.friendships enable row level security;
revoke all on public.friendships from anon, authenticated;
grant select on public.friendships to authenticated;
create policy "Players can view their own friendships"
  on public.friendships for select to authenticated using ((select auth.uid()) = user_id);

insert into public.store_items (id, name, category, rarity, price, asset_path, sort_order) values
  ('frame-glacial', 'Glacial', 'frame', 'common', 150, 'assets/store/frames/glacial.webp', 1),
  ('frame-carmesi', 'Carmesí', 'frame', 'common', 300, 'assets/store/frames/carmesi.webp', 2),
  ('frame-guardian', 'Guardián', 'frame', 'rare', 500, 'assets/store/frames/guardian.webp', 3),
  ('frame-llama', 'Llama', 'frame', 'rare', 700, 'assets/store/frames/llama.webp', 4),
  ('frame-violeta', 'Violeta', 'frame', 'rare', 850, 'assets/store/frames/violeta.webp', 5),
  ('frame-solar', 'Solar', 'frame', 'epic', 1100, 'assets/store/frames/solar.webp', 6),
  ('frame-prisma', 'Prisma', 'frame', 'epic', 1500, 'assets/store/frames/prisma.webp', 7),
  ('frame-sombrio', 'Sombrío', 'frame', 'legendary', 1800, 'assets/store/frames/sombrio.webp', 8),
  ('frame-aurora', 'Aurora', 'frame', 'legendary', 2200, 'assets/store/frames/aurora.webp', 9),
  ('frame-ascension', 'Ascensión', 'frame', 'legendary', 2500, 'assets/store/frames/ascension.webp', 10),
  ('banner-esmeralda', 'Sello Esmeralda', 'banner', 'common', 150, 'assets/store/banners/esmeralda.webp', 11),
  ('banner-carmesi', 'Sello Carmesí', 'banner', 'rare', 600, 'assets/store/banners/carmesi.webp', 12),
  ('banner-violeta', 'Sello Violeta', 'banner', 'epic', 1250, 'assets/store/banners/violeta.webp', 13),
  ('banner-dorado', 'Sello Dorado', 'banner', 'legendary', 2400, 'assets/store/banners/dorado.webp', 14);

create or replace function public.purchase_cosmetic(p_item_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_price integer;
  v_balance integer;
begin
  if v_user_id is null then
    return jsonb_build_object('ok', false, 'reason', 'not_authenticated');
  end if;

  select vc into v_balance from public.player_stats where user_id = v_user_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'wallet_missing');
  end if;

  select price into v_price from public.store_items where id = p_item_id and is_active = true;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'item_unavailable');
  end if;

  if exists (select 1 from public.user_inventory where user_id = v_user_id and item_id = p_item_id) then
    return jsonb_build_object('ok', false, 'reason', 'already_owned', 'balance', v_balance);
  end if;

  if v_balance < v_price then
    return jsonb_build_object('ok', false, 'reason', 'insufficient_funds', 'balance', v_balance);
  end if;

  update public.player_stats set vc = vc - v_price
  where user_id = v_user_id returning vc into v_balance;
  insert into public.user_inventory (user_id, item_id) values (v_user_id, p_item_id);

  return jsonb_build_object('ok', true, 'reason', 'purchased', 'balance', v_balance);
end;
$$;
revoke all on function public.purchase_cosmetic(text) from public, anon, authenticated;
grant execute on function public.purchase_cosmetic(text) to authenticated;

create or replace function public.equip_cosmetic(p_item_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_category text;
begin
  if v_user_id is null then
    return jsonb_build_object('ok', false, 'reason', 'not_authenticated');
  end if;

  if p_item_id is null then
    update public.user_inventory set equipped = false where user_id = v_user_id;
    return jsonb_build_object('ok', true, 'reason', 'unequipped');
  end if;

  select si.category into v_category
  from public.store_items si
  join public.user_inventory ui on ui.item_id = si.id
  where ui.user_id = v_user_id and ui.item_id = p_item_id and si.is_active = true;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'not_owned');
  end if;

  update public.user_inventory ui set equipped = false
  from public.store_items si
  where ui.user_id = v_user_id and ui.item_id = si.id and si.category = v_category;
  update public.user_inventory set equipped = true
  where user_id = v_user_id and item_id = p_item_id;

  return jsonb_build_object('ok', true, 'reason', 'equipped');
end;
$$;
revoke all on function public.equip_cosmetic(text) from public, anon, authenticated;
grant execute on function public.equip_cosmetic(text) to authenticated;

create or replace function public.add_friend(p_friend_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
begin
  if v_user_id is null then
    return jsonb_build_object('ok', false, 'reason', 'not_authenticated');
  end if;
  if p_friend_id is null or p_friend_id = v_user_id then
    return jsonb_build_object('ok', false, 'reason', 'invalid_player');
  end if;
  if not exists (select 1 from public.profiles where user_id = p_friend_id) then
    return jsonb_build_object('ok', false, 'reason', 'player_not_found');
  end if;

  insert into public.friendships (user_id, friend_id)
  values (v_user_id, p_friend_id) on conflict do nothing;
  insert into public.friendships (user_id, friend_id)
  values (p_friend_id, v_user_id) on conflict do nothing;

  return jsonb_build_object('ok', true, 'reason', 'added');
end;
$$;
revoke all on function public.add_friend(uuid) from public, anon, authenticated;
grant execute on function public.add_friend(uuid) to authenticated;

create or replace function public.remove_friend(p_friend_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
begin
  if v_user_id is null then
    return jsonb_build_object('ok', false, 'reason', 'not_authenticated');
  end if;
  delete from public.friendships
  where (user_id = v_user_id and friend_id = p_friend_id)
     or (user_id = p_friend_id and friend_id = v_user_id);
  return jsonb_build_object('ok', true, 'reason', 'removed');
end;
$$;
revoke all on function public.remove_friend(uuid) from public, anon, authenticated;
grant execute on function public.remove_friend(uuid) to authenticated;
