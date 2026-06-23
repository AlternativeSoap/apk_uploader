-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  APK Uploader — Supabase Teardown (undo supabase.sql)                    ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝
--
-- QUICK START
--   1. Supabase Dashboard → SQL Editor → New query
--   2. Paste this entire file → Run
--
-- WHAT THIS REMOVES (everything created by supabase.sql)
--   • All files in storage bucket `apk-uploads`
--   • Storage bucket `apk-uploads`
--   • Table `public.apk_uploads` (data, index, constraints, comments)
--   • RLS policies on `apk_uploads` and `storage.objects` for this app
--   • Table grants for `apk_uploads`
--
-- WHAT THIS DOES NOT REMOVE
--   • The `pgcrypto` extension (other tables may use it)
--   • Your Supabase project or other buckets/tables
--
-- WARNING: This permanently deletes all uploaded APKs and upload history.
-- SAFE TO RE-RUN: idempotent — missing objects are skipped.
--
-- NOTE: Supabase blocks direct DELETE on storage tables by default (orphan-file
-- protection). Section 2 sets storage.allow_delete_query for this admin script.
-- =============================================================================


-- ─────────────────────────────────────────────────────────────────────────────
-- Configuration (must match supabase.sql / index.html BUCKET)
-- ─────────────────────────────────────────────────────────────────────────────
-- Bucket ID: apk-uploads
-- Table:     public.apk_uploads


-- ─────────────────────────────────────────────────────────────────────────────
-- 1 · Storage RLS policies (drop before deleting bucket objects)
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "apk_uploader_storage_select" ON storage.objects;
DROP POLICY IF EXISTS "apk_uploader_storage_insert" ON storage.objects;

-- Legacy policy names from README / older setups
DROP POLICY IF EXISTS "Public APK download" ON storage.objects;
DROP POLICY IF EXISTS "Allow APK upload"    ON storage.objects;


-- ─────────────────────────────────────────────────────────────────────────────
-- 2 · Storage bucket + all APK files
-- ─────────────────────────────────────────────────────────────────────────────
-- Supabase rejects bare DELETE on storage.* unless allow_delete_query is set.
-- Must run inside one transaction so SET LOCAL applies to all deletes below.
BEGIN;

SET LOCAL storage.allow_delete_query = 'true';

DELETE FROM storage.objects
WHERE bucket_id = 'apk-uploads';

-- Newer Supabase projects also track folder prefixes
DO $prefixes$
BEGIN
  IF to_regclass('storage.prefixes') IS NOT NULL THEN
    DELETE FROM storage.prefixes
    WHERE bucket_id = 'apk-uploads';
  END IF;
END $prefixes$;

DELETE FROM storage.buckets
WHERE id = 'apk-uploads';

COMMIT;


-- ─────────────────────────────────────────────────────────────────────────────
-- 3 · Table RLS policies
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "apk_uploader_select" ON public.apk_uploads;
DROP POLICY IF EXISTS "apk_uploader_insert" ON public.apk_uploads;

-- Legacy policy names from README / older setups
DROP POLICY IF EXISTS "Public read access"  ON public.apk_uploads;
DROP POLICY IF EXISTS "Service role insert" ON public.apk_uploads;
DROP POLICY IF EXISTS "Allow public insert" ON public.apk_uploads;


-- ─────────────────────────────────────────────────────────────────────────────
-- 4 · Revoke table privileges (only if table still exists)
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'apk_uploads'
  ) THEN
    REVOKE ALL ON public.apk_uploads FROM anon, authenticated, service_role, PUBLIC;
  END IF;
END $$;


-- ─────────────────────────────────────────────────────────────────────────────
-- 5 · Metadata table (index + constraints drop with the table)
-- ─────────────────────────────────────────────────────────────────────────────
DROP TABLE IF EXISTS public.apk_uploads CASCADE;


-- ─────────────────────────────────────────────────────────────────────────────
-- 6 · Refresh API schema cache
-- ─────────────────────────────────────────────────────────────────────────────
NOTIFY pgrst, 'reload schema';


-- ─────────────────────────────────────────────────────────────────────────────
-- 7 · Self-check (Messages panel in SQL Editor)
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
  v_bucket_exists boolean;
  v_table_exists  boolean;
  v_object_count  bigint;
  v_table_policy_count int;
  v_storage_policy_count int;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM storage.buckets WHERE id = 'apk-uploads'
  ) INTO v_bucket_exists;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'apk_uploads'
  ) INTO v_table_exists;

  SELECT count(*) INTO v_object_count
  FROM storage.objects
  WHERE bucket_id = 'apk-uploads';

  SELECT count(*) INTO v_table_policy_count
  FROM pg_policies
  WHERE schemaname = 'public' AND tablename = 'apk_uploads';

  SELECT count(*) INTO v_storage_policy_count
  FROM pg_policies
  WHERE schemaname = 'storage'
    AND tablename = 'objects'
    AND policyname IN (
      'apk_uploader_storage_select',
      'apk_uploader_storage_insert',
      'Public APK download',
      'Allow APK upload'
    );

  RAISE NOTICE '────────────────────────────────────────';
  RAISE NOTICE 'APK Uploader teardown verification';
  RAISE NOTICE '────────────────────────────────────────';

  IF v_bucket_exists THEN
    RAISE WARNING '✗ Bucket "apk-uploads" still exists';
  ELSE
    RAISE NOTICE '✓ Bucket "apk-uploads" removed';
  END IF;

  IF v_object_count > 0 THEN
    RAISE WARNING '✗ % storage object(s) remain in apk-uploads', v_object_count;
  ELSE
    RAISE NOTICE '✓ No storage objects left for apk-uploads';
  END IF;

  IF v_table_exists THEN
    RAISE WARNING '✗ Table public.apk_uploads still exists';
  ELSE
    RAISE NOTICE '✓ Table public.apk_uploads removed';
  END IF;

  IF v_table_policy_count > 0 THEN
    RAISE WARNING '✗ % apk_uploads polic(ies) remain', v_table_policy_count;
  ELSE
    RAISE NOTICE '✓ apk_uploads policies removed';
  END IF;

  IF v_storage_policy_count > 0 THEN
    RAISE WARNING '✗ % apk-uploads storage polic(ies) remain', v_storage_policy_count;
  ELSE
    RAISE NOTICE '✓ apk-uploads storage policies removed';
  END IF;

  RAISE NOTICE '────────────────────────────────────────';
  RAISE NOTICE 'To set up again: run supabase.sql';
  RAISE NOTICE '────────────────────────────────────────';
END $$;
