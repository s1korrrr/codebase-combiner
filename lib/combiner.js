const fs = require('fs');
const path = require('path');
const { Minimatch } = require('minimatch');

function buildMatchers(patterns) {
  return (patterns || []).map(
    (pattern) => new Minimatch(pattern, { dot: true, nocase: false, nocomment: false })
  );
}

function stripDot(ext) {
  return ext.startsWith('.') ? ext.slice(1) : ext;
}

function deriveAllowedExtensions(patterns) {
  const extensions = new Set();
  (patterns || []).forEach((pattern) => {
    const normalized = pattern.replace('**/', '');
    const ext = path.extname(normalized);
    if (ext) {
      extensions.add(stripDot(ext.toLowerCase()));
    }
  });
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
  outputAbsolute
) {
  const results = [];
  const root = path.resolve(rootPath);

  async function walk(currentPath) {
    const entries = await fs.promises.readdir(currentPath, { withFileTypes: true });

    for (const entry of entries) {
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
        await walk(absolutePath);
      } else if (entry.isFile()) {
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

        const stats = await fs.promises.stat(absolutePath);
        if (stats.size > maxFileSizeKB * 1024) {
          continue;
        }

        const buffer = await fs.promises.readFile(absolutePath);
        if (isBinaryBuffer(buffer)) {
          continue;
        }

        results.push({
          absolutePath,
          relativePath,
          content: buffer.toString('utf8'),
        });
      }
    }
  }

  await walk(root);
  return results;
}

function isBinaryBuffer(buffer) {
  const len = Math.min(buffer.length, 1024);
  for (let i = 0; i < len; i += 1) {
    const byte = buffer[i];
    if (byte === 0) {
      return true;
    }
    if (byte > 0x7f) {
      // allow a small amount of non-ASCII
      if (i > 80) {
        return true;
      }
    }
  }
  return false;
}

function renderBlock(file, outputFormat) {
  if (outputFormat === 'md') {
    const lang = languageFromExtension(path.extname(file.relativePath));
    return `## ${file.relativePath}\n\n\`\`\`${lang}\n${file.content}\n\`\`\`\n\n`;
  }

  return `// File: ${file.relativePath}\n${file.content}\n\n`;
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
};
