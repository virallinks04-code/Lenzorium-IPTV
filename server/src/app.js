import express from 'express';
import Stripe from 'stripe';
import { activatePage, setupPage } from './pages.js';

const ID_RE = /^[0-9A-F]{2}(:[0-9A-F]{2}){5}$/;
const KEY_RE = /^\d{6}$/;
const normId = (s) => String(s ?? '').trim().toUpperCase();
const normKey = (s) => String(s ?? '').replace(/\s+/g, '');

/** Tiny fixed-window rate limiter (per IP, per route group). */
function limiter(max, windowMs) {
  const hits = new Map();
  return (req, res, next) => {
    const k = req.ip;
    const now = Date.now();
    const h = hits.get(k);
    if (!h || h.reset < now) {
      hits.set(k, { n: 1, reset: now + windowMs });
      if (hits.size > 50_000) hits.clear();
      return next();
    }
    if (++h.n > max) return res.status(429).json({ error: 'Too many requests, try again shortly.' });
    next();
  };
}

export function createApp(store, env = process.env) {
  const app = express();
  app.set('trust proxy', env.TRUST_PROXY === '1');
  app.disable('x-powered-by');

  const stripe = env.STRIPE_SECRET_KEY ? new Stripe(env.STRIPE_SECRET_KEY) : null;
  const prices = { yearly: env.STRIPE_PRICE_YEARLY, lifetime: env.STRIPE_PRICE_LIFETIME };
  const publicUrl = (env.PUBLIC_URL || 'https://activate.lenzorium.com').replace(/\/$/, '');
  const devActivate = env.DEV_ACTIVATE === '1' && !stripe;
  const creditCost = { yearly: Number(env.CREDITS_YEARLY || 1), lifetime: Number(env.CREDITS_LIFETIME || 3) };

  // Stripe needs the raw body to verify the signature: register before json().
  app.post('/api/stripe/webhook', express.raw({ type: 'application/json' }), (req, res) => {
    if (!stripe || !env.STRIPE_WEBHOOK_SECRET) return res.status(404).end();
    let event;
    try {
      event = stripe.webhooks.constructEvent(req.body, req.headers['stripe-signature'], env.STRIPE_WEBHOOK_SECRET);
    } catch (e) {
      return res.status(400).send(`Webhook error: ${e.message}`);
    }
    if (event.type === 'checkout.session.completed') {
      const s = event.data.object;
      const deviceId = s.metadata?.deviceId;
      const plan = s.metadata?.plan;
      if (s.payment_status === 'paid' && deviceId && plan) {
        try {
          store.activate(deviceId, plan, { source: 'stripe', ref: s.payment_intent || s.id, email: s.customer_details?.email || null });
        } catch (e) {
          console.error('activation failed', deviceId, e.message);
          return res.status(500).end();
        }
      }
    }
    res.json({ received: true });
  });

  app.use(express.json({ limit: '32kb' }));
  app.use(express.urlencoded({ extended: false, limit: '32kb' }));
  app.use((req, res, next) => {
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('Referrer-Policy', 'no-referrer');
    next();
  });

  const deviceLimit = limiter(Number(env.RATE_DEVICE || 60), 60_000);
  const webLimit = limiter(Number(env.RATE_WEB || 20), 60_000);

  // ------------------------------------------------------------ app API

  app.post('/api/device/check', deviceLimit, (req, res) => {
    const id = normId(req.body?.deviceId);
    const key = normKey(req.body?.deviceKey);
    if (!ID_RE.test(id) || !KEY_RE.test(key)) return res.status(400).json({ error: 'Invalid device ID or key' });
    const d = store.touch(id, key, String(req.body.platform || '').slice(0, 20), String(req.body.appVersion || '').slice(0, 20));
    if (!d) return res.status(403).json({ error: 'Device key does not match' });
    res.json({ ...store.status(d), serverTime: new Date().toISOString(), playlists: store.pendingPlaylists(id) });
  });

  app.post('/api/device/playlists/ack', deviceLimit, (req, res) => {
    const id = normId(req.body?.deviceId);
    const d = store.device(id);
    if (!d || d.device_key !== normKey(req.body?.deviceKey)) return res.status(403).json({ error: 'Unknown device' });
    store.ackPlaylists(id, Array.isArray(req.body.ids) ? req.body.ids.slice(0, 50) : []);
    res.json({ ok: true });
  });

  // ------------------------------------------------------------ website

  const checkDevice = (body) => {
    const id = normId(body?.deviceId);
    const key = normKey(body?.deviceKey);
    if (!ID_RE.test(id) || !KEY_RE.test(key)) return { error: 'Check the device ID and key shown on your TV.' };
    const d = store.device(id);
    if (!d) return { error: 'This device has not been seen yet. Open Lenzorium Player on it first.' };
    if (d.device_key !== key) return { error: 'The device key does not match. Check the key on your TV.' };
    return { id, d };
  };

  app.get('/', (req, res) => res.type('html').send(activatePage({ device: normId(req.query.device), devActivate })));
  app.get('/setup', (req, res) => res.type('html').send(setupPage({ device: normId(req.query.device) })));
  app.get('/done', (req, res) => res.type('html').send(activatePage({ done: true })));

  app.post('/api/checkout', webLimit, async (req, res) => {
    const c = checkDevice(req.body);
    if (c.error) return res.status(400).json({ error: c.error });
    const plan = req.body.plan === 'lifetime' ? 'lifetime' : 'yearly';
    const email = String(req.body.email || '').trim().slice(0, 200) || undefined;
    if (devActivate) {
      store.activate(c.id, plan, { source: 'dev', email: email ?? null });
      return res.json({ activated: true });
    }
    if (!stripe || !prices[plan]) return res.status(503).json({ error: 'Payments are not set up yet.' });
    if (c.d.plan === 'lifetime') return res.status(400).json({ error: 'This device already has a lifetime licence.' });
    try {
      const session = await stripe.checkout.sessions.create({
        mode: 'payment',
        line_items: [{ price: prices[plan], quantity: 1 }],
        customer_email: email,
        metadata: { deviceId: c.id, plan },
        payment_intent_data: { metadata: { deviceId: c.id, plan } },
        success_url: `${publicUrl}/done`,
        cancel_url: `${publicUrl}/?device=${encodeURIComponent(c.id)}`,
      });
      res.json({ url: session.url });
    } catch (e) {
      console.error('stripe error', e.message);
      res.status(502).json({ error: 'Could not start the payment. Please try again.' });
    }
  });

  app.post('/api/device/playlist', webLimit, (req, res) => {
    const c = checkDevice(req.body);
    if (c.error) return res.status(400).json({ error: c.error });
    const b = req.body;
    const type = ['m3uUrl', 'xtream'].includes(b.type) ? b.type : null;
    const s = (v, n = 500) => String(v ?? '').trim().slice(0, n);
    if (!type) return res.status(400).json({ error: 'Choose M3U link or Xtream Codes.' });
    if (type === 'm3uUrl' && !/^https?:\/\//i.test(s(b.url))) return res.status(400).json({ error: 'Enter the full playlist link, starting with http:// or https://' });
    if (type === 'xtream' && (!s(b.url) || !s(b.username) || !s(b.password))) return res.status(400).json({ error: 'Enter the server, username and password.' });
    store.pushPlaylist(c.id, {
      name: s(b.name, 60) || 'Playlist',
      type,
      url: s(b.url),
      username: s(b.username, 200),
      password: s(b.password, 200),
      epgUrl: s(b.epgUrl),
    });
    res.json({ ok: true });
  });

  // ------------------------------------------------------------ resellers

  const reseller = (req, res, next) => {
    const key = (req.headers.authorization || '').replace(/^Bearer\s+/i, '');
    const r = key && store.resellerByKey(key);
    if (!r) return res.status(401).json({ error: 'Invalid reseller key' });
    req.reseller = r;
    next();
  };

  app.get('/api/reseller/me', reseller, (req, res) => {
    res.json({ name: req.reseller.name, credits: req.reseller.credits, costs: creditCost, recent: store.resellerActivations(req.reseller.id) });
  });

  app.post('/api/reseller/activate', webLimit, reseller, (req, res) => {
    const c = checkDevice(req.body);
    if (c.error) return res.status(400).json({ error: c.error });
    const plan = req.body.plan === 'lifetime' ? 'lifetime' : 'yearly';
    const r = store.resellerActivate(req.reseller, c.id, plan, creditCost[plan]);
    if (!r.ok) return res.status(400).json({ error: r.error });
    res.json({ ok: true, credits: r.credits, device: store.status(store.device(c.id)) });
  });

  // ------------------------------------------------------------ admin

  const admin = (req, res, next) => {
    const token = (req.headers.authorization || '').replace(/^Bearer\s+/i, '');
    if (!env.ADMIN_TOKEN || token !== env.ADMIN_TOKEN) return res.status(401).json({ error: 'Unauthorised' });
    next();
  };

  app.post('/api/admin/resellers', admin, (req, res) => {
    const name = String(req.body?.name || '').trim();
    if (!name) return res.status(400).json({ error: 'name required' });
    res.json(store.createReseller(name, Number(req.body.credits || 0)));
  });

  app.post('/api/admin/resellers/:id/credits', admin, (req, res) => {
    const r = store.addCredits(Number(req.params.id), Number(req.body?.credits || 0));
    if (!r) return res.status(404).json({ error: 'not found' });
    res.json(r);
  });

  app.get('/api/admin/devices/:id', admin, (req, res) => {
    const d = store.device(normId(req.params.id));
    if (!d) return res.status(404).json({ error: 'not found' });
    res.json({ id: d.id, ...store.status(d), email: d.email, platform: d.platform, lastSeen: d.last_seen && new Date(d.last_seen).toISOString() });
  });

  app.get('/healthz', (req, res) => res.json({ ok: true }));
  return app;
}
