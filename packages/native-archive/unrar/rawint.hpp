#ifndef _RAR_RAWINT_
#define _RAR_RAWINT_

// XLib: unaligned hardware support does not make typed unaligned C++ access
// well-defined. memcpy preserves the fast path without alignment/aliasing UB.
#include <cstring>

#define  rotls(x,n,xsize)  (((x)<<(n)) | ((x)>>(xsize-(n))))
#define  rotrs(x,n,xsize)  (((x)>>(n)) | ((x)<<(xsize-(n))))
#define  rotl32(x,n)       rotls(x,n,32)
#define  rotr32(x,n)       rotrs(x,n,32)

inline uint RawGet2(const void *Data)
{
  byte *D=(byte *)Data;
  return D[0]+(D[1]<<8);
}


inline uint32 RawGet4(const void *Data)
{
#if defined(BIG_ENDIAN) || !defined(ALLOW_MISALIGNED)
  byte *D=(byte *)Data;
  return uint32(D[0]) | (uint32(D[1])<<8) | (uint32(D[2])<<16) | (uint32(D[3])<<24);
#else
  uint32 Value;
  memcpy(&Value,Data,sizeof(Value));
  return Value;
#endif
}


inline uint64 RawGet8(const void *Data)
{
#if defined(BIG_ENDIAN) || !defined(ALLOW_MISALIGNED)
  byte *D=(byte *)Data;
  return INT32TO64(RawGet4(D+4),RawGet4(D));
#else
  uint64 Value;
  memcpy(&Value,Data,sizeof(Value));
  return Value;
#endif
}


inline void RawPut2(uint Field,void *Data)
{
  byte *D=(byte *)Data;
  D[0]=(byte)(Field);
  D[1]=(byte)(Field>>8);
}


inline void RawPut4(uint Field,void *Data)
{
#if defined(BIG_ENDIAN) || !defined(ALLOW_MISALIGNED)
  byte *D=(byte *)Data;
  D[0]=(byte)(Field);
  D[1]=(byte)(Field>>8);
  D[2]=(byte)(Field>>16);
  D[3]=(byte)(Field>>24);
#else
  uint32 Value=(uint32)Field;
  memcpy(Data,&Value,sizeof(Value));
#endif
}


inline void RawPut8(uint64 Field,void *Data)
{
#if defined(BIG_ENDIAN) || !defined(ALLOW_MISALIGNED)
  byte *D=(byte *)Data;
  D[0]=(byte)(Field);
  D[1]=(byte)(Field>>8);
  D[2]=(byte)(Field>>16);
  D[3]=(byte)(Field>>24);
  D[4]=(byte)(Field>>32);
  D[5]=(byte)(Field>>40);
  D[6]=(byte)(Field>>48);
  D[7]=(byte)(Field>>56);
#else
  memcpy(Data,&Field,sizeof(Field));
#endif
}


#if defined(LITTLE_ENDIAN) && defined(ALLOW_MISALIGNED)
#define USE_MEM_BYTESWAP
#endif

// Load 4 big endian bytes from memory and return uint32.
inline uint32 RawGetBE4(const byte *m)
{
#if defined(USE_MEM_BYTESWAP) && defined(_MSC_VER)
  return _byteswap_ulong(RawGet4(m));
#elif defined(USE_MEM_BYTESWAP) && (defined(__clang__) || defined(__GNUC__))
  return __builtin_bswap32(RawGet4(m));
#else
  return uint32(m[0])<<24 | uint32(m[1])<<16 | uint32(m[2])<<8 | m[3];
#endif
}


// Load 8 big endian bytes from memory and return uint64.
inline uint64 RawGetBE8(const byte *m)
{
#if defined(USE_MEM_BYTESWAP) && defined(_MSC_VER)
  return _byteswap_uint64(RawGet8(m));
#elif defined(USE_MEM_BYTESWAP) && (defined(__clang__) || defined(__GNUC__))
  return __builtin_bswap64(RawGet8(m));
#else
  return uint64(m[0])<<56 | uint64(m[1])<<48 | uint64(m[2])<<40 | uint64(m[3])<<32 |
         uint64(m[4])<<24 | uint64(m[5])<<16 | uint64(m[6])<<8 | m[7];
#endif
}


// Save integer to memory as big endian.
inline void RawPutBE4(uint i,byte *mem)
{
#if defined(USE_MEM_BYTESWAP) && defined(_MSC_VER)
  RawPut4(_byteswap_ulong((uint32)i),mem);
#elif defined(USE_MEM_BYTESWAP) && (defined(__clang__) || defined(__GNUC__))
  RawPut4(__builtin_bswap32((uint32)i),mem);
#else
  mem[0]=byte(i>>24);
  mem[1]=byte(i>>16);
  mem[2]=byte(i>>8);
  mem[3]=byte(i);
#endif
}


// Save integer to memory as big endian.
inline void RawPutBE8(uint64 i,byte *mem)
{
#if defined(USE_MEM_BYTESWAP) && defined(_MSC_VER)
  RawPut8(_byteswap_uint64(i),mem);
#elif defined(USE_MEM_BYTESWAP) && (defined(__clang__) || defined(__GNUC__))
  RawPut8(__builtin_bswap64(i),mem);
#else
  mem[0]=byte(i>>56);
  mem[1]=byte(i>>48);
  mem[2]=byte(i>>40);
  mem[3]=byte(i>>32);
  mem[4]=byte(i>>24);
  mem[5]=byte(i>>16);
  mem[6]=byte(i>>8);
  mem[7]=byte(i);
#endif
}


inline uint32 ByteSwap32(uint32 i)
{
#ifdef _MSC_VER
  return _byteswap_ulong(i);
#elif defined(__clang__) || defined(__GNUC__)
  return  __builtin_bswap32(i);
#else
  return (rotl32(i,24)&0xFF00FF00)|(rotl32(i,8)&0x00FF00FF);
#endif
}




inline bool IsPow2(uint64 n) // Check if 'n' is power of 2.
{
  return (n & (n-1))==0;
}


inline uint64 GetGreaterOrEqualPow2(uint64 n)
{
  uint64 p=1;
  while (p<n)
    p*=2;
  return p;
}


inline uint64 GetLessOrEqualPow2(uint64 n)
{
  uint64 p=1;
  while (p*2<=n)
    p*=2;
  return p;
}
#endif
