const eslint = require('@eslint/js');
const prettier = require('eslint-config-prettier');
const globals = require('globals');

module.exports = [
  {
    ignores: ['node_modules/**', 'SwiftExplorerApp/.build/**', 'coverage/**', '*.vsix'],
  },
  eslint.configs.recommended,
  {
    files: ['extension.js', 'lib/**/*.js', 'test/**/*.js'],
    languageOptions: {
      ecmaVersion: 'latest',
      sourceType: 'commonjs',
      globals: globals.node,
    },
  },
  prettier,
];
