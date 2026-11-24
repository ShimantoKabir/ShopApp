// LOCAL ONLY. Never run this against the real server: it creates shops and erases a shop's entries.
//
//   npx wrangler@3 dev --local --port 8799 --persist-to ./.tmp-test-state
//   node test/worker.test.mjs http://127.0.0.1:8799 <ADMIN_KEY> [<legacy SHOP_KEY> [<the number its next entry must get>]]
//
// The optional last argument is the old single-shop key. Pass it when the local
// database still has the old "ops" table (from before many shops): the test then
// checks that shop came through the move whole.
const [, , base = 'http://127.0.0.1:8799', adminKey = 'test-admin', legacyKey, expectedNext] = process.argv;
let failed = 0;

const call = (path, { method = 'GET', body, key } = {}) =>
  fetch(base + path, {
    method,
    headers: { ...(key ? { authorization: `Bearer ${key}` } : {}), 'content-type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body),
  }).then(async (r) => ({ status: r.status, body: await r.json().catch(() => null) }));

const check = (name, ok, detail = '') => {
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${ok ? '' : '  ' + detail}`);
  if (!ok) failed++;
};

const run = Date.now().toString(36);
const op = (n, extra = {}) => ({ opId: `op-${run}-${n}-padding`, device: 'phone-A', at: 1000 + n, payload: `{"n":${n}}`, ...extra });
const admin = (path, opts = {}) => call(path, { ...opts, key: adminKey });

// --- the admin
check('no key is refused', (await call('/v1/ping')).status === 401);
check('a wrong key is refused', (await call('/v1/ping', { key: 'nope' })).status === 401);
check('an empty key is refused', (await call('/v1/ping', { key: '' })).status === 401);
check('the admin key is not a shop key', (await call('/v1/ping', { key: adminKey })).status === 401);
check('creating a shop without the admin key is refused', (await call('/v1/admin/shops', { method: 'POST', body: { name: 'x' } })).status === 401);
check('creating a shop with a wrong key is refused', (await call('/v1/admin/shops', { method: 'POST', body: { name: 'x' }, key: 'nope' })).status === 401);
check('a nameless shop is refused', (await admin('/v1/admin/shops', { method: 'POST', body: { name: '  ' } })).status === 400);

const a = await admin('/v1/admin/shops', { method: 'POST', body: { name: `Shop A ${run}` } });
const b = await admin('/v1/admin/shops', { method: 'POST', body: { name: `Shop B ${run}` } });
check('a new shop gets an id and its own key', a.status === 201 && a.body.id && a.body.key?.length >= 32 && a.body.key !== b.body.key, JSON.stringify(a.body));
const keyA = a.body.key;
const keyB = b.body.key;
check("a shop key is not the admin's", (await call('/v1/admin/shops', { key: keyA })).status === 401);
const shops = await admin('/v1/admin/shops');
check('the admin sees every shop, but never a key', shops.body.shops.some((s) => s.id === a.body.id) && !JSON.stringify(shops.body).includes(keyA));

// --- a new shop is empty, and numbering starts at 1 for each
check('a new shop is empty', (await call('/v1/ping', { key: keyA })).body.head === 0);
const a1 = await call('/v1/ops', { method: 'POST', body: op(1), key: keyA });
const b1 = await call('/v1/ops', { method: 'POST', body: op(2, { device: 'phone-B' }), key: keyB });
check('each shop starts counting at 1', a1.body.seq === 1 && b1.body.seq === 1, JSON.stringify([a1.body, b1.body]));

// --- order within a shop
const a2 = await call('/v1/ops', { method: 'POST', body: op(3), key: keyA });
const a3 = await call('/v1/ops', { method: 'POST', body: op(4), key: keyA });
check('entries get increasing numbers', a2.body.seq === 2 && a3.body.seq === 3, JSON.stringify([a2.body, a3.body]));

// --- a retry is not a second copy
const again = await call('/v1/ops', { method: 'POST', body: op(3), key: keyA });
check('the same entry sent twice keeps one number', again.body.seq === a2.body.seq);
const afterRetry = await call('/v1/ops', { method: 'POST', body: op(5), key: keyA });
check('and uses up no number', afterRetry.body.seq === 4, JSON.stringify(afterRetry.body));

// --- shops cannot see each other
const readA = await call('/v1/ops?after=0', { key: keyA });
const readB = await call('/v1/ops?after=0', { key: keyB });
check("shop A reads only its own entries", readA.body.ops.length === 4 && readA.body.ops.every((o) => o.payload.startsWith('{"n"')) && !readA.body.ops.some((o) => o.opId === op(2).opId));
check("shop B reads only its own entry", readB.body.ops.length === 1 && readB.body.ops[0].opId === op(2).opId);
check('heads are per shop', readA.body.head === 4 && readB.body.head === 1);
const sameId = await call('/v1/ops', { method: 'POST', body: op(1), key: keyB });
check('the same entry id in another shop is a separate entry', sameId.body.seq === 2 && (await call('/v1/ping', { key: keyA })).body.head === 4);

// --- reading back
const list = await call('/v1/ops?after=0', { key: keyA });
check('entries come back in order with who sent them', list.body.ops.map((o) => o.seq).join() === '1,2,3,4' && list.body.ops[0].device === 'phone-A');
check('payload comes back exactly as sent', list.body.ops[0].payload === '{"n":1}');
const part = await call('/v1/ops?after=1&limit=1', { key: keyA });
check('after and limit page through the list', part.body.ops.length === 1 && part.body.ops[0].seq === 2);
check('nothing after the head is an empty list', (await call('/v1/ops?after=4', { key: keyA })).body.ops.length === 0);

// --- bad input
const bad = (extra) => call('/v1/ops', { method: 'POST', body: { ...op(9), ...extra }, key: keyA });
check('a missing opId is refused', (await bad({ opId: undefined })).status === 400);
check('a missing payload is refused', (await bad({ payload: '' })).status === 400);
check('a non-number time is refused', (await bad({ at: 'now' })).status === 400);
check('a negative "after" is refused', (await call('/v1/ops?after=-1', { key: keyA })).status === 400);
check('too large a payload is refused', (await bad({ opId: `op-${run}-big-padding`, payload: 'x'.repeat(900_001) })).status === 413);
check('a large but allowed payload is stored', (await bad({ opId: `op-${run}-large-padding`, payload: 'y'.repeat(800_000) })).status === 200);
check('unknown paths are 404', (await call('/v1/nothing', { key: keyA })).status === 404);
check('no refused entry used up a number', (await call('/v1/ping', { key: keyA })).body.head === 5);

// --- erasing one shop leaves the others alone
const headB = (await call('/v1/ping', { key: keyB })).body.head;
const headA = (await call('/v1/ping', { key: keyA })).body.head;
check('erasing without a key is refused', (await call('/v1/erase', { method: 'POST', body: op(20) })).status === 401);
check('a bad erase notice is refused and nothing is erased', (await call('/v1/erase', { method: 'POST', body: { ...op(21), payload: '' }, key: keyA })).status === 400 && (await call('/v1/ping', { key: keyA })).body.head === headA);
const erased = await call('/v1/erase', { method: 'POST', body: op(22), key: keyA });
check('erasing returns a number above all earlier ones', erased.status === 200 && erased.body.seq === headA + 1, JSON.stringify(erased.body));
const afterErase = await call('/v1/ops?after=0', { key: keyA });
check('only the notice is left', afterErase.body.ops.length === 1 && afterErase.body.ops[0].opId === op(22).opId);
check('the other shop is untouched', (await call('/v1/ping', { key: keyB })).body.head === headB && (await call('/v1/ops?after=0', { key: keyB })).body.ops.length === 2);
const sameErase = await call('/v1/erase', { method: 'POST', body: op(22), key: keyA });
check('the same erase sent twice changes nothing more', sameErase.body.seq === erased.body.seq && (await call('/v1/ops?after=0', { key: keyA })).body.ops.length === 1);
const next = await call('/v1/ops', { method: 'POST', body: op(23), key: keyA });
check('new entries carry on from the notice', next.body.seq === erased.body.seq + 1);
check('a phone behind the erase sees the notice first', (await call(`/v1/ops?after=${headA - 1}`, { key: keyA })).body.ops[0].opId === op(22).opId);

// --- a new key replaces the old one
const rotated = await admin(`/v1/admin/shops/${b.body.id}/key`, { method: 'POST' });
check('a new key works and has the same data', rotated.status === 200 && (await call('/v1/ping', { key: rotated.body.key })).body.head === headB);
check('the old key stops working', (await call('/v1/ping', { key: keyB })).status === 401);
check('the other shop is not affected by it', (await call('/v1/ping', { key: keyA })).status === 200);
check('a key for a shop that does not exist is refused', (await admin('/v1/admin/shops/ffffffffffff/key', { method: 'POST' })).status === 404);

// --- the shop that existed before many shops
if (legacyKey) {
  const ping = await call('/v1/ping', { key: legacyKey });
  check('the old shop key still works', ping.status === 200 && ping.body.head > 0, JSON.stringify(ping.body));
  const all = await call('/v1/ops?after=0&limit=500', { key: legacyKey });
  const seqs = all.body.ops.map((o) => o.seq);
  check('its entries came through, in order', seqs.length > 0 && seqs.every((s, i) => i === 0 || s > seqs[i - 1]));
  const more = await call('/v1/ops', { method: 'POST', body: op(30), key: legacyKey });
  check('new entries carry on after the highest number it ever had (never reusing one)', more.body.seq > ping.body.head && (!expectedNext || more.body.seq === Number(expectedNext)), JSON.stringify([ping.body, more.body]));
  check('the other shops did not get its entries', (await call('/v1/ping', { key: keyA })).body.head < 10);
}

console.log(failed === 0 ? '\nALL PASSED' : `\n${failed} FAILED`);
process.exit(failed === 0 ? 0 : 1);
