import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { createApp } from '../src/app.js';
import { openDb } from '../src/db.js';

let server, base, store;
const env = { DEV_ACTIVATE: '1', ADMIN_TOKEN: 'admintest', RATE_DEVICE: '1000', RATE_WEB: '1000' };
const dev = { deviceId: 'A4:3F:9C:21:7E:B0', deviceKey: '482917', platform: 'android', appVersion: '1.0.0' };

const post = async (path, body, headers = {}) => {
  const r = await fetch(base + path, { method: 'POST', headers: { 'Content-Type': 'application/json', ...headers }, body: JSON.stringify(body) });
  return { status: r.status, body: await r.json() };
};

before(async () => {
  store = openDb(':memory:');
  server = createApp(store, env).listen(0);
  await new Promise((r) => server.once('listening', r));
  base = `http://127.0.0.1:${server.address().port}`;
});
after(() => server.close());

test('first check starts a 7-day trial', async () => {
  const r = await post('/api/device/check', dev);
  assert.equal(r.status, 200);
  assert.equal(r.body.status, 'trial');
  const days = (new Date(r.body.trialEndsAt) - Date.now()) / 86400000;
  assert.ok(days > 6.9 && days <= 7);
  assert.deepEqual(r.body.playlists, []);
});

test('rejects a wrong key and bad formats', async () => {
  assert.equal((await post('/api/device/check', { ...dev, deviceKey: '000000' })).status, 403);
  assert.equal((await post('/api/device/check', { ...dev, deviceId: 'nope' })).status, 400);
});

test('expired trial reports expired', async () => {
  const id = 'B0:00:00:00:00:01';
  store.touch(id, '111111', 'windows', '1.0.0', Date.now() - 8 * 86400000);
  const r = await post('/api/device/check', { ...dev, deviceId: id, deviceKey: '111111' });
  assert.equal(r.body.status, 'expired');
});

test('web activation (test mode) unlocks the device; yearly stacks', async () => {
  const r = await post('/api/checkout', { deviceId: dev.deviceId.toLowerCase(), deviceKey: '482 917', plan: 'yearly', email: 'a@b.c' });
  assert.equal(r.status, 200);
  assert.equal(r.body.activated, true);
  const c = await post('/api/device/check', dev);
  assert.equal(c.body.status, 'active');
  assert.equal(c.body.plan, 'yearly');
  const first = new Date(c.body.expiresAt);
  await post('/api/checkout', { ...dev, plan: 'yearly' });
  const c2 = await post('/api/device/check', dev);
  assert.ok(new Date(c2.body.expiresAt) - first > 364 * 86400000);
});

test('checkout refuses unknown devices and wrong keys', async () => {
  assert.equal((await post('/api/checkout', { deviceId: 'C0:00:00:00:00:00', deviceKey: '123456', plan: 'yearly' })).status, 400);
  assert.equal((await post('/api/checkout', { ...dev, deviceKey: '999999', plan: 'yearly' })).status, 400);
});

test('playlist sent from the web reaches the device once', async () => {
  const s = await post('/api/device/playlist', { ...dev, type: 'xtream', name: 'Home', url: 'http://provider.example:8080', username: 'u', password: 'p' });
  assert.equal(s.status, 200);
  const c = await post('/api/device/check', dev);
  assert.equal(c.body.playlists.length, 1);
  assert.equal(c.body.playlists[0].username, 'u');
  await post('/api/device/playlists/ack', { ...dev, ids: [c.body.playlists[0].id] });
  const c2 = await post('/api/device/check', dev);
  assert.equal(c2.body.playlists.length, 0);
});

test('resellers spend credits to activate', async () => {
  const created = await post('/api/admin/resellers', { name: 'Shop', credits: 3 }, { Authorization: 'Bearer admintest' });
  assert.equal(created.status, 200);
  const auth = { Authorization: `Bearer ${created.body.apiKey}` };
  const id = 'D0:00:00:00:00:02';
  await post('/api/device/check', { ...dev, deviceId: id, deviceKey: '222222' });
  const a = await post('/api/reseller/activate', { deviceId: id, deviceKey: '222222', plan: 'lifetime' }, auth);
  assert.equal(a.status, 200);
  assert.equal(a.body.credits, 0);
  assert.equal(a.body.device.plan, 'lifetime');
  const b = await post('/api/reseller/activate', { deviceId: id, deviceKey: '222222', plan: 'yearly' }, auth);
  assert.equal(b.status, 400);
  const me = await fetch(base + '/api/reseller/me', { headers: auth }).then((r) => r.json());
  assert.equal(me.credits, 0);
  assert.equal(me.recent.length, 1);
  assert.equal((await post('/api/reseller/activate', { deviceId: id, deviceKey: '222222' }, { Authorization: 'Bearer nope' })).status, 401);
});

test('admin API needs the token', async () => {
  assert.equal((await post('/api/admin/resellers', { name: 'x' })).status, 401);
});

test('pages render and escape input', async () => {
  const html = await fetch(base + '/?device=%3Cscript%3E').then((r) => r.text());
  assert.ok(html.includes('Activate your device'));
  assert.ok(!html.includes('<SCRIPT>'));
  const setup = await fetch(base + '/setup').then((r) => r.text());
  assert.ok(setup.includes('Send a playlist to your TV'));
});

test('stripe ref is applied only once', () => {
  const id = 'E0:00:00:00:00:03';
  store.touch(id, '333333');
  assert.equal(store.activate(id, 'yearly', { source: 'stripe', ref: 'pi_1' }), true);
  assert.equal(store.activate(id, 'yearly', { source: 'stripe', ref: 'pi_1' }), false);
});
