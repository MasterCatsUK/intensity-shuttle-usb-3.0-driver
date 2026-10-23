// GPL-2.0-or-later. Modified 19 October 2026 for Shuttle Player.
// USB scheduling/FIFO correction retained from Shuttle Camera 0.1.47 PlaybackTest.cpp.
#import <Foundation/Foundation.h>
#include "PlayerEngine.hpp"
#include <libusb.h>
#include <array>
#include <chrono>
#include <csignal>
#include <cstdio>
#include <cerrno>
static volatile sig_atomic_t interrupted=0;
int shuttleCapturePreflight();
static void stop(int){interrupted=1;}
struct Playback;
struct Slot {Playback* owner=nullptr;libusb_transfer* transfer=nullptr;std::vector<uint8_t> packet;bool pending=false;int correction=0;uint64_t endTick=0;};
struct Playback {
    shuttle_output::Mode mode;libusb_device_handle* device=nullptr;
    unsigned frame=0,completed=0,packetErrors=0,transferErrors=0;
    bool stopping=false,failed=false,traceFIFO=false;unsigned fifoLogs=0;
    unsigned fifoLevel=0,fifoCapacity=32768;bool fifoValid=false;
    double fifoAverage=0;int pendingCorrection=0;int64_t totalCorrection=0;
    std::vector<uint8_t> wire;size_t wireOffset=0;uint64_t microframe=0;
    std::unique_ptr<player::Engine> engine;std::unique_ptr<player::Mapping> preview;
    std::string commands;
    void controls(){
        char bytes[1024];unsigned total=0;
        for(;;){ssize_t n=read(STDIN_FILENO,bytes,sizeof(bytes));if(n<0){if(errno==EAGAIN||errno==EWOULDBLOCK)break;if(errno==EINTR)continue;interrupted=1;break;}if(!n){interrupted=1;break;}
            commands.append(bytes,size_t(n));if(commands.size()>8192){interrupted=1;break;}
            size_t newline;while((newline=commands.find('\n'))!=std::string::npos){engine->command(commands.substr(0,newline));commands.erase(0,newline+1);}
            if((total+=unsigned(n))>=4096)break;
        }
        if(engine->stopping)interrupted=1;
    }
    std::vector<uint8_t> nextWireFrame(){
        controls();std::vector<uint8_t> picture;std::vector<int32_t> pcm;
        engine->render(frame,picture,pcm);
        engine->publish(*preview,picture,pcm);
        auto packet=shuttle_output::encode(mode,picture.data(),picture.size(),shuttle_output::profile(mode).width*2,pcm.data(),pcm.size(),frame);
        ++frame;return packet;
    }
    void pollFIFO() {
        uint32_t raw=0;
        int rc=libusb_control_transfer(device,0xc0,214,0,12,reinterpret_cast<uint8_t*>(&raw),4,500);
        if(rc!=4){fifoValid=false;return;}
        fifoCapacity=raw&0x800?49152:32768;
        fifoLevel=raw&0x800?(raw&0x3ff)*48:(raw&0x7ff)*16;
        fifoAverage=fifoValid?fifoAverage*0.8+fifoLevel*0.2:fifoLevel;fifoValid=true;
        if(traceFIFO&&fifoLogs++%10==0){printf("FIFO raw=%08x fill=%u/%u avg=%.0f pending=%d adjusted=%lld\n",raw,fifoLevel,fifoCapacity,fifoAverage,pendingCorrection,(long long)totalCorrection);fflush(stdout);}
    }
    void fill(Slot& slot) {
        auto p=shuttle_output::profile(mode);
        const size_t wireSize=16+size_t(p.width)*2*p.totalLines+(p.totalLines/5)*8+p.maxAudio()*24;
        const auto wordAt=[&](uint64_t tick){return uint64_t(static_cast<unsigned __int128>(tick)*(wireSize/4)*p.rateNom/(8000ULL*p.rateDen));};
        std::array<unsigned,256> lengths;
        size_t total=0;
        for(unsigned n=0;n<256;++n){lengths[n]=unsigned((wordAt(microframe+1)-wordAt(microframe))*4);++microframe;total+=lengths[n];}
        slot.correction=fifoValid?(std::max(-4096,std::min(4096,int((fifoCapacity/2.0-fifoAverage-pendingCorrection)/8))) /4)*4:0;
        unsigned correctionWords=unsigned(std::abs(slot.correction))/4;
        for(unsigned n=0;n<256;++n){int change=int(((n+1)*correctionWords/256)-(n*correctionWords/256))*4;lengths[n]=unsigned(int(lengths[n])+(slot.correction<0?-change:change));}
        total=size_t(int64_t(total)+slot.correction);slot.endTick=microframe;
        if(wire.empty()){wire=nextWireFrame();wireOffset=0;}
        slot.packet.resize(total);size_t offset=0;
        while(offset<total){
            if(wireOffset==wire.size()){wire=nextWireFrame();wireOffset=0;if(wire.size()!=wireSize)throw std::runtime_error("Wire frame length changed");}
            size_t count=std::min(total-offset,wire.size()-wireOffset);memcpy(slot.packet.data()+offset,wire.data()+wireOffset,count);wireOffset+=count;offset+=count;
        }
        // Whole-millisecond transfers keep Darwin's USB scheduling exact for
        // fractional rates. Wire frames may cross a transfer boundary.
        libusb_fill_iso_transfer(slot.transfer,device,0x01,slot.packet.data(),int(slot.packet.size()),256,done,&slot,1000);
        for(unsigned n=0;n<256;++n)slot.transfer->iso_packet_desc[n].length=lengths[n];
    }
    bool submit(Slot& slot) {
        try {fill(slot);}catch(const std::exception& error){fprintf(stderr,"Decode: %s\n",error.what());failed=true;return false;}
        int rc=libusb_submit_transfer(slot.transfer);
        if(rc) { fprintf(stderr,"Submit: %s\n",libusb_error_name(rc));failed=true;return false; }
        slot.pending=true;pendingCorrection+=slot.correction;totalCorrection+=slot.correction;return true;
    }
    static void LIBUSB_CALL done(libusb_transfer* transfer) {
        auto& slot=*static_cast<Slot*>(transfer->user_data);auto& p=*slot.owner;slot.pending=false;p.pendingCorrection-=slot.correction;
        if(transfer->status==LIBUSB_TRANSFER_CANCELLED)return;
        if(transfer->status!=LIBUSB_TRANSFER_COMPLETED) {++p.transferErrors;p.failed=true;}
        for(int n=0;n<transfer->num_iso_packets;++n)
            if(transfer->iso_packet_desc[n].status!=LIBUSB_TRANSFER_COMPLETED){++p.packetErrors;p.failed=true;}

        ++p.completed;
        if(!p.stopping && !p.failed && !interrupted) p.submit(slot);
    }
};
int main(int argc,char**argv){@autoreleasepool{
    if(argc!=6){fputs("Usage: ShuttlePlayerOutput MODE MOVIE FIT(0-2) PREVIEW VOLUME(0-1)\n",stderr);return 64;}
    signal(SIGINT,stop);signal(SIGTERM,stop);signal(SIGPIPE,SIG_IGN);
    Playback p;std::string mode=argv[1];
    const char* modes[]={"576i50","1080i50","1080p25","480i5994","1080i5994","1080p2997"};
    int index=-1;for(int n=0;n<6;++n)if(mode==modes[n])index=n;if(index<0)return 64;p.mode=shuttle_output::Mode(index);
    try{
        p.preview.reset(new player::Mapping(argv[4],false));
        p.engine.reset(new player::Engine(argv[2],p.mode,shuttle_output::sizingValue(strtol(argv[3],nullptr,10)),true));
        p.engine->command(std::string("volume ")+argv[5]);p.engine->paused=true;
    }catch(const std::exception& e){fprintf(stderr,"%s\n",e.what());return 65;}
    if(shuttleCapturePreflight()!=0){fputs("Stop capture and close camera previews before playing.\n",stderr);return 10;}
    libusb_context* ctx=nullptr;if(libusb_init(&ctx))return 1;
    p.device=libusb_open_device_with_vid_pid(ctx,0x1edb,0xbd3b);
    if(!p.device){fputs("Intensity Shuttle USB 3.0 is not available.\n",stderr);libusb_exit(ctx);return 2;}
    int rc=libusb_claim_interface(p.device,0);
    if(rc){fprintf(stderr,"Shuttle is busy or unavailable: %s\n",libusb_error_name(rc));libusb_close(p.device);libusb_exit(ctx);return 3;}
    if(shuttleCapturePreflight()!=0){libusb_release_interface(p.device,0);libusb_close(p.device);libusb_exit(ctx);return 10;}
    rc=libusb_set_interface_alt_setting(p.device,0,1);
    if(rc){fprintf(stderr,"Cannot start USB output: %s\n",libusb_error_name(rc));libusb_release_interface(p.device,0);libusb_close(p.device);libusb_exit(ctx);return 4;}
    int flags=fcntl(STDIN_FILENO,F_GETFL,0);fcntl(STDIN_FILENO,F_SETFL,flags|O_NONBLOCK);
    p.traceFIFO=getenv("SHUTTLE_TRACE_FIFO")!=nullptr;p.pollFIFO();std::array<Slot,4> slots;
    for(auto& slot:slots){slot.owner=&p;slot.transfer=libusb_alloc_transfer(256);if(!slot.transfer){p.failed=true;break;}if(!p.submit(slot))break;}
    if(!p.failed){puts("PLAYER_READY");fflush(stdout);}
    auto lastFIFO=std::chrono::steady_clock::now();
    while(!interrupted&&!p.failed){
        p.controls();timeval tv{0,10000};int result=libusb_handle_events_timeout(ctx,&tv);if(result<0&&result!=LIBUSB_ERROR_INTERRUPTED&&!interrupted){p.failed=true;break;}
        if(std::chrono::steady_clock::now()-lastFIFO>std::chrono::milliseconds(100)){p.pollFIFO();lastFIFO=std::chrono::steady_clock::now();}
    }
    p.stopping=true;for(auto& slot:slots)if(slot.pending)libusb_cancel_transfer(slot.transfer);
    auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(3);
    auto pending=[&]{for(auto& slot:slots)if(slot.pending)return true;return false;};
    while(pending()&&std::chrono::steady_clock::now()<deadline){timeval tv{0,100000};libusb_handle_events_timeout(ctx,&tv);}
    if(pending()){fputs("USB output did not stop in time.\n",stderr);fflush(nullptr);_Exit(5);}
    for(auto& slot:slots)if(slot.transfer)libusb_free_transfer(slot.transfer);
    rc=libusb_set_interface_alt_setting(p.device,0,2);
    libusb_release_interface(p.device,0);libusb_close(p.device);libusb_exit(ctx);
    if(p.failed||p.packetErrors||rc){fputs("USB output stopped after a transfer error.\n",stderr);return 1;}
    return 0;
}}
