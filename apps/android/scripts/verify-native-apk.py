#!/usr/bin/env python3
"""Audit shipping JNI ABIs against NDK API23 exports and Android's 16KiB packaging rules."""
import argparse,json,pathlib,re,subprocess,tempfile,zipfile
parser=argparse.ArgumentParser();parser.add_argument('apk',type=pathlib.Path);parser.add_argument('--sdk',type=pathlib.Path,required=True);parser.add_argument('--report',type=pathlib.Path,required=True);args=parser.parse_args()
ndk=args.sdk/'ndk/27.2.12479018/toolchains/llvm/prebuilt/darwin-x86_64';elf=ndk/'bin/llvm-readelf'
def read(*argv):return subprocess.check_output([str(a) for a in argv],text=True)
report=[]
with tempfile.TemporaryDirectory(prefix='xlib-android-elf-') as directory,zipfile.ZipFile(args.apk) as apk:
 for abi,triple in [('arm64-v8a','aarch64-linux-android'),('armeabi-v7a','arm-linux-androideabi'),('x86_64','x86_64-linux-android')]:
  target=pathlib.Path(directory)/(abi+'.so');target.write_bytes(apk.read('lib/'+abi+'/libxlib_archive.so'))
  headers=read(elf,'-lW',target);dynamic=read(elf,'-dW',target);symbols=read(elf,'--dyn-syms','-W',target)
  alignment=[int(line.split()[-1],16) for line in headers.splitlines() if line.strip().startswith('LOAD')];assert alignment and min(alignment)>=16384,(abi,'LOAD alignment')
  relro=[line.split() for line in headers.splitlines() if line.strip().startswith('GNU_RELRO')];assert all((int(r[2],16)+int(r[5],16))%16384==0 for r in relro),(abi,'RELRO alignment')
  imports={line.split()[-1].split('@')[0] for line in symbols.splitlines() if len(line.split())>=8 and ' UND ' in line and ' WEAK ' not in line}
  weak=sorted({line.split()[-1].split('@')[0] for line in symbols.splitlines() if len(line.split())>=8 and ' UND ' in line and ' WEAK ' in line})
  exports=set();needed=re.findall(r'Shared library: \[(.*?)\]',dynamic)
  for library in needed:
   library_path=ndk/'sysroot/usr/lib'/triple/'23'/library;assert library_path.is_file(),library_path
   exports|={line.split()[-1].split('@')[0] for line in read(elf,'--dyn-syms','-W',library_path).splitlines() if len(line.split())>=8 and ' UND ' not in line}
  missing=sorted(imports-exports);assert not missing,(abi,missing)
  report.append(dict(abi=abi,api=23,loadAlignment=alignment,relroAligned=True,needed=needed,unresolvedStrongSymbols=missing,optionalWeakSymbols=weak))
  # Notices must be present in the actual package.
 for asset in ['UnRAR-LICENSE.txt','UnRAR-ACKNOWLEDGMENTS.txt','libarchive-COPYING.txt']:assert apk.read('assets/'+asset)
result=read(args.sdk/'build-tools/35.0.0/zipalign','-c','-P','16','4',args.apk)
args.report.parent.mkdir(parents=True,exist_ok=True);args.report.write_text(json.dumps(dict(abis=report,zipalign16KiB='passed',notes='API23 symbol/ELF/APK audit; runtime acceptance is recorded separately.'),indent=2)+'\n')
print('Three ABIs: API23 strong imports, 16KiB LOAD/RELRO, APK ZIP alignment and notices passed')
