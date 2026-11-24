// The shops' shared logs. One server holds many shops: each shop has its own
// key and its own private, ordered list of changes. A shop's phones store every
// change here and replay the list in the same order, so every phone of that
// shop ends up with the same data. The server knows nothing about products,
// sales or stock, and one shop can never see another's list.
//
// Phones (the shop's key):   Authorization: Bearer <shop key>
//   GET  /v1/ping                  -> { ok, head }
//   GET  /v1/ops?after=N&limit=M   -> { ops: [{ seq, opId, device, at, payload }], head }
//   POST /v1/ops {opId,device,at,payload} -> { seq }   (same opId twice = same seq)
//   POST /v1/erase {opId,device,at,payload} -> { seq }
//        Deletes EVERY entry of this shop and leaves just this one (the "shop
//        erased" notice, which each phone acts on the next time it reads).
//        Numbers keep rising, so a phone that missed it can never mistake a
//        later shop for the old one.
//
// The person who runs the server (the admin key, a secret on this Worker):
//   POST /v1/admin/shops {name}          -> { id, name, key }   a new shop; the key is shown ONCE
//   GET  /v1/admin/shops                 -> { shops: [{ id, name, createdAt, head }] }
//   POST /v1/admin/shops/<id>/key        -> { id, key }         a new key (the old one stops working)
//
// Only a hash of each shop's key is stored.

const MAX_PAYLOAD = 900_000; // characters; D1 rows are limited to 2 MB
const MAX_LIMIT = 500;

const json = (body, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' },
  });

const fail = (status, error) => json({ error }, status);

/** Compares two strings without stopping at the first difference. */
function sameSecret(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string' || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

const toHex = (bytes) => [...new Uint8Array(bytes)].map((b) => b.toString(16).padStart(2, '0')).join('');

async function sha256(text) {
  return toHex(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text)));
}

const randomHex = (bytes) => toHex(crypto.getRandomValues(new Uint8Array(bytes)));

// ---------------------------------------------------------------- schema

let schemaReady = false;
async function ensureSchema(db, env) {
  if (schemaReady) return;
  await db.exec(
    'CREATE TABLE IF NOT EXISTS shops (id TEXT PRIMARY KEY, name TEXT NOT NULL, key_hash TEXT NOT NULL UNIQUE, last_seq INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL)',
  );
  await db.exec(
    'CREATE TABLE IF NOT EXISTS shop_ops (shop_id TEXT NOT NULL, seq INTEGER NOT NULL, op_id TEXT NOT NULL, device TEXT NOT NULL, at INTEGER NOT NULL, payload TEXT NOT NULL, PRIMARY KEY (shop_id, seq), UNIQUE (shop_id, op_id))',
  );
  await migrateSingleShop(db, env);
  schemaReady = true;
}

/**
 * Before many shops, this server held one shop's list in a table named "ops",
 * with the one key kept as the SHOP_KEY secret. That shop becomes the shop
 * "main": same key, same entries, same numbers (and it carries on from the
 * highest number ever used, so numbers are never reused). The old table is
 * left in place, renamed, as a backup. Safe to run again: it does nothing once
 * "main" exists.
 */
async function migrateSingleShop(db, env) {
  const old = await db.prepare("SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'ops'").first();
  if (!old || !env.SHOP_KEY) return;
  const done = await db.prepare("SELECT id FROM shops WHERE id = 'main'").first();
  if (done) return;
  const highest = await db.prepare('SELECT COALESCE(MAX(seq), 0) AS n FROM ops').first();
  const used = await db.prepare("SELECT seq FROM sqlite_sequence WHERE name = 'ops'").first().catch(() => null);
  const last = Math.max(highest.n, used?.seq ?? 0);
  await db.batch([
    db
      .prepare("INSERT INTO shops (id, name, key_hash, last_seq, created_at) VALUES ('main', 'Main shop', ?, ?, ?)")
      .bind(await sha256(env.SHOP_KEY), last, Date.now()),
    db.prepare(
      "INSERT INTO shop_ops (shop_id, seq, op_id, device, at, payload) SELECT 'main', seq, op_id, device, at, payload FROM ops",
    ),
  ]);
  try {
    await db.exec('ALTER TABLE ops RENAME TO ops_before_many_shops');
  } catch {
    // Only tidiness: the copy above is what counts.
  }
}

// ---------------------------------------------------------------- a shop's own list

async function head(db, shopId) {
  const row = await db.prepare('SELECT COALESCE(MAX(seq), 0) AS head FROM shop_ops WHERE shop_id = ?').bind(shopId).first();
  return row.head;
}

async function listOps(db, shopId, url) {
  const after = Number.parseInt(url.searchParams.get('after') ?? '0', 10);
  const asked = Number.parseInt(url.searchParams.get('limit') ?? `${MAX_LIMIT}`, 10);
  if (!Number.isInteger(after) || after < 0) return fail(400, 'bad after');
  const limit = Math.min(Number.isInteger(asked) && asked > 0 ? asked : MAX_LIMIT, MAX_LIMIT);
  const { results } = await db
    .prepare(
      'SELECT seq, op_id AS opId, device, at, payload FROM shop_ops WHERE shop_id = ? AND seq > ? ORDER BY seq ASC LIMIT ?',
    )
    .bind(shopId, after, limit)
    .all();
  return json({ ops: results, head: await head(db, shopId) });
}

async function readEntry(request) {
  let body;
  try {
    body = await request.json();
  } catch {
    return fail(400, 'not json');
  }
  const { opId, device, at, payload } = body ?? {};
  if (typeof opId !== 'string' || opId.length < 8 || opId.length > 80) return fail(400, 'bad opId');
  if (typeof device !== 'string' || device.length === 0 || device.length > 80) return fail(400, 'bad device');
  if (!Number.isInteger(at)) return fail(400, 'bad at');
  if (typeof payload !== 'string' || payload.length === 0) return fail(400, 'bad payload');
  if (payload.length > MAX_PAYLOAD) return fail(413, 'payload too large');
  return { opId, device, at, payload };
}

const seqOf = async (db, shopId, opId) =>
  (await db.prepare('SELECT seq FROM shop_ops WHERE shop_id = ? AND op_id = ?').bind(shopId, opId).first())?.seq;

/** The statements that add one entry with the shop's next number (and nothing if it is already there). */
function appendStatements(db, shopId, e) {
  return [
    db
      .prepare(
        'UPDATE shops SET last_seq = last_seq + 1 WHERE id = ? AND NOT EXISTS (SELECT 1 FROM shop_ops WHERE shop_id = ? AND op_id = ?)',
      )
      .bind(shopId, shopId, e.opId),
    db
      .prepare(
        'INSERT INTO shop_ops (shop_id, seq, op_id, device, at, payload) SELECT id, last_seq, ?, ?, ?, ? FROM shops WHERE id = ? AND NOT EXISTS (SELECT 1 FROM shop_ops WHERE shop_id = ? AND op_id = ?)',
      )
      .bind(e.opId, e.device, e.at, e.payload, shopId, shopId, e.opId),
  ];
}

async function addOp(db, shopId, request) {
  const entry = await readEntry(request);
  if (entry instanceof Response) return entry;
  // A retry of the same operation (the phone never heard the answer) must not
  // be recorded twice. One step: the number is taken and the entry stored together.
  await db.batch(appendStatements(db, shopId, entry));
  return json({ seq: await seqOf(db, shopId, entry.opId) });
}

async function eraseAll(db, shopId, request) {
  const entry = await readEntry(request);
  if (entry instanceof Response) return entry;
  // The same erase sent twice (the answer was lost) must not wipe the list again.
  const known = await seqOf(db, shopId, entry.opId);
  if (known) return json({ seq: known });
  // One step: either everything is gone and the notice is there, or nothing changed.
  const [bump, ...rest] = appendStatements(db, shopId, entry);
  await db.batch([bump, db.prepare('DELETE FROM shop_ops WHERE shop_id = ? AND op_id <> ?').bind(shopId, entry.opId), ...rest]);
  return json({ seq: await seqOf(db, shopId, entry.opId) });
}

// ---------------------------------------------------------------- the admin: creating shops

const newKey = () => randomHex(24);

async function createShop(db, request) {
  let body;
  try {
    body = await request.json();
  } catch {
    return fail(400, 'not json');
  }
  const name = typeof body?.name === 'string' ? body.name.trim() : '';
  if (name.length === 0 || name.length > 80) return fail(400, 'bad name');
  const id = randomHex(6);
  const key = newKey();
  await db
    .prepare('INSERT INTO shops (id, name, key_hash, last_seq, created_at) VALUES (?, ?, ?, 0, ?)')
    .bind(id, name, await sha256(key), Date.now())
    .run();
  return json({ id, name, key }, 201);
}

async function listShops(db) {
  const { results } = await db
    .prepare(
      'SELECT s.id, s.name, s.created_at AS createdAt, COALESCE((SELECT MAX(seq) FROM shop_ops o WHERE o.shop_id = s.id), 0) AS head FROM shops s ORDER BY s.created_at',
    )
    .all();
  return json({ shops: results });
}

async function newShopKey(db, id) {
  const shop = await db.prepare('SELECT id FROM shops WHERE id = ?').bind(id).first();
  if (!shop) return fail(404, 'no such shop');
  const key = newKey();
  await db.prepare('UPDATE shops SET key_hash = ? WHERE id = ?').bind(await sha256(key), id).run();
  return json({ id, key });
}

// ---------------------------------------------------------------- routing

export default {
  async fetch(request, env) {
    const header = request.headers.get('authorization') ?? '';
    const token = header.startsWith('Bearer ') ? header.slice(7) : '';
    const url = new URL(request.url);
    const method = request.method;
    try {
      await ensureSchema(env.DB, env);

      if (url.pathname.startsWith('/v1/admin/')) {
        if (!env.ADMIN_KEY || !sameSecret(token, env.ADMIN_KEY)) return fail(401, 'unauthorized');
        if (url.pathname === '/v1/admin/shops' && method === 'POST') return await createShop(env.DB, request);
        if (url.pathname === '/v1/admin/shops' && method === 'GET') return await listShops(env.DB);
        const rotate = url.pathname.match(/^\/v1\/admin\/shops\/([0-9a-z]+)\/key$/);
        if (rotate && method === 'POST') return await newShopKey(env.DB, rotate[1]);
        return fail(404, 'not found');
      }

      const shop = token ? await env.DB.prepare('SELECT id FROM shops WHERE key_hash = ?').bind(await sha256(token)).first() : null;
      if (!shop) return fail(401, 'unauthorized');
      const shopId = shop.id;

      if (url.pathname === '/v1/ping' && method === 'GET') return json({ ok: true, head: await head(env.DB, shopId) });
      if (url.pathname === '/v1/ops' && method === 'GET') return await listOps(env.DB, shopId, url);
      if (url.pathname === '/v1/ops' && method === 'POST') return await addOp(env.DB, shopId, request);
      if (url.pathname === '/v1/erase' && method === 'POST') return await eraseAll(env.DB, shopId, request);
      return fail(404, 'not found');
    } catch (e) {
      return fail(500, 'server error');
    }
  },
};
