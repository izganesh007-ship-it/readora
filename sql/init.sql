CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS citext;

DO $$ BEGIN
  CREATE TYPE book_access AS ENUM ('FREE','PAID');
EXCEPTION WHEN duplicate_object THEN null; END $$;
DO $$ BEGIN
  CREATE TYPE purchase_status AS ENUM ('PENDING','PAID','EXPIRED','INVALID');
EXCEPTION WHEN duplicate_object THEN null; END $$;
DO $$ BEGIN
  CREATE TYPE download_status AS ENUM ('ACTIVE','USED','EXPIRED','REVOKED');
EXCEPTION WHEN duplicate_object THEN null; END $$;
DO $$ BEGIN
  CREATE TYPE admin_role AS ENUM ('OWNER','ADMIN','EDITOR','SUPPORT');
EXCEPTION WHEN duplicate_object THEN null; END $$;

CREATE TABLE IF NOT EXISTS admins (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email citext UNIQUE NOT NULL,
  password_hash text NOT NULL,
  role admin_role NOT NULL DEFAULT 'ADMIN',
  two_factor_secret text,
  failed_attempts int NOT NULL DEFAULT 0,
  locked_until timestamptz,
  last_login_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email citext UNIQUE,
  display_name text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text UNIQUE NOT NULL,
  slug text UNIQUE NOT NULL,
  description text,
  cover_url text,
  sort_order int NOT NULL DEFAULT 0,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS books (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL,
  slug text UNIQUE NOT NULL,
  author text NOT NULL,
  category_id uuid REFERENCES categories(id) ON DELETE SET NULL,
  description text NOT NULL,
  preview_text text,
  access book_access NOT NULL DEFAULT 'PAID',
  price_cents int NOT NULL DEFAULT 0 CHECK (price_cents >= 0),
  currency char(3) NOT NULL DEFAULT 'USD',
  cover_key text,
  epub_key text,
  pdf_key text,
  reader_format text NOT NULL DEFAULT 'CHAPTERS' CHECK (reader_format IN ('CHAPTERS','TXT','HTML','PDF')),
  reader_content text,
  reader_content_key text,
  allow_free_download boolean NOT NULL DEFAULT false,
  rating numeric(3,2) NOT NULL DEFAULT 0,
  review_count int NOT NULL DEFAULT 0,
  popularity_score int NOT NULL DEFAULT 0,
  published_at timestamptz,
  featured boolean NOT NULL DEFAULT false,
  is_active boolean NOT NULL DEFAULT true,
  search_vector tsvector GENERATED ALWAYS AS (
    setweight(to_tsvector('english', coalesce(title,'')), 'A') ||
    setweight(to_tsvector('english', coalesce(author,'')), 'A') ||
    setweight(to_tsvector('english', coalesce(description,'')), 'B') ||
    setweight(to_tsvector('english', coalesce(preview_text,'')), 'C')
  ) STORED,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS tags (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text UNIQUE NOT NULL,
  slug text UNIQUE NOT NULL
);

CREATE TABLE IF NOT EXISTS book_tags (
  book_id uuid NOT NULL REFERENCES books(id) ON DELETE CASCADE,
  tag_id uuid NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
  PRIMARY KEY (book_id, tag_id)
);

CREATE TABLE IF NOT EXISTS book_chapters (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  book_id uuid NOT NULL REFERENCES books(id) ON DELETE CASCADE,
  chapter_index int NOT NULL,
  title text NOT NULL,
  content text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(book_id, chapter_index)
);

CREATE TABLE IF NOT EXISTS reviews (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  book_id uuid NOT NULL REFERENCES books(id) ON DELETE CASCADE,
  user_id uuid REFERENCES users(id) ON DELETE SET NULL,
  reviewer_name text NOT NULL,
  rating int NOT NULL CHECK (rating BETWEEN 1 AND 5),
  body text NOT NULL,
  is_approved boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS purchases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES users(id) ON DELETE SET NULL,
  book_id uuid NOT NULL REFERENCES books(id) ON DELETE RESTRICT,
  buyer_email citext,
  amount_cents int NOT NULL,
  currency char(3) NOT NULL DEFAULT 'USD',
  status purchase_status NOT NULL DEFAULT 'PENDING',
  payment_provider text,
  provider_payment_id text,
  provider_checkout_url text,
  btcpay_invoice_id text UNIQUE,
  btcpay_checkout_link text,
  access_token_hash text,
  paid_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS download_links (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  purchase_id uuid NOT NULL REFERENCES purchases(id) ON DELETE CASCADE,
  book_id uuid NOT NULL REFERENCES books(id) ON DELETE RESTRICT,
  token_hash text UNIQUE NOT NULL,
  status download_status NOT NULL DEFAULT 'ACTIVE',
  expires_at timestamptz NOT NULL,
  redeemed_at timestamptz,
  redeemed_ip inet,
  user_agent text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS reader_progress (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES users(id) ON DELETE CASCADE,
  anon_key text,
  book_id uuid NOT NULL REFERENCES books(id) ON DELETE CASCADE,
  chapter_index int NOT NULL DEFAULT 0,
  percent numeric(5,2) NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, book_id),
  UNIQUE(anon_key, book_id)
);

CREATE TABLE IF NOT EXISTS homepage_sections (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL,
  slug text UNIQUE NOT NULL,
  section_type text NOT NULL DEFAULT 'MANUAL',
  sort_order int NOT NULL DEFAULT 0,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS homepage_section_books (
  section_id uuid NOT NULL REFERENCES homepage_sections(id) ON DELETE CASCADE,
  book_id uuid NOT NULL REFERENCES books(id) ON DELETE CASCADE,
  sort_order int NOT NULL DEFAULT 0,
  PRIMARY KEY(section_id, book_id)
);

CREATE TABLE IF NOT EXISTS promotions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  code text UNIQUE,
  discount_percent int CHECK(discount_percent BETWEEN 0 AND 100),
  starts_at timestamptz,
  ends_at timestamptz,
  is_active boolean NOT NULL DEFAULT true
);

CREATE TABLE IF NOT EXISTS book_views (
  id bigserial PRIMARY KEY,
  book_id uuid NOT NULL REFERENCES books(id) ON DELETE CASCADE,
  ip_hash text,
  user_agent text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS audit_logs (
  id bigserial PRIMARY KEY,
  actor_admin_id uuid REFERENCES admins(id) ON DELETE SET NULL,
  action text NOT NULL,
  entity_type text,
  entity_id text,
  ip inet,
  metadata jsonb NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS books_search_idx ON books USING GIN(search_vector);
CREATE INDEX IF NOT EXISTS books_category_idx ON books(category_id);
CREATE INDEX IF NOT EXISTS books_featured_idx ON books(featured) WHERE featured = true;
CREATE INDEX IF NOT EXISTS books_popularity_idx ON books(popularity_score DESC);
CREATE INDEX IF NOT EXISTS book_chapters_book_idx ON book_chapters(book_id, chapter_index);
CREATE INDEX IF NOT EXISTS purchases_access_token_idx ON purchases(access_token_hash);
CREATE INDEX IF NOT EXISTS purchases_invoice_idx ON purchases(btcpay_invoice_id);
CREATE INDEX IF NOT EXISTS purchases_provider_payment_idx ON purchases(provider_payment_id);
CREATE INDEX IF NOT EXISTS purchases_status_idx ON purchases(status);
CREATE INDEX IF NOT EXISTS download_links_token_idx ON download_links(token_hash);
CREATE INDEX IF NOT EXISTS download_links_status_expires_idx ON download_links(status, expires_at);
CREATE INDEX IF NOT EXISTS book_views_book_created_idx ON book_views(book_id, created_at DESC);

INSERT INTO categories(name, slug, description) VALUES
('Fiction','fiction','Premium literary and genre fiction'),
('Technology','technology','Software, AI, security and databases'),
('Business','business','Markets, startups and strategy'),
('Sci-Fi','sci-fi','Speculative futures and space stories')
ON CONFLICT DO NOTHING;

-- Compatibility for existing databases created before later Readora revisions
ALTER TABLE purchases ADD COLUMN IF NOT EXISTS access_token_hash text;
CREATE INDEX IF NOT EXISTS purchases_access_token_idx ON purchases(access_token_hash);

ALTER TABLE books ADD COLUMN IF NOT EXISTS reader_format text NOT NULL DEFAULT 'CHAPTERS';
ALTER TABLE books ADD COLUMN IF NOT EXISTS reader_content text;
ALTER TABLE books ADD COLUMN IF NOT EXISTS reader_content_key text;
ALTER TABLE books ADD COLUMN IF NOT EXISTS allow_free_download boolean NOT NULL DEFAULT false;
