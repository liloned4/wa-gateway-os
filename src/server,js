/**
 * WA Gateway OSS (Baileys + Express)
 * Fitur:
 * - Login QR: GET /qr (PNG)
 * - Health: GET /health
 * - Kirim teks: POST /send { to, message }
 * - Kirim media: POST /send-media (form-data: to, caption?, file)
 * - Webhook (opsional): set WEBHOOK_URL untuk terima event message & receipt
 *
 * ⚠️ Catatan: Menggunakan jalur WhatsApp Web (reverse-engineered).
 * Berisiko melanggar ToS & nomor bisa diblokir. Pakailah nomor cadangan.
 */

import makeWASocket, {
  DisconnectReason,
  useMultiFileAuthState,
  fetchLatestBaileysVersion,
  makeInMemoryStore
} from "@adiwajshing/baileys";
import Pino from "pino";
import express from "express";
import dotenv from "dotenv";
import multer from "multer";
import fs from "fs";
import path from "path";
import QRCode from "qrcode";
import axios from "axios";
import http from "http";

dotenv.config();

// ====== Config/env ======
const PORT = process.env.PORT || 3000;
const WEBHOOK_URL = process.env.WEBHOOK_URL || ""; // jika diisi, semua pesan masuk & receipt diposting ke sini
const API_KEY = process.env.API_KEY || "";         // jika diisi, wajib kirim header x-api-key

// ====== Logger ======
const logger = Pino({ level: "info" });

// ====== Express app ======
const app = express();
app.use(express.json({ limit: "5mb" }));

// (opsional) simple CORS
app.use((req, res, next) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type, x-api-key");
  if (req.method === "OPTIONS") return res.sendStatus(204);
  next();
});

// API key guard (opsional)
function guard(req, res, next) {
  if (!API_KEY) return next();
  const key = req.headers["x-api-key"];
  if (key !== API_KEY) return res.status(401).json({ error: "Unauthorized" });
  next();
}

// Upload handler untuk media
const upload = multer({ dest: "uploads/" });

// ====== Baileys store & socket ======
const store = makeInMemoryStore({ logger });
let sock;          // socket instance
let latestQR = ""; // QR string terakhir (untuk /qr)

// Pastikan folder penting ada
fs.mkdirSync("uploads", { recursive: true });
fs.mkdirSync("auth", { recursive: true });

// ====== Start WA connection ======
async function start() {
  const { state, saveCreds } = await useMultiFileAuthState("auth");
  const { version, isLatest } = await fetchLatestBaileysVersion();
  logger.info({ version, isLatest }, "Using WA version");

  sock = makeWASocket({
    version,
    logger,
    printQRInTerminal: true, // QR juga tampil di terminal container
    auth: state,
    syncFullHistory: false,
    browser: ["WA-Gateway-OS", "Chrome", "1.0"], // nama perangkat
  });

  store.bind(sock.ev);
  sock.ev.on("creds.update", saveCreds);

  // Status koneksi
  sock.ev.on("connection.update", (u) => {
    const { connection, lastDisconnect, qr } = u;
    if (qr) {
      latestQR = qr;
      logger.info("QR updated — open /qr to scan");
    }
    if (connection === "close") {
      const code = (lastDisconnect?.error)?.output?.statusCode;
      const shouldReconnect = code !== DisconnectReason.loggedOut;
      logger.warn({ code, err: lastDisconnect?.error?.message }, "Connection closed");
      if (shouldReconnect) start();
    } else if (connection === "open") {
      latestQR = "";
      logger.info("✅ WhatsApp connected");
    }
  });

  // Pesan masuk
  sock.ev.on("messages.upsert", async (m) => {
    try {
      const msg = m.messages?.[0];
      if (!msg) return;
      // Abaikan pesan dari diri sendiri
      if (msg.key.fromMe) return;

      const remoteJid = msg.key.remoteJid;
      const type = msg.message?.conversation
        ? "text"
        : Object.keys(msg.message || {})[0];

      const text =
        msg.message?.conversation ||
        msg.message?.extendedTextMessage?.text ||
        msg.message?.imageMessage?.caption ||
        "";

      // Contoh auto-reply sederhana
      if ((text || "").trim().toLowerCase() === "ping") {
        await sock.sendMessage(remoteJid, { text: "pong" });
      }

      // Forward ke webhook jika diset
      if (WEBHOOK_URL) {
        axios.post(
          WEBHOOK_URL,
          { event: "message", remoteJid, type, text, message: msg },
          { timeout: 5000 }
        ).catch(() => {});
      }
    } catch (e) {
      logger.error({ e }, "messages.upsert error");
    }
  });

  // Update receipt (delivered/read)
  sock.ev.on("message-receipt.update", async (updates) => {
    try {
      if (!WEBHOOK_URL) return;
      await axios.post(WEBHOOK_URL, { event: "receipt", updates });
    } catch {}
  });
}

// ====== Helpers ======
function normalizeJid(input) {
  // terima 62xxxxxxxxxx atau 62xxxxxxxxxx@s.whatsapp.net
  return input.includes("@s.whatsapp.net")
    ? input
    : `${input.replace(/\D/g, "")}@s.whatsapp.net`;
}

function safeUnlink(filePath) {
  fs.unlink(filePath, () => {});
}

// ====== Routes ======
app.get("/health", (req, res) => {
  const connected = !!sock?.user;
  res.json({
    status: connected ? "connected" : (latestQR ? "scan_qr" : "disconnected"),
    user: sock?.user || null
  });
});

// Render QR sebagai PNG
app.get("/qr", async (req, res) => {
  if (!latestQR) return res.status(404).send("QR not available");
  try {
    const dataUrl = await QRCode.toDataURL(latestQR, { margin: 1, scale: 6 });
    const img = Buffer.from(dataUrl.split(",")[1], "base64");
    res.setHeader("Content-Type", "image/png");
    res.send(img);
  } catch (e) {
    res.status(500).json({ error: "Failed to render QR" });
  }
});

// Kirim teks
app.post("/send", guard, async (req, res) => {
  try {
    const { to, message } = req.body || {};
    if (!to || !message) {
      return res.status(400).json({ error: "Field 'to' dan 'message' wajib diisi" });
    }
    if (!sock) return res.status(503).json({ error: "Socket not ready" });
    const jid = normalizeJid(to);
    const result = await sock.sendMessage(jid, { text: message });
    res.json({ ok: true, result });
  } catch (e) {
    res.status(500).json({ error: String(e) });
  }
});

// Kirim media (image/doc)
app.post("/send-media", guard, upload.single("file"), async (req, res) => {
  try {
    const { to, caption } = req.body || {};
    if (!to || !req.file) {
      if (req.file) safeUnlink(req.file.path);
      return res.status(400).json({ error: "Field 'to' dan 'file' wajib diisi" });
    }
    if (!sock) {
      safeUnlink(req.file.path);
      return res.status(503).json({ error: "Socket not ready" });
    }

    const jid = normalizeJid(to);
    const filepath = path.resolve(req.file.path);
    const mime = req.file.mimetype;

    const content = mime.startsWith("image/")
      ? { image: fs.readFileSync(filepath), caption }
      : {
          document: fs.readFileSync(filepath),
          fileName: req.file.originalname,
          mimetype: mime,
          caption
        };

    const result = await sock.sendMessage(jid, content);
    safeUnlink(filepath);
    res.json({ ok: true, result });
  } catch (e) {
    if (req.file) safeUnlink(req.file.path);
    res.status(500).json({ error: String(e) });
  }
});

// ====== HTTP server & graceful shutdown ======
const server = http.createServer(app);

async function shutdown(signal) {
  try {
    logger.warn(`${signal} received, shutting down...`);
    server.close(() => logger.info("HTTP server closed"));
    // Baileys tidak punya "close" resmi utk sock di v6, biarkan proses exit
    setTimeout(() => process.exit(0), 500).unref();
  } catch (e) {
    logger.error(e, "Error during shutdown");
    process.exit(1);
  }
}

["SIGINT", "SIGTERM"].forEach(sig => process.on(sig, () => shutdown(sig)));

// ====== Boot ======
start().catch(err => {
  logger.error({ err }, "Failed to start WA socket");
});
server.listen(PORT, () => {
  logger.info(`HTTP listening on :${PORT}`);
});
