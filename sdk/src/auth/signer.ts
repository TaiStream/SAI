import { normalizeSuiAddress } from '@mysten/sui/utils';
import { createSignableRequest, serializeCanonicalRequest } from './canonical';
import type { CanonicalRequest, PersonalMessageSigner, SignableRequestInput, SignedHttpRequest } from './types';

export interface SignOptions {
  signerAddress?: string;
}

export async function signCanonicalRequest(
  request: CanonicalRequest,
  signer: PersonalMessageSigner,
  options: SignOptions = {}
): Promise<SignedHttpRequest> {
  const payload = serializeCanonicalRequest(request);
  const message = new TextEncoder().encode(payload);
  const { signature } = await signer.signPersonalMessage({ message });

  const resolvedSigner = options.signerAddress ?? (signer.getAddress ? await signer.getAddress() : undefined);
  if (!resolvedSigner) {
    throw new Error('signerAddress is required when signer.getAddress() is unavailable');
  }

  return {
    request,
    signature,
    signer: normalizeSuiAddress(resolvedSigner),
    payload,
  };
}

export async function signHttpRequest(
  input: SignableRequestInput,
  signer: PersonalMessageSigner,
  options: SignOptions = {}
): Promise<SignedHttpRequest> {
  const request = createSignableRequest(input);
  return signCanonicalRequest(request, signer, options);
}
