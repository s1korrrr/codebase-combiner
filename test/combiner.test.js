const { expect } = require('chai');
const { describe, it } = require('node:test');
const fs = require('fs/promises');
const path = require('path');
const os = require('os');
const { spawnSync } = require('child_process');

const {
  buildMatchers,
  buildExtensionSet,
  deriveAllowedExtensions,
  collectFiles,
  isBinaryBuffer,
  renderBlock,
  safeOutputFileName,
  atomicWriteFile,
  normalizeMaxFileSizeKB,
  parseRunFilterInput,
} = require('../lib/combiner');

describe('combiner helpers', () => {
  it('bounds adversarial glob matching time', () => {
    const script = [
      "const { buildMatchers } = require('./lib/combiner');",
      "const pattern = `${Array.from({ length: 11 }, () => '**/a').join('/')}/b`;",
      "const candidate = Array(30).fill('a').join('/');",
      'try {',
      '  buildMatchers([pattern])[0].match(candidate);',
      '  process.exit(2);',
      '} catch (error) {',
      '  if (!/at most two globstar segments/i.test(error.message)) throw error;',
      '}',
    ].join('\n');

    const result = spawnSync(process.execPath, ['-e', script], {
      cwd: path.join(__dirname, '..'),
      encoding: 'utf8',
      timeout: 1000,
    });

    expect(result.error, result.error?.message).to.equal(undefined);
    expect(result.status, result.stderr).to.equal(0);
  });

  it('rejects patterns with more than two globstar segments', () => {
    expect(() => buildMatchers(['**/Sources/**/Generated/**/*.swift'])).to.throw(
      /at most two globstar segments/i
    );
    expect(() => buildMatchers(['**/{Sources/**,Tests/**}/{Generated/**,Fixtures/**}'])).to.throw(
      /at most two globstar segments/i
    );
    expect(() => buildMatchers(['**/Sources/**/*.swift'])).not.to.throw();
    expect(() => buildMatchers(['[**][**][**].js'])).not.to.throw();
    expect(() => buildMatchers(['foo**bar**baz**.js'])).not.to.throw();
  });

  it('derives allowed extensions from include globs', () => {
    const allowed = deriveAllowedExtensions(['**/*.js', '**/*.swift', '**/*.md']);
    expect(Array.from(allowed).sort()).to.deep.equal(['js', 'md', 'swift']);
  });

  it('fails open when extension derivation sees complex or extensionless globs', () => {
    expect(deriveAllowedExtensions(['**/*.{js,ts}'])).to.deep.equal(new Set());
    expect(deriveAllowedExtensions(['**/*.[jt]s'])).to.deep.equal(new Set());
    expect(deriveAllowedExtensions(['**/*.@(js|ts)'])).to.deep.equal(new Set());
    expect(deriveAllowedExtensions(['**/*.js', 'README'])).to.deep.equal(new Set());
  });

  it('rejects glob inputs that exceed safe compilation bounds', () => {
    expect(() => buildMatchers(Array(129).fill('**/*.js'))).to.throw(/at most 128/i);
    expect(() => buildMatchers(['a'.repeat(1025)])).to.throw(/at most 1,024/i);
    expect(() => buildMatchers(['**/' + '{a,b}'.repeat(9)])).to.throw(/brace expansions/i);
    expect(() => buildMatchers(['**/{1..1000}.js'])).to.throw(/brace expansions/i);
  });

  it('skips excluded extensions, large files, and binaries', async () => {
    const root = await fs.mkdtemp(path.join(os.tmpdir(), 'combiner-'));
    const outputPath = path.join(root, 'combined.txt');

    await fs.writeFile(path.join(root, 'app.js'), 'console.log("ok");');
    await fs.writeFile(path.join(root, 'notes.txt'), 'notes');
    await fs.writeFile(path.join(root, 'readme.md'), '# readme');
    await fs.writeFile(path.join(root, 'binary.bin'), Buffer.from([0x00, 0x01, 0x02]));
    await fs.writeFile(path.join(root, 'large.txt'), 'x'.repeat(2048));
    await fs.writeFile(outputPath, 'should not be included');

    const includeMatchers = buildMatchers(['**/*']);
    const excludeMatchers = buildMatchers(['**/*.md']);
    const allowedExtensions = buildExtensionSet(['js', 'txt']);
    const excludeExtensions = buildExtensionSet(['bin']);

    const files = await collectFiles(
      root,
      includeMatchers,
      excludeMatchers,
      allowedExtensions,
      excludeExtensions,
      1,
      outputPath
    );

    const relativePaths = files.map((file) => file.relativePath).sort();
    expect(relativePaths).to.deep.equal(['app.js', 'notes.txt']);
    expect(files.skipSummary).to.deep.equal({
      binary: 0,
      oversized: 1,
      unreadable: 0,
      symbolicLink: 0,
      workspaceLimit: 0,
    });
  });

  it('reports binary and symlink-race skips without leaking paths', async () => {
    const root = await fs.mkdtemp(path.join(os.tmpdir(), 'combiner-skip-summary-'));
    const outside = path.join(
      await fs.mkdtemp(path.join(os.tmpdir(), 'combiner-skip-outside-')),
      'outside.txt'
    );
    const swapped = path.join(root, 'swapped.txt');
    await fs.writeFile(path.join(root, 'binary.txt'), Buffer.from([0, 1, 2]));
    await fs.writeFile(swapped, 'inside');
    await fs.writeFile(outside, 'outside');
    await fs.symlink(outside, path.join(root, 'linked.txt'));

    const files = await collectFiles(
      root,
      buildMatchers(['**/*']),
      [],
      buildExtensionSet(['txt']),
      new Set(),
      512,
      path.join(root, 'combined.txt'),
      {
        beforeFileOpen: async (candidate) => {
          if (candidate !== swapped) return;
          await fs.unlink(swapped);
          await fs.symlink(outside, swapped);
        },
      }
    );

    expect(files).to.have.length(0);
    expect(files.skipSummary).to.deep.equal({
      binary: 1,
      oversized: 0,
      unreadable: 0,
      symbolicLink: 2,
      workspaceLimit: 0,
    });
    expect(JSON.stringify(files.skipSummary)).not.to.include(root);
    expect(JSON.stringify(files.skipSummary)).not.to.include(outside);
  });

  it('rejects a symbolic-link traversal root', async () => {
    const realRoot = await fs.mkdtemp(path.join(os.tmpdir(), 'combiner-real-root-'));
    const parent = await fs.mkdtemp(path.join(os.tmpdir(), 'combiner-link-root-'));
    const linkedRoot = path.join(parent, 'workspace');
    await fs.writeFile(path.join(realRoot, 'secret.txt'), 'outside workspace');
    await fs.symlink(realRoot, linkedRoot);

    let error;
    try {
      await collectFiles(
        linkedRoot,
        buildMatchers(['**/*']),
        [],
        buildExtensionSet(['txt']),
        new Set(),
        512,
        path.join(parent, 'combined.txt')
      );
    } catch (caught) {
      error = caught;
    }

    expect(error?.name).to.equal('RootSymlinkError');
  });

  it('preserves explicitly submitted empty run filters', () => {
    expect(parseRunFilterInput('', 'glob')).to.deep.equal([]);
    expect(parseRunFilterInput('', 'extension')).to.deep.equal([]);
    expect(parseRunFilterInput('**/*.js, **/*.md', 'glob')).to.deep.equal(['**/*.js', '**/*.md']);
    expect(parseRunFilterInput('.JS, swift', 'extension')).to.deep.equal(['js', 'swift']);
  });

  it('bounds aggregate file count and bytes', async () => {
    const root = await fs.mkdtemp(path.join(os.tmpdir(), 'combiner-limits-'));
    await fs.writeFile(path.join(root, 'a.txt'), '1234');
    await fs.writeFile(path.join(root, 'b.txt'), '5678');

    const result = await collectFiles(
      root,
      buildMatchers(['**/*']),
      [],
      buildExtensionSet(['txt']),
      new Set(),
      512,
      path.join(root, 'combined.txt'),
      { maxFiles: 1, maxBytes: 4, maxDepth: 8 }
    );

    expect(result).to.have.length(1);
    expect(result.skippedByWorkspaceLimit).to.equal(1);
  });

  it('bounds traversal depth', async () => {
    const root = await fs.mkdtemp(path.join(os.tmpdir(), 'combiner-depth-'));
    await fs.mkdir(path.join(root, 'one', 'two'), { recursive: true });
    await fs.writeFile(path.join(root, 'one', 'two', 'deep.txt'), 'deep');

    const result = await collectFiles(
      root,
      buildMatchers(['**/*']),
      [],
      buildExtensionSet(['txt']),
      new Set(),
      512,
      path.join(root, 'combined.txt'),
      { maxFiles: 10, maxBytes: 1024, maxDepth: 1 }
    );

    expect(result).to.deep.equal([]);
    expect(result.skippedByWorkspaceLimit).to.equal(1);
  });

  it('honors cancellation between files in a flat directory', async () => {
    const root = await fs.mkdtemp(path.join(os.tmpdir(), 'combiner-cancel-'));
    await fs.writeFile(path.join(root, 'a.txt'), 'a');
    await fs.writeFile(path.join(root, 'b.txt'), 'b');
    const controller = new AbortController();
    const originalStat = require('fs').promises.stat;
    let statCount = 0;
    require('fs').promises.stat = async (...args) => {
      const value = await originalStat(...args);
      statCount += 1;
      if (statCount === 1) controller.abort();
      return value;
    };

    try {
      let cancellationError;
      try {
        await collectFiles(
          root,
          buildMatchers(['**/*']),
          [],
          buildExtensionSet(['txt']),
          new Set(),
          512,
          path.join(root, 'combined.txt'),
          {
            maxFiles: 10,
            maxBytes: 1024,
            maxDepth: 8,
            maxVisitedEntries: 10,
            signal: controller.signal,
          }
        );
      } catch (error) {
        cancellationError = error;
      }
      expect(cancellationError?.message).to.equal('Combination cancelled.');
      expect(statCount).to.equal(1);
    } finally {
      require('fs').promises.stat = originalStat;
    }
  });

  it('fails closed when filtered traversal exceeds its bound', async () => {
    const root = await fs.mkdtemp(path.join(os.tmpdir(), 'combiner-visits-'));
    await fs.writeFile(path.join(root, 'b.txt'), 'b');
    await fs.writeFile(path.join(root, 'a.txt'), 'a');
    await fs.writeFile(path.join(root, 'c.log'), 'c');

    let traversalError;
    try {
      await collectFiles(
        root,
        buildMatchers(['**/*']),
        [],
        buildExtensionSet(['txt']),
        new Set(),
        512,
        path.join(root, 'combined.txt'),
        { maxFiles: 1, maxBytes: 1024, maxDepth: 8, maxVisitedEntries: 2 }
      );
    } catch (error) {
      traversalError = error;
    }
    expect(traversalError?.name).to.equal('WorkspaceLimitError');
  });

  it('selects the accepted subset deterministically', async () => {
    const root = await fs.mkdtemp(path.join(os.tmpdir(), 'combiner-order-'));
    await fs.writeFile(path.join(root, 'b.txt'), 'b');
    await fs.writeFile(path.join(root, 'a.txt'), 'a');

    const result = await collectFiles(
      root,
      buildMatchers(['**/*']),
      [],
      buildExtensionSet(['txt']),
      new Set(),
      512,
      path.join(root, 'combined.txt'),
      { maxFiles: 1, maxBytes: 1024, maxDepth: 8, maxVisitedEntries: 10 }
    );
    expect(result.map((file) => file.relativePath)).to.deep.equal(['a.txt']);
  });

  it('rejects a file swapped to a symlink after directory enumeration', async () => {
    const root = await fs.mkdtemp(path.join(os.tmpdir(), 'combiner-file-race-'));
    const outside = path.join(
      await fs.mkdtemp(path.join(os.tmpdir(), 'combiner-outside-')),
      'secret.txt'
    );
    const target = path.join(root, 'safe.txt');
    await fs.writeFile(target, 'workspace content');
    await fs.writeFile(outside, 'outside content');

    const result = await collectFiles(
      root,
      buildMatchers(['**/*']),
      [],
      buildExtensionSet(['txt']),
      new Set(),
      512,
      path.join(root, 'combined.txt'),
      {
        beforeFileOpen: async (candidate) => {
          if (candidate !== target) return;
          await fs.unlink(target);
          await fs.symlink(outside, target);
        },
      }
    );

    expect(result).to.deep.equal([]);
  });

  it('rejects a parent directory swapped to an escaping symlink before file open', async () => {
    const root = await fs.mkdtemp(path.join(os.tmpdir(), 'combiner-parent-race-'));
    const inside = path.join(root, 'inside');
    const displaced = path.join(root, 'inside-original');
    const outside = await fs.mkdtemp(path.join(os.tmpdir(), 'combiner-parent-outside-'));
    const target = path.join(inside, 'item.txt');
    await fs.mkdir(inside);
    await fs.writeFile(target, 'workspace content');
    await fs.writeFile(path.join(outside, 'item.txt'), 'outside content');

    const result = await collectFiles(
      root,
      buildMatchers(['**/*']),
      [],
      buildExtensionSet(['txt']),
      new Set(),
      512,
      path.join(root, 'combined.txt'),
      {
        beforeFileOpen: async (candidate) => {
          if (candidate !== target) return;
          await fs.rename(inside, displaced);
          await fs.symlink(outside, inside);
        },
      }
    );

    expect(result).to.deep.equal([]);
  });

  it('detects binary buffers', () => {
    expect(isBinaryBuffer(Buffer.from('plain text'))).to.equal(false);
    expect(isBinaryBuffer(Buffer.from([0x00, 0x61]))).to.equal(true);
  });

  it('accepts valid UTF-8 text regardless of non-ASCII character position', () => {
    const localizedSource = Buffer.from(`${'a'.repeat(100)}Zażółć gęślą jaźń`);
    expect(isBinaryBuffer(localizedSource)).to.equal(false);
  });

  it('rejects malformed UTF-8 even when it contains no NUL bytes', () => {
    expect(isBinaryBuffer(Buffer.from([0xff, 0xfe, 0xfd, 0x61]))).to.equal(true);
  });

  it('does not reject a valid multibyte character split at the sample boundary', () => {
    const prefix = Buffer.from('a'.repeat(8191));
    const suffix = Buffer.from('ż');
    expect(isBinaryBuffer(Buffer.concat([prefix, suffix]))).to.equal(false);
  });

  it('renders markdown blocks with language hints', () => {
    const block = renderBlock({ relativePath: 'src/main.swift', content: 'print("hi")' }, 'md');
    expect(block).to.include('```swift');
    expect(block).to.include('## src/main.swift');
  });

  it('renders markdown safely when content contains fences or paths contain newlines', () => {
    const block = renderBlock(
      {
        relativePath: 'docs/unsafe\n# heading.md',
        content: 'before\n```js\ninside\n````\nafter',
      },
      'md'
    );
    expect(block).to.include('`````markdown');
    expect(block).to.include('\n`````\n');
    expect(block).not.to.include('unsafe\n# heading');
  });

  it('renders plain-text headers safely when paths contain line separators', () => {
    const block = renderBlock(
      { relativePath: 'unsafe\r\n// File: forged.txt\u2028tail.txt', content: 'safe' },
      'txt'
    );
    expect(block).to.equal('// File: unsafe // File: forged.txt tail.txt\nsafe\n\n');
  });

  it('preserves an existing destination when an atomic write is aborted', async () => {
    const root = await fs.mkdtemp(path.join(os.tmpdir(), 'combiner-atomic-'));
    const destination = path.join(root, 'combined.txt');
    await fs.writeFile(destination, 'original');
    const controller = new AbortController();
    const realWriteFile = fs.writeFile;

    let writeCount = 0;
    const fsPromises = {
      writeFile: async (...args) => {
        await realWriteFile(...args);
        writeCount += 1;
        controller.abort();
      },
      rename: fs.rename,
      unlink: fs.unlink,
    };

    let error;
    try {
      await atomicWriteFile(destination, 'replacement', {
        signal: controller.signal,
        fsPromises,
        nonce: 'abort-test',
      });
    } catch (caught) {
      error = caught;
    }

    expect(writeCount).to.equal(1);
    expect(error?.name).to.equal('AbortError');
    expect(await fs.readFile(destination, 'utf8')).to.equal('original');
    expect((await fs.readdir(root)).sort()).to.deep.equal(['combined.txt']);
  });

  it('constrains configured output names to a file in the chosen root', () => {
    expect(safeOutputFileName('combined_code.txt')).to.equal('combined_code.txt');
    expect(safeOutputFileName('../../outside.txt')).to.equal('outside.txt');
    expect(safeOutputFileName('/tmp/outside.txt')).to.equal('outside.txt');
    expect(safeOutputFileName('')).to.equal('combined_code.txt');
    expect(safeOutputFileName('.')).to.equal('combined_code.txt');
  });

  it('validates the configured per-file size boundary', () => {
    expect(normalizeMaxFileSizeKB(512)).to.equal(512);
    expect(() => normalizeMaxFileSizeKB(0)).to.throw(/between 1 and 8,192/i);
    expect(() => normalizeMaxFileSizeKB(Number.NaN)).to.throw(/between 1 and 8,192/i);
    expect(() => normalizeMaxFileSizeKB(8193)).to.throw(/between 1 and 8,192/i);
  });
});
