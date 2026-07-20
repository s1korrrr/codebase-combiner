# Third-Party Notices

Codebase Combiner itself is licensed under the Apache License 2.0. The native macOS app declares no third-party Swift package dependencies.

The packaged VS Code extension includes these runtime dependencies:

| Dependency      | Version | License |
| --------------- | ------: | ------- |
| minimatch       |   9.0.9 | ISC     |
| brace-expansion |   2.1.2 | MIT     |
| balanced-match  |   1.0.2 | MIT     |

The corresponding license texts are distributed in each package's directory under `node_modules` and are included in the VSIX. Development-only dependencies are governed by their own licenses in `package-lock.json` and are not runtime components of the native macOS app.

Release maintainers must re-check this inventory against `package-lock.json` whenever runtime dependencies change.
