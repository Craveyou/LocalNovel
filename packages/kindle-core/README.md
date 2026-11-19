# XLib Kindle core (development)

This is an offline, UI-independent synchronous JavaScript core. `entities.js`,
`vendor/mobi.decoder.js`, and `core.js` are the same sources for Node reference
tests, Apple JavaScriptCore, and the Android host. Android integration and its
evidence are owned by the Android task (`apps/android/docs/0.14.1-kindle-delivery.md`).

The narrow host contract is `XLibKindle.parse({size, read(offset, count)}, cancelled)`.
`read` returns exactly `count` bytes in a Uint8Array and never performs network I/O.
Each invocation owns its engine; do not share one mutable VM across simultaneous
books. `cancelled` must remain callable during parsing. Source records are read
on demand; selected decompressed text has a 32 MiB hard limit, individual reads
16 MiB, HTML depth 128/nodes 200000, navigation/targets/units 10000,
KF8 cumulative reconstruction copies 128 MiB, and a per-parse operation budget. These are
enforced safety limits, not measured device-performance claims.

## Dependency and redistribution

Decoder derived from [foliate-js mobi.js](https://github.com/johnfactotum/foliate-js/blob/78914aef4466eb960965702401634c2cb348e9b1/mobi.js),
fixed commit `78914aef4466eb960965702401634c2cb348e9b1`.
Upstream original SHA-256: `016526df13a9f11ee6671a8c74346e1cf41fe6bdfe50165fdcbf744f015694f3`.
MIT copyright/permission is preserved in `vendor/LICENSE` and distributed in
AppleShared/application resource bundles. No libmobi/LGPL dependency is linked.
No browser, external executable, server conversion, DRM implementation or
third-party viewer UI is imported.

Local adaptations: synchronous host-sliced reads, non-DOM publication output,
no mixed-book fallback, header/record/index/variable-integer checks, bounded
PalmDOC/HUFF/CDIC recursion and expansion, operation/cancellation hooks.
The malformed-file regression initially exposed unbounded index iteration;
the integer/index bounds now reject it. A bounded mutation test is not full fuzzing.

## Output and profile status

Preparation output includes selected mode, sanitized chapter HTML, canonical
text, chapter starts, valid anchors/TOC, source-to-canonical spans and offline
image byte ranges and `coverResource` (declared embedded cover, otherwise first
usable embedded image, or null). Cover extraction does not change canonical text.
Source HTML in the mapping is the selected reconstructed
publication HTML, not a screen page or a converted EPUB byte stream.

The `kindle-text-v1` reference algorithm is documented in
`docs/architecture/kindle-text-v1.md`. Node/JavaScriptCore canonical vectors,
real iOS WebKit text/image/selection tests, typed persistence, API validation and
PostgreSQL migration tests have passed. iOS uses these reference coordinates;
Android has verified the six shared publications' canonical output and rendering
flows. A five-stage actual Android/iOS HTTPS/PostgreSQL continuation passed;
see `docs/product/plans/0.14.1-kindle-cross-client-validation.md`.
Do not call this a released profile or full device/whole-version acceptance. Current fixture publications are complete
readable synthetic MOBI6, PalmDOC, HUFF/CDIC, KF8 and mixed files, not just headers;
they contain original CC0 XLib text and a tiny original test image. They are
regression samples, not evidence of every publisher variant or device budgets.

```sh
node --max-old-space-size=256 --test packages/kindle-core/test/core.test.mjs
node packages/kindle-core/build.mjs
node packages/kindle-core/build.mjs --check
node scripts/generate-kindle-fixtures.mjs
make test-apple-shared
```

The generated Apple resource bundle is checked byte-for-byte against these
sources. Functionality, safety and simulator tests run now; connected-device
performance and stress remain deferred by Decision 0020.
