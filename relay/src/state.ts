import { createCipheriv, createDecipheriv, randomBytes } from "node:crypto";
import { chmod, mkdir, open, readFile, rename, rm, writeFile } from "node:fs/promises";
import { dirname } from "node:path";

export interface AuthRequestRecord {
  id: string;
  publisherId: string;
  applicationId: string;
  sessionSlot: string;
  capabilities: string[];
  requestedScopes: string[];
  proofHash: string;
  oauthState: string;
  pkceVerifier: string;
  status: "pending" | "completed" | "consumed" | "failed";
  sessionId: string;
  resultBrokerCredential: string;
  failureCode: string;
  createdAt: number;
  expiresAt: number;
}

export interface SessionRecord {
  id: string;
  sessionSlot: string;
  publisherId: string;
  applicationId: string;
  userId: string;
  username: string;
  channelId: string;
  channelSlug: string;
  capabilities: string[];
  scopes: string[];
  brokerCredentialHash: string;
  brokerExpiresAt: number;
  accessToken: string;
  refreshToken: string;
  tokenType: string;
  tokenExpiresAt: number;
  createdAt: number;
  updatedAt: number;
}

export interface SubscriptionRecord {
  id: string;
  channelId: string;
  eventType: string;
  eventVersion: number;
  active: boolean;
  updatedAt: number;
}

export interface ReplayRecord {
  messageId: string;
  expiresAt: number;
}

export interface PendingRevocationRecord {
  id: string;
  accessToken: string;
  refreshToken: string;
  attempts: number;
  retryAfter: number;
}

export interface IdempotencyRecord {
  keyHash: string;
  sessionId: string;
  operationId: string;
  requestHash: string;
  status: "pending" | "completed";
  responseStatus: number;
  responseBody: unknown;
  responseHeaders: Record<string, string>;
  responseAvailable: boolean;
  responseBytes: number;
  createdAt: number;
  expiresAt: number;
}

export interface RelayState {
  schemaVersion: 1;
  authRequests: AuthRequestRecord[];
  sessions: SessionRecord[];
  subscriptions: SubscriptionRecord[];
  replayEntries: ReplayRecord[];
  pendingRevocations: PendingRevocationRecord[];
  idempotencyEntries: IdempotencyRecord[];
}

export interface StateStore {
  snapshot(): RelayState;
  mutate<T>(operation: (state: RelayState) => T | Promise<T>): Promise<T>;
}

export function emptyRelayState(): RelayState {
  return { schemaVersion: 1, authRequests: [], sessions: [], subscriptions: [], replayEntries: [], pendingRevocations: [], idempotencyEntries: [] };
}

export class MemoryStateStore implements StateStore {
  protected state: RelayState;
  private queue: Promise<void> = Promise.resolve();

  constructor(initial: RelayState = emptyRelayState()) {
    this.state = structuredClone(initial);
  }

  snapshot(): RelayState {
    return structuredClone(this.state);
  }

  mutate<T>(operation: (state: RelayState) => T | Promise<T>): Promise<T> {
    const result = this.queue.then(async () => {
      const draft = structuredClone(this.state);
      const value = await operation(draft);
      validateState(draft);
      this.state = draft;
      await this.afterMutation();
      return value;
    });
    this.queue = result.then(() => undefined, () => undefined);
    return result;
  }

  protected async afterMutation(): Promise<void> {}
}

export class EncryptedFileStateStore extends MemoryStateStore {
  private readonly path: string;
  private readonly key: Buffer;

  private constructor(path: string, key: Buffer, state: RelayState) {
    super(state);
    this.path = path;
    this.key = Buffer.from(key);
  }

  static async open(path: string, key: Buffer): Promise<EncryptedFileStateStore> {
    if (!path) throw new Error("Encrypted state path is required");
    if (key.length !== 32) throw new Error("Encrypted state key must be exactly 32 bytes");
    let state = emptyRelayState();
    try {
      const source = JSON.parse(await readFile(path, "utf8")) as EncryptedDocument;
      state = migrateState(decryptState(source, key));
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw new Error("Unable to decrypt or authenticate relay state", { cause: error });
    }
    validateState(state);
    return new EncryptedFileStateStore(path, key, state);
  }

  protected override async afterMutation(): Promise<void> {
    const directory = dirname(this.path);
    await mkdir(directory, { recursive: true, mode: 0o700 });
    const temporary = `${this.path}.${process.pid}.${randomBytes(6).toString("hex")}.tmp`;
    try {
      await writeFile(temporary, JSON.stringify(encryptState(this.state, this.key)), { encoding: "utf8", mode: 0o600, flag: "wx" });
      const file = await open(temporary, "r");
      try { await file.sync(); }
      catch (error) {
        const code = (error as NodeJS.ErrnoException).code;
        if (process.platform !== "win32" || (code !== "EPERM" && code !== "EINVAL" && code !== "ENOTSUP")) throw error;
      }
      finally { await file.close(); }
      await rename(temporary, this.path);
      await chmod(this.path, 0o600).catch(() => undefined);
      const parent = await open(directory, "r").catch(() => null);
      if (parent) {
        try { await parent.sync(); }
        catch { /* Directory fsync is not supported on every host filesystem. */ }
        finally { await parent.close(); }
      }
    } finally {
      await rm(temporary, { force: true }).catch(() => undefined);
    }
  }
}

interface EncryptedDocument {
  format: "redot-kicker-state";
  version: 1;
  algorithm: "aes-256-gcm";
  iv: string;
  tag: string;
  ciphertext: string;
}

const AAD = Buffer.from("redot-kicker-state/v1", "utf8");

function encryptState(state: RelayState, key: Buffer): EncryptedDocument {
  const iv = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", key, iv);
  cipher.setAAD(AAD);
  const ciphertext = Buffer.concat([cipher.update(JSON.stringify(state), "utf8"), cipher.final()]);
  return { format: "redot-kicker-state", version: 1, algorithm: "aes-256-gcm", iv: iv.toString("base64url"), tag: cipher.getAuthTag().toString("base64url"), ciphertext: ciphertext.toString("base64url") };
}

function decryptState(document: EncryptedDocument, key: Buffer): RelayState {
  if (document.format !== "redot-kicker-state" || document.version !== 1 || document.algorithm !== "aes-256-gcm") throw new Error("Unsupported encrypted relay state format");
  const decipher = createDecipheriv("aes-256-gcm", key, Buffer.from(document.iv, "base64url"));
  decipher.setAAD(AAD);
  decipher.setAuthTag(Buffer.from(document.tag, "base64url"));
  const plaintext = Buffer.concat([decipher.update(Buffer.from(document.ciphertext, "base64url")), decipher.final()]);
  return JSON.parse(plaintext.toString("utf8")) as RelayState;
}

function migrateState(state: RelayState): RelayState {
  if (state.schemaVersion === 1 && !Array.isArray(state.idempotencyEntries)) state.idempotencyEntries = [];
  return state;
}

function validateState(state: RelayState): void {
  if (state.schemaVersion !== 1 || !Array.isArray(state.authRequests) || !Array.isArray(state.sessions) || !Array.isArray(state.subscriptions) || !Array.isArray(state.replayEntries) || !Array.isArray(state.pendingRevocations) || !Array.isArray(state.idempotencyEntries)) throw new Error("Relay state schema is invalid");
}
