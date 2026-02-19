import { createHash, randomUUID } from 'crypto';
import type { CanonicalRequest, HttpMethod, SignableRequestInput } from './types';

const ALLOWED_METHODS: ReadonlySet<string> = new Set([
  'GET',
  'POST',
  'PUT',
  'PATCH',
  'DELETE',
  'HEAD',
  'OPTIONS',
]);

const DEFAULT_SIGNED_HEADERS = ['host', 'content-type', 'x-sai-target'];

function normalizeMethod(method: string): HttpMethod {
  const upper = method.toUpperCase();
  if (!ALLOWED_METHODS.has(upper)) {
    throw new Error(`Unsupported HTTP method for signing: ${method}`);
  }
  return upper as HttpMethod;
}

function normalizePath(pathname: string): string {
  if (!pathname) return '/';
  return pathname.replace(/\/+/g, '/');
}

function normalizeQuery(url: URL): string {
  const entries = [...url.searchParams.entries()].sort(([a], [b]) => a.localeCompare(b));
  return entries
    .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`)
    .join('&');
}

function pickHeaders(headers?: Record<string, string | undefined>): Record<string, string> {
  const output: Record<string, string> = {};
  const normalized = Object.fromEntries(
    Object.entries(headers ?? {}).map(([k, v]) => [k.toLowerCase(), (v ?? '').trim()])
  );

  for (const key of DEFAULT_SIGNED_HEADERS) {
    if (normalized[key]) {
      output[key] = normalized[key];
    }
  }

  return output;
}

function toBytes(input: string | Uint8Array | undefined): Uint8Array {
  if (input === undefined) return new Uint8Array();
  if (input instanceof Uint8Array) return input;
  return new TextEncoder().encode(input);
}

export function sha256Hex(input: string | Uint8Array | undefined): string {
  const bytes = toBytes(input);
  return createHash('sha256').update(bytes).digest('hex');
}

export function createSignableRequest(input: SignableRequestInput): CanonicalRequest {
  const url = new URL(input.url);
  return {
    method: normalizeMethod(input.method),
    path: normalizePath(url.pathname),
    query: normalizeQuery(url),
    headers: pickHeaders({
      host: url.host,
      ...(input.headers ?? {}),
    }),
    bodySha256: sha256Hex(input.body),
    audience: input.audience,
    chainId: input.chainId,
    timestampMs: input.timestampMs ?? Date.now(),
    nonce: input.nonce ?? randomUUID(),
  };
}

export function serializeCanonicalRequest(req: CanonicalRequest): string {
  const orderedHeaders = Object.entries(req.headers)
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([k, v]) => `${k}:${v}`)
    .join('\n');

  return [
    'SAI-HTTP-REQ',
    'v1',
    req.method,
    req.path,
    req.query,
    orderedHeaders,
    req.bodySha256,
    req.audience ?? '',
    req.chainId ?? '',
    String(req.timestampMs),
    req.nonce,
  ].join('\n');
}
