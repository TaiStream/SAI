import { normalizeSuiAddress } from '@mysten/sui/utils';
import { verifySignedRequest } from '../auth';
import type { SaiClient } from '../client';
import { VisibilityTier } from '../types';
import type { AuthorizeDecision, AuthorizeInput, SaiPolicy } from './types';

export class SaiPolicyGuard {
  constructor(
    private readonly saiClient: SaiClient,
    private readonly policy: SaiPolicy = {}
  ) { }

  async authorizeSignedRequest(input: AuthorizeInput): Promise<AuthorizeDecision> {
    const verify = await verifySignedRequest(input.signedRequest, {
      expectedAudience: input.expectedAudience,
      maxAgeMs: input.maxAgeMs,
    });

    if (!verify.ok || !verify.signer) {
      return { ok: false, reason: verify.reason ?? 'Signature verification failed' };
    }

    const agent = await this.saiClient.getAgent(input.agentObjectId);
    const signer = normalizeSuiAddress(verify.signer);
    const owner = normalizeSuiAddress(agent.owner);
    const wallet = normalizeSuiAddress(agent.wallet);

    const signerMode = this.policy.signerMustMatch ?? 'owner-or-wallet';
    if (signerMode === 'owner' && signer !== owner) {
      return { ok: false, reason: 'Signer is not agent owner' };
    }
    if (signerMode === 'wallet' && signer !== wallet) {
      return { ok: false, reason: 'Signer is not agent wallet' };
    }
    if (signerMode === 'owner-or-wallet' && signer !== owner && signer !== wallet) {
      return { ok: false, reason: 'Signer does not match owner or wallet' };
    }
    if (signerMode === 'delegate') {
      const delegates = (agent.delegates ?? []).map((d) => normalizeSuiAddress(d));
      if (!delegates.includes(signer)) {
        return { ok: false, reason: 'Signer is not an agent delegate' };
      }
    }
    if (signerMode === 'any-authorized') {
      const delegates = (agent.delegates ?? []).map((d) => normalizeSuiAddress(d));
      if (signer !== owner && signer !== wallet && !delegates.includes(signer)) {
        return { ok: false, reason: 'Signer is not authorized (not owner, wallet, or delegate)' };
      }
    }

    if (this.policy.requireActive !== false && !agent.isActive) {
      return { ok: false, reason: 'Agent is inactive' };
    }

    if (this.policy.minCredScore !== undefined && agent.credScore < this.policy.minCredScore) {
      return { ok: false, reason: `Agent cred too low (${agent.credScore})` };
    }

    const tier = await this.saiClient.getVisibilityTier(input.agentObjectId);
    const maxTier = this.policy.maxAllowedTier ?? VisibilityTier.Standard;
    if (tier > maxTier) {
      return { ok: false, reason: `Agent tier too low (${tier})` };
    }

    return { ok: true, signer };
  }
}
