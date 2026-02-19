import type { SignedHttpRequest } from '../auth/types';
import type { VisibilityTier } from '../types';

export interface SaiPolicy {
  requireActive?: boolean;
  minCredScore?: number;
  /** 0=Pristine ... 4=Suspended. Lower is better. */
  maxAllowedTier?: VisibilityTier | number;
  /** Which on-chain identity should match signer. */
  signerMustMatch?: 'owner' | 'wallet' | 'owner-or-wallet' | 'delegate' | 'any-authorized';
}

export interface AuthorizeInput {
  signedRequest: SignedHttpRequest;
  agentObjectId: string;
  expectedAudience?: string;
  maxAgeMs?: number;
}

export interface AuthorizeDecision {
  ok: boolean;
  reason?: string;
  signer?: string;
}
