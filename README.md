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

Go to **Supabase Dashboard → SQL Editor → New Query**, open [`supabase.sql`](supabase.sql) from this repo, paste the full file, and **Run**.

That creates the `apk-uploads` bucket, `apk_uploads` table, grants, and RLS policies in one step.

### 2. Configure `config.js`

Edit `config.js` with your Supabase project URL and **anon** (public) key from **Dashboard → Settings → API**:

```js
const SUPABASE_URL = 'https://YOUR-PROJECT-REF.supabase.co';
const SUPABASE_ANON_KEY = 'your-anon-key-here';
```

**Important:** The URL must match an **active** project. If uploads show `Failed to fetch`, the project may be paused, deleted, or the URL in `config.js` is wrong — fix credentials in the dashboard, not by redeploying GitHub Pages alone.

### 3. Push to GitHub (GitHub Pages)

Commit `config.js` (with your real keys) and push to `main`. Pages deploys automatically from the root.

Go to **repo Settings → Pages → Source: Deploy from a branch → Branch: `main` / `/ (root)`** if not already enabled.

## Troubleshooting

| Symptom | Fix |
|--------|-----|
| `Failed to fetch` on upload | Supabase URL unreachable — create/restore project, update `config.js`, run `supabase.sql`, push |
| `permission denied` / RLS error | Re-run `supabase.sql` (grants + policies) |
| `table apk_uploads` not found | Run `supabase.sql` in SQL Editor |

## Files

| File | Purpose |
|------|---------|
| `index.html` | Upload page — drop APK, auto-uploads, shows QR code |
| `download.html` | Download page — fetches latest APK from Supabase, auto-downloads |
| `config.js` | Your Supabase URL + anon key (edit this) |
| `supabase.sql` | One-shot database + storage setup for SQL Editor |
