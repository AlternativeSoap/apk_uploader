# APK Uploader

Upload APK files and instantly get a download link + QR code.  
Phones scan the QR → download → install. That simple.

## 🌐 Live Site

**[https://alternativesoap.github.io/apk_uploader/](https://alternativesoap.github.io/apk_uploader/)**

## How it works

1. Open the site above
2. Drag & drop your `.apk` file (or click to browse)
3. File uploads to Supabase cloud storage
4. You get a **QR code** + **direct download link**
5. Scan QR on any phone → downloads & installs the APK

No server needed — everything runs client-side via GitHub Pages + Supabase.

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

Your site will be live at `https://alternativesoap.github.io/apk_uploader/`

## Files

| File | Purpose |
|------|---------|
| `index.html` | Upload page — drag & drop, upload to Supabase, shows QR |
| `download.html` | Mobile download page — users land here from QR code |
| `config.js` | Your Supabase URL + anon key (edit this) |
