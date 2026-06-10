-- =============================================================================
-- Phase 2: Public catalog + per-customer custom prices ("price quotes")
--   1. Anyone (no login) can browse ACTIVE products at list price.
--   2. Admin can pin a custom price per (customer, product) that OVERRIDES the
--      customer's discount_pct. Server-side pricing trigger honors it.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- CUSTOMER_PRICES  (admin-managed price quote per customer per product)
--   Effective price for a customer:
--     custom_price if a row exists here, else base_price * (1 - discount_pct).
-- ---------------------------------------------------------------------------
create table if not exists public.customer_prices (
  customer_id  uuid not null references public.profiles(id) on delete cascade,
  product_id   uuid not null references public.products(id) on delete cascade,
  custom_price numeric(12,2) not null check (custom_price >= 0),
  updated_at   timestamptz not null default now(),
  primary key (customer_id, product_id)
);

alter table public.customer_prices enable row level security;

-- Customer reads only their own quote; admin reads/manages everything.
drop policy if exists cprice_select on public.customer_prices;
create policy cprice_select on public.customer_prices
  for select using (customer_id = auth.uid() or public.is_admin());

drop policy if exists cprice_admin_write on public.customer_prices;
create policy cprice_admin_write on public.customer_prices
  for all using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------------------
-- PUBLIC CATALOG (no login)
--   The existing products_select policy already evaluates to "active" for
--   anonymous visitors (auth.uid() is null -> no visibility rows -> sees all
--   active products). Make the grant explicit so the public catalog cannot
--   break if default grants are ever tightened.
-- ---------------------------------------------------------------------------
grant select on public.products to anon;

-- Guests must never read pricing/visibility internals of other customers.
revoke all on public.customer_prices  from anon;
revoke all on public.customer_products from anon;
revoke all on public.profiles          from anon;
revoke all on public.orders            from anon;
revoke all on public.order_items       from anon;

-- ---------------------------------------------------------------------------
-- SERVER-SIDE PRICING (updated)
--   unit_price resolution order:
--     1. customer_prices.custom_price for (customer, product)   <- price quote
--     2. products.base_price * (1 - profiles.discount_pct/100)  <- discount
--   The client still cannot dictate the price it pays.
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
  v_custom   numeric(12,2);
  v_customer uuid;
begin
  select customer_id into v_customer from public.orders where id = new.order_id;
  select coalesce(discount_pct, 0) into v_discount from public.profiles where id = v_customer;

  if new.product_id is not null then
    select custom_price into v_custom
      from public.customer_prices
     where customer_id = v_customer and product_id = new.product_id;

    if v_custom is not null then
      new.unit_price := v_custom;
    else
      select base_price into v_base from public.products where id = new.product_id;
      if v_base is not null then
        new.unit_price := round(v_base * (1 - coalesce(v_discount, 0) / 100.0), 2);
      end if;
    end if;
  end if;

  new.line_total := round(new.unit_price * new.qty, 2);
  return new;
end;
$$;

revoke execute on function public.set_order_item_price() from public, anon, authenticated;
