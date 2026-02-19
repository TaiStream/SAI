import { normalizeSuiAddress } from '@mysten/sui/utils';
import { verifyPersonalMessageSignature } from '@mysten/sui/verify';
import { serializeCanonicalRequest } from './canonical';
import type { VerifyOptions, VerifyResult, SignedHttpRequest } from './types';

export async function verifySignedRequest(
  signed: SignedHttpRequest,
  options: VerifyOptions = {}
): Promise<VerifyResult> {
  try {
    const normalizedSigner = normalizeSuiAddress(signed.signer);

    if (options.expectedSigner && normalizeSuiAddress(options.expectedSigner) !== normalizedSigner) {
      return { ok: false, reason: 'Signer does not match expected signer' };
    }

    if (options.expectedAudience && signed.request.audience !== options.expectedAudience) {
      return { ok: false, reason: 'Audience mismatch' };
    }

    const now = options.nowMs ?? Date.now();
    const maxAgeMs = options.maxAgeMs ?? 5 * 60_000;
    if (Math.abs(now - signed.request.timestampMs) > maxAgeMs) {
      return { ok: false, reason: 'Request is expired or from the future' };
    }

    const canonicalPayload = serializeCanonicalRequest(signed.request);
    if (canonicalPayload !== signed.payload) {
      return { ok: false, reason: 'Payload does not match canonical request' };
    }

    await verifyPersonalMessageSignature(
      new TextEncoder().encode(canonicalPayload),
      signed.signature,
      { address: normalizedSigner }
    );

    return { ok: true, signer: normalizedSigner };
  } catch (error: any) {
    return { ok: false, reason: error?.message ?? 'Signature verification failed' };
  }
}
