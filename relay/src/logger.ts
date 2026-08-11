export interface SafeLogger {
  info(event: string, fields?: Record<string, string | number | boolean>): void;
  warn(event: string, fields?: Record<string, string | number | boolean>): void;
  error(event: string, fields?: Record<string, string | number | boolean>): void;
}

export class JsonConsoleLogger implements SafeLogger {
  info(event: string, fields: Record<string, string | number | boolean> = {}): void { this.write("info", event, fields); }
  warn(event: string, fields: Record<string, string | number | boolean> = {}): void { this.write("warn", event, fields); }
  error(event: string, fields: Record<string, string | number | boolean> = {}): void { this.write("error", event, fields); }

  private write(level: string, event: string, fields: Record<string, string | number | boolean>): void {
    const safe: Record<string, string | number | boolean> = {};
    for (const [key, value] of Object.entries(fields)) {
      if (/token|secret|credential|authorization|cookie|body|payload|code|verifier|state|url/i.test(key)) continue;
      safe[key] = value;
    }
    process.stdout.write(`${JSON.stringify({ timestamp: new Date().toISOString(), level, event, ...safe })}\n`);
  }
}

export class NullLogger implements SafeLogger {
  info(): void {}
  warn(): void {}
  error(): void {}
}
