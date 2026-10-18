// GPL-2.0-or-later. Offline OutputHost tests: every Core Audio call and every
// preferences access is replaced. No NSApplication, helper or audio I/O starts.
// Build from the workspace:
// xcrun clang++ -std=c++14 -fobjc-arc -Wno-deprecated-declarations \
//   -mmacosx-version-min=27.0 tools/audio_route_test.mm -framework Cocoa \
//   -framework CoreMediaIO -framework SystemExtensions -o /private/tmp/shuttle-audio-route-test
// /private/tmp/shuttle-audio-route-test
#import <Cocoa/Cocoa.h>
#import <CoreAudio/CoreAudio.h>
#import <objc/runtime.h>
#include <cassert>
#include <vector>

static AudioDeviceID fakeCurrent=10;
static bool fakePriorAvailable=true,fakeHDMIAvailable=true;
static bool fakeReadFailure=false,fakeWriteFailure=false,fakeChangeDuringRestore=false;
static std::vector<AudioDeviceID> fakeWrites;
static AudioObjectPropertyListenerBlock fakeListener;
static NSString* FakeUID(AudioDeviceID device) {
    return device==10?@"fake.speakers":device==20?@"local.shuttle.audio.hdmi":@"fake.headphones";
}
static OSStatus FakeGet(AudioObjectID device,const AudioObjectPropertyAddress* address,
    UInt32 qualifierBytes,const void* qualifier,UInt32* bytes,void* data) {
    switch(address->mSelector) {
        case kAudioHardwarePropertyDefaultOutputDevice:
            if(fakeReadFailure)return -1;
            *(AudioDeviceID*)data=fakeCurrent;return 0;
        case kAudioHardwarePropertyTranslateUIDToDevice: {
            NSString* uid=(__bridge NSString*)*(CFStringRef*)qualifier;
            *(AudioDeviceID*)data=[uid isEqual:@"local.shuttle.audio.hdmi"]&&fakeHDMIAvailable?20:
                [uid isEqual:@"fake.speakers"]&&fakePriorAvailable?10:[uid isEqual:@"fake.headphones"]?30:0;
            if(fakeChangeDuringRestore&&[uid isEqual:@"fake.speakers"])fakeCurrent=30;
            return 0;
        }
        case kAudioDevicePropertyDeviceIsAlive:*(UInt32*)data=1;return 0;
        case kAudioDevicePropertyDeviceUID:
        case kAudioObjectPropertyName: {
            NSString* value=address->mSelector==kAudioDevicePropertyDeviceUID?FakeUID(device):
                device==10?@"FAKE speakers":device==20?@"FAKE Shuttle HDMI":@"FAKE headphones";
            *(CFStringRef*)data=(CFStringRef)CFRetain((__bridge CFStringRef)value);return 0;
        }
    }
    assert(false&&"Unexpected Core Audio read");return -1;
}
static OSStatus FakeSize(AudioObjectID device,const AudioObjectPropertyAddress* address,
    UInt32 qualifierBytes,const void* qualifier,UInt32* bytes) {
    assert(address->mSelector==kAudioDevicePropertyStreams);*bytes=sizeof(AudioStreamID);return 0;
}
static OSStatus FakeSettable(AudioObjectID device,const AudioObjectPropertyAddress* address,Boolean* writable) {
    assert(address->mSelector==kAudioHardwarePropertyDefaultOutputDevice);*writable=true;return 0;
}
static OSStatus FakeSet(AudioObjectID device,const AudioObjectPropertyAddress* address,
    UInt32 qualifierBytes,const void* qualifier,UInt32 bytes,const void* data) {
    // Any attempted alert/input write fails this test immediately.
    assert(address->mSelector==kAudioHardwarePropertyDefaultOutputDevice);
    assert(address->mScope==kAudioObjectPropertyScopeGlobal);
    if(fakeWriteFailure)return -2;
    fakeCurrent=*(const AudioDeviceID*)data;fakeWrites.push_back(fakeCurrent);return 0;
}
static OSStatus FakeAdd(AudioObjectID device,const AudioObjectPropertyAddress* address,
    dispatch_queue_t queue,AudioObjectPropertyListenerBlock listener) {
    assert(address->mSelector==kAudioHardwarePropertyDefaultOutputDevice);fakeListener=[listener copy];return 0;
}
static OSStatus FakeRemove(AudioObjectID device,const AudioObjectPropertyAddress* address,
    dispatch_queue_t queue,AudioObjectPropertyListenerBlock listener) {fakeListener=nil;return 0;}

@interface FakePrefs:NSObject
@property NSMutableDictionary* values;
@property BOOL saveSucceeds;
@end
@implementation FakePrefs
- (id)init{if((self=[super init])){self.values=[NSMutableDictionary dictionary];self.saveSucceeds=YES;}return self;}
- (NSString*)stringForKey:(NSString*)key{return self.values[key];}
- (void)setObject:(id)value forKey:(NSString*)key{self.values[key]=value;}
- (void)removeObjectForKey:(NSString*)key{[self.values removeObjectForKey:key];}
- (BOOL)synchronize{return self.saveSucceeds;}
@end
static FakePrefs* fakePrefs;
static id FakeStandardDefaults(id object,SEL selector){return fakePrefs;}

// Headers are already imported, so these redirect only implementation calls.
#define AudioObjectGetPropertyData FakeGet
#define AudioObjectGetPropertyDataSize FakeSize
#define AudioObjectIsPropertySettable FakeSettable
#define AudioObjectSetPropertyData FakeSet
#define AudioObjectAddPropertyListenerBlock FakeAdd
#define AudioObjectRemovePropertyListenerBlock FakeRemove
#define main OutputHostUnusedMain
#include "../src/output/OutputHost.mm"
#undef main

static void Reset() {
    fakeCurrent=10;fakePriorAvailable=fakeHDMIAvailable=true;
    fakeReadFailure=fakeWriteFailure=fakeChangeDuringRestore=false;
    fakeWrites.clear();fakeListener=nil;fakePrefs=[FakePrefs new];
}
static void ExternalSelection(AudioDeviceID device) {
    fakeCurrent=device;
    if(fakeListener){auto address=shuttle_audio_route::mediaOutputAddress();fakeListener(1,&address);}
}
int main(){@autoreleasepool {
    puts("OFFLINE TEST: Core Audio and preferences are fakes; no NSApplication or helper is launched.");
    Method method=class_getClassMethod(NSUserDefaults.class,@selector(standardUserDefaults));
    IMP original=method_setImplementation(method,(IMP)FakeStandardDefaults);
    NSNotification* quit=[NSNotification notificationWithName:NSApplicationWillTerminateNotification object:nil];

    Reset();OutputHost* host=[OutputHost new];[host beginAudioRouteMonitoring];assert(fakeWrites.empty());
    [host useHDMIAudio:nil];assert(fakeCurrent==20&&host.managesMediaAudio);
    assert([host.previousMediaAudioUID isEqual:@"fake.speakers"]);
    [host useHDMIAudio:nil];assert(fakeWrites.size()==1&&[host.previousMediaAudioUID isEqual:@"fake.speakers"]);
    [host stopOutput:nil];assert(fakeCurrent==10&&!host.managesMediaAudio&&!host.previousMediaAudioUID&&fakeWrites.size()==2);
    [host applicationWillTerminate:quit];

    Reset();host=[OutputHost new];[host beginAudioRouteMonitoring];[host useHDMIAudio:nil];
    ExternalSelection(30);assert(!host.managesMediaAudio&&!host.previousMediaAudioUID);
    ExternalSelection(20);[host stopOutput:nil];assert(fakeCurrent==20&&fakeWrites.size()==1);[host applicationWillTerminate:quit];

    Reset();host=[OutputHost new];[host useHDMIAudio:nil];fakePriorAvailable=false;
    [host stopOutput:nil];assert(fakeCurrent==20&&host.previousMediaAudioUID);
    fakePriorAvailable=true;[host restoreAudio:nil];assert(fakeCurrent==10&&!host.previousMediaAudioUID);

    Reset();fakePrefs.values[shuttle_audio_route::PreviousUIDPreference]=@"fake.speakers";fakeCurrent=20;
    host=[OutputHost new];[host beginAudioRouteMonitoring];assert(!host.managesMediaAudio&&fakeWrites.empty());
    [host applicationWillTerminate:quit];assert(fakeCurrent==20&&fakeWrites.empty());
    [host restoreAudio:nil];assert(fakeCurrent==10&&fakeWrites.size()==1);

    Reset();host=[OutputHost new];[host useHDMIAudio:nil];[host applicationWillTerminate:quit];assert(fakeCurrent==10&&fakeWrites.size()==2);
    Reset();host=[OutputHost new];fakeWriteFailure=true;[host useHDMIAudio:nil];assert(fakeCurrent==10&&!host.managesMediaAudio&&!host.previousMediaAudioUID&&fakeWrites.empty());
    Reset();host=[OutputHost new];fakeReadFailure=true;[host useHDMIAudio:nil];assert(fakeCurrent==10&&!host.previousMediaAudioUID&&fakeWrites.empty());
    Reset();host=[OutputHost new];fakeHDMIAvailable=false;[host useHDMIAudio:nil];assert(fakeCurrent==10&&fakeWrites.empty());
    Reset();host=[OutputHost new];fakePrefs.saveSucceeds=NO;[host useHDMIAudio:nil];assert(fakeCurrent==10&&!host.previousMediaAudioUID&&fakeWrites.empty());

    Reset();host=[OutputHost new];[host useHDMIAudio:nil];fakeCurrent=30;
    [host stopOutput:nil];assert(fakeCurrent==30&&!host.previousMediaAudioUID&&fakeWrites.size()==1);
    Reset();host=[OutputHost new];[host useHDMIAudio:nil];fakeChangeDuringRestore=true;
    [host stopOutput:nil];assert(fakeCurrent==30&&!host.previousMediaAudioUID&&fakeWrites.size()==1);
    Reset();host=[OutputHost new];[host useHDMIAudio:nil];[host restorePreviousAudio:@"FAKE helper exit" explicit:NO];assert(fakeCurrent==10&&fakeWrites.size()==2);

    method_setImplementation(method,original);
    puts("PASS: startup read-only; explicit dOut only; repeat-click preservation; Stop/helper-exit/quit restore; later choices preserved; missing-device retry; explicit crash recovery; read/write/persistence failures.");
}return 0;}
