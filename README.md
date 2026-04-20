# APK Uploader

Drop an APK → get a QR code → anyone scans it → instant install.  
The latest uploaded APK is always the one people download. One QR to rule them all.

## 🌐 Live Site

- **Upload page:** [https://alternativesoap.github.io/apk_uploader/](https://alternativesoap.github.io/apk_uploader/)
- **Download page (QR target):** [https://alternativesoap.github.io/apk_uploader/download.html](https://alternativesoap.github.io/apk_uploader/download.html)

## How it works

1. Open the upload page
2. Drop your `.apk` file — it uploads instantly (no extra buttons)
3. A QR code appears pointing to the download page
4. Show the QR to anyone — they scan it and the APK auto-downloads
5. Upload a new APK anytime — the same QR now serves the new file

The QR code URL never changes. It always fetches the latest APK from Supabase.

## Setup (one-time)

### 1. Run SQL in Supabase

Go to **Supabase Dashboard → SQL Editor → New Query** and run:

```sql
INSERT INTO storage.buckets (id, name, public)
VALUES ('apk-uploads', 'apk-uploads', true)
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS apk_uploads (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  original_name text NOT NULL,
  storage_path text NOT NULL,
  file_size bigint NOT NULL,
  download_url text NOT NULL,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE apk_uploads ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Public read access" ON apk_uploads
  FOR SELECT USING (true);

CREATE POLICY "Service role insert" ON apk_uploads
  FOR INSERT WITH CHECK (true);

CREATE POLICY "Public APK download" ON storage.objects
  FOR SELECT TO public
  USING (bucket_id = 'apk-uploads');

CREATE POLICY "Allow APK upload" ON storage.objects
  FOR INSERT TO public
  WITH CHECK (bucket_id = 'apk-uploads');
```

### 2. Configure `config.js`

Edit `config.js` with your Supabase project URL and **anon** (public) key from **Dashboard → Settings → API**:

```js
const SUPABASE_URL = 'https://your-project.supabase.co';
const SUPABASE_ANON_KEY = 'your-anon-key-here';
```

### 3. Enable GitHub Pages

Go to **repo Settings → Pages → Source: Deploy from a branch → Branch: `main` / `/ (root)`** → Save.

## Files

| File | Purpose |
|------|---------|
| `index.html` | Upload page — drop APK, auto-uploads, shows QR code |
| `download.html` | Download page — fetches latest APK from Supabase, auto-downloads |
| `config.js` | Your Supabase URL + anon key (edit this) |
