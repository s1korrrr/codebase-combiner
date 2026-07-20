const { expect } = require('chai');
const { describe, it } = require('node:test');

const manifest = require('../package.json');

describe('extension manifest', () => {
  it('publishes canonical repository links under the RSI Tech organization', () => {
    expect(manifest.publisher).to.equal('s1korrrr');
    expect(manifest.license).to.equal('Apache-2.0');
    expect(manifest.author).to.deep.equal({
      name: 'RSI Tech',
      email: 'info@rsitech.ai',
      url: 'https://rsitech.ai',
    });
    expect(manifest.repository).to.deep.equal({
      type: 'git',
      url: 'https://github.com/rsitech-ai/codebase-combiner.git',
    });
    expect(manifest.bugs?.url).to.equal('https://github.com/rsitech-ai/codebase-combiner/issues');
    expect(manifest.homepage).to.equal('https://rsitech.ai');
  });

  it('declares local-file-only virtual workspace support', () => {
    expect(manifest.capabilities?.virtualWorkspaces).to.deep.equal({
      supported: false,
      description: 'Combining files requires access to a local file-system workspace.',
    });
  });

  it('ignores workspace-controlled filters in Restricted Mode', () => {
    expect(manifest.capabilities?.untrustedWorkspaces).to.deep.equal({
      supported: 'limited',
      description:
        'Workspace-defined filters are ignored in Restricted Mode so an untrusted repository cannot broaden file collection.',
      restrictedConfigurations: [
        'codebaseCombiner.outputFormat',
        'codebaseCombiner.outputFileName',
        'codebaseCombiner.includeGlobs',
        'codebaseCombiner.excludeGlobs',
        'codebaseCombiner.includeExtensions',
        'codebaseCombiner.excludeExtensions',
        'codebaseCombiner.maxFileSizeKB',
        'codebaseCombiner.useExtensionsFilter',
      ],
    });
  });

  it('bounds every array configuration accepted from settings', () => {
    for (const key of [
      'codebaseCombiner.includeGlobs',
      'codebaseCombiner.excludeGlobs',
      'codebaseCombiner.includeExtensions',
      'codebaseCombiner.excludeExtensions',
    ]) {
      const property = manifest.contributes.configuration.properties[key];
      expect(property.maxItems, key).to.equal(128);
      expect(property.items.maxLength, key).to.equal(1024);
    }
  });
});
