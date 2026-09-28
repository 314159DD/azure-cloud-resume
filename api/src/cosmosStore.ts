// CounterStore adapter for Cosmos DB (NoSQL API).
// Authenticates with the function's managed identity: the account has
// local (key) auth disabled, so there is no key or connection string anywhere, only the endpoint.
import { Container, CosmosClient, ErrorResponse } from "@azure/cosmos";
import { DefaultAzureCredential, ManagedIdentityCredential, type TokenCredential } from "@azure/identity";
import type { CounterStore } from "./counter";

interface CounterDoc {
  id: string;
  count: number;
}

const hasStatus = (e: unknown, code: number): boolean => (e as ErrorResponse | undefined)?.code === code;

export class CosmosCounterStore implements CounterStore {
  constructor(private readonly container: Container) {}

  static fromEnv(env: NodeJS.ProcessEnv = process.env): CosmosCounterStore {
    const endpoint = env.COSMOS_ENDPOINT;
    if (!endpoint) throw new Error("COSMOS_ENDPOINT is not set");
    // In Azure the app settings name the user-assigned identity; locally, DefaultAzureCredential falls
    // back to the developer's Azure CLI login.
    const credential: TokenCredential = env.AZURE_CLIENT_ID
      ? new ManagedIdentityCredential({ clientId: env.AZURE_CLIENT_ID })
      : new DefaultAzureCredential();
    const client = new CosmosClient({ endpoint, aadCredentials: credential });
    const container = client.database(env.COSMOS_DATABASE ?? "cloudresume").container(env.COSMOS_CONTAINER ?? "counters");
    return new CosmosCounterStore(container);
  }

  async increment(id: string): Promise<number> {
    const count = await this.patchIncrement(id);
    if (count !== null) return count;
    // First visit ever: create the document. If a concurrent request created it first (409), the
    // document now exists and one more atomic increment is enough.
    try {
      await this.container.items.create<CounterDoc>({ id, count: 1 });
      return 1;
    } catch (e) {
      if (!hasStatus(e, 409)) throw e;
    }
    const retried = await this.patchIncrement(id);
    if (retried === null) throw new Error(`Counter ${id} disappeared during creation`);
    return retried;
  }

  /** Server-side atomic increment; a read-modify-write would lose visits under concurrency. Null if missing. */
  private async patchIncrement(id: string): Promise<number | null> {
    try {
      const { resource } = await this.container
        .item(id, id)
        .patch<CounterDoc>([{ op: "incr", path: "/count", value: 1 }]);
      if (!resource) throw new Error("Patch returned no document");
      return resource.count;
    } catch (e) {
      if (hasStatus(e, 404)) return null;
      throw e;
    }
  }

  async get(id: string): Promise<number> {
    try {
      const { resource } = await this.container.item(id, id).read<CounterDoc>();
      return resource?.count ?? 0;
    } catch (e) {
      if (hasStatus(e, 404)) return 0;
      throw e;
    }
  }
}
