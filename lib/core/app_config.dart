/// Where this shop's shared log lives (the Cloudflare Worker). Not a secret:
/// every request still needs the shop's key. Staff only have to type the key.
const defaultSyncUrl = 'https://hardware-shop-sync.kabir3483.workers.dev';
