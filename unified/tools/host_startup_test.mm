// GPL-2.0-or-later. OFFLINE regression coverage for the Final Cut sender startup.
// All NSTask, CMIO, Core Audio, defaults, and readiness timers are local fakes.
// No helper, USB transfer, device property write, audio route, or driver activation.
// Build: xcrun clang++ -std=c++14 -fobjc-arc -Wno-deprecated-declarations \
//   -mmacosx-version-min=27.0 tools/host_startup_test.mm -framework Cocoa \
//   -framework CoreMediaIO -framework CoreMedia -framework SystemExtensions \
//   -o /private/tmp/shuttle-host-startup-test
#import <Cocoa/Cocoa.h>
#import <CoreAudio/CoreAudio.h>
#import <CoreMediaIO/CoreMediaIO.h>
#import <CoreMedia/CoreMedia.h>
#include <cassert>
#include <cstdio>
#include <cstring>

static unsigned failures=0,audioWrites=0,cmioWrites=0,taskLaunches=0,taskTerminates=0;
static unsigned cmioReads=0,readsBeforeLaunch=0;
static bool helperStarted=false,launchShouldFail=false,devicePresent=false;
static bool wrongUID=false,multipleStreams=false;
static NSArray<NSString*>* publishedFormats;
static NSMutableArray<NSString*>* events;
static void Check(BOOL condition,NSString* detail) {
    printf("%s %s\n",condition?"PASS":"FAIL",detail.UTF8String);
    if(!condition)++failures;
}
static void CMIOReadEvent(void) {
    ++cmioReads;if(!helperStarted)++readsBeforeLaunch;[events addObject:@"enumerate"];
}
static OSStatus FakeAudioGet(AudioObjectID object,const AudioObjectPropertyAddress* address,
    UInt32 qualifierBytes,const void* qualifier,UInt32* bytes,void* value) {
    if(address->mSelector==kAudioHardwarePropertyDefaultOutputDevice){*(AudioDeviceID*)value=10;return 0;}
    if(address->mSelector==kAudioDevicePropertyDeviceUID||address->mSelector==kAudioObjectPropertyName){
        *(CFStringRef*)value=(CFStringRef)CFRetain(address->mSelector==kAudioDevicePropertyDeviceUID?CFSTR("offline.speakers"):CFSTR("Offline speakers"));return 0;
    }
    assert(false&&"Unexpected audio read");return -1;
}
static OSStatus FakeAudioSize(AudioObjectID,const AudioObjectPropertyAddress*,UInt32,const void*,UInt32*) {assert(false);return -1;}
static OSStatus FakeAudioSettable(AudioObjectID,const AudioObjectPropertyAddress*,Boolean*) {assert(false);return -1;}
static OSStatus FakeAudioSet(AudioObjectID,const AudioObjectPropertyAddress*,UInt32,const void*,UInt32,const void*) {++audioWrites;assert(false&&"Audio writes forbidden");return -1;}
static OSStatus FakeAudioAdd(AudioObjectID,const AudioObjectPropertyAddress*,dispatch_queue_t,AudioObjectPropertyListenerBlock) {return 0;}
static OSStatus FakeAudioRemove(AudioObjectID,const AudioObjectPropertyAddress*,dispatch_queue_t,AudioObjectPropertyListenerBlock) {return 0;}
static OSStatus FakeCMIOSize(CMIOObjectID object,const CMIOObjectPropertyAddress* address,UInt32,const void*,UInt32* bytes) {
    CMIOReadEvent();
    assert(object==kCMIOObjectSystemObject&&address->mSelector==kCMIOHardwarePropertyDevices);
    *bytes=devicePresent?sizeof(CMIOObjectID):0;return 0;
}
static OSStatus FakeCMIOGet(CMIOObjectID object,const CMIOObjectPropertyAddress* address,UInt32,const void*,UInt32 available,UInt32* bytes,void* value) {
    CMIOReadEvent();
    switch(address->mSelector){
        case kCMIOHardwarePropertyDevices:
            *bytes=devicePresent?sizeof(CMIOObjectID):0;
            if(devicePresent){assert(available>=sizeof(CMIOObjectID));*(CMIOObjectID*)value=77;}return 0;
        case kCMIODevicePropertyDeviceUID:
            assert(object==77);*(CFStringRef*)value=(CFStringRef)CFRetain(wrongUID?CFSTR("offline.other.camera"):CFSTR("local.shuttle.output.cmio"));*bytes=sizeof(CFStringRef);return 0;
        case kCMIODevicePropertyStreams:
            assert(object==77&&address->mScope==kCMIODevicePropertyScopeOutput);*(CMIOObjectID*)value=88;
            *bytes=multipleStreams?2*sizeof(CMIOObjectID):sizeof(CMIOObjectID);return 0;
        case kCMIOStreamPropertyFormatDescriptions: {
            assert(object==88);NSMutableArray* result=[NSMutableArray array];
            for(NSString* name in publishedFormats){
                CMVideoFormatDescriptionRef description=nullptr;
                NSDictionary* extensions=@{(__bridge NSString*)kCMFormatDescriptionExtension_FormatName:name};
                OSStatus status=CMVideoFormatDescriptionCreate(kCFAllocatorDefault,'2vuy',1920,1080,(__bridge CFDictionaryRef)extensions,&description);
                assert(status==0&&description);[result addObject:CFBridgingRelease(description)];
            }
            *(CFArrayRef*)value=(CFArrayRef)CFRetain((__bridge CFArrayRef)result);*bytes=sizeof(CFArrayRef);return 0;
        }
        default:assert(false&&"Unexpected CMIO read");return -1;
    }
}
static OSStatus FakeCMIOSet(CMIOObjectID,const CMIOObjectPropertyAddress*,UInt32,const void*,UInt32,const void*) {++cmioWrites;assert(false&&"CMIO writes forbidden");return -1;}

@interface StartupDefaults:NSObject
@property NSMutableDictionary* values;
+ (instancetype)standardUserDefaults;
@end
@implementation StartupDefaults
+ (instancetype)standardUserDefaults {static StartupDefaults* defaults;if(!defaults){defaults=[StartupDefaults new];defaults.values=[NSMutableDictionary dictionary];}return defaults;}
- (NSInteger)integerForKey:(NSString*)key{return [self.values[key] integerValue];}
- (BOOL)boolForKey:(NSString*)key{return [self.values[key] boolValue];}
- (NSString*)stringForKey:(NSString*)key{return self.values[key];}
- (void)setInteger:(NSInteger)value forKey:(NSString*)key{self.values[key]=@(value);}
- (void)setBool:(BOOL)value forKey:(NSString*)key{self.values[key]=@(value);}
- (void)setObject:(id)value forKey:(NSString*)key{self.values[key]=value;}
- (void)removeObjectForKey:(NSString*)key{[self.values removeObjectForKey:key];}
- (BOOL)synchronize{return YES;}
@end

@interface StartupTimer:NSObject
@property BOOL valid;
@property NSTimeInterval interval;
@property(copy) void (^block)(StartupTimer*);
+ (instancetype)scheduledTimerWithTimeInterval:(NSTimeInterval)interval repeats:(BOOL)repeats block:(void (^)(StartupTimer*))block;
- (void)invalidate;
- (void)fire;
@end
@implementation StartupTimer
+ (instancetype)scheduledTimerWithTimeInterval:(NSTimeInterval)interval repeats:(BOOL)repeats block:(void (^)(StartupTimer*))block {
    StartupTimer* timer=[StartupTimer new];timer.valid=YES;timer.interval=interval;timer.block=block;return timer;
}
- (void)invalidate{self.valid=NO;}
- (void)fire{if(self.valid&&self.block)self.block(self);}
@end

@interface StartupTask:NSObject
@property BOOL running;
@property NSURL* executableURL;
@property NSArray* arguments;
@property id standardOutput,standardError;
@property int terminationStatus;
@property(copy) void (^terminationHandler)(StartupTask*);
@end
@implementation StartupTask
- (BOOL)launchAndReturnError:(NSError**)error {
    ++taskLaunches;[events addObject:@"launch"];
    if(launchShouldFail){if(error)*error=[NSError errorWithDomain:@"OfflineStartupTest" code:123 userInfo:@{NSLocalizedDescriptionKey:@"Fake helper launch failure"}];return NO;}
    self.running=YES;helperStarted=true;return YES;
}
- (void)terminate {
    ++taskTerminates;[events addObject:@"terminate"];self.running=NO;helperStarted=false;self.terminationStatus=0;
    if(self.terminationHandler)self.terminationHandler(self);
}
- (void)waitUntilExit{assert(!self.running);}
@end

@interface StartupWindow:NSWindow
@end
@implementation StartupWindow
- (void)makeKeyAndOrderFront:(id)sender{}
- (void)orderFront:(id)sender{}
- (void)orderFrontRegardless{}
@end

#define AudioObjectGetPropertyData FakeAudioGet
#define AudioObjectGetPropertyDataSize FakeAudioSize
#define AudioObjectIsPropertySettable FakeAudioSettable
#define AudioObjectSetPropertyData FakeAudioSet
#define AudioObjectAddPropertyListenerBlock FakeAudioAdd
#define AudioObjectRemovePropertyListenerBlock FakeAudioRemove
#define CMIOObjectGetPropertyData FakeCMIOGet
#define CMIOObjectGetPropertyDataSize FakeCMIOSize
#define CMIOObjectSetPropertyData FakeCMIOSet
#define NSUserDefaults StartupDefaults
#define NSTask StartupTask
#define NSTimer StartupTimer
#define NSWindow StartupWindow
#define main ProductionOutputMain
#include "../src/output/OutputHost.mm"
#undef main
#undef NSWindow
#undef NSTimer
#undef NSTask
#undef NSUserDefaults

static OutputHost* NewHost(void) {
    OutputHost* host=[OutputHost new];host.embedded=YES;
    [host applicationDidFinishLaunching:[NSNotification notificationWithName:NSApplicationDidFinishLaunchingNotification object:NSApplication.sharedApplication]];
    // These test-owned windows are closed explicitly between scenarios. Avoid
    // AppKit's legacy extra release while ARC retains the controller property.
    host.window.releasedWhenClosed=NO;
    return host;
}
static void DrainMainQueue(void) {
    __block bool drained=false;dispatch_async(dispatch_get_main_queue(),^{drained=true;});
    while(!drained)[NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
}
static void Cleanup(OutputHost* host) {
    [host applicationWillTerminate:[NSNotification notificationWithName:NSApplicationWillTerminateNotification object:NSApplication.sharedApplication]];
    DrainMainQueue();[host.window close];
}
static void ResetScenario(void) {
    helperStarted=false;launchShouldFail=false;devicePresent=false;wrongUID=false;multipleStreams=false;publishedFormats=@[];
    cmioReads=0;readsBeforeLaunch=0;events=[NSMutableArray array];
    [[StartupDefaults standardUserDefaults].values removeAllObjects];
}
static void SelectTimeline(OutputHost* host) {
    [host.source selectItemAtIndex:2];[host sourceChanged:nil];[host.mode selectItemAtIndex:2];
}

int main(void){@autoreleasepool {
    puts("OFFLINE startup regression: all tasks, timers, CMIO, audio and preferences are fake; all windows stay hidden.");
    NSApplication.sharedApplication.activationPolicy=NSApplicationActivationPolicyAccessory;

    ResetScenario();OutputHost* first=NewHost();SelectTimeline(first);
    Check([first.start.title isEqual:@"Start Final Cut"],@"timeline source gives a specific Start action");
    Cleanup(first);OutputHost* relaunched=NewHost();
    Check(relaunched.source.indexOfSelectedItem==2,@"Final Cut source survives a fresh host instance");
    Check([relaunched.start.title isEqual:@"Start Final Cut"],@"relaunch retains timeline-specific Start action");
    Check(taskLaunches==0&&cmioReads==0,@"relaunch neither starts a helper nor enumerates CMIO");Cleanup(relaunched);

    ResetScenario();OutputHost* host=NewHost();SelectTimeline(host);unsigned before=taskLaunches;
    [host startOutput:nil];StartupTask* task=host.task;StartupTimer* timer=host.readinessTimer;
    Check(taskLaunches==before+1&&task.running,@"Start launches the fake sender immediately with no CMIO device present");
    Check([task.arguments isEqual:@[@"--sink",@"1080p25",@"live"]],@"timeline source launches the persistent matching-mode sink");
    Check(cmioReads==0&&[events.firstObject isEqual:@"launch"],@"helper launches before any CMIO readiness enumeration");
    Check(timer.valid&&timer.interval>0&&timer.interval<=0.2,@"readiness is checked asynchronously with a bounded periodic timer");
    Check(!host.start.enabled&&host.stop.enabled&&!host.mode.enabled&&!host.source.enabled,@"running controls prevent conflicting sources/formats");
    Check([host.readinessLabel.stringValue containsString:@"Starting"],@"initial status tells the user to wait before enabling Final Cut");
    [timer fire];
    Check(cmioReads>0&&readsBeforeLaunch==0,@"missing device is enumerated only after sender launch");
    Check(timer.valid&&![host.readinessLabel.stringValue hasPrefix:@"Ready"],@"missing driver does not advertise readiness");
    devicePresent=true;publishedFormats=@[@"1080p29.97"];[timer fire];
    Check(timer.valid&&![host.readinessLabel.stringValue hasPrefix:@"Ready"],@"a different singleton format cannot become Ready");
    publishedFormats=@[@"1080p25",@"1080p29.97"];[timer fire];
    Check(timer.valid&&![host.readinessLabel.stringValue hasPrefix:@"Ready"],@"an old multi-format device cannot become Ready");
    publishedFormats=@[@"1080p25"];[timer fire];
    Check(!timer.valid&&host.readinessTimer==nil&&[host.readinessLabel.stringValue hasPrefix:@"Ready for Final Cut"],@"only the matching published singleton enables the Ready instruction");
    Check(task.running,@"readiness never replaces or stops the active sender");
    Cleanup(host);

    ResetScenario();helperStarted=true;devicePresent=true;
    NSArray* names=@[@"576i50",@"1080i50",@"1080p25",@"480i59.94",@"1080i59.94",@"1080p29.97"];
    for(NSInteger mode=0;mode<6;++mode){
        publishedFormats=@[names[mode]];Check(timelineOutputReady(mode),[NSString stringWithFormat:@"ready check accepts matching singleton %@",names[mode]]);
        Check(!timelineOutputReady((mode+1)%6),[NSString stringWithFormat:@"ready check rejects %@ for another selected mode",names[mode]]);
    }
    Check(!timelineOutputReady(-1)&&!timelineOutputReady(6),@"invalid mode indexes cannot enumerate or report Ready");
    publishedFormats=@[];Check(!timelineOutputReady(2),@"empty format list is unavailable");
    publishedFormats=@[@"1080p25"];wrongUID=true;Check(!timelineOutputReady(2),@"another CMIO device UID cannot impersonate the Shuttle");
    wrongUID=false;multipleStreams=true;Check(!timelineOutputReady(2),@"ambiguous stream list is unavailable");helperStarted=false;

    ResetScenario();host=NewHost();SelectTimeline(host);[host startOutput:nil];timer=host.readinessTimer;task=host.task;before=taskTerminates;
    host.readinessDeadline=[NSDate dateWithTimeIntervalSinceNow:-1];[timer fire];DrainMainQueue();
    Check(taskTerminates==before+1&&!task.running&&host.task==nil,@"missing-driver deadline terminates and releases the fake sender");
    Check(!timer.valid&&host.readinessTimer==nil,@"timeout invalidates its asynchronous timer");
    Check(host.start.enabled&&host.mode.enabled&&host.source.enabled&&!host.stop.enabled,@"timeout restores idle controls");
    Check([host.log.string containsString:@"did not become ready"],@"timeout retains actionable missing-driver guidance in the log");Cleanup(host);

    ResetScenario();launchShouldFail=true;host=NewHost();SelectTimeline(host);before=taskLaunches;[host startOutput:nil];
    Check(taskLaunches==before+1&&host.task==nil&&host.readinessTimer==nil,@"launch failure leaves neither sender nor timer");
    Check(host.start.enabled&&host.mode.enabled&&host.source.enabled&&!host.stop.enabled,@"launch failure keeps controls available for retry");
    Check([host.readinessLabel.stringValue containsString:@"could not start"]&&[host.log.string containsString:@"Fake helper launch failure"],@"launch failure presents the actual error");
    Check(cmioReads==0,@"failed sender launch never enumerates CMIO");Cleanup(host);

    Check(audioWrites==0&&cmioWrites==0,@"all scenarios perform zero Core Audio and CMIO writes");
    ResetScenario();host=NewHost();[host.source selectItemAtIndex:3];[host sourceChanged:nil];
    before=taskLaunches;[host startOutput:nil];
    Check(taskLaunches==before+1&&[host.task.arguments[0] isEqual:@"--premiere"],@"Premiere starts a separate USB source without CMIO enumeration");
    Check(cmioReads==0&&![host.readinessLabel.stringValue containsString:@"Ready for Premiere"],@"Premiere is not ready merely because its process starts");
    [host handleOutputText:@"Premiere USB "];[host handleOutputText:@"ready — enable Mercury Transmit."];
    Check([host.readinessLabel.stringValue containsString:@"Ready for Premiere"]&&!host.readinessTimer,@"Premiere readiness requires physical USB completion, including split log chunks");Cleanup(host);
    printf("RESULT: %u failures; %u fake launches, %u fake terminations, zero real helpers or device writes.\n",failures,taskLaunches,taskTerminates);
    return failures?1:0;
}}
