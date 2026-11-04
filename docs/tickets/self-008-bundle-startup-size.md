# Bundle, startup time and size

Parent: [self-001](self-001-compiler-to-js-epic.md)
Status: open

21 MB JS for runFrontend alone. Ideas: minify, dead-decl pruning by `[export]`/entry reachability, per-module chunks loaded lazily
(ES modules + dynamic import), snapshot of post-initialization state, gzip/brotli serve, WASM not in scope. Measure parse+init time in
Node and Chrome. Related: js-014 item 4 (`--bundle`).
