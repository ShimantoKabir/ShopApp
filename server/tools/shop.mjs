// Run this on your own computer to manage the shops on the server.
//
//   node tools/shop.mjs create "Hasan Hardware"     a new shop; its key is saved in shops/<id>.txt (not shown)
//   node tools/shop.mjs list                         every shop and how many changes it holds
//   node tools/shop.mjs new-key <id>                 a new key for a shop (the old one stops working)
//
// It needs ADMIN_KEY.txt in this folder (the server's admin key). The server
// address is read from SERVER_URL.txt if there is one, or from the SERVER_URL
// environment variable. Keys are written to files, never printed: hand a shop's
// key to its owner yourself.
import { mkdirSync, readFileSync, writeFileSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = join(dirname(fileURLToPath(import.meta.url)), '..');
const read = (name) => (existsSync(join(here, name)) ? readFileSync(join(here, name), 'utf8').trim() : '');

const base = (process.env.SERVER_URL || read('SERVER_URL.txt') || 'https://hardware-shop-sync.kabir3483.workers.dev').replace(/\/$/, '');
const adminKey = process.env.ADMIN_KEY || read('ADMIN_KEY.txt');
if (!adminKey) {
  console.error('No admin key: put it in server/ADMIN_KEY.txt.');
  process.exit(1);
}

const call = async (path, method = 'GET', body) => {
  const r = await fetch(base + path, {
    method,
    headers: { authorization: `Bearer ${adminKey}`, 'content-type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const data = await r.json().catch(() => null);
  if (!r.ok) {
    console.error(`The server said no (${r.status}): ${data?.error ?? 'unknown'}`);
    process.exit(1);
  }
  return data;
};

const saveKey = (id, name, key) => {
  mkdirSync(join(here, 'shops'), { recursive: true });
  const file = join('shops', `${id}.txt`);
  writeFileSync(join(here, file), `${key}\n`, { mode: 0o600 });
  console.log(`Shop "${name}"  id ${id}\nIts key is saved in server/${file.replace(/\\/g, '/')} (give it to the owner; it is shown nowhere else).`);
};

const [, , command, arg] = process.argv;
if (command === 'create' && arg) {
  const shop = await call('/v1/admin/shops', 'POST', { name: arg });
  saveKey(shop.id, shop.name, shop.key);
} else if (command === 'list') {
  const { shops } = await call('/v1/admin/shops');
  if (shops.length === 0) console.log('No shops yet.');
  for (const s of shops) console.log(`${s.id}  ${s.name}  (${s.head} changes, made ${new Date(s.createdAt).toISOString().slice(0, 10)})`);
} else if (command === 'new-key' && arg) {
  const shop = await call(`/v1/admin/shops/${encodeURIComponent(arg)}/key`, 'POST');
  saveKey(shop.id, arg, shop.key);
} else {
  console.error('Usage: node tools/shop.mjs create "<shop name>" | list | new-key <shop id>');
  process.exit(1);
}
