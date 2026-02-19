export type HttpMethod =
  | 'GET'
  | 'POST'
  | 'PUT'
  | 'PATCH'
  | 'DELETE'
  | 'HEAD'
  | 'OPTIONS';

export interface SignableRequestInput {
  method: string;
  url: string;
  headers?: Record<string, string | undefined>;
  body?: string | Uint8Array;
  /** Intended audience/service identifier. */
  audience?: string;
  /** Optional Sui chain/network marker (for domain separation). */
  chainId?: string;
  /** Epoch ms when signature is created. Defaults to now. */
  timestampMs?: number;
  /** Unique token for replay protection. Defaults to random UUID. */
  nonce?: string;
}

export interface CanonicalRequest {
  method: HttpMethod;
  path: string;
  query: string;
  headers: Record<string, string>;
  bodySha256: string;
  audience?: string;
  chainId?: string;
  timestampMs: number;
  nonce: string;
}

export interface SignedHttpRequest {
  request: CanonicalRequest;
  signature: string;
  signer: string;
  payload: string;
}

export interface PersonalMessageSigner {
  signPersonalMessage(input: { message: Uint8Array }): Promise<{ signature: string }>;
  getAddress?: () => Promise<string>;
}

export interface VerifyOptions {
  expectedSigner?: string;
  expectedAudience?: string;
  maxAgeMs?: number;
  nowMs?: number;
}

export interface VerifyResult {
  ok: boolean;
  signer?: string;
  reason?: string;
}
