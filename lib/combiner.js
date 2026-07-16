const fs = require('fs');
const path = require('path');
const { randomUUID } = require('crypto');
const { TextDecoder } = require('util');
const { Minimatch } = require('minimatch');

function buildMatchers(patterns) {
  const configuredPatterns = patterns || [];
  if (configuredPatterns.length > 128) {
    throw new Error('Glob filters support at most 128 patterns.');
  }
  configuredPatterns.forEach(validateGlobPattern);
  return configuredPatterns.map(
    (pattern) => new Minimatch(pattern, { dot: true, nocase: false, nocomment: false })
  );
}

function validateGlobPattern(pattern) {
  if (typeof pattern !== 'string') {
    throw new TypeError('Glob patterns must be strings.');
  }
  if (pattern.length > 1024) {
    throw new Error('Each glob pattern must contain at most 1,024 characters.');
  }

  let expansionCount = 1;
  let groupStart = -1;
  for (let index = 0; index < pattern.length; index += 1) {
    const character = pattern[index];
    if (character === '\\') {
      index += 1;
      continue;
    }
    if (character === '{') {
      if (groupStart !== -1) {
        throw new Error('Nested brace expansions are not supported.');
      }
      groupStart = index + 1;
      continue;
    }
    if (character !== '}' || groupStart === -1) continue;

    const alternatives = braceAlternativeCount(pattern.slice(groupStart, index));
    if (alternatives > 1) {
      expansionCount *= alternatives;
      if (!Number.isSafeInteger(expansionCount) || expansionCount > 256) {
        throw new Error('Glob brace expansions must produce at most 256 alternatives.');
      }
    }
    groupStart = -1;
  }
}

function braceAlternativeCount(body) {
  const range = body.match(/^(-?\d+|[A-Za-z])\.\.(-?\d+|[A-Za-z])(?:\.\.(-?\d+))?$/);
  if (range) {
    const start = /^-?\d+$/.test(range[1]) ? Number(range[1]) : range[1].codePointAt(0);
    const end = /^-?\d+$/.test(range[2]) ? Number(range[2]) : range[2].codePointAt(0);
    const step = range[3] === undefined ? 1 : Math.abs(Number(range[3]));
    if (!Number.isSafeInteger(start) || !Number.isSafeInteger(end) || !step) {
      throw new Error('Glob brace ranges must use finite, non-zero integer steps.');
    }
    return Math.floor(Math.abs(end - start) / step) + 1;
  }

  let alternatives = 1;
  for (let index = 0; index < body.length; index += 1) {
    if (body[index] === '\\') {
      index += 1;
    } else if (body[index] === ',') {
      alternatives += 1;
    }
  }
  return alternatives;
}

function stripDot(ext) {
  return ext.startsWith('.') ? ext.slice(1) : ext;
}

function safeOutputFileName(configuredName) {
  const candidate = path.basename(String(configuredName || '').trim());
  return candidate && candidate !== '.' && candidate !== path.sep ? candidate : 'combined_code.txt';
}

function normalizeMaxFileSizeKB(value) {
  const numericValue = Number(value);
  if (!Number.isInteger(numericValue) || numericValue < 1 || numericValue > 8192) {
    throw new Error('Maximum file size must be an integer between 1 and 8,192 KB.');
  }
  return numericValue;
}

function deriveAllowedExtensions(patterns) {
  const extensions = new Set();
  for (const pattern of patterns || []) {
    const ext = stripDot(path.posix.extname(String(pattern)).toLowerCase());
    if (!ext || !/^[a-z0-9_+-]+$/.test(ext)) {
      return new Set();
    }
    extensions.add(ext);
  }
  return extensions;
}

function buildExtensionSet(list) {
  return new Set((list || []).map((s) => stripDot(String(s).trim().toLowerCase())).filter(Boolean));
}

function normalizedExtension(relativePath) {
  return stripDot(path.extname(relativePath).toLowerCase());
}

function matchesAny(matchers, relativePath) {
  return matchers.some((m) => m.match(relativePath));
}

function matchesInclude(matchers, relativePath) {
  if (!matchers.length) return true;
  return matchesAny(matchers, relativePath);
}

async function collectFiles(
  rootPath,
  includeMatchers,
  excludeMatchers,
  allowedExtensions,
  excludeExtensions,
  maxFileSizeKB,
  outputAbsolute,
  limits = { maxFiles: 10000, maxBytes: 64 * 1024 * 1024, maxDepth: 128 }
) {
  const effectiveLimits = {
    maxFiles: 10000,
    maxBytes: 64 * 1024 * 1024,
    maxDepth: 128,
    maxVisitedEntries: 50000,
    ...limits,
  };
  const results = [];
  let acceptedBytes = 0;
  let skippedByWorkspaceLimit = 0;
  let visitedEntries = 0;
  const root = path.resolve(rootPath);
  const canonicalRoot = await fs.promises.realpath(root);

  function throwIfAborted() {
    if (!effectiveLimits.signal?.aborted) return;
    const error = new Error('Combination cancelled.');
    error.name = 'AbortError';
    throw error;
  }

  async function walk(currentPath, depth = 0) {
    throwIfAborted();
    if (depth > effectiveLimits.maxDepth) {
      skippedByWorkspaceLimit += 1;
      return;
    }
    const entries = [];
    const directory = await fs.promises.opendir(currentPath);
    for await (const entry of directory) {
      throwIfAborted();
      if (visitedEntries >= effectiveLimits.maxVisitedEntries) {
        const error = new Error(
          `Workspace exceeds the traversal safety limit of ${effectiveLimits.maxVisitedEntries} entries.`
        );
        error.name = 'WorkspaceLimitError';
        throw error;
      }
      visitedEntries += 1;
      entries.push(entry);
    }
    entries.sort((lhs, rhs) => lhs.name.localeCompare(rhs.name, 'en'));

    for (const entry of entries) {
      throwIfAborted();
      const absolutePath = path.join(currentPath, entry.name);
      const relativePath = pathToPosix(path.relative(root, absolutePath)) || entry.name;

      if (absolutePath === outputAbsolute) {
        continue; // never include the output file itself
      }

      if (entry.isDirectory()) {
        if (
          matchesAny(excludeMatchers, relativePath) ||
          matchesAny(excludeMatchers, `${relativePath}/`)
        ) {
          continue;
        }
        await walk(absolutePath, depth + 1);
      } else if (entry.isFile()) {
        if (results.length >= effectiveLimits.maxFiles) {
          skippedByWorkspaceLimit += 1;
          continue;
        }
        if (matchesAny(excludeMatchers, relativePath)) {
          continue;
        }
        if (!matchesInclude(includeMatchers, relativePath)) {
          continue;
        }

        const ext = normalizedExtension(relativePath);

        if (excludeExtensions.size > 0 && ext && excludeExtensions.has(ext)) {
          continue;
        }

        if (allowedExtensions.size > 0) {
          if (!ext || !allowedExtensions.has(ext)) {
            continue;
          }
        }

        await effectiveLimits.beforeFileOpen?.(absolutePath);
        const readResult = await readWorkspaceFile(
          absolutePath,
          canonicalRoot,
          maxFileSizeKB * 1024
        );
        throwIfAborted();
        if (!readResult) {
          continue;
        }
        const { buffer } = readResult;
        if (acceptedBytes > effectiveLimits.maxBytes - buffer.length) {
          skippedByWorkspaceLimit += 1;
          continue;
        }
        if (isBinaryBuffer(buffer)) {
          continue;
        }

        results.push({
          absolutePath,
          relativePath,
          content: buffer.toString('utf8'),
        });
        acceptedBytes += buffer.length;
      }
    }
  }

  await walk(root);
  Object.defineProperty(results, 'skippedByWorkspaceLimit', {
    value: skippedByWorkspaceLimit,
    enumerable: false,
  });
  Object.defineProperty(results, 'visitedEntries', {
    value: visitedEntries,
    enumerable: false,
  });
  return results;
}

async function readWorkspaceFile(absolutePath, canonicalRoot, maximumBytes) {
  let handle;
  try {
    handle = await fs.promises.open(
      absolutePath,
      fs.constants.O_RDONLY | fs.constants.O_CLOEXEC | fs.constants.O_NOFOLLOW
    );
    const openedMetadata = await handle.stat({ bigint: true });
    if (!openedMetadata.isFile() || openedMetadata.size < 0n) return null;
    if (openedMetadata.size > BigInt(maximumBytes)) return null;

    const canonicalPath = await fs.promises.realpath(absolutePath);
    if (!isWithinRoot(canonicalRoot, canonicalPath)) return null;
    const currentMetadata = await fs.promises.stat(canonicalPath, { bigint: true });
    if (
      !currentMetadata.isFile() ||
      currentMetadata.dev !== openedMetadata.dev ||
      currentMetadata.ino !== openedMetadata.ino
    ) {
      return null;
    }

    const chunks = [];
    let totalBytes = 0;
    while (totalBytes <= maximumBytes) {
      const remaining = maximumBytes - totalBytes + 1;
      const chunk = Buffer.allocUnsafe(Math.min(64 * 1024, remaining));
      const { bytesRead } = await handle.read(chunk, 0, chunk.length, totalBytes);
      if (bytesRead === 0) break;
      chunks.push(chunk.subarray(0, bytesRead));
      totalBytes += bytesRead;
    }
    if (totalBytes > maximumBytes) return null;
    return { buffer: Buffer.concat(chunks, totalBytes) };
  } catch {
    return null;
  } finally {
    await handle?.close();
  }
}

function isWithinRoot(root, candidate) {
  const relative = path.relative(root, candidate);
  return (
    relative === '' ||
    (!path.isAbsolute(relative) && relative !== '..' && !relative.startsWith(`..${path.sep}`))
  );
}

function isBinaryBuffer(buffer) {
  if (buffer.includes(0)) {
    return true;
  }

  try {
    const decoder = new TextDecoder('utf-8', { fatal: true });
    decoder.decode(buffer);
    return false;
  } catch {
    return true;
  }
}

function renderBlock(file, outputFormat) {
  if (outputFormat === 'md') {
    const lang = languageFromExtension(path.extname(file.relativePath));
    const heading = escapeMarkdownHeading(file.relativePath);
    const fence = markdownFence(file.content);
    return `## ${heading}\n\n${fence}${lang}\n${file.content}\n${fence}\n\n`;
  }

  return `// File: ${file.relativePath}\n${file.content}\n\n`;
}

function markdownFence(content) {
  const longestRun = Math.max(0, ...(String(content).match(/`+/g) || []).map((run) => run.length));
  return '`'.repeat(Math.max(3, longestRun + 1));
}

function escapeMarkdownHeading(value) {
  return String(value)
    .replace(/[\r\n\u2028\u2029]+/g, ' ')
    .replace(/([\\`*_[\]<>#])/g, '\\$1');
}

async function atomicWriteFile(
  destination,
  content,
  { signal, fsPromises = fs.promises, nonce = randomUUID() } = {}
) {
  const temporaryPath = path.join(
    path.dirname(destination),
    `.${path.basename(destination)}.${process.pid}.${nonce}.tmp`
  );
  try {
    throwIfSignalAborted(signal);
    await fsPromises.writeFile(temporaryPath, content, {
      encoding: 'utf8',
      flag: 'wx',
      signal,
    });
    throwIfSignalAborted(signal);
    await fsPromises.rename(temporaryPath, destination);
  } catch (operationError) {
    try {
      await fsPromises.unlink(temporaryPath);
    } catch (cleanupError) {
      if (cleanupError?.code !== 'ENOENT') {
        operationError.cleanupError = cleanupError;
      }
    }
    throw operationError;
  }
}

function throwIfSignalAborted(signal) {
  if (!signal?.aborted) return;
  const error = new Error('Combination cancelled.');
  error.name = 'AbortError';
  throw error;
}

function languageFromExtension(ext) {
  const map = {
    '.js': 'javascript',
    '.ts': 'typescript',
    '.jsx': 'javascript',
    '.tsx': 'typescriptreact',
    '.json': 'json',
    '.md': 'markdown',
    '.py': 'python',
    '.rb': 'ruby',
    '.rs': 'rust',
    '.go': 'go',
    '.java': 'java',
    '.kt': 'kotlin',
    '.swift': 'swift',
    '.php': 'php',
    '.cs': 'csharp',
    '.c': 'c',
    '.h': 'c',
    '.cpp': 'cpp',
    '.hpp': 'cpp',
    '.m': 'objective-c',
    '.mm': 'objective-cpp',
    '.sh': 'bash',
    '.zsh': 'bash',
    '.bash': 'bash',
    '.ps1': 'powershell',
    '.sql': 'sql',
    '.html': 'html',
    '.css': 'css',
    '.scss': 'scss',
    '.less': 'less',
    '.yml': 'yaml',
    '.yaml': 'yaml',
    '.toml': 'toml',
    '.ini': 'ini',
    '.conf': 'ini',
  };
  return map[ext.toLowerCase()] || '';
}

function pathToPosix(p) {
  return p.split(path.sep).join('/');
}

module.exports = {
  buildMatchers,
  deriveAllowedExtensions,
  buildExtensionSet,
  normalizedExtension,
  matchesAny,
  matchesInclude,
  collectFiles,
  isBinaryBuffer,
  renderBlock,
  languageFromExtension,
  stripDot,
  pathToPosix,
  safeOutputFileName,
  atomicWriteFile,
  normalizeMaxFileSizeKB,
};
