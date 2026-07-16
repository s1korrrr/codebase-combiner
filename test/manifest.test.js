const { expect } = require('chai');
const { describe, it } = require('node:test');

const manifest = require('../package.json');

describe('extension manifest', () => {
  it('declares local-file-only virtual workspace support', () => {
    expect(manifest.capabilities?.virtualWorkspaces).to.deep.equal({
      supported: false,
      description: 'Combining files requires access to a local file-system workspace.',
    });
  });

  it('declares safe support for untrusted workspaces', () => {
    expect(manifest.capabilities?.untrustedWorkspaces).to.deep.equal({
      supported: true,
    });
  });
});
