// Tries a Cosmos DB data-plane read from outside the virtual network, signed in with the current Azure CLI
// identity. With public network access disabled, the account must refuse it at the firewall (HTTP 403,
// "... through public internet ..."), before any role check. Exits 0 only in that case.
//
//   node scripts/probe-cosmos-public.mjs <cosmos-endpoint>     (run after `npm ci` in api/)
import { createRequire } from "node:module";

const require = createRequire(new URL("../api/package.json", import.meta.url));
const { CosmosClient } = require("@azure/cosmos");
const { AzureCliCredential } = require("@azure/identity");

const endpoint = process.argv[2];
if (!endpoint) {
  console.error("usage: probe-cosmos-public.mjs <cosmos-endpoint>");
  process.exit(2);
}

const client = new CosmosClient({ endpoint, aadCredentials: new AzureCliCredential() });
try {
  await client.database("cloudresume").container("counters").item("resume", "resume").read();
  console.log("FAIL: the read from the public internet succeeded");
  process.exit(1);
} catch (e) {
  const message = String(e?.message ?? e).split("\n")[0];
  if (e?.code === 403 && /public internet/i.test(message)) {
    console.log(`PASS: refused from the public internet (HTTP 403): ${message.slice(0, 160)}`);
    process.exit(0);
  }
  console.log(`FAIL: unexpected response (HTTP ${e?.code}): ${message.slice(0, 200)}`);
  process.exit(1);
}
