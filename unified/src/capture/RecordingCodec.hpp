// GPL-2.0-or-later. App recording choices; independent of USB/camera format.
#pragma once
#include <CoreMedia/CoreMedia.h>
#include <CoreVideo/CoreVideo.h>
#include <cstring>
namespace shuttle_recording {
enum class Codec { ProRes422, ProResLT, ProResHQ, ProResProxy, Uncompressed, H264, HEVC };
struct CodecInfo { const char *key,*title;CMVideoCodecType type;bool interlaced; };
static const CodecInfo Codecs[]={
 {"prores422","ProRes 422",kCMVideoCodecType_AppleProRes422,true},
 {"prores-lt","ProRes 422 LT",kCMVideoCodecType_AppleProRes422LT,true},
 {"prores-hq","ProRes 422 HQ",kCMVideoCodecType_AppleProRes422HQ,true},
 {"prores-proxy","ProRes 422 Proxy",kCMVideoCodecType_AppleProRes422Proxy,true},
 {"uncompressed","Uncompressed 4:2:2",kCVPixelFormatType_422YpCbCr8,true},
 {"h264","H.264 (progressive)",kCMVideoCodecType_H264,false},
 {"hevc","HEVC (progressive)",kCMVideoCodecType_HEVC,false}
};
constexpr unsigned CodecCount=sizeof(Codecs)/sizeof(Codecs[0]);
inline const CodecInfo& info(Codec codec){unsigned i=unsigned(codec);return Codecs[i<CodecCount?i:0];}
inline bool parse(const char *key,Codec &codec){for(unsigned i=0;i<CodecCount;i++)if(key&&!strcmp(Codecs[i].key,key)){codec=Codec(i);return true;}return false;}
inline bool prores(Codec codec){return unsigned(codec)<=unsigned(Codec::ProResProxy);}
inline bool compatible(Codec codec,bool fields){return !fields||info(codec).interlaced;}
}
