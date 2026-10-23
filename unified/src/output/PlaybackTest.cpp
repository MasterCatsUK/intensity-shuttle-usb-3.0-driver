// GPL-2.0-or-later. Explicitly started development playback test.
#include "OutputPacket.hpp"
#include "MovieSource.hpp"
#include "IdleScreen.hpp"
#include "DesktopSource.hpp"
#include "SharedOutput.hpp"
#include "OutputAudio.hpp"
#include "AudioCursor.hpp"
#include "WireClock.hpp"
#include "AudioSyncPreference.hpp"
#include "ListeningOutput.hpp"
#include "MirrorFrame.hpp"
#include "Scopes.hpp"
#include <CoreMedia/CoreMedia.h>
#include <libusb.h>
#include <array>
#include <chrono>
#include <csignal>
#include <cstdio>
#include <memory>
#include <string>
#include <algorithm>
#include <cmath>

static volatile sig_atomic_t interrupted=0;
int shuttleCapturePreflight();
static void stop(int) { interrupted=1; }
struct Playback;
struct PlayedFrame {uint64_t sequence,generation,startTick,fractionNS;};
struct Slot { Playback* owner=nullptr;libusb_transfer* transfer=nullptr;std::vector<uint8_t> packet;std::vector<PlayedFrame> sequences;bool pending=false;int correction=0;uint64_t endTick=0; };
struct Playback {
    shuttle_output::Mode mode;libusb_device_handle* device=nullptr;
    unsigned frame=0, completed=0, packetErrors=0, transferErrors=0;
    bool stopping=false,failed=false,premiere=false,premiereReady=false;
    shuttle_output::Sizing sizing=shuttle_output::Sizing::Fit;
    std::unique_ptr<MovieSource> movie;
    std::unique_ptr<shuttle_idle::Screen> idle;
    std::unique_ptr<DesktopSource> desktop;
    std::unique_ptr<shuttle_output_audio::LiveAudioOffset> audioOffset;int lastAudioOffset=0;
    int timecodeState=-1;bool idleScreenActive=false,idleOnly=false;
    shuttle_output_audio::StereoMeters meters;
    std::unique_ptr<shuttle_sink::Reader> sink;uint64_t wireSequence=0,wireGeneration=0,wireStartTick=0,wireFractionNS=0;bool wireAcknowledge=false;
    std::unique_ptr<shuttle_output_audio::Reader> sinkAudio;shuttle_output_audio::AudioCursor audioCursor;shuttle_output_audio::WireClock wireClock;shuttle_output_audio::VideoClockDomain videoClock=shuttle_output_audio::VideoClockDomain::Unknown;uint64_t ptsGeneration=UINT64_MAX;unsigned ptsLogged=0;
    std::unique_ptr<shuttle_listen::Output> listening;
    std::unique_ptr<shuttle_mirror::Feed> mirror;shuttle_scopes::AsyncRenderer scopes;bool dualOutput=false;
    bool startup=false,startupHeld=false;bool repeat=false;std::string filename;unsigned movieIndex=0;
    std::vector<uint8_t> wire;size_t wireOffset=0;uint64_t microframe=0;
    unsigned fifoLevel=0,fifoCapacity=32768;bool fifoValid=false;
    bool traceFIFO=false;double fifoAverage=0;int pendingCorrection=0;int64_t totalCorrection=0;
    void pollFIFO() {
        uint32_t raw=0;
        int rc=libusb_control_transfer(device,0xc0,214,0,12,reinterpret_cast<uint8_t*>(&raw),4,500);
        if(rc!=4){fifoValid=false;return;}
        fifoCapacity=raw&0x800?49152:32768;
        fifoLevel=raw&0x800?(raw&0x3ff)*48:(raw&0x7ff)*16;
        fifoAverage=fifoValid?fifoAverage*0.8+fifoLevel*0.2:fifoLevel;fifoValid=true;
        if(traceFIFO){printf("FIFO raw=%08x fill=%u/%u avg=%.0f pending=%d adjusted=%lld\n",raw,fifoLevel,fifoCapacity,fifoAverage,pendingCorrection,(long long)totalCorrection);fflush(stdout);}
    }
    std::chrono::steady_clock::time_point end;
    std::vector<uint8_t> nextWireFrame(uint64_t wireHostNS=0) {
        auto p=shuttle_output::profile(mode);
        static const uint8_t bars[8][3]={{235,128,128},{210,16,146},{170,166,16},{145,54,34},{106,202,222},{81,90,240},{41,240,110},{16,128,128}};
        std::vector<uint8_t> source(p.width*p.height*2);
        std::vector<int32_t> pcm;
        bool showTC=sink&&shuttle_output_audio::timecodeOverlayEnabled.load();
        const unsigned tcPosition=shuttle_output_audio::timecodeOverlayPosition.load();
        if(movie){
            if(repeat&&movieIndex>=unsigned(std::ceil(movie->duration()*p.rateNom/p.rateDen))){movie.reset(new MovieSource(filename,mode,sizing));movieIndex=0;}
            movie->read(movieIndex++,source,pcm);
            if(startup&&movieIndex>=unsigned(std::ceil(movie->duration()*p.rateNom/p.rateDen))&&!startupHeld){startupHeld=true;puts("Startup movie finished — holding last frame until an app action.");fflush(stdout);}
        }
        if(desktop){
            if(!desktop->read(source))shuttle_idle::black(source,p.width,p.height);
            if(sinkAudio&&wireHostNS>shuttle_output_audio::OutputLatencyNS){
                uint64_t first=uint64_t(static_cast<unsigned __int128>(wireHostNS-shuttle_output_audio::OutputLatencyNS)*48000/1000000000);
                sinkAudio->read(shuttle_output_audio::offsetAudioSample(first,audioOffset?audioOffset->milliseconds():0),p.audioFrames(frame),pcm);
            }
        }
        if(sink){sink->read(source,p.width,p.height);wireSequence=sink->sequence;wireGeneration=sink->generation;wireAcknowledge=sink->acknowledge;
            if(sink->generation!=ptsGeneration){timecodeState=-1;meters.reset();}
            if(sink->acknowledge){int state=shuttle_sink::validTimecode(sink->timecode)?1:0;if(state!=timecodeState){timecodeState=state;char text[16];shuttle_sink::timecodeText(sink->timecode,text);fprintf(stderr,"%s frame timecode: %s%s\n",premiere?"Premiere":"Final Cut",text,state?"":" (not supplied)");}}
            if(sink->generation!=ptsGeneration){ptsGeneration=sink->generation;ptsLogged=0;videoClock=shuttle_output_audio::VideoClockDomain::Unknown;}
            if(sink->acknowledge&&videoClock==shuttle_output_audio::VideoClockDomain::Unknown){auto now=CMTimeConvertScale(CMClockGetTime(CMClockGetHostTimeClock()),1000000000,kCMTimeRoundingMethod_Default).value;videoClock=shuttle_output_audio::classifyPTS(sink->hostNS,uint64_t(now));fprintf(stderr,"CMIO audio alignment: %s clock\n",videoClock==shuttle_output_audio::VideoClockDomain::Host?"client host presentation":"USB wire presentation (relative client PTS)");}
            if(sink->acknowledge&&(ptsLogged++<3||ptsLogged%50==0)){auto now=CMTimeConvertScale(CMClockGetTime(CMClockGetHostTimeClock()),1000000000,kCMTimeRoundingMethod_Default).value;fprintf(stderr,"CMIO video PTS: %llu ns; %.3f ms from host now; sequence %llu; generation %llu; audio received %llu\n",(unsigned long long)sink->hostNS,(double(sink->hostNS)-double(now))/1e6,(unsigned long long)sink->sequence,(unsigned long long)sink->generation,(unsigned long long)(sinkAudio?sinkAudio->receivedFrames():0));}
            // Native clients may provide host presentation timestamps. FCP's
            // direct sink instead supplies a local sequence time starting at
            // zero, with no absolute audio-clock mapping. For that path, use
            // USB completion times and queued microframes to estimate when this
            // wire frame is presented. Never add media-relative PTS to uptime.
            const bool relative=videoClock==shuttle_output_audio::VideoClockDomain::Wire;
            const uint64_t presentation=relative?wireHostNS:sink->hostNS;
            const uint64_t bufferPTS=presentation>shuttle_output_audio::OutputLatencyNS?presentation-shuttle_output_audio::OutputLatencyNS:0;
            uint64_t first=0;unsigned frames=p.audioFrames(frame);
            const bool usable=videoClock!=shuttle_output_audio::VideoClockDomain::Unknown&&(!relative||wireHostNS);
            int offset=audioOffset?audioOffset->milliseconds():0;
            if(offset!=lastAudioOffset){lastAudioOffset=offset;fprintf(stderr,"HDMI timeline audio sync: %+d ms (negative earlier, positive later)\n",offset);}
            if(usable&&sinkAudio&&audioCursor.take(relative||sink->acknowledge,bufferPTS,sink->generation,frames,p.rateNom,p.rateDen,first))sinkAudio->read(shuttle_output_audio::offsetAudioSample(first,offset),frames,pcm);
        }
        if(sink&&idle){idleScreenActive=idle->update(source,sink->acknowledge,sink->hasPicture());if(idleScreenActive)showTC=false;}
        const unsigned left=(frame*8)%(p.width-128);
        if(idleOnly&&idle){idle->apply(source,false);idleScreenActive=true;showTC=false;}
        if(!movie&&!sink&&!desktop&&!idleOnly)for(unsigned y=0;y<p.height;++y) for(unsigned x=0;x<p.width;x+=2) {
            auto c=bars[x*8/p.width];auto* dest=&source[(y*p.width+x)*2];
            dest[0]=c[1];dest[1]=c[0];dest[2]=c[2];dest[3]=c[0];
            if(y>p.height*3/4 && y<p.height*3/4+64 && x>=left && x<left+128) {
                dest[0]=dest[2]=128;dest[1]=dest[3]=235;
            }
        }
        // Keep the physical fractional-rate audio cadence continuous across
        // movie loop boundaries; a one-sample difference is padded/truncated.
        if(movie)pcm.resize(p.audioFrames(frame)*8,0);
        // Fork the clean rendered picture/PCM before output-only overlays/scopes.
        if(mirror)mirror->write(source,pcm,sink?sink->timecode:shuttle_sink::Timecode{},idleScreenActive,wireHostNS);
        const auto scopeView=startup?shuttle_scopes::View::Video:shuttle_scopes::validView(shuttle_output_audio::monitorView.load());
        const bool pictureView=scopeView==shuttle_scopes::View::Video;
        if(!idleScreenActive&&!idleOnly)scopes.replace(source,p.width,p.height,scopeView);
        // Scopes are a clean measurement display; remembered video overlays
        // return when Video is selected, without changing their saved choices.
        if(pictureView&&!startup){
            shuttle_sink::overlaySafeZones(source,p.width,p.height,shuttle_output_audio::titleSafeEnabled.load(),shuttle_output_audio::actionSafeEnabled.load());
            if(showTC)shuttle_sink::overlayTimecode(source,p.width,p.height,sink->timecode,tcPosition);
        }
        meters.update(pcm,double(p.rateDen)/p.rateNom);
        if(listening)listening->push(pcm);
        if(pictureView&&!startup&&shuttle_output_audio::audioMetersEnabled.load()){
            shuttle_sink::TimecodeBox avoid{};
            if(showTC)avoid=shuttle_sink::timecodeOverlayBox(p.width,p.height,sink->timecode,tcPosition);
            shuttle_sink::overlayAudioMeters(source,p.width,p.height,meters,shuttle_output_audio::audioMetersPosition.load(),avoid);
        }
        auto packet=shuttle_output::encode(mode,source.data(),source.size(),p.width*2,pcm.empty()?nullptr:pcm.data(),pcm.size(),frame);
        ++frame;
        return packet;
    }
    void fill(Slot& slot) {
        slot.sequences.clear();
        const uint64_t startTick=microframe;
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
        auto deadlineAt=[&](size_t offset){uint64_t ns=0;shuttle_output_audio::WireClock::position(startTick,lengths.data(),lengths.size(),offset,wireStartTick,wireFractionNS);wireClock.atTick(wireStartTick,wireFractionNS,ns);return ns;};
        if(wire.empty()){wire=nextWireFrame(deadlineAt(0));wireOffset=0;}
        slot.packet.resize(total);size_t offset=0;
        while(offset<total){
            if(wireOffset==wire.size()){wire=nextWireFrame(deadlineAt(offset));wireOffset=0;if(wire.size()!=wireSize)throw std::runtime_error("Wire frame length changed");}
            size_t count=std::min(total-offset,wire.size()-wireOffset);memcpy(slot.packet.data()+offset,wire.data()+wireOffset,count);wireOffset+=count;offset+=count;
            if(sink&&wireOffset==wire.size()&&wireAcknowledge)slot.sequences.push_back({wireSequence,wireGeneration,wireStartTick,wireFractionNS});
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
        if(!p.failed){uint64_t now=CMTimeConvertScale(CMClockGetTime(CMClockGetHostTimeClock()),1000000000,kCMTimeRoundingMethod_Default).value;p.wireClock.completed(slot.endTick,now);if(p.sink){if(!p.mirror||p.mirror->ready())p.sink->markOutputReady();if(p.premiere&&!p.premiereReady&&(!p.mirror||p.mirror->ready())){p.premiereReady=true;puts("Premiere USB ready — enable Mercury Transmit in Premiere Playback settings.");fflush(stdout);}for(auto f:slot.sequences){uint64_t presented=now;p.wireClock.atTick(f.startTick,f.fractionNS,presented);p.sink->played(f.sequence,presented,f.generation);}}}
        ++p.completed;
        if(!p.stopping && !p.failed && !interrupted && std::chrono::steady_clock::now()<p.end) p.submit(slot);
    }
};
int main(int argc,char**argv) {
    if(argc!=4 || (std::string(argv[1])!="--startup" && std::string(argv[1])!="--bars" && std::string(argv[1])!="--play" && std::string(argv[1])!="--loop" && std::string(argv[1])!="--sink" && std::string(argv[1])!="--virtual-sink" && std::string(argv[1])!="--premiere-dual" && std::string(argv[1])!="--premiere" && std::string(argv[1])!="--desktop" && std::string(argv[1])!="--idle")) { puts("Usage: ShuttlePlayback --bars MODE SECONDS(1-60)\n       ShuttlePlayback --play|--loop MODE MOVIE_FILE\n       ShuttlePlayback --sink|--premiere MODE live\n       ShuttlePlayback --desktop MODE DISPLAY_ID\n       ShuttlePlayback --idle MODE live\nClose all Shuttle capture clients first. No firmware writes are sent.");return 64; }
    Playback p;std::string mode=argv[2];
    if(mode=="576i50")p.mode=shuttle_output::Mode::PAL576i50;
    else if(mode=="1080i50")p.mode=shuttle_output::Mode::HD1080i50;
    else if(mode=="1080p25")p.mode=shuttle_output::Mode::HD1080p25;
    else if(mode=="480i5994")p.mode=shuttle_output::Mode::NTSC480i5994;
    else if(mode=="1080i5994")p.mode=shuttle_output::Mode::HD1080i5994;
    else if(mode=="1080p2997")p.mode=shuttle_output::Mode::HD1080p2997;
    else return 64;
    CFPreferencesAppSynchronize(CFSTR("local.shuttle.camera"));Boolean exists=false;long sizing=CFPreferencesGetAppIntegerValue(CFSTR("PlaybackSizing"),CFSTR("local.shuttle.camera"),&exists);p.sizing=shuttle_output::sizingValue(exists?sizing:0);
    long connector=CFPreferencesGetAppIntegerValue(CFSTR("OutputConnector"),CFSTR("local.shuttle.camera"),&exists);if(!shuttle_output::connectorSupports(static_cast<shuttle_output::Connector>(exists&&connector>=0&&connector<4?connector:0),unsigned(p.mode))){fprintf(stderr,"Choose PAL or NTSC for S-Video/Composite output.\n");return 64;}
    p.startup=std::string(argv[1])=="--startup";if(p.startup)p.sizing=shuttle_output::Sizing::Stretch;
    p.idle.reset(new shuttle_idle::Screen(p.mode));
    p.dualOutput=std::string(argv[1])=="--virtual-sink"||std::string(argv[1])=="--premiere-dual";
    if(p.dualOutput){try{p.mirror.reset(new shuttle_mirror::Feed(argv[3],false,unsigned(p.mode)));}catch(const std::exception& e){fprintf(stderr,"Simultaneous output: %s\n",e.what());return 65;}}
    p.premiere=std::string(argv[1])=="--premiere"||std::string(argv[1])=="--premiere-dual";bool isDesktop=std::string(argv[1])=="--desktop",isSink=std::string(argv[1])=="--sink"||p.premiere||p.dualOutput,isMovie=std::string(argv[1])!="--bars"&&std::string(argv[1])!="--idle"&&!isSink&&!isDesktop;p.idleOnly=std::string(argv[1])=="--idle";p.repeat=std::string(argv[1])=="--loop";double seconds=0;
    if(isDesktop){try{char* tail=nullptr;unsigned long id=strtoul(argv[3],&tail,10);if(*tail||!id||id>UINT32_MAX)return 64;p.desktop.reset(new DesktopSource(uint32_t(id),p.mode,p.sizing));p.sinkAudio.reset(new shuttle_output_audio::Reader);}catch(const std::exception& e){fprintf(stderr,"Desktop: %s\n",e.what());return 65;}}
    else if(isMovie) {try {p.filename=argv[3];p.movie.reset(new MovieSource(p.filename,p.mode,p.sizing));seconds=p.movie->duration();}catch(const std::exception& error){fprintf(stderr,"Movie: %s\n",error.what());return 65;}}
    else if(isSink){try{p.sink.reset(new shuttle_sink::Reader(unsigned(p.mode),false,p.premiere?shuttle_sink::PremierePort:p.dualOutput?shuttle_sink::VirtualPort:shuttle_sink::Port));p.sinkAudio.reset(new shuttle_output_audio::Reader);shuttle_sink::prepareTimecodeOverlay();int initial=shuttle_output_audio::readLiveAudioOffsetPreference();p.audioOffset.reset(new shuttle_output_audio::LiveAudioOffset(initial,shuttle_output_audio::readLiveAudioOffsetPreference));p.lastAudioOffset=initial;fprintf(stderr,"HDMI timeline audio sync: %+d ms (negative earlier, positive later)\n",initial);}catch(const std::exception& e){fprintf(stderr,"A/V driver: %s. Activate the output driver first.\n",e.what());return 65;}}
    else if(p.idleOnly){}
    else {char* tail=nullptr;long value=strtol(argv[3],&tail,10);if(*tail||value<1||value>60)return 64;seconds=value;}
    if(!p.audioOffset&&!p.startup){try{shuttle_sink::prepareTimecodeOverlay();int initial=shuttle_output_audio::readLiveAudioOffsetPreference();p.audioOffset.reset(new shuttle_output_audio::LiveAudioOffset(initial,shuttle_output_audio::readLiveAudioOffsetPreference));}catch(const std::exception& e){fprintf(stderr,"Output overlays: %s\n",e.what());return 65;}}
    if(!p.startup)p.listening.reset(new shuttle_listen::Output);
    signal(SIGINT,stop);signal(SIGTERM,stop);
    if(shuttleCapturePreflight()!=0) {fputs("Close every Shuttle camera client before output testing.\n",stderr);return 10;}
    libusb_context* ctx=nullptr;if(libusb_init(&ctx))return 1;
    p.device=libusb_open_device_with_vid_pid(ctx,0x1edb,0xbd3b);
    if(!p.device){puts("Shuttle not available");libusb_exit(ctx);return 2;}
    int rc=libusb_claim_interface(p.device,0);
    if(rc) {fprintf(stderr,"Cannot claim idle Shuttle: %s\n",libusb_error_name(rc));libusb_close(p.device);libusb_exit(ctx);return 3;}
    if(shuttleCapturePreflight()!=0) {libusb_release_interface(p.device,0);libusb_close(p.device);libusb_exit(ctx);return 10;}
    rc=libusb_set_interface_alt_setting(p.device,0,1);
    if(rc) {fprintf(stderr,"Output alternate: %s\n",libusb_error_name(rc));libusb_release_interface(p.device,0);libusb_close(p.device);libusb_exit(ctx);return 4;}
    p.traceFIFO=getenv("SHUTTLE_TRACE_FIFO")!=nullptr;
    bool useFIFO=getenv("SHUTTLE_DISABLE_FIFO")==nullptr;
    if(useFIFO)p.pollFIFO();
    std::array<Slot,4> slots;
    p.end=p.repeat||isSink||isDesktop||p.idleOnly||p.startup?std::chrono::steady_clock::time_point::max():std::chrono::steady_clock::now()+std::chrono::milliseconds(int64_t(seconds*1000));
    for(auto& slot:slots) {slot.owner=&p;slot.transfer=libusb_alloc_transfer(256);if(!slot.transfer){p.failed=true;break;}if(!p.submit(slot))break;}
    printf("USB output: %s; %.3f seconds%s; %s\n",mode.c_str(),seconds,p.repeat?" per loop (Stop output to finish)":"",isSink?(p.premiere?"Premiere Mercury Transmit video + Core Audio HDMI stereo":"CMIO timeline video + timestamped HDMI stereo audio"):isDesktop?"Mac desktop mirror + Core Audio HDMI stereo":isMovie?"movie video and stereo audio":p.idleOnly?"idle screen; silent audio":"colour bars + moving white block; silent audio");fflush(stdout);
    auto lastFIFO=std::chrono::steady_clock::now();
    while(!interrupted&&!p.failed&&std::chrono::steady_clock::now()<p.end) {
        if((p.dualOutput||p.startup)&&getppid()==1){fputs("Shuttle Video closed; stopping paired output.\n",stderr);p.failed=true;break;}
        if(p.mirror&&!p.mirror->alive()){fputs("Mac display output disconnected; stopping simultaneous output.\n",stderr);p.failed=true;break;}
        if(p.sink){try{auto profile=shuttle_output::profile(p.mode);p.sink->pump(profile.width,profile.height);if(p.sinkAudio)p.sinkAudio->pump();}catch(const std::exception& e){fprintf(stderr,"A/V driver: %s\n",e.what());p.failed=true;break;}}
        timeval tv{0,p.sink?1000:100000};int eventRC=libusb_handle_events_timeout(ctx,&tv);if(eventRC<0&&eventRC!=LIBUSB_ERROR_INTERRUPTED&&!interrupted){p.failed=true;break;}
        if(useFIFO&&std::chrono::steady_clock::now()-lastFIFO>std::chrono::milliseconds(100)){p.pollFIFO();lastFIFO=std::chrono::steady_clock::now();}
    }
    p.stopping=true;
    for(auto& slot:slots) if(slot.pending)libusb_cancel_transfer(slot.transfer);
    auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(3);
    auto pending=[&]{for(auto& slot:slots)if(slot.pending)return true;return false;};
    while(pending()&&std::chrono::steady_clock::now()<deadline) {timeval tv{0,100000};libusb_handle_events_timeout(ctx,&tv);}
    printf("Completed 32-ms USB chunks: %u; generated video frames: %u; transfer errors: %u; packet errors: %u; cancellation complete: %s\n",p.completed,p.frame,p.transferErrors,p.packetErrors,pending()?"no":"yes");
    if(pending()) {fflush(nullptr);_Exit(5);} // Keep in-flight memory alive until process cleanup.
    for(auto& slot:slots)if(slot.transfer)libusb_free_transfer(slot.transfer);
    rc=libusb_set_interface_alt_setting(p.device,0,2);
    printf("Restore input alternate: %s\n",libusb_error_name(rc));
    libusb_release_interface(p.device,0);libusb_close(p.device);libusb_exit(ctx);
    return p.failed||p.packetErrors||rc?1:0;
}
