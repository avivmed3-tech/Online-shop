-- =============================================================================
-- Phase 3: Rich catalog — subcategories, multi-image gallery, variants with
--          per-variant SKUs, badges (מבצע/חדש) and featured flag.
--   The client renders a procedural multi-view gallery when images = '[]',
--   so demo items always show several pictures even with no hosted photos.
-- =============================================================================

alter table public.products
  add column if not exists subcategory text,
  add column if not exists images   jsonb   not null default '[]'::jsonb,
  add column if not exists variants jsonb   not null default '[]'::jsonb,
  add column if not exists badge    text,
  add column if not exists featured boolean not null default false;

-- Badge is a fixed vocabulary the UI knows how to render.
alter table public.products drop constraint if exists products_badge_check;
alter table public.products
  add constraint products_badge_check
  check (badge is null or badge in ('מבצע','חדש'));

-- images / variants must be JSON arrays ([{label, sku}] for variants).
alter table public.products drop constraint if exists products_images_check;
alter table public.products
  add constraint products_images_check
  check (jsonb_typeof(images) = 'array');

alter table public.products drop constraint if exists products_variants_check;
alter table public.products
  add constraint products_variants_check
  check (jsonb_typeof(variants) = 'array');

-- Professional SKUs are unique (ignoring blank/missing); also makes the demo
-- seed idempotent via ON CONFLICT.
create unique index if not exists products_sku_key
  on public.products (sku)
  where sku is not null and sku <> '';

create index if not exists products_category_idx
  on public.products (category, subcategory);
