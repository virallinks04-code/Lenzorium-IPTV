import { DatabaseSync } from 'node:sqlite';
import { createHash, randomBytes } from 'node:crypto';

const DAY = 24 * 60 * 60 * 1000;

export function openDb(path = process.env.DB_PATH || 'lenzorium.db') {
  const db = new DatabaseSync(path);
  db.exec(`
    PRAGMA journal_mode = WAL;
    CREATE TABLE IF NOT EXISTS devices(
      id TEXT PRIMARY KEY, device_key TEXT NOT NULL, created INTEGER NOT NULL, trial_ends INTEGER NOT NULL,
      plan TEXT NOT NULL DEFAULT 'trial', expires_at INTEGER, email TEXT, payment_ref TEXT,
      platform TEXT, app_version TEXT, last_seen INTEGER);
    CREATE TABLE IF NOT EXISTS pending_playlists(
      id INTEGER PRIMARY KEY AUTOINCREMENT, device_id TEXT NOT NULL, payload TEXT NOT NULL, created INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS resellers(
      id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, key_hash TEXT NOT NULL UNIQUE,
      credits INTEGER NOT NULL DEFAULT 0, created INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS activations(
      id INTEGER PRIMARY KEY AUTOINCREMENT, device_id TEXT NOT NULL, source TEXT NOT NULL, plan TEXT NOT NULL,
      ref TEXT, reseller_id INTEGER, created INTEGER NOT NULL);
    CREATE UNIQUE INDEX IF NOT EXISTS ux_activation_ref ON activations(ref) WHERE ref IS NOT NULL;
  `);
  return new Store(db);
}

export const hashKey = (k) => createHash('sha256').update(k).digest('hex');

export class Store {
  constructor(db) {
    this.db = db;
    this.trialDays = Number(process.env.TRIAL_DAYS || 7);
  }

  device(id) {
    return this.db.prepare('SELECT * FROM devices WHERE id = ?').get(id);
  }

  /** Registers the device on first contact and starts its trial. */
  touch(id, key, platform, appVersion, now = Date.now()) {
    let d = this.device(id);
    if (!d) {
      this.db
        .prepare('INSERT INTO devices(id, device_key, created, trial_ends, platform, app_version, last_seen) VALUES(?,?,?,?,?,?,?)')
        .run(id, key, now, now + this.trialDays * DAY, platform ?? null, appVersion ?? null, now);
      return this.device(id);
    }
    if (d.device_key !== key) return null;
    this.db.prepare('UPDATE devices SET platform = ?, app_version = ?, last_seen = ? WHERE id = ?').run(platform ?? d.platform, appVersion ?? d.app_version, now, id);
    return this.device(id);
  }

  status(d, now = Date.now()) {
    if (d.plan === 'lifetime') return { status: 'active', plan: 'lifetime', expiresAt: null, trialEndsAt: null };
    if (d.plan === 'yearly') {
      const active = d.expires_at && d.expires_at > now;
      return { status: active ? 'active' : 'expired', plan: 'yearly', expiresAt: iso(d.expires_at), trialEndsAt: null };
    }
    return { status: d.trial_ends > now ? 'trial' : 'expired', plan: 'trial', expiresAt: null, trialEndsAt: iso(d.trial_ends) };
  }

  /**
   * Activates a device. Yearly plans stack on top of any time left.
   * Returns false if this payment/ref was already applied (idempotent webhooks).
   */
  activate(deviceId, plan, { source, ref = null, email = null, resellerId = null, now = Date.now() }) {
    const d = this.device(deviceId);
    if (!d) throw new Error('unknown device');
    if (ref && this.db.prepare('SELECT 1 FROM activations WHERE ref = ?').get(ref)) return false;
    this.db.exec('BEGIN');
    try {
      if (plan === 'lifetime') {
        this.db.prepare("UPDATE devices SET plan = 'lifetime', expires_at = NULL WHERE id = ?").run(deviceId);
      } else if (plan === 'yearly') {
        if (d.plan === 'lifetime') throw new Error('device already has a lifetime licence');
        const base = d.plan === 'yearly' && d.expires_at > now ? d.expires_at : now;
        this.db.prepare("UPDATE devices SET plan = 'yearly', expires_at = ? WHERE id = ?").run(base + 365 * DAY, deviceId);
      } else {
        throw new Error('unknown plan');
      }
      if (email || ref) {
        this.db.prepare('UPDATE devices SET email = COALESCE(?, email), payment_ref = COALESCE(?, payment_ref) WHERE id = ?').run(email, ref, deviceId);
      }
      this.db
        .prepare('INSERT INTO activations(device_id, source, plan, ref, reseller_id, created) VALUES(?,?,?,?,?,?)')
        .run(deviceId, source, plan, ref, resellerId, now);
      this.db.exec('COMMIT');
      return true;
    } catch (e) {
      this.db.exec('ROLLBACK');
      throw e;
    }
  }

  // Playlists typed on the website for a device. Deleted once delivered.
  pushPlaylist(deviceId, payload) {
    this.db.prepare('INSERT INTO pending_playlists(device_id, payload, created) VALUES(?,?,?)').run(deviceId, JSON.stringify(payload), Date.now());
  }

  pendingPlaylists(deviceId) {
    return this.db
      .prepare('SELECT id, payload FROM pending_playlists WHERE device_id = ? ORDER BY id')
      .all(deviceId)
      .map((r) => ({ id: String(r.id), ...JSON.parse(r.payload) }));
  }

  ackPlaylists(deviceId, ids) {
    const st = this.db.prepare('DELETE FROM pending_playlists WHERE device_id = ? AND id = ?');
    for (const id of ids) st.run(deviceId, Number(id));
  }

  /** Undelivered playlists are removed after a day (they contain logins). */
  purgeOldPlaylists(now = Date.now()) {
    this.db.prepare('DELETE FROM pending_playlists WHERE created < ?').run(now - DAY);
  }

  // Resellers
  createReseller(name, credits = 0) {
    const key = 'rk_' + randomBytes(24).toString('hex');
    const r = this.db.prepare('INSERT INTO resellers(name, key_hash, credits, created) VALUES(?,?,?,?)').run(name, hashKey(key), credits, Date.now());
    return { id: Number(r.lastInsertRowid), name, credits, apiKey: key };
  }

  resellerByKey(key) {
    return this.db.prepare('SELECT * FROM resellers WHERE key_hash = ?').get(hashKey(key));
  }

  addCredits(resellerId, n) {
    this.db.prepare('UPDATE resellers SET credits = credits + ? WHERE id = ?').run(n, resellerId);
    return this.db.prepare('SELECT id, name, credits FROM resellers WHERE id = ?').get(resellerId);
  }

  /** Spends credits and activates in one transaction. */
  resellerActivate(reseller, deviceId, plan, cost) {
    const fresh = this.db.prepare('SELECT credits FROM resellers WHERE id = ?').get(reseller.id);
    if (fresh.credits < cost) return { ok: false, error: 'Not enough credits' };
    this.db.prepare('UPDATE resellers SET credits = credits - ? WHERE id = ? AND credits >= ?').run(cost, reseller.id, cost);
    try {
      this.activate(deviceId, plan, { source: 'reseller', resellerId: reseller.id });
    } catch (e) {
      this.db.prepare('UPDATE resellers SET credits = credits + ? WHERE id = ?').run(cost, reseller.id);
      return { ok: false, error: e.message };
    }
    return { ok: true, credits: fresh.credits - cost };
  }

  resellerActivations(resellerId, limit = 50) {
    return this.db
      .prepare('SELECT device_id AS deviceId, plan, created FROM activations WHERE reseller_id = ? ORDER BY id DESC LIMIT ?')
      .all(resellerId, limit)
      .map((r) => ({ ...r, created: iso(r.created) }));
  }
}

const iso = (ms) => (ms == null ? null : new Date(ms).toISOString());
