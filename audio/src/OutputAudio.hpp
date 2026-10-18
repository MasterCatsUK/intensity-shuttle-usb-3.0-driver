// GPL-2.0-or-later. Timestamped stereo audio between Core Audio output and USB sender.
#pragma once
#include <cstdint>
#include <cstring>
#include <cmath>
#include <vector>
#include <stdexcept>
#include <cstdio>
#include <sys/socket.h>
#include <netinet/in.h>
#include <fcntl.h>
#include <unistd.h>
namespace shuttle_output_audio {
constexpr uint16_t Port=49382;constexpr uint32_t Magic=0x32414f53,MaxFrames=480;
constexpr uint32_t OutputLatencyFrames=12288;
constexpr uint64_t OutputLatencyNS=uint64_t(OutputLatencyFrames)*1000000000/48000;
struct Packet {uint32_t magic=Magic,version=1,frames=0,rate=48000;uint64_t firstSample=0;float samples[MaxFrames*2];};
constexpr size_t HeaderBytes=24;
static_assert(sizeof(Packet)==3864,"Audio layout changed");
inline bool valid(const Packet& p,size_t size){if(size<HeaderBytes||p.magic!=Magic||p.version!=1||!p.frames||p.frames>MaxFrames||p.rate!=48000||size!=HeaderBytes+p.frames*8||p.firstSample>UINT64_MAX-MaxFrames)return false;for(unsigned n=0;n<p.frames*2;++n)if(!std::isfinite(p.samples[n])||p.samples[n]<-1||p.samples[n]>1)return false;return true;}
inline uint64_t sampleAt(uint64_t ns){return uint64_t((static_cast<unsigned __int128>(ns)*48000+500000000)/1000000000);}
class Reader {
    static constexpr size_t Capacity=262144;
    struct Sample {uint64_t tag=UINT64_MAX;float left=0,right=0;};
    std::vector<Sample> ring;int fd=-1;uint64_t received=0,matched=0,requested=0;
public:
    Reader():ring(Capacity){fd=socket(AF_INET,SOCK_DGRAM,0);if(fd<0)throw std::runtime_error("Cannot create HDMI audio receiver");fcntl(fd,F_SETFL,fcntl(fd,F_GETFL)|O_NONBLOCK);int buffer=1024*1024;setsockopt(fd,SOL_SOCKET,SO_RCVBUF,&buffer,sizeof(buffer));sockaddr_in a{};a.sin_len=sizeof(a);a.sin_family=AF_INET;a.sin_port=htons(Port);a.sin_addr.s_addr=htonl(INADDR_LOOPBACK);if(bind(fd,(sockaddr*)&a,sizeof(a))){close(fd);fd=-1;throw std::runtime_error("HDMI audio receiver is already in use");}}
    ~Reader(){if(fd>=0)close(fd);fprintf(stderr,"HDMI audio: %llu samples received; %llu/%llu requested samples matched timestamps\n",(unsigned long long)received,(unsigned long long)matched,(unsigned long long)requested);}
    uint64_t receivedFrames() const{return received;}
    void pump(){for(unsigned count=0;count<128;++count){Packet p;ssize_t n=recv(fd,&p,sizeof(p),0);if(n<0)break;if(!valid(p,size_t(n)))continue;for(unsigned k=0;k<p.frames;++k){auto& s=ring[(p.firstSample+k)%Capacity];s.tag=p.firstSample+k;s.left=p.samples[k*2];s.right=p.samples[k*2+1];}received+=p.frames;}}
    void read(uint64_t first,unsigned count,std::vector<int32_t>& pcm){pump();pcm.assign(size_t(count)*8,0);requested+=count;for(unsigned k=0;k<count;++k){auto& s=ring[(first+k)%Capacity];if(s.tag!=first+k)continue;++matched;pcm[k*8]=int32_t(std::lrint(double(s.left)*8388607));pcm[k*8+1]=int32_t(std::lrint(double(s.right)*8388607));}}
};
}
