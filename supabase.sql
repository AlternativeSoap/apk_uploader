-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  APK Uploader — Supabase Database Setup                                  ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝
--
-- QUICK START
--   1. Supabase Dashboard → SQL Editor → New query
--   2. Paste this entire file → Run
--   3. Set SUPABASE_URL + SUPABASE_ANON_KEY in config.js → upload a test APK
--
-- ARCHITECTURE
--   Browser (anon key, no login)
--        │
--        ├─► storage.objects  INSERT  →  bucket: apk-uploads  (.apk file)
--        └─► apk_uploads      INSERT  →  metadata + public download URL
--
--        download.html
--        └─► apk_uploads      SELECT  →  latest row by created_at DESC
--
-- WHY GRANTS + RLS BOTH MATTER
--   Tables created via SQL do NOT auto-grant the `anon` role.
--   PostgREST checks GRANT first, then RLS. Missing either causes failures.
--
-- SECURITY NOTE
--   Anyone with your anon key can upload APKs. That is intentional for this
--   static GitHub Pages app. Do not embed the service_role key in the frontend.
--
-- SAFE TO RE-RUN: all statements are idempotent.
-- =============================================================================


-- ─────────────────────────────────────────────────────────────────────────────
-- Configuration (single source of truth — keep in sync with index.html BUCKET)
-- ─────────────────────────────────────────────────────────────────────────────
-- Bucket ID:     apk-uploads
-- Max APK size:  1 GiB (1 073 741 824 bytes)
-- MIME filter:   none (browsers send varying types for .apk files)


-- ─────────────────────────────────────────────────────────────────────────────
-- 1 · Extensions
-- ─────────────────────────────────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "pgcrypto";


-- ─────────────────────────────────────────────────────────────────────────────
-- 2 · Storage bucket
-- ─────────────────────────────────────────────────────────────────────────────
-- public = true  → direct URL downloads work without signed URLs
-- ON CONFLICT    → fixes buckets created earlier as private or size-limited
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'apk-uploads',
  'apk-uploads',
  true,
  1073741824,   -- 1 GiB
  NULL          -- allow any MIME type
)
ON CONFLICT (id) DO UPDATE SET
  public             = EXCLUDED.public,
  file_size_limit    = GREATEST(
                         COALESCE(storage.buckets.file_size_limit, 0),
                         EXCLUDED.file_size_limit
                       ),
  allowed_mime_types = EXCLUDED.allowed_mime_types;


-- ─────────────────────────────────────────────────────────────────────────────
-- 3 · Metadata table
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.apk_uploads (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  original_name text        NOT NULL,
  storage_path  text        NOT NULL,
  file_size     bigint      NOT NULL,
  download_url  text        NOT NULL,
  created_at    timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT apk_uploads_original_name_not_empty
    CHECK (length(trim(original_name)) > 0),
  CONSTRAINT apk_uploads_storage_path_not_empty
    CHECK (length(trim(storage_path)) > 0),
  CONSTRAINT apk_uploads_download_url_not_empty
    CHECK (length(trim(download_url)) > 0),
  CONSTRAINT apk_uploads_file_size_positive
    CHECK (file_size > 0)
);

COMMENT ON TABLE public.apk_uploads IS
  'APK Uploader — one row per upload. download.html reads the latest row.';

COMMENT ON COLUMN public.apk_uploads.original_name IS 'Original .apk filename from the uploader';
COMMENT ON COLUMN public.apk_uploads.storage_path  IS 'Object key inside the apk-uploads bucket';
COMMENT ON COLUMN public.apk_uploads.file_size     IS 'Size in bytes';
COMMENT ON COLUMN public.apk_uploads.download_url  IS 'Public storage URL returned by getPublicUrl()';
COMMENT ON COLUMN public.apk_uploads.created_at    IS 'Used to determine the latest APK';

-- Fast path for: .order('created_at', { ascending: false }).limit(1)
CREATE INDEX IF NOT EXISTS apk_uploads_created_at_idx
  ON public.apk_uploads (created_at DESC);

-- Apply constraints when the table already existed from an earlier setup
DO $migrate$ BEGIN
  ALTER TABLE public.apk_uploads
    ADD CONSTRAINT apk_uploads_original_name_not_empty
    CHECK (length(trim(original_name)) > 0);
EXCEPTION WHEN duplicate_object THEN NULL;
END $migrate$;

DO $migrate$ BEGIN
  ALTER TABLE public.apk_uploads
    ADD CONSTRAINT apk_uploads_storage_path_not_empty
    CHECK (length(trim(storage_path)) > 0);
EXCEPTION WHEN duplicate_object THEN NULL;
END $migrate$;

DO $migrate$ BEGIN
  ALTER TABLE public.apk_uploads
    ADD CONSTRAINT apk_uploads_download_url_not_empty
    CHECK (length(trim(download_url)) > 0);
EXCEPTION WHEN duplicate_object THEN NULL;
END $migrate$;

DO $migrate$ BEGIN
  ALTER TABLE public.apk_uploads
    ADD CONSTRAINT apk_uploads_file_size_positive
    CHECK (file_size > 0);
EXCEPTION WHEN duplicate_object THEN NULL;
END $migrate$;


-- ─────────────────────────────────────────────────────────────────────────────
-- 4 · Privileges
-- ─────────────────────────────────────────────────────────────────────────────
-- Revoke default public access, then grant only what the app needs.
REVOKE ALL ON public.apk_uploads FROM PUBLIC;

GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

GRANT SELECT, INSERT ON public.apk_uploads TO anon;
GRANT SELECT, INSERT ON public.apk_uploads TO authenticated;
GRANT ALL            ON public.apk_uploads TO service_role;


-- ─────────────────────────────────────────────────────────────────────────────
-- 5 · Row Level Security — apk_uploads
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.apk_uploads ENABLE ROW LEVEL SECURITY;

-- Clean up legacy / duplicate policy names from earlier setups
DROP POLICY IF EXISTS "Public read access"   ON public.apk_uploads;
DROP POLICY IF EXISTS "Service role insert"  ON public.apk_uploads;
DROP POLICY IF EXISTS "Allow public insert"  ON public.apk_uploads;
DROP POLICY IF EXISTS "apk_uploader_select" ON public.apk_uploads;
DROP POLICY IF EXISTS "apk_uploader_insert" ON public.apk_uploads;

CREATE POLICY "apk_uploader_select"
  ON public.apk_uploads
  AS PERMISSIVE
  FOR SELECT
  TO anon, authenticated
  USING (true);

CREATE POLICY "apk_uploader_insert"
  ON public.apk_uploads
  AS PERMISSIVE
  FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);


-- ─────────────────────────────────────────────────────────────────────────────
-- 6 · Row Level Security — storage.objects
-- ─────────────────────────────────────────────────────────────────────────────
-- Public buckets bypass RLS for URL downloads, but uploads always need INSERT.
-- Policies must target `anon` — that is the role the browser client uses.

DROP POLICY IF EXISTS "Public APK download"         ON storage.objects;
DROP POLICY IF EXISTS "Allow APK upload"            ON storage.objects;
DROP POLICY IF EXISTS "apk_uploader_storage_select" ON storage.objects;
DROP POLICY IF EXISTS "apk_uploader_storage_insert" ON storage.objects;

CREATE POLICY "apk_uploader_storage_select"
  ON storage.objects
  AS PERMISSIVE
  FOR SELECT
  TO anon, authenticated
  USING (bucket_id = 'apk-uploads');

CREATE POLICY "apk_uploader_storage_insert"
  ON storage.objects
  AS PERMISSIVE
  FOR INSERT
  TO anon, authenticated
  WITH CHECK (bucket_id = 'apk-uploads');


-- ─────────────────────────────────────────────────────────────────────────────
-- 7 · Refresh API schema cache
-- ─────────────────────────────────────────────────────────────────────────────
NOTIFY pgrst, 'reload schema';


-- ─────────────────────────────────────────────────────────────────────────────
-- 8 · Self-check (prints results in the SQL Editor “Messages” panel)
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
  v_bucket_public   boolean;
  v_bucket_limit    bigint;
  v_table_exists    boolean;
  v_anon_grants     text[];
  v_table_policies  int;
  v_storage_policies int;
BEGIN
  SELECT public, file_size_limit
  INTO v_bucket_public, v_bucket_limit
  FROM storage.buckets
  WHERE id = 'apk-uploads';

  SELECT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'apk_uploads'
  ) INTO v_table_exists;

  SELECT coalesce(array_agg(privilege_type ORDER BY privilege_type), '{}')
  INTO v_anon_grants
  FROM information_schema.role_table_grants
  WHERE table_schema = 'public'
    AND table_name   = 'apk_uploads'
    AND grantee      = 'anon';

  SELECT count(*) INTO v_table_policies
  FROM pg_policies
  WHERE schemaname = 'public' AND tablename = 'apk_uploads';

  SELECT count(*) INTO v_storage_policies
  FROM pg_policies
  WHERE schemaname = 'storage' AND tablename = 'objects'
    AND policyname LIKE 'apk_uploader_storage_%';

  RAISE NOTICE '────────────────────────────────────────';
  RAISE NOTICE 'APK Uploader setup verification';
  RAISE NOTICE '────────────────────────────────────────';

  IF v_bucket_public IS NULL THEN
    RAISE WARNING '✗ Bucket "apk-uploads" not found';
  ELSIF v_bucket_public THEN
    RAISE NOTICE '✓ Bucket "apk-uploads" exists and is public (limit: % bytes)', v_bucket_limit;
  ELSE
    RAISE WARNING '✗ Bucket exists but public = false — re-run section 2';
  END IF;

  IF v_table_exists THEN
    RAISE NOTICE '✓ Table public.apk_uploads exists';
  ELSE
    RAISE WARNING '✗ Table public.apk_uploads missing';
  END IF;

  IF v_anon_grants @> ARRAY['SELECT', 'INSERT'] THEN
    RAISE NOTICE '✓ anon grants: %', array_to_string(v_anon_grants, ', ');
  ELSE
    RAISE WARNING '✗ anon grants incomplete (need SELECT + INSERT): %',
      coalesce(array_to_string(v_anon_grants, ', '), '(none)');
  END IF;

  IF v_table_policies >= 2 THEN
    RAISE NOTICE '✓ apk_uploads policies: %', v_table_policies;
  ELSE
    RAISE WARNING '✗ apk_uploads policies: % (expected ≥ 2)', v_table_policies;
  END IF;

  IF v_storage_policies >= 2 THEN
    RAISE NOTICE '✓ storage policies: %', v_storage_policies;
  ELSE
    RAISE WARNING '✗ storage policies: % (expected ≥ 2)', v_storage_policies;
  END IF;

  RAISE NOTICE '────────────────────────────────────────';
  RAISE NOTICE 'Next: set config.js → upload a test APK';
  RAISE NOTICE '────────────────────────────────────────';
END $$;
