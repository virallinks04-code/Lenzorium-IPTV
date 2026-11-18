import { createApp } from './app.js';
import { openDb } from './db.js';

const store = openDb();
const app = createApp(store);
const port = Number(process.env.PORT || 8080);

setInterval(() => store.purgeOldPlaylists(), 60 * 60 * 1000).unref();

app.listen(port, () => {
  console.log(`Lenzorium licence server on :${port}`);
  if (!process.env.STRIPE_SECRET_KEY) console.log('Stripe not configured' + (process.env.DEV_ACTIVATE === '1' ? ' — DEV_ACTIVATE on: activations are free (testing only)' : ''));
  if (!process.env.ADMIN_TOKEN) console.log('ADMIN_TOKEN not set — admin API disabled');
});
