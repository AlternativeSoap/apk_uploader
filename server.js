require('dotenv').config();
const express = require('express');
const multer = require('multer');
const path = require('path');
const QRCode = require('qrcode');
const os = require('os');
const { createClient } = require('@supabase/supabase-js');

const app = express();
const PORT = process.env.PORT || 3000;

// Supabase client (service role for server-side uploads)
const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_KEY
);

const BUCKET = 'apk-uploads';

// Multer: buffer in memory (then we push to Supabase Storage)
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 500 * 1024 * 1024 }, // 500 MB
  fileFilter: (req, file, cb) => {
    if (path.extname(file.originalname).toLowerCase() !== '.apk') {
      return cb(new Error('Only .apk files are allowed'));
    }
    cb(null, true);
  }
});

// Serve static files
app.use(express.static(path.join(__dirname, 'public')));

// Upload endpoint → Supabase Storage
app.post('/upload', (req, res) => {
  upload.single('apkFile')(req, res, async (err) => {
    if (err) {
      const message = err instanceof multer.MulterError
        ? (err.code === 'LIMIT_FILE_SIZE' ? 'File too large (max 500 MB)' : err.message)
        : err.message;
      return res.status(400).json({ error: message });
    }

    if (!req.file) {
      return res.status(400).json({ error: 'No file uploaded' });
    }

    try {
      // Sanitize + unique filename
      const sanitized = req.file.originalname.replace(/[^a-zA-Z0-9._-]/g, '_');
      const storagePath = `${Date.now()}-${sanitized}`;

      // Upload to Supabase Storage
      const { error: uploadError } = await supabase.storage
        .from(BUCKET)
        .upload(storagePath, req.file.buffer, {
          contentType: 'application/vnd.android.package-archive',
          upsert: false
        });

      if (uploadError) {
        console.error('Supabase upload error:', uploadError);
        return res.status(500).json({ error: 'Failed to upload to storage: ' + uploadError.message });
      }

      // Get public URL
      const { data: urlData } = supabase.storage
        .from(BUCKET)
        .getPublicUrl(storagePath);

      const publicUrl = urlData.publicUrl;

      // Save metadata to database
      const { error: dbError } = await supabase
        .from('apk_uploads')
        .insert({
          original_name: req.file.originalname,
          storage_path: storagePath,
          file_size: req.file.size,
          download_url: publicUrl
        });

      if (dbError) {
        console.error('DB insert error:', dbError);
        // File is uploaded, just log the metadata error
      }

      // Build download page URL (served from our own static page)
      const downloadPageUrl = `/download.html?url=${encodeURIComponent(publicUrl)}&name=${encodeURIComponent(req.file.originalname)}&size=${req.file.size}`;

      res.json({
        success: true,
        filename: req.file.originalname,
        size: req.file.size,
        downloadUrl: publicUrl,
        downloadPageUrl
      });
    } catch (e) {
      console.error('Upload error:', e);
      res.status(500).json({ error: 'Server error during upload' });
    }
  });
});

// QR code generation endpoint
app.get('/qr', async (req, res) => {
  const url = req.query.url;
  if (!url) return res.status(400).send('Missing url parameter');

  try {
    const qrDataUrl = await QRCode.toDataURL(url, {
      width: 300,
      margin: 2,
      color: { dark: '#000000', light: '#ffffff' }
    });
    res.json({ qr: qrDataUrl });
  } catch (err) {
    res.status(500).json({ error: 'Failed to generate QR code' });
  }
});

// Get local network IP for sharing
function getLocalIP() {
  const interfaces = os.networkInterfaces();
  for (const name of Object.keys(interfaces)) {
    for (const iface of interfaces[name]) {
      if (iface.family === 'IPv4' && !iface.internal) {
        return iface.address;
      }
    }
  }
  return 'localhost';
}

app.listen(PORT, '0.0.0.0', () => {
  const localIP = getLocalIP();
  console.log('\n  ╔══════════════════════════════════════════╗');
  console.log('  ║         APK Uploader is running!         ║');
  console.log('  ╠══════════════════════════════════════════╣');
  console.log(`  ║  Local:   http://localhost:${PORT}          ║`);
  console.log(`  ║  Network: http://${localIP}:${PORT}     ║`);
  console.log('  ╚══════════════════════════════════════════╝\n');
  console.log('  Files are stored in Supabase Storage.');
  console.log('  Share the Network URL with devices on your network.\n');
});
