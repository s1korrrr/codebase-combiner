# E2E Workspace

This disposable fixture verifies Codebase Combiner without touching user source files.

- `Sources/App.swift` is selectable UTF-8 source.
- `Sources/Invalid.bin` contains a NUL byte and must be reported as binary when `.bin` is allowed.
- `.hidden-note.txt` verifies hidden-file filtering.

The audit may change scan preferences, select files, copy combined output, and save exports only inside its temporary E2E data directory.
