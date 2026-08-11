import { createHash, randomBytes } from "node:crypto";
import type { Server as HttpServer, IncomingMessage } from "node:http";
import type { Duplex } from "node:stream";
import WebSocket, { WebSocketServer } from "ws";
import type { RelayConfig } from "./config.js";
import type { SafeLogger } from "./logger.js";

interface TicketRecord {
  sessionId: string;
  subscriptionIds: string[];
  expiresAt: number;
}

interface ClientRecord {
  socket: WebSocket;
  sessionId: string;
  subscriptionIds: Set<string>;
  queue: string[];
  queuedBytes: number;
  sending: boolean;
}

export class DownlinkHub {
  private readonly config: RelayConfig;
  private readonly logger: SafeLogger;
  private readonly server = new WebSocketServer({ noServer: true, perMessageDeflate: false, clientTracking: false, maxPayload: 1024 });
  private readonly tickets = new Map<string, TicketRecord>();
  private readonly clients = new Set<ClientRecord>();
  private httpServer: HttpServer | null = null;

  constructor(config: RelayConfig, logger: SafeLogger) {
    this.config = config;
    this.logger = logger;
  }

  attach(server: HttpServer): void {
    if (this.httpServer) throw new Error("Downlink hub is already attached");
    this.httpServer = server;
    server.on("upgrade", this.handleUpgrade);
  }

  issueTicket(sessionId: string, subscriptionIds: string[], socketUrl: string): { ticket: string; expiresAt: number; socketUrl: string } {
    this.pruneTickets();
    const ticket = randomBytes(32).toString("base64url");
    const expiresAt = nowSeconds() + this.config.ticketTtlSeconds;
    this.tickets.set(hash(ticket), { sessionId, subscriptionIds: [...subscriptionIds], expiresAt });
    return { ticket, expiresAt, socketUrl };
  }

  publish(sessionId: string, subscriptionId: string, envelope: Record<string, unknown>): number {
    const serialized = JSON.stringify(envelope);
    const bytes = Buffer.byteLength(serialized);
    if (bytes > this.config.maxSocketPacketBytes) {
      this.logger.warn("downlink_packet_rejected", { bytes });
      return 0;
    }
    let accepted = 0;
    for (const client of this.clients) {
      if (client.socket.readyState !== WebSocket.OPEN || client.sessionId !== sessionId || !client.subscriptionIds.has(subscriptionId)) continue;
      if (client.queue.length >= this.config.maxSocketQueueEntries || client.queuedBytes + bytes > this.config.maxSocketQueueEntries * this.config.maxSocketPacketBytes) {
        client.socket.close(1013, "relay_queue_overflow");
        continue;
      }
      client.queue.push(serialized);
      client.queuedBytes += bytes;
      accepted += 1;
      this.flush(client);
    }
    return accepted;
  }

  closeSession(sessionId: string, reason = "session_revoked"): void {
    for (const client of this.clients) if (client.sessionId === sessionId) client.socket.close(1008, reason.slice(0, 120));
  }

  activeConnectionCount(): number {
    return this.clients.size;
  }

  async close(): Promise<void> {
    if (this.httpServer) this.httpServer.off("upgrade", this.handleUpgrade);
    this.httpServer = null;
    for (const client of this.clients) client.socket.terminate();
    this.clients.clear();
    this.tickets.clear();
    await new Promise<void>((resolve) => this.server.close(() => resolve()));
  }

  private readonly handleUpgrade = (request: IncomingMessage, socket: Duplex, head: Buffer): void => {
    let url: URL;
    try { url = new URL(request.url ?? "/", "http://relay.invalid"); }
    catch { return rejectUpgrade(socket, 400); }
    if (url.pathname !== "/v1/events/socket" || url.search) return rejectUpgrade(socket, 404);
    const authorization = Array.isArray(request.headers.authorization) ? "" : String(request.headers.authorization ?? "");
    const match = /^Ticket ([A-Za-z0-9_-]{20,256})$/.exec(authorization);
    if (!match?.[1]) return rejectUpgrade(socket, 401);
    this.pruneTickets();
    const record = this.tickets.get(hash(match[1]));
    if (!record || record.expiresAt <= nowSeconds()) return rejectUpgrade(socket, 401);
    this.tickets.delete(hash(match[1]));
    this.server.handleUpgrade(request, socket, head, (webSocket) => this.accept(webSocket, record));
  };

  private accept(socket: WebSocket, ticket: TicketRecord): void {
    const client: ClientRecord = { socket, sessionId: ticket.sessionId, subscriptionIds: new Set(ticket.subscriptionIds), queue: [], queuedBytes: 0, sending: false };
    this.clients.add(client);
    socket.on("message", () => socket.close(1008, "client_messages_not_supported"));
    socket.once("close", () => this.clients.delete(client));
    socket.once("error", () => this.clients.delete(client));
  }

  private flush(client: ClientRecord): void {
    if (client.sending || client.socket.readyState !== WebSocket.OPEN || client.queue.length === 0) return;
    const payload = client.queue.shift();
    if (payload === undefined) return;
    client.queuedBytes -= Buffer.byteLength(payload);
    client.sending = true;
    client.socket.send(payload, { binary: false, compress: false }, (error) => {
      client.sending = false;
      if (error) client.socket.close(1011, "relay_send_failed");
      else this.flush(client);
    });
  }

  private pruneTickets(): void {
    const now = nowSeconds();
    for (const [key, ticket] of this.tickets) if (ticket.expiresAt <= now) this.tickets.delete(key);
  }
}

function hash(value: string): string {
  return createHash("sha256").update(value).digest("base64url");
}

function nowSeconds(): number {
  return Math.floor(Date.now() / 1000);
}

function rejectUpgrade(socket: Duplex, status: number): void {
  const message = status === 401 ? "Unauthorized" : status === 404 ? "Not Found" : "Bad Request";
  socket.write(`HTTP/1.1 ${status} ${message}\r\nConnection: close\r\nCache-Control: no-store\r\nContent-Length: 0\r\n\r\n`);
  socket.destroy();
}
