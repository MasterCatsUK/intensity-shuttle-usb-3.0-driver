// GPL-2.0-or-later. Bounded loopback transport from CMIO's service account to USB host.
#pragma once
#include <atomic>
#include <cstdint>
#include <cstring>
#include <stdexcept>
#include <vector>
#include <memory>
#include <deque>
#include <array>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <fcntl.h>
#include <unistd.h>
#include <cerrno>
#include <chrono>
#include <cstdio>
#include "Timecode.hpp"
namespace shuttle_sink {
constexpr size_t MaxBytes=1920*1080*2,Count=8;
constexpr uint64_t Magic=0x53484f5554303033ULL;
constexpr uint16_t Port=47539,PremierePort=47540;
// CMIO clients can stop and immediately restart a stream during preroll.
// Resetting that client's TCP session rejects stale USB acknowledgements, but
// must not make the still-running physical device appear to be unplugged.
class PublicationGuard {
public:
    using Clock=std::chrono::steady_clock;
    static constexpr unsigned ReconnectMilliseconds=1000;
private:
    Clock::time_point expectedReconnectUntil{};
public:
    void normalStreamStopped(bool matchingSenderReady,Clock::time_point now=Clock::now()){
        expectedReconnectUntil=matchingSenderReady?now+std::chrono::milliseconds(ReconnectMilliseconds):Clock::time_point{};
    }
    void clear(){expectedReconnectUntil={};}
    bool keepPublished(bool senderReady,unsigned senderMode,unsigned publishedMode,Clock::time_point now=Clock::now()){
        if(senderReady){clear();return senderMode==publishedMode;}
        return expectedReconnectUntil!=Clock::time_point{}&&now<expectedReconnectUntil;
    }
};
struct Frame {uint64_t sequence=0,hostNS=0;uint32_t width=0,height=0;Timecode timecode;uint8_t image[MaxBytes];};
struct Ring {
    std::atomic<uint64_t> written{0},read{0},ackCount{0},ackSequence{0},ackNS{0};
    std::atomic<uint32_t> producer{0},consumer{0},mode{2};
    Frame slots[Count];
};
struct Header {uint64_t magic,sequence,hostNS;uint32_t mode,width,height,bytes;Timecode timecode;};
struct Ack {uint64_t magic,sequence,hostNS;};
inline void nonblock(int fd){fcntl(fd,F_SETFL,fcntl(fd,F_GETFL)|O_NONBLOCK);int yes=1,buffer=1024*1024;setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&yes,sizeof(yes));setsockopt(fd,IPPROTO_TCP,TCP_NODELAY,&yes,sizeof(yes));setsockopt(fd,SOL_SOCKET,SO_SNDBUF,&buffer,sizeof(buffer));setsockopt(fd,SOL_SOCKET,SO_RCVBUF,&buffer,sizeof(buffer));}
inline sockaddr_in endpoint(uint16_t port=Port){sockaddr_in a{};a.sin_len=sizeof(a);a.sin_family=AF_INET;a.sin_addr.s_addr=htonl(INADDR_LOOPBACK);a.sin_port=htons(port);return a;}
class Mapping {
    uint16_t port=Port;std::unique_ptr<Ring> ring;int fd=-1;bool connecting=false;std::vector<uint8_t> pending;size_t sent=0,ackRead=0;Ack ack{};
    std::deque<Ack> completions;
    std::chrono::steady_clock::time_point next{};
    void disconnect(){if(fd>=0)close(fd);fd=-1;connecting=false;pending.clear();completions.clear();sent=ackRead=0;ring->consumer=0;ring->read=ring->written.load();next=std::chrono::steady_clock::now()+std::chrono::seconds(1);}
public:
    explicit Mapping(uint16_t selectedPort=Port):port(selectedPort){}
    ~Mapping(){if(fd>=0)close(fd);}
    void open(bool){ring.reset(new Ring{});}
    void reset(){disconnect();ring.reset(new Ring{});next={};}
    Ring& data(){return *ring;}
    bool popCompletion(Ack& event){if(completions.empty())return false;event=completions.front();completions.pop_front();return true;}
    // The provider may discover the USB sender's mode before publishing a
    // stream. Active streams keep the strict matching check.
    void pump(bool discoverMode=false){
        if(fd<0){if(std::chrono::steady_clock::now()<next)return;fd=socket(AF_INET,SOCK_STREAM,0);if(fd<0)return;nonblock(fd);auto a=endpoint(port);int rc=connect(fd,(sockaddr*)&a,sizeof(a));if(rc&&errno!=EINPROGRESS){disconnect();return;}connecting=rc!=0;}
        if(connecting){fd_set w;FD_ZERO(&w);FD_SET(fd,&w);timeval t{};if(select(fd+1,nullptr,&w,nullptr,&t)<=0)return;int error=0;socklen_t n=sizeof(error);if(getsockopt(fd,SOL_SOCKET,SO_ERROR,&error,&n)||error){disconnect();return;}connecting=false;}
        for(;;){ssize_t n=recv(fd,reinterpret_cast<char*>(&ack)+ackRead,sizeof(ack)-ackRead,0);if(n>0){ackRead+=size_t(n);if(ackRead==sizeof(ack)){if(ack.magic!=Magic){disconnect();return;}if(ack.sequence==UINT64_MAX){if(ack.hostNS>=6||(!discoverMode&&ack.hostNS!=ring->mode.load())){disconnect();return;}if(discoverMode)ring->mode=uint32_t(ack.hostNS);ring->consumer=1;}else{if(completions.size()>=Count*8){disconnect();return;}completions.push_back(ack);ring->ackSequence=ack.sequence;ring->ackNS=ack.hostNS;ring->ackCount.fetch_add(1);}ackRead=0;}}else {if(n==0||(errno!=EAGAIN&&errno!=EWOULDBLOCK&&errno!=EINTR))disconnect();break;}}
        if(fd<0||!ring->consumer.load())return;
        if(pending.empty()){uint64_t r=ring->read.load();if(r==ring->written.load())return;auto& f=ring->slots[r%Count];Header h{Magic,f.sequence,f.hostNS,ring->mode.load(),f.width,f.height,f.width*f.height*2,f.timecode};pending.resize(sizeof(h)+h.bytes);memcpy(pending.data(),&h,sizeof(h));memcpy(pending.data()+sizeof(h),f.image,h.bytes);sent=0;ring->read.store(r+1);}
        while(sent<pending.size()){ssize_t n=send(fd,pending.data()+sent,pending.size()-sent,0);if(n>0)sent+=size_t(n);else {if(n==0||(errno!=EAGAIN&&errno!=EWOULDBLOCK&&errno!=EINTR))disconnect();return;}}
        pending.clear();
    }
};
class Reader {
    int server=-1,fd=-1;unsigned mode;bool outputReady;Header header{};size_t headerRead=0,imageRead=0;std::vector<uint8_t> incoming,last,acks;size_t ackSent=0;
    struct Received {uint64_t sequence,hostNS;std::vector<uint8_t> image;Timecode timecode;};std::deque<Received> ready;
    uint64_t receivedCount=0,playedCount=0;
    void disconnect(){if(fd>=0){close(fd);++generation;}fd=-1;headerRead=imageRead=ackSent=0;incoming.clear();acks.clear();ready.clear();}
    void flush(){while(fd>=0&&ackSent<acks.size()){ssize_t n=send(fd,acks.data()+ackSent,acks.size()-ackSent,0);if(n>0)ackSent+=size_t(n);else {if(n==0||(errno!=EAGAIN&&errno!=EWOULDBLOCK&&errno!=EINTR))disconnect();return;}}if(ackSent==acks.size()){acks.clear();ackSent=0;}}
public:
    uint64_t sequence=0,hostNS=0,generation=0;bool acknowledge=false;
    Timecode timecode;
    Reader(unsigned selected,bool initiallyReady=true,uint16_t port=Port):mode(selected),outputReady(initiallyReady){server=socket(AF_INET,SOCK_STREAM,0);if(server<0)throw std::runtime_error("Cannot create output transport");nonblock(server);int yes=1;setsockopt(server,SOL_SOCKET,SO_REUSEADDR,&yes,sizeof(yes));auto a=endpoint(port);if(bind(server,(sockaddr*)&a,sizeof(a))||listen(server,1)){close(server);server=-1;throw std::runtime_error("Output transport is already in use");}}
    // Production USB playback releases the hello only after a real completed
    // transfer. Merely owning a listening socket must never expose a device.
    void markOutputReady(){outputReady=true;}
    ~Reader(){fprintf(stderr,"CMIO transport: %llu complete frames received; %llu playback acknowledgements\n",(unsigned long long)receivedCount,(unsigned long long)playedCount);disconnect();if(server>=0)close(server);}
    void pump(unsigned width,unsigned height){
        if(!outputReady)return;
        if(fd<0){fd=accept(server,nullptr,nullptr);if(fd>=0){++generation;nonblock(fd);Ack hello{Magic,UINT64_MAX,mode};acks.resize(sizeof(hello));memcpy(acks.data(),&hello,sizeof(hello));ackSent=0;}}flush();
        while(fd>=0&&ready.size()<Count){
            if(headerRead<sizeof(header)){ssize_t n=recv(fd,reinterpret_cast<char*>(&header)+headerRead,sizeof(header)-headerRead,0);if(n>0)headerRead+=size_t(n);else{if(n==0||(errno!=EAGAIN&&errno!=EWOULDBLOCK&&errno!=EINTR))disconnect();break;}if(headerRead<sizeof(header))continue;
                if(header.magic!=Magic||header.mode!=mode||header.width!=width||header.height!=height||header.bytes!=size_t(width)*height*2){disconnect();throw std::runtime_error("Final Cut format differs from the selected output format");}incoming.resize(header.bytes);imageRead=0;}
            ssize_t n=recv(fd,incoming.data()+imageRead,incoming.size()-imageRead,0);if(n>0)imageRead+=size_t(n);else{if(n==0||(errno!=EAGAIN&&errno!=EWOULDBLOCK&&errno!=EINTR))disconnect();break;}
            if(imageRead==incoming.size()){ready.push_back({header.sequence,header.hostNS,std::move(incoming),header.timecode});++receivedCount;headerRead=imageRead=0;}
        }
    }
    void read(std::vector<uint8_t>& image,unsigned width,unsigned height){
        pump(width,height);acknowledge=false;if(!ready.empty()){sequence=ready.front().sequence;hostNS=ready.front().hostNS;last=std::move(ready.front().image);timecode=ready.front().timecode;ready.pop_front();acknowledge=true;}
        if(last.empty()){last.resize(size_t(width)*height*2);for(size_t n=0;n<last.size();n+=4){last[n]=last[n+2]=128;last[n+1]=last[n+3]=16;}}image=last;
    }
    void played(uint64_t seq,uint64_t ns,uint64_t connection){if(fd<0||connection!=generation)return;if(acks.size()-ackSent>1024*1024){disconnect();return;}++playedCount;Ack a{Magic,seq,ns};size_t at=acks.size();acks.resize(at+sizeof(a));memcpy(acks.data()+at,&a,sizeof(a));flush();}
};
}
