#include <jni.h>
#include <XLibArchiveCore.h>
#include <XLibUnRAR.h>
#include <sys/stat.h>
#include <cstring>
#include <string>
#include <memory>

namespace {
constexpr int64_t ENTRY=128LL*1024*1024, TOTAL=4LL*1024*1024*1024;
void fail(JNIEnv* env,const char* message){if(!env->ExceptionCheck())env->ThrowNew(env->FindClass("java/io/IOException"),message?message:"Archive validation failed");}
struct Reader {archive* value=archive_read_new();~Reader(){if(value)archive_read_free(value);}};
struct Unrar {xur_reader* value=nullptr;~Unrar(){if(value)xur_close(value);}};
struct Sink {
    JNIEnv* env; jobject cancellation,output; jmethodID cancelled,write;
    jbyteArray buffer; int64_t actual=0,total=0,expected=0; bool selected=false;
    bool check(){return env->ExceptionCheck()||env->CallBooleanMethod(cancellation,cancelled)||env->ExceptionCheck();}
    bool put(const void* bytes,size_t n){
        if(check()){fail(env,"Archive operation cancelled");return false;}
        actual+=n;total+=n;
        if(actual>expected||actual>ENTRY||total>TOTAL){fail(env,"Archive expanded data exceeds limit");return false;}
        if(selected&&output){env->SetByteArrayRegion(buffer,0,n,static_cast<const jbyte*>(bytes));if(!env->ExceptionCheck())env->CallVoidMethod(output,write,buffer,0,static_cast<jint>(n));}
        return !env->ExceptionCheck();
    }
};
int unrarSink(void* context,const void* bytes,size_t count){return static_cast<Sink*>(context)->put(bytes,count)?0:1;}
}
extern "C" JNIEXPORT void JNICALL
Java_com_xlib_txtreader_NativeComicArchive_visit(JNIEnv* env,jclass,jbyteArray pathBytes,jint wanted,jobject visitor,jobject cancellation,jobject output){
    auto length=env->GetArrayLength(pathBytes);std::string path(length,'\0');env->GetByteArrayRegion(pathBytes,0,length,reinterpret_cast<jbyte*>(path.data()));
    if(env->ExceptionCheck())return;
    struct stat info{};if(path.find('\0')!=std::string::npos||stat(path.c_str(),&info)||!S_ISREG(info.st_mode)||info.st_size<=0||info.st_size>1024LL*1024*1024){fail(env,"Invalid archive source");return;}
    Reader reader;Unrar unrar;
    if(!reader.value){fail(env,"Cannot allocate archive reader");return;}
    archive_read_support_filter_none(reader.value);
    archive_read_support_format_zip_seekable(reader.value);archive_read_support_format_rar(reader.value);archive_read_support_format_rar5(reader.value);
    archive_read_set_format_option(reader.value,"zip","mac-ext",nullptr);
    archive_read_set_format_option(reader.value,"rar","xlib-metadata-only","1");
    if(archive_read_open_filename(reader.value,path.c_str(),65536)!=ARCHIVE_OK){fail(env,archive_error_string(reader.value));return;}
    auto entryMethod=env->GetMethodID(env->GetObjectClass(visitor),"entry","(I[BJZ)V");
    Sink sink{env,cancellation,output,env->GetMethodID(env->GetObjectClass(cancellation),"cancelled","()Z"),output?env->GetMethodID(env->GetObjectClass(output),"write","([BII)V"):nullptr,env->NewByteArray(65536)};
    if(env->ExceptionCheck())return;
    archive_entry* entry=nullptr;int index=0,result;int64_t declared=0,names=0;bool found=false,rar4=false;
    char buffer[65536];
    while((result=archive_read_next_header(reader.value,&entry))==ARCHIVE_OK){
        if(sink.check()){fail(env,"Archive operation cancelled");return;}
        const char* name=archive_entry_pathname_utf8(entry);int type=archive_entry_filetype(entry);int64_t size=archive_entry_size(entry);
        if(++index>20000||!name||std::strlen(name)>8192||(names+=std::strlen(name))>64*1024*1024||!archive_entry_size_is_set(entry)||size<0||size>ENTRY||(declared+=size)>TOTAL||archive_entry_is_encrypted(entry)||archive_entry_symlink(entry)||archive_entry_hardlink(entry)||(type!=AE_IFREG&&type!=AE_IFDIR)){
            fail(env,"Unsafe archive entry or resource limit exceeded");return;
        }
        jbyteArray raw=env->NewByteArray(std::strlen(name));if(!raw)return;
        env->SetByteArrayRegion(raw,0,std::strlen(name),reinterpret_cast<const jbyte*>(name));
        env->CallVoidMethod(visitor,entryMethod,index-1,raw,static_cast<jlong>(size),type==AE_IFDIR);env->DeleteLocalRef(raw);
        if(env->ExceptionCheck())return;
        if(index==1){rar4=archive_format(reader.value)==ARCHIVE_FORMAT_RAR;if(rar4){unrar.value=xur_open(path.c_str());if(!unrar.value){fail(env,"Cannot open RAR decoder");return;}}}
        sink.actual=0;sink.expected=size;sink.selected=wanted==-2||wanted==index-1;
        if(rar4){
            if(xur_next(unrar.value,size,type==AE_IFDIR,0)||xur_process(unrar.value,unrarSink,&sink)){fail(env,xur_error(unrar.value));return;}
        }else{
            la_ssize_t n;while((n=archive_read_data(reader.value,buffer,sizeof(buffer)))>0)if(!sink.put(buffer,n))return;
            if(n<0){fail(env,archive_error_string(reader.value));return;}
        }
        if(sink.check()){fail(env,"Archive operation cancelled");return;}
        if(sink.actual!=size){fail(env,"Archive entry size mismatch");return;}
        if(wanted>=0&&sink.selected){found=true;break;}
    }
    if(!found&&result!=ARCHIVE_EOF){fail(env,archive_error_string(reader.value));return;}
    if(wanted>=0&&!found){fail(env,"Archive page missing");return;}
    if(wanted<0&&rar4&&xur_next(unrar.value,0,0,1)!=1){fail(env,"RAR metadata does not match decoder");return;}
}
