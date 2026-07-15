const vscode = require('vscode');
const fs = require('fs');
const path = require('path');
const {
  buildMatchers,
  deriveAllowedExtensions,
  buildExtensionSet,
  collectFiles,
  renderBlock,
  safeOutputFileName,
  stripDot,
} = require('./lib/combiner');

function activate(context) {
  const combineWorkspace = vscode.commands.registerCommand(
    'codebaseCombiner.combineWorkspace',
    handleCombineWorkspace
  );

  const combineFolder = vscode.commands.registerCommand(
    'codebaseCombiner.combineFolder',
    handleCombineFolder
  );

  context.subscriptions.push(combineWorkspace, combineFolder);
}

function deactivate() {}

async function handleCombineWorkspace() {
  const config = getConfig();
  const folder = await pickWorkspaceFolder();
  if (!folder) {
    return;
  }

  const filters = await promptForFilters(config);
  if (!filters) {
    return;
  }

  const outputPath = await promptForOutputPath(folder.uri.fsPath, config.outputFileName);
  if (!outputPath) {
    return;
  }

  await combineRoot(folder.uri.fsPath, outputPath, { ...config, ...filters });
}

async function handleCombineFolder(uri) {
  const config = getConfig();
  let targetPath;

  try {
    if (uri && uri.fsPath) {
      const stats = await fs.promises.stat(uri.fsPath);
      targetPath = stats.isDirectory() ? uri.fsPath : path.dirname(uri.fsPath);
    } else {
      const folder = await pickWorkspaceFolder();
      if (!folder) {
        return;
      }
      targetPath = folder.uri.fsPath;
    }
  } catch (err) {
    vscode.window.showErrorMessage(`Codebase Combiner: ${err.message}`);
    return;
  }

  const filters = await promptForFilters(config);
  if (!filters) {
    return;
  }

  const outputPath = await promptForOutputPath(targetPath, config.outputFileName);
  if (!outputPath) {
    return;
  }

  await combineRoot(targetPath, outputPath, { ...config, ...filters });
}

async function combineRoot(rootPath, outputAbsolute, config) {
  const includeMatchers = buildMatchers(config.includeGlobs);
  const excludeMatchers = buildMatchers(config.excludeGlobs);
  const includeExtensions = buildExtensionSet(config.includeExtensions);
  const excludeExtensions = buildExtensionSet(config.excludeExtensions);

  const allowedExtensions = includeExtensions.size
    ? includeExtensions
    : config.useExtensionsFilter
      ? deriveAllowedExtensions(config.includeGlobs)
      : new Set();

  try {
    await fs.promises.mkdir(path.dirname(outputAbsolute), { recursive: true });
  } catch (err) {
    vscode.window.showErrorMessage(
      `Codebase Combiner: cannot create output folder: ${err.message}`
    );
    return;
  }

  try {
    await vscode.window.withProgress(
      {
        location: vscode.ProgressLocation.Notification,
        title: 'Codebase Combiner: combining files…',
        cancellable: true,
      },
      async (_progress, cancellationToken) => {
        const controller = new AbortController();
        const cancellation = cancellationToken.onCancellationRequested(() => controller.abort());
        try {
          const files = await collectFiles(
            rootPath,
            includeMatchers,
            excludeMatchers,
            allowedExtensions,
            excludeExtensions,
            config.maxFileSizeKB,
            outputAbsolute,
            {
              maxFiles: 10000,
              maxBytes: 64 * 1024 * 1024,
              maxDepth: 128,
              signal: controller.signal,
            }
          );

          const content = files.map((file) => renderBlock(file, config.outputFormat)).join('');
          await fs.promises.writeFile(outputAbsolute, content, 'utf8');

          const document = await vscode.workspace.openTextDocument(outputAbsolute);
          await vscode.window.showTextDocument(document, { preview: false });

          vscode.window.showInformationMessage(
            `Codebase Combiner: combined ${files.length} file(s) into ${path.basename(outputAbsolute)}${files.skippedByWorkspaceLimit ? `; skipped ${files.skippedByWorkspaceLimit} item(s) at workspace safety limits` : ''}.`
          );
        } finally {
          cancellation.dispose();
        }
      }
    );
  } catch (err) {
    if (err.name === 'AbortError') {
      vscode.window.showInformationMessage('Codebase Combiner: combination cancelled.');
      return;
    }
    vscode.window.showErrorMessage(`Codebase Combiner failed: ${err.message}`);
  }
}

function getConfig() {
  const config = vscode.workspace.getConfiguration('codebaseCombiner');
  return {
    outputFormat: config.get('outputFormat', 'txt'),
    outputFileName: config.get('outputFileName', 'combined_code.txt'),
    includeGlobs: config.get('includeGlobs', ['**/*']),
    excludeGlobs: config.get('excludeGlobs', [
      '**/node_modules/**',
      '**/.git/**',
      '**/.vscode/**',
      '**/dist/**',
      '**/build/**',
    ]),
    includeExtensions: config.get('includeExtensions', []),
    excludeExtensions: config.get('excludeExtensions', [
      'png',
      'jpg',
      'jpeg',
      'gif',
      'mp4',
      'zip',
      'bin',
      'lock',
    ]),
    maxFileSizeKB: config.get('maxFileSizeKB', 512),
    useExtensionsFilter: config.get('useExtensionsFilter', true),
  };
}

async function pickWorkspaceFolder() {
  const folders = vscode.workspace.workspaceFolders;
  if (!folders || folders.length === 0) {
    vscode.window.showInformationMessage('Codebase Combiner: open a workspace or folder first.');
    return null;
  }

  if (folders.length === 1) {
    return folders[0];
  }

  const pick = await vscode.window.showQuickPick(
    folders.map((f) => ({ label: f.name, description: f.uri.fsPath, folder: f })),
    { placeHolder: 'Select workspace folder to combine' }
  );

  return pick ? pick.folder : null;
}

async function promptForOutputPath(rootPath, defaultName) {
  const uri = await vscode.window.showSaveDialog({
    defaultUri: vscode.Uri.file(path.join(rootPath, safeOutputFileName(defaultName))),
    filters: {
      'Text and Markdown': ['txt', 'md'],
      'All Files': ['*'],
    },
    saveLabel: 'Combine',
    title: 'Choose combined output file',
  });
  return uri?.fsPath;
}

async function promptForFilters(config) {
  const choice = await vscode.window.showQuickPick(
    [
      {
        label: 'Use configured filters',
        description: 'Use include/exclude globs from settings',
        value: 'config',
      },
      {
        label: 'Edit filters for this run',
        description: 'Customize include/exclude globs',
        value: 'edit',
      },
    ],
    {
      placeHolder: 'Select filters to use for Codebase Combiner',
    }
  );

  if (!choice) {
    return null; // user cancelled
  }

  if (choice.value === 'config') {
    return {
      includeGlobs: config.includeGlobs,
      excludeGlobs: config.excludeGlobs,
    };
  }

  const includeInput = await vscode.window.showInputBox({
    prompt: 'Include glob patterns (comma or newline separated)',
    value: (config.includeGlobs || ['**/*']).join(', '),
    ignoreFocusOut: true,
  });
  if (includeInput === undefined) {
    return null;
  }

  const excludeInput = await vscode.window.showInputBox({
    prompt: 'Exclude glob patterns (comma or newline separated)',
    value: (config.excludeGlobs || []).join(', '),
    ignoreFocusOut: true,
  });
  if (excludeInput === undefined) {
    return null;
  }

  const includeExtInput = await vscode.window.showInputBox({
    prompt: 'Only include these extensions (comma or space separated, leave empty for any)',
    value: (config.includeExtensions || []).join(', '),
    ignoreFocusOut: true,
  });
  if (includeExtInput === undefined) {
    return null;
  }

  const excludeExtInput = await vscode.window.showInputBox({
    prompt: 'Exclude these extensions (comma or space separated)',
    value: (config.excludeExtensions || []).join(', '),
    ignoreFocusOut: true,
  });
  if (excludeExtInput === undefined) {
    return null;
  }

  const includeGlobs = coercePatterns(splitPatterns(includeInput), config.includeGlobs || ['**/*']);
  const excludeGlobs = coercePatterns(splitPatterns(excludeInput), config.excludeGlobs || []);
  const includeExtensions = coercePatterns(
    splitExtensions(includeExtInput),
    config.includeExtensions || []
  );
  const excludeExtensions = coercePatterns(
    splitExtensions(excludeExtInput),
    config.excludeExtensions || []
  );

  return { includeGlobs, excludeGlobs, includeExtensions, excludeExtensions };
}

function splitPatterns(text) {
  return text
    .split(/[\n,]/)
    .map((s) => s.trim())
    .filter(Boolean);
}

function splitExtensions(text) {
  return text
    .split(/[\s,;|]+/)
    .map((s) => stripDot(s.trim().toLowerCase()))
    .filter(Boolean);
}

function coercePatterns(list, fallback) {
  return list.length ? list : fallback;
}

module.exports = {
  activate,
  deactivate,
};
