#pragma once
// Compatibility include expected by libarchive's Android build. This reader
// limits source files to 1 GiB and never extracts to disk; min23's off_t is
// sufficient on 32-bit ABIs. Do not remap libc calls to API24 large-file symbols.
