/* UnRAR source code may be used in any software to handle
   RAR archives without limitations free of charge, but cannot be
   used to develop RAR (WinRAR) compatible archiver and to
   re-create RAR compression algorithm, which is proprietary.
   Distribution of modified UnRAR source code in separate form
   or as a part of other software is permitted, provided that
   full text of this paragraph, starting from "UnRAR source code"
   words, is included in license, or in documentation if license
   is not available, and in source code comments of resulting package.

   XLib: read-only, memory-output adapter; no RAR_EXTRACT operation. */
#include "rar.hpp"
#include "XLibUnRAR.h"
#include <mutex>
#include <new>

// Upstream's ErrHandler is process-global. Serialize ALL DLL entry points,
// including close, and reset sticky error state before switching handles.
static std::mutex engine_mutex;
struct xur_reader {
  HANDLE handle = nullptr;
  const char *error = nullptr;
  xur_sink sink = nullptr;
  void *context = nullptr;
  uint64_t expected = 0, produced = 0, expanded = 0, declared = 0;
  unsigned entries = 0;
  bool pending = false;
};
static void reset_error() { ErrHandler.Clean(); ErrHandler.SetSilent(true); }
static int CALLBACK callback(UINT message, LPARAM data, LPARAM p1, LPARAM p2) {
  xur_reader *r = reinterpret_cast<xur_reader *>(data);
  if (message != UCM_PROCESSDATA) {
    r->error = "UnRAR: encrypted, split or oversized dictionary is unsupported";
    return -1;
  }
  if (!r->sink || p2 < 0 || uint64_t(p2) > r->expected - r->produced ||
      uint64_t(p2) > (uint64_t(4) << 30) - r->expanded) {
    r->error = "UnRAR: expanded data exceeds declared size or budget";
    return -1;
  }
  const unsigned char *bytes = reinterpret_cast<const unsigned char *>(p1);
  size_t remaining = size_t(p2);
  while (remaining) {
    size_t chunk = remaining > 65536 ? 65536 : remaining;
    if (r->sink(r->context, bytes, chunk)) {
      r->error = "UnRAR: decoding cancelled";
      return -1;
    }
    bytes += chunk; remaining -= chunk;
    r->produced += chunk; r->expanded += chunk;
  }
  return 1;
}
extern "C" xur_reader *xur_open(const char *path) {
  xur_reader *r = new(std::nothrow) xur_reader;
  if (!r) return nullptr;
  try {
    std::lock_guard<std::mutex> lock(engine_mutex);
    reset_error();
    std::wstring wide;
    UtfToWide(path, wide);
    RAROpenArchiveDataEx options{};
    options.ArcNameW = const_cast<wchar_t *>(wide.c_str());
    options.OpenMode = RAR_OM_EXTRACT; // TEST below, never filesystem extract.
    options.Callback = callback;
    options.UserData = reinterpret_cast<LPARAM>(r);
    r->handle = RAROpenArchiveEx(&options);
    if (!r->handle || options.OpenResult)
      r->error = "UnRAR: cannot open archive";
    if (options.Flags & (ROADF_VOLUME | ROADF_ENCHEADERS))
      r->error = "UnRAR: encrypted or split archive is unsupported";
  } catch (...) { r->error = "UnRAR: decoder initialization failed"; }
  return r;
}
extern "C" int xur_next(xur_reader *r, int64_t size, int directory, int eof) {
  if (!r || r->error || !r->handle || r->pending) return -1;
  try {
    std::lock_guard<std::mutex> lock(engine_mutex);
    reset_error();
    RARHeaderDataEx header{};
    int result = RARReadHeaderEx(r->handle, &header);
    if (eof && result == ERAR_END_ARCHIVE) return 1;
    uint64_t unpacked = (uint64_t(header.UnpSizeHigh) << 32) | header.UnpSize;
    if (result || eof || size < 0 || unpacked != uint64_t(size) ||
        !!(header.Flags & RHDF_DIRECTORY) != !!directory ||
        (header.Flags & (RHDF_SPLITBEFORE | RHDF_SPLITAFTER | RHDF_ENCRYPTED)) ||
        header.RedirType || header.DictSize > 65536 ||
        unpacked > (uint64_t(128) << 20) || ++r->entries > 20000 ||
        unpacked > (uint64_t(4) << 30) - r->declared) {
      r->error = "UnRAR: invalid header, unsupported entry or resource limit";
      return -1;
    }
    r->expected = unpacked; r->produced = 0; r->declared += unpacked;
    r->pending = true;
    return 0;
  } catch (...) { r->error = "UnRAR: header decoding failed"; return -1; }
}
extern "C" int xur_process(xur_reader *r, xur_sink sink, void *context) {
  if (!r || r->error || !r->pending || !sink) return -1;
  try {
    std::lock_guard<std::mutex> lock(engine_mutex);
    reset_error();
    r->sink = sink; r->context = context;
    int result = RARProcessFile(r->handle, RAR_TEST, nullptr, nullptr);
    r->sink = nullptr; r->context = nullptr; r->pending = false;
    if (result || r->produced != r->expected) {
      if (!r->error) r->error = "UnRAR: corrupt data, CRC failure or unsupported method";
      return -1;
    }
    return 0;
  } catch (...) {
    r->sink = nullptr; r->context = nullptr;
    r->error = "UnRAR: decompression failed"; return -1;
  }
}
extern "C" const char *xur_error(xur_reader *r) {
  return r && r->error ? r->error : "UnRAR: validation failed";
}
extern "C" void xur_close(xur_reader *r) {
  if (!r) return;
  try {
    std::lock_guard<std::mutex> lock(engine_mutex);
    reset_error();
    if (r->handle) RARCloseArchive(r->handle);
  } catch (...) { }
  delete r;
}
