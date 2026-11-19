# RAR4 solid: official UnRAR integration

The product owner approved official UnRAR on 2026-10-24 after the alternative
library/license comparison. This resolves the dependency decision, not the
whole R014-04 / G1 acceptance gate.

## Pinned dependency and license

- Official source: https://www.rarlab.com/rar/unrarsrc-7.2.7.tar.gz
- Actual version.hpp: **7.23 final**, 2026-06-27, RARVER_BETA=0.
- SHA-256: `01d903a7dcf413cb2925696d7796e48e38d471f79bfe7ef3ad2aebf6c12dbefd`.
- The source filename is not the product semantic version.
- Full upstream license and acknowledgments remain in unrar/license.txt and
  unrar/acknow.txt. The application packages the complete license in
  AppleShared's Resources/UnRAR-LICENSE.txt. The required restriction paragraph
  also appears in the adapter source.
- This is freeware/source-available under the UnRAR-specific license, NOT
  MIT/BSD/OSI open source. No RAR compressor is implemented or distributed.

The earlier temporary 7.30 beta 1 compilation POC is superseded by this stable
pin; its outputs were never application dependencies.

## Read-only design

AppleShared keeps libarchive 3.8.9 for ZIP and RAR5. For RAR4, libarchive parses
strict original names/header CRCs/attributes in a new explicit
`rar:xlib-metadata-only` mode. That mode allows solid metadata but **refuses
libarchive body reads**; default libarchive behavior still rejects RAR4 solid.
This is not deletion of the upstream solid guard followed by broken decoding.

A separate XLibUnRAR C ABI decodes the same physical entries sequentially with
`RAR_TEST` and `UCM_PROCESSDATA`. Header sizes, directory flags and EOF agree
with the independent metadata parser. Bodies and solid predecessors are all
drained for CRC and expanded-byte accounting. Never call RAR_EXTRACT or use an
entry name as a filesystem destination. Original path validation is not replaced
by UnRAR's normalized/display names.

The Swift adapter uses synchronous <=64 KiB output callbacks, checks Task
cancellation and budgets before retaining each chunk, and discards failed output.
The callback/context cannot escape; callbacks must not reenter the decoder.
All UnRAR DLL operations, including close, serialize around its process-global
ErrHandler and reset sticky errors when switching handles. Reader dictionaries
remain per handle. RAR_SMP is disabled to avoid parallel decode workers.

Limits: 1 GiB input / 20,000 entries / 128 MiB per entry / 4 GiB expanded per
full scan; 64 MiB declared dictionary and PPMd model limit before native
allocation. The DLL profile caps WinSize/WinSizeLimit, and model.cpp rejects
PPMd model declarations above 64 MiB before StartSubAllocator. Native PPMd
structures can allocate more than the declared model size on 64-bit systems;
this is NOT a 64 MiB total-process or total-heap guarantee. Image buffers/caches
are separate budgets. Decompression before an output callback is not preemptible.
Reject encryption, split volumes, SFX, links/special files and unsafe names.

Additional local safety patch: `rawint.hpp` uses `memcpy` for unaligned integer
loads/stores and endian-swapping helpers, rather than dereferencing unaligned
`uint32/uint64` pointers. UBSan exposed the original access on a valid RAR4
sample; the patch preserves endian/byte semantics. Seven unaligned offsets
with LE/BE 32/64-bit round trips and the paired-decoder mutation regression
guard this change. No sanitizer diagnostic is suppressed for this patch.

## Reproducible positive corpus

`contracts/fixtures/documents/comic-basic-rar4-solid.cbr` contains the same
24 original PNG pages and README as comic-basic.cbz, genuinely compressed as
one RAR4 solid stream by the separate developer RAR 6.24 trial CLI.
The tool is NOT included in the repository or runtime dependencies.
The fixture generator canonicalizes ASCII path separators and header CRCs only,
leaving compressed bodies, per-file CRCs and cross-file solid dependencies intact.
Two generation runs produced identical bytes:

- 19,059 bytes
- SHA-256 `3d12d67d112b8bdaf98eb1e144011e34e59ccd3ba4143c936897e07424a79adb`
- Same comic-order-v1 page keys and manifest hash as the original CBZ
- Original artwork redistribution permission is included in the archive README

Optional regeneration:
`python3 scripts/generate-rar4-solid-fixture.py --rar-tool /absolute/RAR-6.24/rar`.
Normal builds/tests consume the checked-in asset and never download/run a CLI.

## Validation boundaries

Shared tests cover all 24 pages in reverse order, sequential visits and reopen,
identical expanded bytes versus CBZ, native chunk cancellation, corrupt/truncated
input, independent concurrent solid readers and recovery after a failed decode.
Existing RAR4 Unicode/raw-name, encryption/link/split rejection and RAR5/ZIP
regressions remain enabled. See the 0.14.1 implementation record for actual iOS
and shared test runs.

SwiftPM and CMake expose XLibUnRAR; Android must explicitly consume the same
adapter and metadata-only policy in JNI. No Android application changes are
made here. The public facade now separately passes NDK API23 compile/link for
three ABIs and 16 KiB PT_LOAD alignment of a developer shared probe (see
ANDROID.md). Neither this nor Host/Apple compilation proves final JNI/APK
packaging or runtime acceptance. Full algorithm/filter coverage, malicious
corpus/coverage-guided fuzzing, physical-device memory/performance and joint G1 acceptance remain
separate work; this integration does not claim universal RAR compatibility.
