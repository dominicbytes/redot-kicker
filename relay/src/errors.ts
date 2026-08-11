export class HttpError extends Error {
  readonly status: number;
  readonly code: string;
  readonly retryable: boolean;

  constructor(status: number, code: string, message: string, retryable = false) {
    super(message);
    this.name = "HttpError";
    this.status = status;
    this.code = code;
    this.retryable = retryable;
  }
}

export function asHttpError(error: unknown): HttpError {
  if (error instanceof HttpError) return error;
  return new HttpError(500, "server_error", "The relay could not complete the request", true);
}
