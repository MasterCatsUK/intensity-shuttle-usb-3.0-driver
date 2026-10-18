// GPL-2.0-or-later. Capture input and HDMI output, built using MIT-licensed libASPL.
#include <aspl/Driver.hpp>
#include <CoreAudio/AudioServerPlugIn.h>
#include <mach/mach_time.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <poll.h>
#include <unistd.h>
#include <syslog.h>
#include <atomic>
#include <array>
#include <thread>
#include "AudioProtocol.hpp"
#include "OutputAudio.hpp"
#include <algorithm>
#include <fcntl.h>

namespace {
constexpr uint64_t RingFrames=65536, DelayFrames=3840;
struct Slot { std::atomic<uint64_t> tag{0}, bits{0}; };
class AudioInput : public aspl::ControlRequestHandler,public aspl::IORequestHandler {
    std::array<Slot,RingFrames> ring;
    std::atomic<bool> running{false};
    std::thread receiver;
    int fd=-1;
    void receive() {
        shuttle_audio::Packet packet;
        bool logged=false;
        while(running) {
            pollfd pfd{fd,POLLIN,0};
            if(poll(&pfd,1,100)<=0) continue;
            ssize_t n=recv(fd,&packet,sizeof(packet),0);
            if(n<=0 || !shuttle_audio::valid(packet,size_t(n))) continue;
            if(!logged) { syslog(LOG_NOTICE,"Shuttle Audio: receiving live stereo PCM");logged=true; }
            uint64_t first=shuttle_audio::sampleAt(packet.hostNS);
            for(unsigned i=0;i<shuttle_audio::Frames;++i) {
                auto &slot=ring[(first+i)%RingFrames];
                uint64_t bits;std::memcpy(&bits,packet.samples+i*2,8);
                slot.tag.store(0);slot.bits.store(bits);slot.tag.store(first+i);
            }
        }
    }
public:
    ~AudioInput() override { OnStopIO(); }
    OSStatus OnStartIO() override {
        fd=socket(AF_INET,SOCK_DGRAM,0);
        if(fd<0) return kAudioHardwareUnspecifiedError;
        int buffer=1048576;setsockopt(fd,SOL_SOCKET,SO_RCVBUF,&buffer,sizeof(buffer));
        sockaddr_in address{};address.sin_len=sizeof(address);address.sin_family=AF_INET;
        address.sin_port=htons(shuttle_audio::Port);address.sin_addr.s_addr=htonl(INADDR_LOOPBACK);
        if(bind(fd,reinterpret_cast<sockaddr *>(&address),sizeof(address))) {
            syslog(LOG_ERR,"Shuttle Audio: local transport bind failed: %m");close(fd);fd=-1;
            return kAudioHardwareUnspecifiedError;
        }
        running=true;receiver=std::thread(&AudioInput::receive,this);
        syslog(LOG_NOTICE,"Shuttle Audio: input started");return noErr;
    }
    void OnStopIO() override {
        running=false;
        if(receiver.joinable()) receiver.join();
        if(fd>=0) { close(fd);fd=-1;syslog(LOG_NOTICE,"Shuttle Audio: input stopped"); }
    }
    void OnReadClientInput(const std::shared_ptr<aspl::Client>&,
          const std::shared_ptr<aspl::Stream>&,Float64,Float64 timestamp,
          void *bytes,UInt32 count) override {
        std::memset(bytes,0,count);
        if(timestamp<double(DelayFrames) || !std::isfinite(timestamp)) return;
        auto *output=static_cast<uint8_t *>(bytes);
        uint64_t first=uint64_t(std::llround(timestamp))-DelayFrames;
        for(unsigned i=0;i<count/8;++i) {
            uint64_t index=first+i;
            const auto &slot=ring[index%RingFrames];
            if(slot.tag.load()!=index) continue;
            uint64_t bits=slot.bits.load();
            if(slot.tag.load()==index) std::memcpy(output+i*8,&bits,8);
        }
    }
};
class AudioOutput : public aspl::ControlRequestHandler,public aspl::IORequestHandler {
    int fd=-1;
public:
    ~AudioOutput() override {OnStopIO();}
    OSStatus OnStartIO() override {
        fd=socket(AF_INET,SOCK_DGRAM,0);if(fd<0)return kAudioHardwareUnspecifiedError;
        fcntl(fd,F_SETFL,fcntl(fd,F_GETFL)|O_NONBLOCK);sockaddr_in a{};a.sin_len=sizeof(a);a.sin_family=AF_INET;a.sin_port=htons(shuttle_output_audio::Port);a.sin_addr.s_addr=htonl(INADDR_LOOPBACK);
        if(connect(fd,(sockaddr*)&a,sizeof(a))){close(fd);fd=-1;return kAudioHardwareUnspecifiedError;}
        syslog(LOG_NOTICE,"Shuttle Audio: HDMI output started");return noErr;
    }
    void OnStopIO() override {if(fd>=0){close(fd);fd=-1;syslog(LOG_NOTICE,"Shuttle Audio: HDMI output stopped");}}
    void OnWriteMixedOutput(const std::shared_ptr<aspl::Stream>&,Float64,Float64 timestamp,const void* bytes,UInt32 count) override {
        if(fd<0||!std::isfinite(timestamp)||timestamp<0||timestamp>double(UINT64_MAX-48000))return;
        auto* source=static_cast<const float*>(bytes);unsigned frames=count/8;uint64_t first=uint64_t(std::llround(timestamp));
        for(unsigned offset=0;offset<frames;){shuttle_output_audio::Packet p;p.frames=std::min<unsigned>(shuttle_output_audio::MaxFrames,frames-offset);p.firstSample=first+offset;
            for(unsigned n=0;n<p.frames*2;++n){float x=source[offset*2+n];p.samples[n]=std::isfinite(x)?std::max(-1.0f,std::min(1.0f,x)):0;}
            send(fd,&p,shuttle_output_audio::HeaderBytes+p.frames*8,0);offset+=p.frames;
        }
    }
};
class AudioDevice : public aspl::Device {
    mach_timebase_info_data_t timebase{};
public:
    AudioDevice(std::shared_ptr<aspl::Context> c,const aspl::DeviceParameters &p):aspl::Device(c,p) {
        mach_timebase_info(&timebase);
    }
protected:
    OSStatus GetZeroTimeStampImpl(UInt32,Float64 *sample,UInt64 *host,UInt64 *seed) override {
        uint64_t ticks=mach_absolute_time();
        long double rate=static_cast<long double>(timebase.numer)/timebase.denom;
        uint64_t frame=uint64_t(static_cast<long double>(ticks)*rate*48000.0L/1.0e9L)/512*512;
        *sample=double(frame);*host=uint64_t(static_cast<long double>(frame)*1.0e9L/48000.0L/rate);
        *seed=1;return noErr;
    }
};
std::shared_ptr<aspl::Driver> createDriver() {
    auto tracer=std::make_shared<aspl::Tracer>(aspl::Tracer::Mode::Noop);
    auto context=std::make_shared<aspl::Context>(tracer);
    aspl::DeviceParameters params;
    params.Name="Intensity Shuttle — Stereo Audio";params.Manufacturer="Local development build";
    params.DeviceUID="local.shuttle.audio.stereo";params.ModelUID="local.shuttle.audio";
    params.SampleRate=48000;params.ChannelCount=2;params.Latency=DelayFrames;
    params.ZeroTimeStampPeriod=512;params.CanBeDefaultForSystemSounds=false;
    auto device=std::make_shared<AudioDevice>(context,params);
    aspl::StreamParameters stream;
    stream.Direction=aspl::Direction::Input;
    stream.Format={48000,kAudioFormatLinearPCM,kAudioFormatFlagIsFloat|kAudioFormatFlagIsPacked,8,1,8,2,32,0};
    device->AddStreamAsync(stream);
    auto handler=std::make_shared<AudioInput>();
    device->SetControlHandler(handler);device->SetIOHandler(handler);
    auto plugin=std::make_shared<aspl::Plugin>(context);plugin->AddDevice(device);
    aspl::DeviceParameters outputParams;
    outputParams.Name="Intensity Shuttle — HDMI Audio";outputParams.Manufacturer="Local development build";
    outputParams.DeviceUID="local.shuttle.audio.hdmi";outputParams.ModelUID="local.shuttle.audio.hdmi";
    outputParams.SampleRate=48000;outputParams.ChannelCount=2;outputParams.Latency=shuttle_output_audio::OutputLatencyFrames;
    outputParams.ZeroTimeStampPeriod=512;outputParams.CanBeDefaultForSystemSounds=false;
    auto output=std::make_shared<AudioDevice>(context,outputParams);
    aspl::StreamParameters outputStream;outputStream.Direction=aspl::Direction::Output;
    outputStream.Format={48000,kAudioFormatLinearPCM,kAudioFormatFlagIsFloat|kAudioFormatFlagIsPacked,8,1,8,2,32,0};output->AddStreamAsync(outputStream);
    auto outputHandler=std::make_shared<AudioOutput>();output->SetControlHandler(outputHandler);output->SetIOHandler(outputHandler);plugin->AddDevice(output);
    return std::make_shared<aspl::Driver>(context,plugin);
}
} // namespace
extern "C" void *ShuttleAudioEntryPoint(CFAllocatorRef,CFUUIDRef type) {
    if(!CFEqual(type,kAudioServerPlugInTypeUUID)) return nullptr;
    static auto driver=createDriver();return driver->GetReference();
}
