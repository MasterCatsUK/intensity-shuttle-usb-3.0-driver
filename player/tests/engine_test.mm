// GPL-2.0-or-later. Real decoding; no USB, camera, audio routing or private footage.
#import <Foundation/Foundation.h>
#include "../src/PlayerEngine.hpp"
#include <cassert>
#include <unistd.h>
static double peak(const std::vector<int32_t>& p){double v=0;for(auto x:p)v=std::max(v,std::abs(double(x)));return v;}
int main(int argc,const char**argv){@autoreleasepool{
    assert(argc==2);unsigned cases=0;
    NSString* path=[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"player-test-%@",NSUUID.UUID.UUIDString]];
    player::Mapping map(path.fileSystemRepresentation,true);player::Mapping client(path.fileSystemRepresentation,false);
    for(unsigned m=0;m<6;++m)for(unsigned fit=0;fit<3;++fit){
        player::Engine e(argv[1],shuttle_output::Mode(m),shuttle_output::Sizing(fit));auto p=shuttle_output::profile(shuttle_output::Mode(m));
        std::vector<uint8_t> image;std::vector<int32_t> audio;
        e.paused=true;e.command("seek 1.04");e.render(0,image,audio);
        assert(image.size()==size_t(p.width)*p.height*2);assert(peak(audio)==0);assert(std::abs(e.position()-1.04)<.05);
        auto frozen=image;e.render(1,image,audio);assert(image==frozen&&peak(audio)==0);
        e.command("pause 0");e.render(2,image,audio);assert(peak(audio)>1000000);
        auto full=peak(audio);e.command("volume .5");e.command("seek 1.04");e.render(3,image,audio);auto half=peak(audio);assert(half>100000&&std::abs(half/full-.5)<.03);
        e.command("volume 0");e.render(4,image,audio);assert(peak(audio)==0);
        e.command("seek 2");e.render(5,image,audio);unsigned y=image[(size_t(p.height/2)*p.width+p.width/2)*2+1];assert(y<40);
        e.command("seek 1.04");e.render(6,image,audio);y=image[(size_t(p.height/2)*p.width+p.width/2)*2+1];assert(y>220);
        // Stretch and Fill must reach both side edges; Fit of 4:3 onto HD has bars.
        unsigned edge=image[(size_t(p.height/2)*p.width+2)*2+1];assert((edge<25)==(fit==0&&p.width==1920));
        e.publish(map,image,audio);assert(client.lock());auto& latest=client.data->frames[(client.data->published-1)%player::PreviewFrames];assert(latest.width==640&&latest.height>300&&latest.generation==e.generation);assert(latest.pixels[(size_t(latest.height/2)*640+320)*4]>220);assert(client.data->rateNom==p.rateNom&&client.data->rateDen==p.rateDen);client.unlock();
        e.command("loop 0");e.command("seek 100000");e.render(7,image,audio);e.render(8,image,audio);assert(e.ended&&peak(audio)==0);
        e.command("pause 0");e.render(9,image,audio);assert(!e.ended&&e.position()<.05);
        e.command("loop 1");e.command("seek 100000");e.render(10,image,audio);e.render(11,image,audio);assert(!e.ended&&e.position()<.05);
        e.command("seek nan");e.command("seek -100");e.render(12,image,audio);assert(e.position()==0);
        e.command("volume inf");e.command("seek 4 garbage");e.command("stop");assert(e.stopping);
        for(unsigned n=0;n<40;++n){e.render(13+n,image,audio);assert(audio.size()==p.audioFrames(13+n)*8);}
        ++cases;
    }
    {
        player::Engine e(argv[1],shuttle_output::Mode::HD1080p25,shuttle_output::Sizing::Stretch,true);e.paused=true;
        std::vector<uint8_t> image;std::vector<int32_t> audio;e.command("seek 2");e.render(0,image,audio);e.command("seek 1.04");
        bool reached=false;for(unsigned n=1;n<400;++n){
            auto begin=std::chrono::steady_clock::now();e.render(n,image,audio);
            assert(std::chrono::steady_clock::now()-begin<std::chrono::milliseconds(100));
            if(std::abs(e.position()-1.04)<.02){reached=true;break;}usleep(5000);
        }
        assert(reached&&peak(audio)==0);assert(image[(540*1920+960)*2+1]>220);
        puts("PASS: background seek coalesces rapid requests and keeps the USB-side render nonblocking while paused.");
    }
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    printf("PASS: %u mode/scaling cases; real forward/back seeks, paused holds, resumed audio, gain/mute, end/replay/loop, whole-frame Stretch, fractional audio cadence and preview IPC.\n",cases);
}}
