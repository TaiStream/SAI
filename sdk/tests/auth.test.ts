import assert from 'assert';
import { createSignableRequest, serializeCanonicalRequest, sha256Hex } from '../src/auth';

(function run() {
  const req = createSignableRequest({
    method: 'post',
    url: 'https://api.tai.io/v1/agent/run?b=2&a=1',
    headers: { 'content-type': 'application/json' },
    body: '{"hello":"world"}',
    timestampMs: 1,
    nonce: 'n-1',
  });

  assert.equal(req.method, 'POST');
  assert.equal(req.path, '/v1/agent/run');
  assert.equal(req.query, 'a=1&b=2');
  assert.equal(req.bodySha256, sha256Hex('{"hello":"world"}'));

  const payload = serializeCanonicalRequest(req);
  assert.ok(payload.includes('SAI-HTTP-REQ'));
  assert.ok(payload.includes('n-1'));

  console.log('auth.test.ts passed');
})();
