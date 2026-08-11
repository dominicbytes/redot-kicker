export interface OperationContract {
  id: string;
  capability: string;
  method: "GET" | "POST" | "PATCH" | "DELETE";
  path: string;
  scopes: readonly string[];
  scopeMode?: "all" | "any";
  write?: boolean;
  confirm?: boolean;
  relay?: boolean;
  unavailable?: boolean;
  body?: boolean;
}

export const CAPABILITY_SCOPES: Readonly<Record<string, readonly string[]>> = Object.freeze({
  "identity.read": ["user:read"],
  "channel.read": ["channel:read"],
  "channel.manage": ["channel:write"],
  "categories.read": [],
  "livestreams.read": [],
  "chat.write": ["chat:write"],
  "chat.delete": ["moderation:chat_message:manage"],
  "events.receive": ["events:subscribe"],
  "events.manage": ["events:subscribe"],
  "rewards.read": ["channel:rewards:read"],
  "rewards.manage": ["channel:rewards:write"],
  "moderation.ban": ["moderation:ban"],
  "kicks.read": ["kicks:read"],
  "streamkey.read": ["streamkey:read"],
});

const operationList: OperationContract[] = [
  operation("categories.search.v2", "categories.read", "GET", "/public/v2/categories"),
  operation("categories.search.v1", "categories.read", "GET", "/public/v1/categories"),
  operation("categories.get.v1", "categories.read", "GET", "/public/v1/categories/{category_id}"),
  operation("channels.get", "channel.read", "GET", "/public/v1/channels", ["channel:read"]),
  operation("channels.update", "channel.manage", "PATCH", "/public/v1/channels", ["channel:write"], { write: true, confirm: true }),
  operation("rewards.list", "rewards.read", "GET", "/public/v1/channels/rewards", ["channel:rewards:read", "channel:rewards:write"], { scopeMode: "any" }),
  operation("rewards.create", "rewards.manage", "POST", "/public/v1/channels/rewards", ["channel:rewards:write"], { write: true, confirm: true }),
  operation("rewards.update", "rewards.manage", "PATCH", "/public/v1/channels/rewards/{id}", ["channel:rewards:write"], { write: true, confirm: true }),
  operation("rewards.delete", "rewards.manage", "DELETE", "/public/v1/channels/rewards/{id}", ["channel:rewards:write"], { write: true, confirm: true }),
  operation("redemptions.list", "rewards.read", "GET", "/public/v1/channels/rewards/redemptions", ["channel:rewards:read", "channel:rewards:write"], { scopeMode: "any" }),
  operation("redemptions.accept", "rewards.manage", "POST", "/public/v1/channels/rewards/redemptions/accept", ["channel:rewards:write"], { write: true, confirm: true }),
  operation("redemptions.reject", "rewards.manage", "POST", "/public/v1/channels/rewards/redemptions/reject", ["channel:rewards:write"], { write: true, confirm: true }),
  operation("chat.send", "chat.write", "POST", "/public/v1/chat", ["chat:write"], { write: true }),
  operation("chat.delete", "chat.delete", "DELETE", "/public/v1/chat/{message_id}", ["moderation:chat_message:manage"], { write: true, confirm: true }),
  operation("subscriptions.list", "events.manage", "GET", "/public/v1/events/subscriptions", [], { relay: true }),
  operation("subscriptions.create", "events.manage", "POST", "/public/v1/events/subscriptions", ["events:subscribe"], { write: true, relay: true }),
  operation("subscriptions.delete", "events.manage", "DELETE", "/public/v1/events/subscriptions", ["events:subscribe"], { write: true, confirm: true, relay: true }),
  operation("kicks.leaderboard", "kicks.read", "GET", "/public/v1/kicks/leaderboard", ["kicks:read"]),
  operation("livestreams.list.v2", "livestreams.read", "GET", "/public/v2/livestreams"),
  operation("livestreams.list.v1", "livestreams.read", "GET", "/public/v1/livestreams"),
  operation("livestreams.by_users", "livestreams.read", "GET", "/public/v1/users/livestreams"),
  operation("livestreams.stats", "livestreams.read", "GET", "/public/v1/livestreams/stats"),
  operation("moderation.ban", "moderation.ban", "POST", "/public/v1/moderation/bans", ["moderation:ban"], { write: true, confirm: true }),
  operation("moderation.unban", "moderation.ban", "DELETE", "/public/v1/moderation/bans", ["moderation:ban"], { write: true, confirm: true, body: true }),
  operation("public_key.get", "events.receive", "GET", "/public/v1/public-key", [], { relay: true }),
  operation("token.introspect", "identity.read", "POST", "/oauth/token/introspect", [], { body: false }),
  operation("users.get", "identity.read", "GET", "/public/v1/users", ["user:read"]),
  operation("stream_key.get", "streamkey.read", "GET", "", ["streamkey:read"], { unavailable: true }),
];

export const OPERATIONS: ReadonlyMap<string, OperationContract> = new Map(operationList.map((value) => [value.id, Object.freeze(value)]));

export const SUPPORTED_EVENTS = new Set([
  "chat.message.sent",
  "channel.followed",
  "channel.subscription.renewal",
  "channel.subscription.gifts",
  "channel.subscription.new",
  "channel.reward.redemption.updated",
  "livestream.status.updated",
  "livestream.metadata.updated",
  "moderation.banned",
  "kicks.gifted",
]);

export function scopesForCapabilities(capabilities: readonly string[]): string[] {
  const values = new Set<string>();
  for (const capability of capabilities) for (const scope of CAPABILITY_SCOPES[capability] ?? []) values.add(scope);
  return [...values].sort();
}

function operation(id: string, capability: string, method: OperationContract["method"], path: string, scopes: readonly string[] = [], options: Omit<OperationContract, "id" | "capability" | "method" | "path" | "scopes"> = {}): OperationContract {
  return { id, capability, method, path, scopes, ...options };
}
