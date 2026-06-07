-- =============================================================================
-- B2B Catalog — Schema, Security (RLS) and tamper-proof pricing
-- Phase 1: users (admin / customer), per-customer discount, product visibility,
--          orders + order history.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- PROFILES  (one row per auth user; extends Supabase auth.users)
--   role = 'admin'    -> the business owner
--   role = 'customer' -> a B2B customer (business)
--   discount_pct      -> per-customer discount applied to every product price
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  role          text not null default 'customer' check (role in ('admin','customer')),
  business_name text,
  contact_name  text,
  phone         text,
  email         text,
  discount_pct  numeric(5,2) not null default 0 check (discount_pct >= 0 and discount_pct <= 100),
  active        boolean not null default true,
  created_at    timestamptz not null default now()
);

-- Admin check helper. SECURITY DEFINER avoids RLS recursion on profiles.
create or replace function public.is_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin' and active
  );
$$;

-- Auto-create a profile row whenever a new auth user is created.
-- Metadata (business_name / contact_name / phone) can be passed at sign-up.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, business_name, contact_name, phone)
  values (
    new.id,
    new.email,
    new.raw_user_meta_data->>'business_name',
    new.raw_user_meta_data->>'contact_name',
    new.raw_user_meta_data->>'phone'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- PRODUCTS  (the business owner's catalog; base_price is the list price)
-- ---------------------------------------------------------------------------
create table if not exists public.products (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  sku         text,
  category    text,
  description text,
  image_url   text,
  base_price  numeric(12,2) not null default 0,
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- CUSTOMER_PRODUCTS  (per-customer visibility / "items relevant to them")
--   Rule: if a customer has NO rows here -> they see ALL active products.
--         if a customer HAS rows here    -> they see ONLY those products.
-- ---------------------------------------------------------------------------
create table if not exists public.customer_products (
  customer_id uuid not null references public.profiles(id) on delete cascade,
  product_id  uuid not null references public.products(id) on delete cascade,
  primary key (customer_id, product_id)
);

-- ---------------------------------------------------------------------------
-- ORDERS + ORDER_ITEMS  (persisted history for admin + each customer)
-- ---------------------------------------------------------------------------
create table if not exists public.orders (
  id          uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.profiles(id) on delete cascade,
  status      text not null default 'pending' check (status in ('pending','confirmed','sent','cancelled')),
  total       numeric(12,2) not null default 0,
  note        text,
  channel     text,          -- 'whatsapp' | 'email' | null
  created_at  timestamptz not null default now()
);
create index if not exists orders_customer_idx on public.orders(customer_id, created_at desc);

create table if not exists public.order_items (
  id          uuid primary key default gen_random_uuid(),
  order_id    uuid not null references public.orders(id) on delete cascade,
  product_id  uuid references public.products(id) on delete set null,
  name        text not null,
  sku         text,
  variant     text,
  unit_price  numeric(12,2) not null default 0,
  qty         integer not null default 1 check (qty > 0),
  line_total  numeric(12,2) not null default 0
);
create index if not exists order_items_order_idx on public.order_items(order_id);

-- ---------------------------------------------------------------------------
-- TAMPER-PROOF PRICING
--   unit_price is computed on the SERVER from products.base_price and the
--   customer's discount_pct — the client cannot dictate the price it pays.
-- ---------------------------------------------------------------------------
create or replace function public.set_order_item_price()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_base     numeric(12,2);
  v_discount numeric(5,2);
  v_customer uuid;
begin
  select customer_id into v_customer from public.orders where id = new.order_id;
  select coalesce(discount_pct, 0) into v_discount from public.profiles where id = v_customer;

  if new.product_id is not null then
    select base_price into v_base from public.products where id = new.product_id;
    if v_base is not null then
      new.unit_price := round(v_base * (1 - coalesce(v_discount, 0) / 100.0), 2);
    end if;
  end if;

  new.line_total := round(new.unit_price * new.qty, 2);
  return new;
end;
$$;

drop trigger if exists trg_set_order_item_price on public.order_items;
create trigger trg_set_order_item_price
  before insert on public.order_items
  for each row execute function public.set_order_item_price();

create or replace function public.recompute_order_total()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order uuid;
begin
  v_order := coalesce(new.order_id, old.order_id);
  update public.orders
     set total = coalesce((select sum(line_total) from public.order_items where order_id = v_order), 0)
   where id = v_order;
  return null;
end;
$$;

drop trigger if exists trg_recompute_order_total on public.order_items;
create trigger trg_recompute_order_total
  after insert or update or delete on public.order_items
  for each row execute function public.recompute_order_total();

-- ---------------------------------------------------------------------------
-- ROW LEVEL SECURITY
-- ---------------------------------------------------------------------------
alter table public.profiles          enable row level security;
alter table public.products          enable row level security;
alter table public.customer_products enable row level security;
alter table public.orders            enable row level security;
alter table public.order_items       enable row level security;

-- PROFILES: read own row or (admin) all; only admin may modify.
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select using (id = auth.uid() or public.is_admin());

drop policy if exists profiles_admin_write on public.profiles;
create policy profiles_admin_write on public.profiles
  for all using (public.is_admin()) with check (public.is_admin());

-- PRODUCTS: admin full access; customer sees active products honoring visibility.
drop policy if exists products_select on public.products;
create policy products_select on public.products
  for select using (
    public.is_admin()
    or (
      active and (
        not exists (select 1 from public.customer_products cp where cp.customer_id = auth.uid())
        or exists (select 1 from public.customer_products cp
                   where cp.customer_id = auth.uid() and cp.product_id = products.id)
      )
    )
  );

drop policy if exists products_admin_write on public.products;
create policy products_admin_write on public.products
  for all using (public.is_admin()) with check (public.is_admin());

-- CUSTOMER_PRODUCTS: customer reads own; admin manages.
drop policy if exists cp_select on public.customer_products;
create policy cp_select on public.customer_products
  for select using (customer_id = auth.uid() or public.is_admin());

drop policy if exists cp_admin_write on public.customer_products;
create policy cp_admin_write on public.customer_products
  for all using (public.is_admin()) with check (public.is_admin());

-- ORDERS: customer reads + creates own; admin reads all + updates status.
drop policy if exists orders_select on public.orders;
create policy orders_select on public.orders
  for select using (customer_id = auth.uid() or public.is_admin());

drop policy if exists orders_insert on public.orders;
create policy orders_insert on public.orders
  for insert with check (customer_id = auth.uid());

drop policy if exists orders_admin_update on public.orders;
create policy orders_admin_update on public.orders
  for update using (public.is_admin()) with check (public.is_admin());

-- ORDER_ITEMS: visible/insertable only for the owning order; admin reads all.
drop policy if exists oi_select on public.order_items;
create policy oi_select on public.order_items
  for select using (
    public.is_admin()
    or exists (select 1 from public.orders o where o.id = order_items.order_id and o.customer_id = auth.uid())
  );

drop policy if exists oi_insert on public.order_items;
create policy oi_insert on public.order_items
  for insert with check (
    exists (select 1 from public.orders o where o.id = order_items.order_id and o.customer_id = auth.uid())
  );

-- ---------------------------------------------------------------------------
-- HARDENING
--   Trigger functions must never be callable directly through the PostgREST
--   RPC API. They still fire as triggers (which run as the table owner, not
--   the calling role). is_admin() is intentionally left executable because the
--   RLS policies above call it on every request.
-- ---------------------------------------------------------------------------
revoke execute on function public.handle_new_user()      from public, anon, authenticated;
revoke execute on function public.set_order_item_price()  from public, anon, authenticated;
revoke execute on function public.recompute_order_total() from public, anon, authenticated;
