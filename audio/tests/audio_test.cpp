// GPL-2.0-or-later. Exercise transport, PCM conversion, and input callback.
#include "../src/AudioDriver.cpp"
#include <cassert>
#include <chrono>
#include <cstdio>
int main() {
    const uint8_t zero[]={0,0,0},pos[]={255,255,127},neg[]={0,0,128};
    assert(shuttle_audio::pcm24(zero)==0);
    assert(shuttle_audio::pcm24(neg)==-1);
    assert(shuttle_audio::pcm24(pos)>0.999999f);
    shuttle_audio::Packet packet{};packet.hostNS=1000000000ULL;
    for(unsigned i=0;i<shuttle_audio::Frames;++i) { packet.samples[i*2]=0.25f;packet.samples[i*2+1]=-0.5f; }
    assert(shuttle_audio::valid(packet,sizeof(packet)));
    assert(!shuttle_audio::valid(packet,sizeof(packet)-1));
    packet.samples[0]=NAN;assert(!shuttle_audio::valid(packet,sizeof(packet)));packet.samples[0]=0.25f;
    auto driver=createDriver();auto device=driver->GetPlugin()->GetDeviceByIndex(0);
    assert(device->GetDeviceUID()=="local.shuttle.audio.stereo");
    assert(device->GetStreamCount(aspl::Direction::Input)==1);
    assert(device->GetStreamCount(aspl::Direction::Output)==0);
    auto stream=device->GetStreamByIndex(aspl::Direction::Input,0);
    assert(stream->GetSampleRate()==48000 && stream->GetChannelCount()==2);
    auto handler=std::make_shared<AudioInput>();
    for(unsigned pass=0;pass<2;++pass) {
        packet.hostNS=(pass+1)*1000000000ULL;
        assert(handler->OnStartIO()==noErr);
        int fd=socket(AF_INET,SOCK_DGRAM,0);assert(fd>=0);
        sockaddr_in a{};a.sin_len=sizeof(a);a.sin_family=AF_INET;a.sin_port=htons(shuttle_audio::Port);a.sin_addr.s_addr=htonl(INADDR_LOOPBACK);
        assert(sendto(fd,&packet,sizeof(packet),0,reinterpret_cast<sockaddr *>(&a),sizeof(a))==sizeof(packet));close(fd);
        float output[512]{};
        bool received=false;
        for(unsigned attempt=0;attempt<20;++attempt) {
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
            handler->OnReadClientInput(nullptr,stream,0,shuttle_audio::sampleAt(packet.hostNS)+DelayFrames,output,sizeof(output));
            if(output[0]==0.25f) { received=true;break; }
        }
        assert(received);
        for(unsigned i=0;i<256;++i) assert(output[i*2]==0.25f && output[i*2+1]==-0.5f);
        handler->OnReadClientInput(nullptr,stream,0,shuttle_audio::sampleAt(packet.hostNS)+DelayFrames+RingFrames,output,sizeof(output));
        for(float v:output) assert(v==0);
        handler->OnStopIO();
    }
    puts("PASS: signed PCM24, malformed packets, input-only 48 kHz stereo, exact channel separation, stale-data silence, transport restart");
}
