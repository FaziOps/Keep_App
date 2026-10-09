-- Keepr schema: households, receipts, items, warranties, attachments,
-- entitlements and AI usage, protected by Row-Level Security (PRD §10).

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table public.profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  display_name text not null default '',
  email        text,
  currency     text not null default 'PKR' check (currency ~ '^[A-Z]{3}$'),
  locale       text not null default 'en',
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create table public.households (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  owner_id   uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create type public.member_role as enum ('owner', 'editor', 'viewer');

create table public.household_members (
  household_id uuid not null references public.households (id) on delete cascade,
  user_id      uuid not null references public.profiles (id) on delete cascade,
  role         public.member_role not null default 'editor',
  joined_at    timestamptz not null default now(),
  primary key (household_id, user_id)
);
create index household_members_user_idx on public.household_members (user_id);

create table public.household_invites (
  id           uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id) on delete cascade,
  email        text not null,
  role         public.member_role not null check (role <> 'owner'),
  code         text not null unique,
  created_by   uuid not null references public.profiles (id) on delete cascade,
  expires_at   timestamptz not null default now() + interval '7 days',
  accepted_at  timestamptz,
  accepted_by  uuid references public.profiles (id) on delete set null
);

create table public.receipts (
  id                uuid primary key,             -- generated on the client (offline-first)
  household_id      uuid not null references public.households (id) on delete cascade,
  created_by        uuid references public.profiles (id) on delete set null,
  merchant          text not null default '',
  purchase_date     date not null,
  total_minor       bigint not null check (total_minor >= 0),
  currency          text not null check (currency ~ '^[A-Z]{3}$'),
  category          text not null default 'other',
  status            text not null default 'confirmed' check (status in (
                      'captured', 'queuedOffline', 'processing', 'needsReview',
                      'extractionFailed', 'manualEntry', 'confirmed', 'archived')),
  return_days       int check (return_days between 0 and 365),
  payment_method    text,
  notes             text,
  ocr_text          text,
  client_updated_at timestamptz not null,         -- last edit on a device (BR-13 last-write-wins)
  version           int not null default 1,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),  -- server time; pull cursor
  deleted_at        timestamptz                   -- tombstone (BR-09)
);
create index receipts_household_updated_idx on public.receipts (household_id, updated_at);
create index receipts_household_date_idx on public.receipts (household_id, purchase_date desc);

create table public.line_items (
  id               uuid primary key,
  receipt_id       uuid not null references public.receipts (id) on delete cascade,
  position         int not null default 0,
  name             text not null,
  quantity         int not null default 1 check (quantity >= 1),
  unit_price_minor bigint not null default 0 check (unit_price_minor >= 0),
  serial_number    text
);
create index line_items_receipt_idx on public.line_items (receipt_id);

create table public.warranties (
  line_item_id uuid primary key references public.line_items (id) on delete cascade,
  months       int not null check (months between 0 and 120),
  provider     text,
  is_extended  boolean not null default false,
  end_date     date not null                      -- purchase_date + months (BR-01)
);
create index warranties_end_date_idx on public.warranties (end_date);

create table public.attachments (
  id           uuid primary key,
  receipt_id   uuid not null references public.receipts (id) on delete cascade,
  kind         text not null default 'receipt' check (kind in ('receipt', 'product', 'serial')),
  mime_type    text not null default 'image/jpeg',
  size_bytes   int not null default 0,
  storage_path text,
  created_at   timestamptz not null default now()
);
create index attachments_receipt_idx on public.attachments (receipt_id);

create table public.entitlements (
  user_id          uuid primary key references public.profiles (id) on delete cascade,
  tier             text not null default 'free' check (tier in ('free', 'premium')),
  scans_used       int not null default 0,
  claim_packs_used int not null default 0,
  period_start     date not null default date_trunc('month', now())::date,
  expires_at       timestamptz,
  updated_at       timestamptz not null default now()
);

create table public.ai_usage (
  id            bigint generated always as identity primary key,
  user_id       uuid not null references public.profiles (id) on delete cascade,
  model         text,
  input_tokens  int,
  output_tokens int,
  latency_ms    int,
  success       boolean not null,
  error         text,
  created_at    timestamptz not null default now()
);
create index ai_usage_user_created_idx on public.ai_usage (user_id, created_at desc);

-- ---------------------------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------------------------

create or replace function public.touch_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

create trigger profiles_touch before update on public.profiles
  for each row execute function public.touch_updated_at();
create trigger households_touch before update on public.households
  for each row execute function public.touch_updated_at();
create trigger receipts_touch before update on public.receipts
  for each row execute function public.touch_updated_at();
create trigger entitlements_touch before update on public.entitlements
  for each row execute function public.touch_updated_at();

-- New account: profile, personal household (owner) and a Free entitlement.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_name text := coalesce(
    nullif(new.raw_user_meta_data ->> 'display_name', ''),
    nullif(new.raw_user_meta_data ->> 'full_name', ''),
    nullif(new.raw_user_meta_data ->> 'name', ''),
    split_part(new.email, '@', 1));
  v_household uuid;
begin
  insert into public.profiles (id, display_name, email) values (new.id, v_name, lower(new.email));
  insert into public.households (name, owner_id) values (v_name || '''s vault', new.id)
    returning id into v_household;
  insert into public.household_members (household_id, user_id, role) values (v_household, new.id, 'owner');
  insert into public.entitlements (user_id) values (new.id);
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Authorization helpers (security definer avoids RLS recursion)
-- ---------------------------------------------------------------------------

create or replace function public.member_role_in(p_household uuid) returns public.member_role
language sql stable security definer set search_path = public as $$
  select role from public.household_members
  where household_id = p_household and user_id = auth.uid()
$$;

create or replace function public.is_member(p_household uuid) returns boolean
language sql stable as $$ select public.member_role_in(p_household) is not null $$;

-- BR-08: owners and editors can change receipts.
create or replace function public.can_edit(p_household uuid) returns boolean
language sql stable as $$ select public.member_role_in(p_household) in ('owner', 'editor') $$;

create or replace function public.shares_household(p_user uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.household_members a
    join public.household_members b on a.household_id = b.household_id
    where a.user_id = auth.uid() and b.user_id = p_user)
$$;

create or replace function public.receipt_household(p_receipt uuid) returns uuid
language sql stable security definer set search_path = public as $$
  select household_id from public.receipts where id = p_receipt
$$;

create or replace function public.try_uuid(p text) returns uuid
language plpgsql immutable as $$
begin
  return p::uuid;
exception when others then
  return null;
end $$;

-- BR-07 member limit for a household, based on the owner's plan.
create or replace function public.member_limit(p_household uuid) returns int
language sql stable security definer set search_path = public as $$
  select case when e.tier = 'premium' and (e.expires_at is null or e.expires_at > now()) then 6 else 2 end
  from public.households h join public.entitlements e on e.user_id = h.owner_id
  where h.id = p_household
$$;

-- ---------------------------------------------------------------------------
-- Row-Level Security (NFR-SEC-02: deny by default)
-- ---------------------------------------------------------------------------

alter table public.profiles          enable row level security;
alter table public.households        enable row level security;
alter table public.household_members enable row level security;
alter table public.household_invites enable row level security;
alter table public.receipts          enable row level security;
alter table public.line_items        enable row level security;
alter table public.warranties        enable row level security;
alter table public.attachments       enable row level security;
alter table public.entitlements      enable row level security;
alter table public.ai_usage          enable row level security;

create policy profiles_read on public.profiles for select
  using (id = auth.uid() or public.shares_household(id));
create policy profiles_update on public.profiles for update
  using (id = auth.uid()) with check (id = auth.uid());

create policy households_read on public.households for select using (public.is_member(id));
create policy households_rename on public.households for update
  using (public.member_role_in(id) = 'owner') with check (public.member_role_in(id) = 'owner');

create policy members_read on public.household_members for select using (public.is_member(household_id));
-- Owners remove others; anyone but the owner may leave.
create policy members_remove on public.household_members for delete using (
  (public.member_role_in(household_id) = 'owner' and role <> 'owner')
  or (user_id = auth.uid() and role <> 'owner'));

create policy invites_read on public.household_invites for select
  using (public.member_role_in(household_id) = 'owner');

create policy receipts_read on public.receipts for select using (public.is_member(household_id));
create policy receipts_insert on public.receipts for insert with check (public.can_edit(household_id));
create policy receipts_update on public.receipts for update
  using (public.can_edit(household_id)) with check (public.can_edit(household_id));

create policy items_read on public.line_items for select
  using (public.is_member(public.receipt_household(receipt_id)));
create policy items_write on public.line_items for all
  using (public.can_edit(public.receipt_household(receipt_id)))
  with check (public.can_edit(public.receipt_household(receipt_id)));

create policy warranties_read on public.warranties for select using (exists (
  select 1 from public.line_items li
  where li.id = line_item_id and public.is_member(public.receipt_household(li.receipt_id))));
create policy warranties_write on public.warranties for all using (exists (
  select 1 from public.line_items li
  where li.id = line_item_id and public.can_edit(public.receipt_household(li.receipt_id))));

create policy attachments_read on public.attachments for select
  using (public.is_member(public.receipt_household(receipt_id)));
create policy attachments_write on public.attachments for all
  using (public.can_edit(public.receipt_household(receipt_id)))
  with check (public.can_edit(public.receipt_household(receipt_id)));

-- Entitlements and AI usage are written only by Edge Functions (service role).
create policy entitlements_read on public.entitlements for select using (user_id = auth.uid());
create policy ai_usage_read on public.ai_usage for select using (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Storage: private bucket, objects stored as <household>/<receipt>/<file>
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('receipts', 'receipts', false, 6291456,
        array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'application/pdf'])
on conflict (id) do nothing;

create policy receipts_objects_read on storage.objects for select to authenticated using (
  bucket_id = 'receipts' and public.is_member(public.try_uuid((storage.foldername(name))[1])));
create policy receipts_objects_insert on storage.objects for insert to authenticated with check (
  bucket_id = 'receipts' and public.can_edit(public.try_uuid((storage.foldername(name))[1])));
create policy receipts_objects_update on storage.objects for update to authenticated using (
  bucket_id = 'receipts' and public.can_edit(public.try_uuid((storage.foldername(name))[1])));
create policy receipts_objects_delete on storage.objects for delete to authenticated using (
  bucket_id = 'receipts' and public.can_edit(public.try_uuid((storage.foldername(name))[1])));

-- ---------------------------------------------------------------------------
-- Sync API (SSD-4)
-- ---------------------------------------------------------------------------

-- Serialises a receipt in the shape the app's ReceiptModel reads.
create or replace function public.receipt_json(p_id uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', r.id,
    'household_id', r.household_id,
    'created_by', r.created_by,
    'merchant', r.merchant,
    'purchase_date', to_char(r.purchase_date, 'YYYY-MM-DD'),
    'total_minor', r.total_minor,
    'currency', r.currency,
    'category', r.category,
    'status', r.status,
    'return_days', r.return_days,
    'payment_method', r.payment_method,
    'notes', r.notes,
    'ocr_text', r.ocr_text,
    'created_at', r.created_at,
    'updated_at', r.client_updated_at,
    'server_updated_at', r.updated_at,
    'deleted_at', r.deleted_at,
    'version', r.version,
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', li.id,
        'name', li.name,
        'quantity', li.quantity,
        'unit_price_minor', li.unit_price_minor,
        'serial_number', li.serial_number,
        'warranty_months', w.months,
        'warranty_provider', w.provider,
        'warranty_extended', coalesce(w.is_extended, false)) order by li.position)
      from public.line_items li left join public.warranties w on w.line_item_id = li.id
      where li.receipt_id = r.id), '[]'::jsonb),
    'attachments', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', a.id,
        'kind', a.kind,
        'mime_type', a.mime_type,
        'size_bytes', a.size_bytes,
        'storage_path', a.storage_path) order by a.created_at)
      from public.attachments a where a.receipt_id = r.id), '[]'::jsonb))
  from public.receipts r where r.id = p_id
$$;

create or replace function public._upsert_attachments(p_receipt uuid, p_items jsonb) returns void
language sql security definer set search_path = public as $$
  insert into public.attachments (id, receipt_id, kind, mime_type, size_bytes, storage_path)
  select (a ->> 'id')::uuid, p_receipt, coalesce(a ->> 'kind', 'receipt'),
         coalesce(a ->> 'mime_type', 'image/jpeg'), coalesce((a ->> 'size_bytes')::int, 0),
         a ->> 'storage_path'
  from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) a
  on conflict (id) do update
    set storage_path = coalesce(excluded.storage_path, public.attachments.storage_path)
$$;

-- Atomically saves a receipt and its children. If the server copy was edited
-- more recently on another device, it wins and is returned (BR-13); new
-- attachments are still added because photos are never discarded.
create or replace function public.upsert_receipt(p_receipt jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_id        uuid := (p_receipt ->> 'id')::uuid;
  v_household uuid := (p_receipt ->> 'household_id')::uuid;
  v_client_ts timestamptz := (p_receipt ->> 'updated_at')::timestamptz;
  v_date      date := (p_receipt ->> 'purchase_date')::date;
  v_existing  public.receipts%rowtype;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if not public.can_edit(v_household) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  select * into v_existing from public.receipts where id = v_id for update;
  if found then
    if not public.can_edit(v_existing.household_id) then
      raise exception 'forbidden' using errcode = '42501';
    end if;
    if v_existing.client_updated_at > v_client_ts then
      perform public._upsert_attachments(v_id, p_receipt -> 'attachments');
      return jsonb_build_object('conflict', true, 'receipt', public.receipt_json(v_id));
    end if;
  end if;

  insert into public.receipts as r (
    id, household_id, created_by, merchant, purchase_date, total_minor, currency, category,
    status, return_days, payment_method, notes, ocr_text, client_updated_at, deleted_at)
  values (
    v_id, v_household, coalesce(v_existing.created_by, auth.uid()),
    coalesce(p_receipt ->> 'merchant', ''), v_date, (p_receipt ->> 'total_minor')::bigint,
    p_receipt ->> 'currency', coalesce(p_receipt ->> 'category', 'other'),
    coalesce(p_receipt ->> 'status', 'confirmed'), (p_receipt ->> 'return_days')::int,
    p_receipt ->> 'payment_method', p_receipt ->> 'notes', p_receipt ->> 'ocr_text',
    v_client_ts, (p_receipt ->> 'deleted_at')::timestamptz)
  on conflict (id) do update set
    household_id = excluded.household_id,
    merchant = excluded.merchant,
    purchase_date = excluded.purchase_date,
    total_minor = excluded.total_minor,
    currency = excluded.currency,
    category = excluded.category,
    status = excluded.status,
    return_days = excluded.return_days,
    payment_method = excluded.payment_method,
    notes = excluded.notes,
    ocr_text = excluded.ocr_text,
    client_updated_at = excluded.client_updated_at,
    deleted_at = excluded.deleted_at,
    version = r.version + 1;

  -- Line items: replace the set with what the device sent.
  delete from public.line_items
  where receipt_id = v_id
    and id not in (select (i ->> 'id')::uuid from jsonb_array_elements(coalesce(p_receipt -> 'items', '[]')) i);

  insert into public.line_items (id, receipt_id, position, name, quantity, unit_price_minor, serial_number)
  select (i ->> 'id')::uuid, v_id, (ord - 1)::int, i ->> 'name', coalesce((i ->> 'quantity')::int, 1),
         coalesce((i ->> 'unit_price_minor')::bigint, 0), i ->> 'serial_number'
  from jsonb_array_elements(coalesce(p_receipt -> 'items', '[]')) with ordinality as t(i, ord)
  on conflict (id) do update set
    position = excluded.position, name = excluded.name, quantity = excluded.quantity,
    unit_price_minor = excluded.unit_price_minor, serial_number = excluded.serial_number;

  -- Warranties: end date derived on the server too (BR-01; Postgres clamps month ends).
  delete from public.warranties w using public.line_items li
  where w.line_item_id = li.id and li.receipt_id = v_id
    and li.id not in (
      select (i ->> 'id')::uuid from jsonb_array_elements(coalesce(p_receipt -> 'items', '[]')) i
      where coalesce((i ->> 'warranty_months')::int, 0) > 0);

  insert into public.warranties (line_item_id, months, provider, is_extended, end_date)
  select (i ->> 'id')::uuid, (i ->> 'warranty_months')::int, i ->> 'warranty_provider',
         coalesce((i ->> 'warranty_extended')::boolean, false),
         (v_date + make_interval(months => (i ->> 'warranty_months')::int))::date
  from jsonb_array_elements(coalesce(p_receipt -> 'items', '[]')) i
  where coalesce((i ->> 'warranty_months')::int, 0) > 0
  on conflict (line_item_id) do update set
    months = excluded.months, provider = excluded.provider,
    is_extended = excluded.is_extended, end_date = excluded.end_date;

  -- Attachments: the device's set (removed photos are dropped).
  delete from public.attachments
  where receipt_id = v_id
    and id not in (select (a ->> 'id')::uuid from jsonb_array_elements(coalesce(p_receipt -> 'attachments', '[]')) a);
  perform public._upsert_attachments(v_id, p_receipt -> 'attachments');

  return jsonb_build_object('conflict', false, 'receipt', public.receipt_json(v_id));
end $$;

-- Changes since a cursor (server time), including tombstones.
create or replace function public.pull_changes(p_household_id uuid, p_since timestamptz default null)
returns setof jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_member(p_household_id) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  return query
    select public.receipt_json(r.id)
    from public.receipts r
    where r.household_id = p_household_id and (p_since is null or r.updated_at > p_since)
    order by r.updated_at
    limit 500;
end $$;

-- ---------------------------------------------------------------------------
-- Household sharing (FR-HH-01..04)
-- ---------------------------------------------------------------------------

create or replace function public.create_household_invite(
  p_household_id uuid, p_email text, p_role public.member_role default 'editor')
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_code text;
  v_expires timestamptz := now() + interval '7 days';
begin
  if public.member_role_in(p_household_id) is distinct from 'owner' then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if p_role = 'owner' then
    raise exception 'invalid_role' using errcode = '22023';
  end if;
  if (select count(*) from public.household_members where household_id = p_household_id)
     >= public.member_limit(p_household_id) then
    raise exception 'member_limit' using errcode = 'P0001';
  end if;
  v_code := upper(substr(encode(gen_random_bytes(6), 'hex'), 1, 8));
  insert into public.household_invites (household_id, email, role, code, created_by, expires_at)
  values (p_household_id, lower(trim(p_email)), p_role, v_code, auth.uid(), v_expires);
  return jsonb_build_object('code', v_code, 'expires_at', v_expires);
end $$;

create or replace function public.accept_household_invite(p_code text) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_invite public.household_invites%rowtype;
  v_email text := lower(auth.jwt() ->> 'email');
begin
  select * into v_invite from public.household_invites
  where code = upper(trim(p_code)) and accepted_at is null and expires_at > now()
  for update;
  -- Codes are bound to the invited email so a leaked code is useless.
  if not found or v_invite.email <> v_email then
    raise exception 'invalid_invite' using errcode = 'P0001';
  end if;
  if (select count(*) from public.household_members where household_id = v_invite.household_id)
     >= public.member_limit(v_invite.household_id) then
    raise exception 'member_limit' using errcode = 'P0001';
  end if;
  insert into public.household_members (household_id, user_id, role)
  values (v_invite.household_id, auth.uid(), v_invite.role)
  on conflict (household_id, user_id) do nothing;
  update public.household_invites set accepted_at = now(), accepted_by = auth.uid() where id = v_invite.id;
  return v_invite.household_id;
end $$;

-- ---------------------------------------------------------------------------
-- AI quota (BR-07), called by the extract-receipt Edge Function only
-- ---------------------------------------------------------------------------

create or replace function public.reserve_ai_scan(p_user uuid) returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_tier    text;
  v_expires timestamptz;
  v_used    int;
  v_period  date;
begin
  insert into public.entitlements (user_id) values (p_user) on conflict (user_id) do nothing;
  select tier, expires_at, scans_used, period_start into v_tier, v_expires, v_used, v_period
  from public.entitlements where user_id = p_user for update;
  if v_period < date_trunc('month', now())::date then
    update public.entitlements
      set scans_used = 0, claim_packs_used = 0, period_start = date_trunc('month', now())::date
      where user_id = p_user;
    v_used := 0;
  end if;
  if not (v_tier = 'premium' and (v_expires is null or v_expires > now())) and v_used >= 15 then
    return false;
  end if;
  update public.entitlements set scans_used = scans_used + 1 where user_id = p_user;
  return true;
end $$;

create or replace function public.refund_ai_scan(p_user uuid) returns void
language sql security definer set search_path = public as $$
  update public.entitlements set scans_used = greatest(scans_used - 1, 0) where user_id = p_user
$$;

revoke execute on function public.reserve_ai_scan(uuid) from public, anon, authenticated;
revoke execute on function public.refund_ai_scan(uuid) from public, anon, authenticated;
revoke execute on function public._upsert_attachments(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.reserve_ai_scan(uuid) to service_role;
grant execute on function public.refund_ai_scan(uuid) to service_role;
