// Regression for the XLib alignment-safe integer access patch.
#include "rar.hpp"
#include <cstdio>
#include <cstring>
int main() {
  byte bytes[32];
  for (unsigned offset=1;offset<8;offset++) {
    memset(bytes,0,sizeof(bytes));
    byte *p=bytes+offset;
    RawPut4(0x89abcdef,p);
    if (RawGet4(p)!=0x89abcdef || p[0]!=0xef || p[3]!=0x89) return 1;
    RawPut8(UINT64_C(0x0123456789abcdef),p);
    if (RawGet8(p)!=UINT64_C(0x0123456789abcdef) || p[0]!=0xef || p[7]!=0x01) return 1;
    RawPutBE4(0x89abcdef,p);
    if (RawGetBE4(p)!=0x89abcdef || p[0]!=0x89 || p[3]!=0xef) return 1;
    RawPutBE8(UINT64_C(0x0123456789abcdef),p);
    if (RawGetBE8(p)!=UINT64_C(0x0123456789abcdef) || p[0]!=0x01 || p[7]!=0xef) return 1;
  }
  puts("UnRAR integer access: seven unaligned offsets, LE/BE 32/64-bit passed");
  return 0;
}
