module.exports = {
  root: true,
  env: {
    node: true,
    es2021: true,
    mocha: true,
  },
  extends: ['eslint:recommended', 'prettier'],
  parserOptions: {
    ecmaVersion: 'latest',
  },
  ignorePatterns: ['node_modules/', 'SwiftExplorerApp/.build/', 'coverage/', '*.vsix'],
};
