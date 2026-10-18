// No devices or production preferences: synthetic audio markers + private suite.
#import <Foundation/Foundation.h>
#include "../src/output/AudioSyncPreference.hpp"
#include "../src/output/AudioCursor.hpp"
#include <cassert>
#include <unistd.h>
using namespace shuttle_output_audio;
static CFStringRef domain;
static int ReadPrivate(){return readOutputPreferences(domain);}
static void WriteSeparateProcess(NSString* executable,NSString* suite,int value,int position=5){
    NSTask* task=[NSTask new];task.executableURL=[NSURL fileURLWithPath:executable];task.arguments=@[@"--write",suite,[NSString stringWithFormat:@"%d",value],[NSString stringWithFormat:@"%d",position+1]];
    NSError* error=nil;assert([task launchAndReturnError:&error]);[task waitUntilExit];assert(task.terminationStatus==0);
}
int main(int argc,char**argv){@autoreleasepool{
    if(argc==5&&!strcmp(argv[1],"--write")){
        auto* defaults=[[NSUserDefaults alloc] initWithSuiteName:@(argv[2])];
        [defaults setInteger:atoi(argv[3]) forKey:@"HDMIAudioOffsetMS"];[defaults setBool:atoi(argv[3])!=0 forKey:@"ShowHDMITimecode"];[defaults setInteger:atoi(argv[4]) forKey:@"HDMITimecodePosition"];
        [defaults setBool:atoi(argv[3])!=0 forKey:@"ShowHDMIAudioMeters"];[defaults setInteger:atoi(argv[4]) forKey:@"HDMIAudioMeterPosition"];
        [defaults setBool:(abs(atoi(argv[3]))&1)!=0 forKey:@"ShowHDMITitleSafe"];[defaults setBool:(abs(atoi(argv[3]))&2)!=0 forKey:@"ShowHDMIActionSafe"];return [defaults synchronize]?0:1;
    }
    assert(offsetAudioSample(480000,-40)==481920); // play the later marker earlier
    assert(offsetAudioSample(480000,40)==478080);  // delay by selecting older sound
    assert(offsetAudioSample(480000,0)==480000);
    assert(offsetAudioSample(1,500)==0&&offsetAudioSample(UINT64_MAX,-100)==UINT64_MAX);
    assert(clampAudioOffset(-1000)==-100&&clampAudioOffset(1000)==500);
    for(auto rate:{25u,30000u}){
        unsigned den=rate==25?1:1001;AudioCursor cursor;uint64_t previous=0,total=0;
        for(unsigned f=0;f<1000;++f){
            uint64_t begin=uint64_t(f)*48000*den/rate,end=uint64_t(f+1)*48000*den/rate;
            uint64_t pts=10000000000ULL+uint64_t(f)*1000000000ULL*den/rate,first=0;
            assert(cursor.take(true,pts,1,unsigned(end-begin),rate,den,first));
            if(f)assert(first==previous);previous=first+end-begin;total+=end-begin;
            for(int offset:{-100,-40,0,40,500}){
                uint64_t adjusted=offsetAudioSample(first,offset);
                assert(__int128(adjusted)==__int128(first)-int64_t(offset)*48);
                // Offset does not alter cadence or create frame rounding gaps.
                assert(offsetAudioSample(first+end-begin,offset)-adjusted==end-begin);
            }
        }
        assert(total==uint64_t(1000)*48000*den/rate);
    }
    NSString* suite=[NSString stringWithFormat:@"local.shuttle.test.audio-sync.%d",getpid()];
    domain=(__bridge CFStringRef)suite;
    ReadPrivate();assert(timecodeOverlayPosition==5); // migrate old unset preference
    assert(!audioMetersEnabled&&audioMetersPosition==2);
    assert(!titleSafeEnabled&&!actionSafeEnabled);
    {LiveAudioOffset live(0,ReadPrivate);
        NSString* executable=[NSURL fileURLWithPath:@(argv[0])].URLByStandardizingPath.path;
        for(int target:{-40,70,0}){
            WriteSeparateProcess(executable,suite,target);
            auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(3);
            while(live.milliseconds()!=target&&std::chrono::steady_clock::now()<deadline)std::this_thread::sleep_for(std::chrono::milliseconds(20));
            assert(live.milliseconds()==target);
            assert(timecodeOverlayEnabled.load()==(target!=0));
            assert(audioMetersEnabled.load()==(target!=0));
            assert(titleSafeEnabled.load()==((abs(target)&1)!=0)&&actionSafeEnabled.load()==((abs(target)&2)!=0));
        }
        for(int position=0;position<6;++position){
            int target=50+position;WriteSeparateProcess(executable,suite,target,position);
            auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(3);
            while(live.milliseconds()!=target&&std::chrono::steady_clock::now()<deadline)std::this_thread::sleep_for(std::chrono::milliseconds(20));
            assert(live.milliseconds()==target&&timecodeOverlayPosition.load()==unsigned(position));
            assert(audioMetersPosition.load()==unsigned(position));
            assert(titleSafeEnabled.load()==((abs(target)&1)!=0)&&actionSafeEnabled.load()==((abs(target)&2)!=0));
        }
    }
    auto* defaults=[[NSUserDefaults alloc] initWithSuiteName:suite];[defaults removePersistentDomainForName:suite];[defaults synchronize];
    puts("PASS: earlier/later marker direction, sample-accurate PAL/NTSC offsets and continuous cadence, clamping/overflow, cross-process saved/live preference propagation and Reset");
    return 0;
}}
