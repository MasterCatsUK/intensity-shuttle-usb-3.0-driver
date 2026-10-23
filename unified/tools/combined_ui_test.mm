// GPL-2.0-or-later. Headless embedded AppKit hit-test/target lifetime check.
// No production action is clicked. Audio, CMIO, preferences and NSTask calls
// in the included app sources are fakes; windows never order on screen.
// Build: xcrun clang++ -std=c++14 -fobjc-arc -Wno-deprecated-declarations \
//   -mmacosx-version-min=27.0 tools/combined_ui_test.mm -framework Cocoa \
//   -framework CoreMediaIO -framework SystemExtensions -Wl,-e,_CombinedUITestMain \
//   -o /private/tmp/shuttle-combined-ui-test
// Run: /private/tmp/shuttle-combined-ui-test ['/Applications/Shuttle Camera.app']
#import <Cocoa/Cocoa.h>
#import <CoreAudio/CoreAudio.h>
#import <CoreMediaIO/CoreMediaIO.h>
#import <objc/runtime.h>
#include <cassert>
#include <cstdio>

static unsigned failures=0,audioWrites=0,cmioWrites=0,taskLaunches=0;
static AudioObjectPropertyListenerBlock testListener;
static OSStatus TestAudioGet(AudioObjectID object,const AudioObjectPropertyAddress* address,
    UInt32 qualifierBytes,const void* qualifier,UInt32* bytes,void* value) {
    if(address->mSelector==kAudioHardwarePropertyDefaultOutputDevice){*(AudioDeviceID*)value=10;return 0;}
    if(address->mSelector==kAudioDevicePropertyDeviceUID||address->mSelector==kAudioObjectPropertyName){
        CFStringRef string=address->mSelector==kAudioDevicePropertyDeviceUID?CFSTR("offline.fake.output"):CFSTR("FAKE speakers");
        *(CFStringRef*)value=(CFStringRef)CFRetain(string);return 0;
    }
    if(address->mSelector==kAudioHardwarePropertyDevices){*(AudioDeviceID*)value=10;*bytes=sizeof(AudioDeviceID);return 0;}
    if(address->mSelector==kAudioDevicePropertyDeviceIsAlive){*(UInt32*)value=1;return 0;}
    assert(false&&"Unexpected audio read in UI construction");return -1;
}
static OSStatus TestAudioSize(AudioObjectID,const AudioObjectPropertyAddress* a,UInt32,const void*,UInt32* size) {
    if(a->mSelector==kAudioHardwarePropertyDevices||a->mSelector==kAudioDevicePropertyStreams){*size=sizeof(AudioDeviceID);return 0;}assert(false);return -1;
}
static OSStatus TestAudioSettable(AudioObjectID,const AudioObjectPropertyAddress*,Boolean*) {assert(false);return -1;}
static OSStatus TestAudioSet(AudioObjectID,const AudioObjectPropertyAddress*,UInt32,const void*,UInt32,const void*) {++audioWrites;assert(false&&"No route actions allowed");return -1;}
static OSStatus TestAudioAdd(AudioObjectID,const AudioObjectPropertyAddress*,dispatch_queue_t,AudioObjectPropertyListenerBlock block) {testListener=[block copy];return 0;}
static OSStatus TestAudioRemove(AudioObjectID,const AudioObjectPropertyAddress*,dispatch_queue_t,AudioObjectPropertyListenerBlock) {testListener=nil;return 0;}
static CFStringRef testCameraJSON=nullptr;
static bool permitSettingsWrite=false;static OSStatus settingsWriteResult=0;static NSString *writtenSettings;
static OSStatus TestCMIOSize(CMIOObjectID,const CMIOObjectPropertyAddress*,UInt32,const void*,UInt32* bytes) {*bytes=testCameraJSON?sizeof(CMIOObjectID):0;return 0;}
static OSStatus TestCMIOGet(CMIOObjectID,const CMIOObjectPropertyAddress* a,UInt32,const void*,UInt32,UInt32* bytes,void* value) {
    if(!testCameraJSON){*bytes=0;return 0;}
    if(a->mSelector==kCMIOHardwarePropertyDevices){*(CMIOObjectID*)value=123;*bytes=sizeof(CMIOObjectID);return 0;}
    CFStringRef text=a->mSelector==kCMIODevicePropertyDeviceUID?CFSTR("local.shuttle.camera.pal"):testCameraJSON;
    *(CFStringRef*)value=(CFStringRef)CFRetain(text);*bytes=sizeof(CFStringRef);return 0;
}
static OSStatus TestCMIOSet(CMIOObjectID,const CMIOObjectPropertyAddress*,UInt32,const void*,UInt32,const void* value) {++cmioWrites;assert(permitSettingsWrite&&"No production CMIO actions allowed");if(!settingsWriteResult){writtenSettings=[(__bridge NSString*)*(CFStringRef*)value copy];testCameraJSON=(__bridge CFStringRef)writtenSettings;}return settingsWriteResult;}

@interface UITestDefaults:NSObject
@property NSMutableDictionary* values;
+ (instancetype)standardUserDefaults;
@end
@implementation UITestDefaults
+ (instancetype)standardUserDefaults {static UITestDefaults* defaults;if(!defaults){defaults=[UITestDefaults new];defaults.values=[NSMutableDictionary dictionary];}return defaults;}
- (NSInteger)integerForKey:(NSString*)key{return [self.values[key] integerValue];}
- (double)doubleForKey:(NSString*)key{return [self.values[key] doubleValue];}
- (void)setDouble:(double)value forKey:(NSString*)key{self.values[key]=@(value);}
- (BOOL)boolForKey:(NSString*)key{return [self.values[key] boolValue];}
- (NSString*)stringForKey:(NSString*)key{return self.values[key];}
- (id)objectForKey:(NSString*)key{return self.values[key];}
- (void)setInteger:(NSInteger)value forKey:(NSString*)key{self.values[key]=@(value);}
- (void)setBool:(BOOL)value forKey:(NSString*)key{self.values[key]=@(value);}
- (void)setObject:(id)value forKey:(NSString*)key{self.values[key]=value;}
- (void)removeObjectForKey:(NSString*)key{[self.values removeObjectForKey:key];}
- (BOOL)synchronize{return YES;}
@end

@interface UITestTask:NSObject
@property BOOL running;
@property NSURL* executableURL;
@property NSArray* arguments;
@property id standardInput,standardOutput,standardError;
- (void)interrupt;
@property int terminationStatus;
@property(copy) void (^terminationHandler)(UITestTask*);
@end
@implementation UITestTask
- (void)interrupt{self.running=NO;}
- (BOOL)launchAndReturnError:(NSError**)error{++taskLaunches;assert(false&&"No helper launch allowed");return NO;}
- (void)terminate{assert(false&&"No task exists in this UI test");}
- (void)waitUntilExit{assert(false&&"No task exists in this UI test");}
@end

static NSHashTable* testWindows;
@interface UITestWindow:NSWindow
@end
@implementation UITestWindow
- (instancetype)initWithContentRect:(NSRect)rect styleMask:(NSWindowStyleMask)mask backing:(NSBackingStoreType)backing defer:(BOOL)defer {
    if((self=[super initWithContentRect:rect styleMask:mask backing:backing defer:defer]))[testWindows addObject:self];return self;
}
- (void)makeKeyAndOrderFront:(id)sender{} // Hidden in this test, not production.
- (void)orderFront:(id)sender{}
- (void)orderFrontRegardless{}
@end
static NSMutableArray<NSURL*> *openedMovies;
@interface UITestWorkspace:NSObject
+ (instancetype)sharedWorkspace;
- (BOOL)openURL:(NSURL*)url;
@end
@implementation UITestWorkspace
+ (instancetype)sharedWorkspace {static UITestWorkspace *w;if(!w)w=[UITestWorkspace new];return w;}
- (BOOL)openURL:(NSURL*)url {if(!openedMovies)openedMovies=[NSMutableArray array];[openedMovies addObject:url];return YES;}
@end
static void IgnoreActivation(id object,SEL selector,BOOL flag){}

#define AudioObjectGetPropertyData TestAudioGet
#define AudioObjectGetPropertyDataSize TestAudioSize
#define AudioObjectIsPropertySettable TestAudioSettable
#define AudioObjectSetPropertyData TestAudioSet
#define AudioObjectAddPropertyListenerBlock TestAudioAdd
#define AudioObjectRemovePropertyListenerBlock TestAudioRemove
#define CMIOObjectGetPropertyData TestCMIOGet
#define CMIOObjectGetPropertyDataSize TestCMIOSize
#define CMIOObjectSetPropertyData TestCMIOSet
#define NSUserDefaults UITestDefaults
#define NSTask UITestTask
#define NSWindow UITestWindow
#define NSWorkspace UITestWorkspace
#include "../src/CombinedHost.mm"
#undef NSWindow
#undef NSWorkspace
#undef NSTask
#undef NSUserDefaults

static bool IsDescendant(NSView* view,NSView* ancestor) {
    for(NSView* current=view;current;current=current.superview)if(current==ancestor)return true;
    return false;
}
static void Check(BOOL condition,NSString* detail) {
    printf("%s %s\n",condition?"PASS":"FAIL",detail.UTF8String);if(!condition)++failures;
}
static NSButton* FindButton(NSView* root,NSString* title) {
    if([root isKindOfClass:NSButton.class]&&[[(NSButton*)root title] isEqual:title])return (NSButton*)root;
    for(NSView* child in root.subviews){NSButton* button=FindButton(child,title);if(button)return button;}return nil;
}
static void CheckControl(NSView* root,NSControl* control,id target,SEL action,NSString* title) {
    Check(control!=nil,[title stringByAppendingString:@" exists"]);if(!control)return;
    NSPoint point=[control convertPoint:NSMakePoint(NSMidX(control.bounds),NSMidY(control.bounds)) toView:root];
    NSView* hit=[root hitTest:point];
    printf("  %s center=(%.1f,%.1f), hit=%s, frame=%s, visible=%s, enabled=%d, target=%s, action=%s\n",
        title.UTF8String,point.x,point.y,NSStringFromClass(hit.class).UTF8String,
        NSStringFromRect(control.frame).UTF8String,NSStringFromRect(control.visibleRect).UTF8String,
        control.enabled,NSStringFromClass([control.target class]).UTF8String,NSStringFromSelector(control.action).UTF8String);
    Check(IsDescendant(hit,control),[title stringByAppendingString:@" receives its center hit"]);
    Check(control.window==root.window,[title stringByAppendingString:@" belongs to the combined window"]);
    Check(!control.hiddenOrHasHiddenAncestor,[title stringByAppendingString:@" has no hidden ancestor"]);
    Check(control.target==target&&control.action==action,[title stringByAppendingString:@" retains the intended target/action"]);
    if(action)Check([target respondsToSelector:action],[title stringByAppendingString:@" target responds"]);
}
static void CheckOutput(CombinedHost* host,NSString* phase) {
    puts(phase.UTF8String);NSView* root=host.window.contentView;OutputHost* output=host.output;
    [root layoutSubtreeIfNeeded];
    Check(host.output.window==host.window&&host.capture.window==host.window,@"both embedded controllers point to the combined window");
    CheckControl(root,output.mode,nil,nullptr,@"Output format");
    CheckControl(root,output.source,output,@selector(sourceChanged:),@"Source");
    if(output.source.indexOfSelectedItem==1)CheckControl(root,output.choose,output,@selector(chooseMovie:),@"Choose movie");else Check(output.choose.hidden&&output.loop.hidden,@"movie controls hidden for other sources");
    CheckControl(root,output.start,output,@selector(startOutput:),@"Start output");
    CheckControl(root,output.stop,output,@selector(stopOutput:),@"Stop output");
    if(output.source.indexOfSelectedItem==1)CheckControl(root,output.loop,nil,nullptr,@"Loop movie");
    CheckControl(root,output.useHDMIAudio,output,@selector(useHDMIAudio:),@"Use Shuttle Audio");
    CheckControl(root,output.restoreAudio,output,@selector(restoreAudio:),@"Restore audio");
    CheckControl(root,FindButton(root,@"Sound settings…"),output,@selector(openAudioSettings:),@"Sound settings");
    Check(![output.log isDescendantOf:root],@"diagnostic log is not on the main window");
    auto* applicationMenu=[NSApp.mainMenu itemAtIndex:0].submenu;
    Check([applicationMenu itemWithTitle:@"About Shuttle Video"].action==@selector(showAbout:),@"About app menu action available");
    auto* quit=[applicationMenu itemWithTitle:@"Quit Shuttle Video"];Check(quit.action==@selector(terminate:)&&[quit.keyEquivalent isEqual:@"q"]&&quit.target==NSApp,@"Quit uses normal application cleanup and Command-Q");
    Check(output.start.enabled&&output.useHDMIAudio.enabled,@"Start and Use Shuttle Audio are enabled while idle");
    Check(!output.stop.enabled&&!output.restoreAudio.enabled,@"Stop/Restore are correctly disabled before any action");
    Check(output.task==nil,@"no task was constructed or launched");
}
// Keep the production main compiled and untouched. The test executable's
// explicit linker entry point calls this function instead.
extern "C" int CombinedUITestMain(int argc,char** argv){@autoreleasepool {
    puts("OFFLINE UI TEST: hidden accessory NSApp; fake audio/CMIO/defaults/NSTask; no button actions clicked.");
    NSApplication* app=NSApplication.sharedApplication;app.activationPolicy=NSApplicationActivationPolicyAccessory;
    Method activate=class_getInstanceMethod(NSApplication.class,@selector(activateIgnoringOtherApps:));
    IMP originalActivate=method_setImplementation(activate,(IMP)IgnoreActivation);
    testWindows=[NSHashTable weakObjectsHashTable];
    CombinedHost* host=[CombinedHost new];__weak OutputHost* weakOutput=nil;__weak NSButton* weakStart=nil;
    @autoreleasepool {
        [host applicationDidFinishLaunching:[NSNotification notificationWithName:NSApplicationDidFinishLaunchingNotification object:app]];
        weakOutput=host.output;weakStart=host.output.start;
        CheckControl(host.window.contentView,host.outputButton,host,@selector(showOutput:),@"Video Output tab");
        CheckControl(host.window.contentView,host.captureButton,host,@selector(showCapture:),@"Capture tab");
        testCameraJSON=CFSTR("{\"standard\":\"PAL\",\"video_input\":\"S-Video\",\"audio_input\":\"Analog RCA\",\"dropout\":\"Hold last frame\",\"output_size\":\"Native\"}");[host.capture refresh:nil];
        Check(!host.capture.brightness.enabled&&!host.capture.pictureApply.enabled&&!host.capture.enablePicture.hidden,@"old camera driver disables picture controls and exposes activation button");
        testCameraJSON=CFSTR("{\"standard\":\"PAL\",\"video_input\":\"S-Video\",\"audio_input\":\"Analog RCA\",\"dropout\":\"Hold last frame\",\"output_size\":\"Native\",\"brightness\":0,\"contrast\":100,\"colour\":100,\"sharpness\":0}");[host.capture refresh:nil];
        Check(host.capture.brightness.enabled&&host.capture.pictureApply.enabled&&!host.capture.livePicture.enabled&&!host.capture.enablePicture.hidden,@"driver16 allows saved controls but explains that live controls need updating");
        testCameraJSON=CFSTR("{\"standard\":\"PAL\",\"video_input\":\"S-Video\",\"audio_input\":\"Analog RCA\",\"dropout\":\"Hold last frame\",\"output_size\":\"Native\",\"brightness\":0,\"contrast\":100,\"colour\":100,\"sharpness\":0,\"picture_live\":true}");[host.capture refresh:nil];
        host.capture.livePicture.enabled=NO;host.capture.enablePicture.hidden=NO;
        [host.capture.standard selectItemWithTitle:@"NTSC"];[host showPicture:nil];
        Check(host.capture.livePicture.enabled&&host.capture.enablePicture.hidden&&[host.capture.standard.titleOfSelectedItem isEqual:@"NTSC"],@"Picture tab refreshes stale capability without discarding unapplied input settings");
        host.capture.enablePicture.hidden=NO;[host.capture activate:host.capture.enablePicture];
        Check(host.capture.enablePicture.hidden&&[host.capture.status.stringValue containsString:@"already enabled"],@"stale Enable action returns without submitting a driver replacement");
        [host.capture.standard selectItemWithTitle:@"PAL"];
        Check(host.capture.livePicture.enabled&&host.capture.pictureApply.enabled&&host.capture.enablePicture.hidden,@"driver17 enables live controls and hides activation button");
        [host showPicture:nil];
        CheckControl(host.window.contentView,host.capture.brightness,host.capture,@selector(pictureChanged:),@"Input brightness");
        CheckControl(host.window.contentView,host.capture.sharpness,host.capture,@selector(pictureChanged:),@"Input sharpness");
        CFStringRef healthy=testCameraJSON;
        testCameraJSON=CFSTR("{\"standard\":\"PAL\",\"video_input\":\"S-Video\",\"audio_input\":\"Analog RCA\",\"dropout\":\"Hold last frame\",\"output_size\":\"1440x1080\",\"brightness\":0,\"contrast\":100,\"colour\":100,\"sharpness\":0,\"picture_live\":true}");
        [host.capture refresh:nil];Check(host.capture.resolution.indexOfSelectedItem==3,@"active 1440 resolution is displayed and cached");
        testCameraJSON=nullptr;[host.capture refresh:nil];Check(host.capture.resolution.indexOfSelectedItem==3&&host.capture.settingsRetry!=nil,@"temporary device disappearance retains resolution and schedules bounded retry");
        Check([[[UITestDefaults standardUserDefaults] objectForKey:@"LastKnownCaptureSettings"][@"output_size"] isEqual:@"1440x1080"],@"transient read failure does not overwrite the known saved resolution");
        testCameraJSON=healthy;[host.capture.resolution selectItemAtIndex:2];[host.capture selectionChanged:host.capture.resolution];[host.capture refresh:nil];Check(host.capture.resolution.indexOfSelectedItem==2,@"automatic retry preserves an unapplied resolution draft");
        [host.capture refresh:host.capture.resolution];Check(host.capture.resolution.indexOfSelectedItem==0&&host.capture.settingsRetry==nil,@"explicit Refresh loads actual settings and cancels retry");
        Check(host.capture.resolution.numberOfItems==8&&host.capture.aspect.numberOfItems==2,@"capture offers eight sizes and independent aspect choice");
        [host.capture.standard selectItemWithTitle:@"PAL"];[host.capture.aspect selectItemAtIndex:1];[host.capture.resolution selectItemAtIndex:1];[host.capture selectionChanged:host.capture.aspect];
        Check([host.capture.resolution.titleOfSelectedItem containsString:@"1024"]&&[host.capture.formatLabel.stringValue containsString:@"16:9"],@"PAL anamorphic square pixels display 1024x576");
        [host.capture.standard selectItemWithTitle:@"NTSC"];[host.capture selectionChanged:host.capture.standard];Check([host.capture.resolution.titleOfSelectedItem containsString:@"854"],@"NTSC widescreen square pixels use even 854 width");
        [host.capture.resolution selectItemAtIndex:5];[host.capture.aspect selectItemAtIndex:0];[host.capture selectionChanged:host.capture.resolution];Check([host.capture.formatLabel.stringValue containsString:@"1920"]&&[host.capture.formatLabel.stringValue containsString:@"side bars"],@"1080p preserves 4:3 with side bars");
        [host.capture.resolution selectItemAtIndex:7];[host.capture selectionChanged:host.capture.resolution];Check(host.capture.fieldOrder.enabled&&[host.capture.formatLabel.stringValue containsString:@"29.97 fps / 59.94i"]&&[host.capture.resolution.titleOfSelectedItem containsString:@"1080i59.94"],@"NTSC interlace reports frame and field rates and enables field order");
        [host.capture.standard selectItemWithTitle:@"PAL"];[host.capture.resolution selectItemAtIndex:6];[host.capture selectionChanged:host.capture.standard];Check([host.capture.resolution.titleOfSelectedItem containsString:@"576i50"]&&[host.capture.formatLabel.stringValue containsString:@"25 fps / 50i"],@"PAL native interlace is distinct from bob-progressive");
        [host.capture.resolution selectItemAtIndex:4];[host.capture selectionChanged:host.capture.resolution];Check(!host.capture.fieldOrder.enabled,@"720p stays progressive with field order disabled");
        [host.capture refresh:host.capture.resolution];Check(host.capture.aspect.indexOfSelectedItem==0,@"legacy driver refresh defaults aspect to 4:3");
        [host showIdle:nil];CheckControl(host.window.contentView,host.idle.screen,host.idle,@selector(screenChanged:),@"HDMI idle policy");
        Check(host.idle.delay.numberOfItems==7&&host.idle.delay.indexOfSelectedItem==3,@"idle delay defaults to two minutes with seven choices");
        for(NSInteger choice=0;choice<7;++choice){[host.idle.delay selectItemAtIndex:choice];[host.idle screenChanged:nil];Check([[UITestDefaults standardUserDefaults] integerForKey:@"HDMIIdleDelaySeconds"]==[@[@0,@30,@60,@120,@300,@600,@(-1)][choice] integerValue],@"idle delay choice saves exact seconds independently");}[host.idle.delay selectItemAtIndex:3];[host.idle screenChanged:nil];
        Check(host.idle.screen.numberOfItems==5,@"Hold, black, bars, picture and silent movie choices");
        // These methods only select a tab; no control actions are dispatched.
        [host showOutput:nil];CheckOutput(host,@"Before autorelease-pool drain");
        [host showCapture:nil];[host showOutput:nil];
    }
    Check(weakOutput==host.output&&weakStart==host.output.start,@"output controller and Start button survive autorelease drain/tab switches");
    printf("CombinedHost output property: %s\n",property_getAttributes(class_getProperty(CombinedHost.class,"output")));
    printf("OutputHost start property: %s\n",property_getAttributes(class_getProperty(OutputHost.class,"start")));
    printf("Live test-window objects after original content transfer: %lu\n",(unsigned long)testWindows.count);
    CheckOutput(host,@"After autorelease-pool drain and Capture→Output tab switches");
    [host.output.source selectItemAtIndex:2];[host.output sourceChanged:nil];
    CheckControl(host.window.contentView,host.output.macView,host.output,@selector(outputViewsChanged:),@"Mac screen Video/Scopes/Off");
    CheckControl(host.window.contentView,host.output.shuttleView,host.output,@selector(outputViewsChanged:),@"Shuttle output Video/Scopes/Off");
    Check(host.output.macView.numberOfItems==3&&host.output.shuttleView.numberOfItems==3,@"Both outputs have exactly Video, Video scopes and Off");
    [host.output.macView selectItemAtIndex:0];[host.output.shuttleView selectItemAtIndex:2];[host.output outputViewsChanged:nil];
    Check([host.output virtualDestination]&&host.output.connector.hidden&&!host.output.virtualDisplay.hidden,@"Mac-only uses Virtual Shuttle without USB");
    CheckControl(host.window.contentView,host.output.virtualDisplay,host.output,@selector(virtualDisplayChanged:),@"Mac output display");
    CheckControl(host.window.contentView,host.output.listen,host.output,@selector(listenChanged:),@"Listen toggle");
    CheckControl(host.window.contentView,host.output.listenDevice,host.output,@selector(listenDeviceChanged:),@"Listening speakers");
    CheckControl(host.window.contentView,host.output.listenVolume,host.output,@selector(listenChanged:),@"Listening volume");
    host.output.audioSyncField.integerValue=-40;[host.output audioSyncChanged:host.output.audioSyncField];
    Check([[UITestDefaults standardUserDefaults] integerForKey:@"VirtualAudioOffsetMS"]==-40&&[[UITestDefaults standardUserDefaults] integerForKey:@"HDMIAudioOffsetMS"]==0,@"Mac-only and hardware sync values remain independent");
    for(NSInteger editor=2;editor<=3;++editor){[host.output.source selectItemAtIndex:editor];[host.output sourceChanged:nil];for(NSInteger mac=0;mac<3;++mac)for(NSInteger usb=0;usb<3;++usb){
        [host.output.macView selectItemAtIndex:mac];[host.output.shuttleView selectItemAtIndex:usb];[host.output outputViewsChanged:nil];BOOL m=mac!=2,u=usb!=2;
        Check([host.output macEnabled]==m&&[host.output shuttleEnabled]==u&&[host.output bothDestinations]==(m&&u),@"All nine destination choices route independently for each editor");
        Check(host.output.start.enabled==(m||u),@"Both Off disables Start without launching anything");
        if(m||u){NSString* name=[host.output outputExecutable];NSArray* args=[host.output outputArguments];Check([name isEqual:m&&!u?@"ShuttleScreenOutput":@"ShuttlePlayback"],@"Disabled Shuttle never launches a USB sender");
            if(m&&u)Check([args[0] isEqual:editor==3?@"--premiere-dual":@"--virtual-sink"],@"Paired editor uses its own ingress port");
            else if(m)Check(editor==3?[args[0] isEqual:@"--premiere"]:args.count==2,@"Mac-only Premiere uses Mercury Transmit ingress, Final Cut uses Virtual Shuttle");
            else Check([args[0] isEqual:editor==3?@"--premiere":@"--sink"],@"Hardware-only keeps the existing editor sender");
        }
        Check([[UITestDefaults standardUserDefaults] integerForKey:@"VirtualOutputView"]==(mac==1?host.output.macScope.indexOfSelectedItem+1:0)&&[[UITestDefaults standardUserDefaults] integerForKey:@"HDMIOutputView"]==(usb==1?host.output.shuttleScope.indexOfSelectedItem+1:0),@"Each output receives its own Video/Scopes preference");
    }}
    [host.output.source selectItemAtIndex:2];[host.output sourceChanged:nil];[host.output.macView selectItemAtIndex:1];[host.output.shuttleView selectItemAtIndex:1];[host.output outputViewsChanged:nil];
    CheckControl(host.window.contentView,host.output.macScope,host.output,@selector(outputViewsChanged:),@"Mac screen scope type");CheckControl(host.window.contentView,host.output.shuttleScope,host.output,@selector(outputViewsChanged:),@"Shuttle scope type");
    for(NSInteger style=0;style<6;++style){[host.output.macScope selectItemAtIndex:style];[host.output.shuttleScope selectItemAtIndex:5-style];[host.output outputViewsChanged:nil];Check([[UITestDefaults standardUserDefaults] integerForKey:@"VirtualOutputView"]==style+1&&[[UITestDefaults standardUserDefaults] integerForKey:@"HDMIOutputView"]==6-style,@"All six scope types stay independent, including scopes on both");}
    Check(!host.output.showTimecode.enabled&&!host.output.showMeters.enabled&&!host.output.titleSafe.enabled&&!host.output.actionSafe.enabled,@"Both scope displays stay clear of overlays");
    [host.output.macView selectItemAtIndex:0];[host.output.shuttleView selectItemAtIndex:0];[host.output outputViewsChanged:nil];
    CheckControl(host.window.contentView,host.output.monitorTarget,host.output,@selector(monitorTargetChanged:),@"Video overlay destination");Check(host.output.showMeters.enabled&&host.output.titleSafe.enabled,@"Both Video restores overlay editing");
    UITestTask* fake=[UITestTask new];host.output.task=fake;[host.output setRunning:YES];[host.output.macView selectItemAtIndex:2];[host.output outputViewsChanged:host.output.macView];Check(host.output.macView.indexOfSelectedItem==0&&[[UITestDefaults standardUserDefaults] integerForKey:@"MacMonitorMode"]==0,@"A running editor's output cannot be silently disconnected");
    [host.output.shuttleView selectItemAtIndex:1];[host.output outputViewsChanged:host.output.shuttleView];Check([[UITestDefaults standardUserDefaults] integerForKey:@"HDMIOutputView"]>0&&host.output.macView.indexOfSelectedItem==0,@"Video to Scopes changes live without a helper restart");host.output.task=nil;[host.output setRunning:NO];
    [host.output.macView selectItemAtIndex:2];[host.output.shuttleView selectItemAtIndex:0];[host.output outputViewsChanged:nil];
    [host.output.monitorTarget selectItemAtIndex:0];[host.output monitorTargetChanged:nil];
    Check(![host.output virtualDestination]&&!host.output.connector.hidden&&host.output.virtualDisplay.hidden&&host.output.audioSyncField.integerValue==0,@"Shuttle-only retains its hardware sync and connector");
    CheckControl(host.window.contentView,host.output.audioSyncField,host.output,@selector(audioSyncChanged:),@"Audio sync value");
    CheckControl(host.window.contentView,host.output.audioSyncStepper,host.output,@selector(audioSyncChanged:),@"Audio sync stepper");
    CheckControl(host.window.contentView,host.output.resetAudioSync,host.output,@selector(resetAudioSync:),@"Reset audio sync");
    Check(host.output.audioSyncField.enabled&&host.output.audioSyncStepper.enabled,@"sync controls enabled for Final Cut");
    CheckControl(host.window.contentView,host.output.showTimecode,host.output,@selector(timecodeChanged:),@"HDMI timecode");
    CheckControl(host.window.contentView,host.output.timecodePosition,host.output,@selector(timecodePositionChanged:),@"Timecode position");
    CheckControl(host.window.contentView,host.output.showMeters,host.output,@selector(metersChanged:),@"HDMI L/R audio meters");
    CheckControl(host.window.contentView,host.output.meterPosition,host.output,@selector(metersChanged:),@"Audio meter position");
    CheckControl(host.window.contentView,host.output.titleSafe,host.output,@selector(safeZonesChanged:),@"Title safe guide");
    CheckControl(host.window.contentView,host.output.actionSafe,host.output,@selector(safeZonesChanged:),@"Action safe guide");
    Check(!host.output.titleSafe.state&&!host.output.actionSafe.state,@"old settings leave both guides off");
    for(unsigned flags=0;flags<4;++flags){host.output.titleSafe.state=flags&1?NSControlStateValueOn:NSControlStateValueOff;host.output.actionSafe.state=flags&2?NSControlStateValueOn:NSControlStateValueOff;[host.output safeZonesChanged:nil];Check([[UITestDefaults standardUserDefaults] boolForKey:@"ShowHDMITitleSafe"]==bool(flags&1)&&[[UITestDefaults standardUserDefaults] boolForKey:@"ShowHDMIActionSafe"]==bool(flags&2),@"guide toggles save independently without output restart");}
    Check(!host.output.showMeters.state&&host.output.meterPosition.indexOfSelectedItem==2&&host.output.meterPosition.numberOfItems==6,@"old settings keep meters off and default bottom right");
    host.output.showMeters.state=NSControlStateValueOn;
    for(NSInteger p=0;p<6;++p){[host.output.meterPosition selectItemAtIndex:p];[host.output metersChanged:nil];Check([[UITestDefaults standardUserDefaults] boolForKey:@"ShowHDMIAudioMeters"]&&[[UITestDefaults standardUserDefaults] integerForKey:@"HDMIAudioMeterPosition"]==p+1,@"independent meter settings saved live");}
    Check(host.output.timecodePosition.numberOfItems==6&&host.output.timecodePosition.indexOfSelectedItem==5,@"all six positions, old settings default bottom centre");
    for(NSInteger position=0;position<6;++position){[host.output.timecodePosition selectItemAtIndex:position];[host.output timecodePositionChanged:nil];Check([[UITestDefaults standardUserDefaults] integerForKey:@"HDMITimecodePosition"]==position+1,@"position saved without restarting output");}
    host.output.showTimecode.state=NSControlStateValueOn;[host.output timecodeChanged:host.output.showTimecode];
    Check([[UITestDefaults standardUserDefaults] boolForKey:@"ShowHDMITimecode"],@"timecode overlay preference saved without a helper restart");
    host.output.audioSyncField.integerValue=-40;[host.output audioSyncChanged:host.output.audioSyncField];
    Check([[UITestDefaults standardUserDefaults] integerForKey:@"HDMIAudioOffsetMS"]==-40&&host.output.audioSyncStepper.integerValue==-40,@"earlier offset saved in fake preferences and stepper");
    [host.output resetAudioSync:nil];
    Check(host.output.audioSyncField.integerValue==0&&[[UITestDefaults standardUserDefaults] integerForKey:@"HDMIAudioOffsetMS"]==0,@"Reset clears adjustment");
    [host.output.source selectItemAtIndex:4];[host.output sourceChanged:nil];
    Check(!host.output.desktopDisplay.hiddenOrHasHiddenAncestor&&host.output.desktopDisplay.enabled,@"Desktop display selector visible and enabled");
    Check(host.output.source.numberOfItems==7&&!host.output.showTimecode.enabled&&host.output.choose.hidden,@"Desktop source keeps editor-only controls and movie chooser separate");
    [host.output.source selectItemAtIndex:5];[host.output sourceChanged:nil];
    Check(host.output.desktopDisplay.hidden&&!host.output.extendedHint.hidden&&!host.output.sizing.hidden&&[host.output.start.title isEqual:@"Start extended display"],@"Extended display has separate source, sizing and drag-windows hint without creating a display");
    for(NSInteger c=0;c<4;++c){[host.output.connector selectItemAtIndex:c];[host.output.mode selectItemAtIndex:2];[host.output connectorChanged:nil];Check(host.output.mode.indexOfSelectedItem==((c==1||c==2)?0:2),@"connector choice constrains output format without starting USB");}
    [host.output.connector selectItemAtIndex:0];[host.output connectorChanged:nil];
    [host showIdle:nil];CheckControl(host.window.contentView,host.idle.startupMovie,host.idle,@selector(startupChanged:),@"Startup movie preference");Check(!NSIntersectsRect(host.idle.startupMovie.frame,host.idle.status.frame),@"Startup preference and status have separate space");host.idle.startupMovie.state=NSControlStateValueOff;[host.idle startupChanged:nil];Check(![UITestDefaults.standardUserDefaults boolForKey:@"PlayStartupMovie"],@"Startup movie can be disabled without changing output/idle choices");host.idle.startupMovie.state=NSControlStateValueOn;[host.idle startupChanged:nil];
    CheckControl(host.window.contentView,host.idle.sizing,host.idle,@selector(screenChanged:),@"Idle media sizing");
    for(NSInteger s=0;s<3;++s){[host.idle.sizing selectItemAtIndex:s];[host.idle screenChanged:nil];Check([[UITestDefaults standardUserDefaults] integerForKey:@"HDMIIdleSizing"]==s,@"idle fit/fill/stretch preference saves exactly");}[host.idle.sizing selectItemAtIndex:0];[host.idle screenChanged:nil];[host showOutput:nil];
    [host.output.source selectItemAtIndex:1];[host.output sourceChanged:nil];
    CheckControl(host.window.contentView,host.output.choose,host.output,@selector(chooseMovie:),@"Movie chooser remains available");
    CheckControl(host.window.contentView,host.output.loop,nil,nullptr,@"Movie loop remains available");
    Check(!host.output.audioSyncField.enabled&&!host.output.audioSyncStepper.enabled&&!host.output.resetAudioSync.enabled,@"timeline-only adjustment disabled for movie files");
    Check(!host.output.showTimecode.enabled,@"Final Cut timecode disabled for movie-file source");
    Check(!host.output.timecodePosition.enabled,@"timecode placement disabled for movie-file source");
    Check(host.output.showMeters.enabled&&host.output.meterPosition.enabled,@"audio meters remain available for movie playback");
    Check(host.output.titleSafe.enabled&&host.output.actionSafe.enabled,@"safe guides available for movie playback");

    [host.output.source selectItemAtIndex:3];[host.output sourceChanged:nil];
    Check([host.output.start.title isEqual:@"Start Premiere"]&&host.output.audioSyncField.enabled&&host.output.showTimecode.enabled,@"Premiere source has specific Start action and timeline overlays/sync");
    Check([host.output.outputHelp.stringValue containsString:@"Mercury Transmit"]&&[host.output.outputHelp.stringValue containsString:@"Virtual Shuttle Audio"],@"Premiere source explains video and the shared Shuttle audio route");

    NSString* appPath=argc>1?@(argv[1]):@"/Applications/Shuttle Camera.app";
    NSBundle* bundle=[NSBundle bundleWithPath:appPath];NSURL* executable=bundle.executableURL;
    NSURL* helper=[executable.URLByDeletingLastPathComponent URLByAppendingPathComponent:@"ShuttlePlayback"];
    printf("Read-only installed bundle: %s\nExecutable: %s\nHelper: %s\n",appPath.UTF8String,executable.path.UTF8String,helper.path.UTF8String);
    Check(executable!=nil&&[[NSFileManager defaultManager] isExecutableFileAtPath:executable.path],@"installed bundle executable resolves and is executable");
    Check(helper!=nil&&[[NSFileManager defaultManager] isExecutableFileAtPath:helper.path],@"production helper URL expression resolves an existing executable beside the host");
    if(argc>2){NSView* v=host.window.contentView;auto* rep=[v bitmapImageRepForCachingDisplayInRect:v.bounds];[v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];[[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@(argv[2]) atomically:YES];}
    if(argc>3){[host showCapture:nil];NSView* v=host.window.contentView;auto* rep=[v bitmapImageRepForCachingDisplayInRect:v.bounds];[v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];[[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@(argv[3]) atomically:YES];}
    if(argc>4){[host showOutput:nil];[host.output.source selectItemAtIndex:1];[host.output sourceChanged:nil];[host.output.mode selectItemAtIndex:2];host.output.fileLabel.stringValue=@"Example movie.mov";host.output.audioRouteLabel.stringValue=@"Output: System speakers";host.output.loop.state=NSControlStateValueOn;NSView* v=host.window.contentView;auto* rep=[v bitmapImageRepForCachingDisplayInRect:v.bounds];[v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];[[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@(argv[4]) atomically:YES];}
    if(argc>5){[host showOutput:nil];[host.output.source selectItemAtIndex:4];[host.output sourceChanged:nil];host.output.audioRouteLabel.stringValue=@"Output: System speakers";NSView* v=host.window.contentView;auto* rep=[v bitmapImageRepForCachingDisplayInRect:v.bounds];[v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];[[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@(argv[5]) atomically:YES];}
    if(argc>6){[host showPicture:nil];NSView* v=host.window.contentView;auto* rep=[v bitmapImageRepForCachingDisplayInRect:v.bounds];[v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];[[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@(argv[6]) atomically:YES];}
    if(argc>7){[host showIdle:nil];NSView* v=host.window.contentView;auto* rep=[v bitmapImageRepForCachingDisplayInRect:v.bounds];[v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];[[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@(argv[7]) atomically:YES];}
    if(argc>8){[host showOutput:nil];[host.output.source selectItemAtIndex:5];[host.output sourceChanged:nil];NSView* v=host.window.contentView;auto* rep=[v bitmapImageRepForCachingDisplayInRect:v.bounds];[v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];[[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@(argv[8]) atomically:YES];}
    Check([NSApp.mainMenu itemAtIndex:2].submenu!=nil,@"Help menu retains setup and diagnostics");
    [host.output.source selectItemAtIndex:6];[host.output sourceChanged:nil];
    Check([host.output.source.titleOfSelectedItem isEqual:@"Idle screen"]&&host.output.sizing.hidden&&!host.output.audioSyncField.enabled&&!host.output.showTimecode.enabled,@"Idle output source uses saved media and excludes editor-only options");
    Check([host.captureButton.title isEqual:@"Input Settings"]&&[host.outputButton.title isEqual:@"Output Settings"],@"Both Settings tabs use the requested plural");
    [host showPicture:nil];
    CheckControl(host.window.contentView,host.monitor.listen,host.monitor,@selector(listenChanged:),@"Listening toggle");
    CheckControl(host.window.contentView,host.monitor.volume,host.monitor,@selector(volumeChanged:),@"Listening volume");
    Check(host.monitor.meters.leftDB==-60&&host.monitor.meters.rightDB==-60,@"Idle meters start at silence, never full scale");
    Check(!host.monitor.active&&host.monitor.listen.state==NSControlStateValueOff,@"Audio monitoring and hardware access stay off at app launch");
    Check(host.monitor.meters.frame.size.height>host.monitor.meters.frame.size.width&&NSMinX(host.monitor.meters.frame)>NSMaxX(host.preview.view.frame),@"Vertical stereo meters sit beside the full preview");
    [host.preview setPreviewAspect:4./3];Check(fabs(host.preview.view.frame.size.width/host.preview.view.frame.size.height-4./3)<.001,@"Preview border follows 4:3");
    [host.preview setPreviewAspect:16./9];Check(fabs(host.preview.view.frame.size.width/host.preview.view.frame.size.height-16./9)<.001,@"Preview border follows 16:9 without cropping");
    CheckControl(host.window.contentView,host.capture.recordButton,host.capture,@selector(startRecording:),@"Direct Record button");
    Check(host.capture.recordButton.enabled&&!host.capture.stopRecordButton.enabled,@"Recorder starts idle, Stop disabled");
    Check([host.capture.recordStatus.stringValue containsString:@"ProRes"],@"Capture status shows the selected codec");
    Check(!host.preview.wantsPreview,@"Opening app leaves USB capture stopped until explicitly requested");
    CheckControl(host.window.contentView,host.previewButton,host,@selector(togglePreview:),@"Show input preview control");
    Check([host applicationShouldTerminate:app]==NSTerminateNow,@"Idle recorder does not delay Quit");
    host.capture.recorderTask=[UITestTask new];host.capture.recorderInput=[NSPipe pipe];NSFileHandle *stopReader=host.capture.recorderInput.fileHandleForReading;
    [host.capture apply:nil];Check([host.capture.status.stringValue containsString:@"Stop recording"]&&!host.capture.applyingSettings,@"Apply protects an active recording before touching the device");
    [host disableCamera:nil];Check(host.capture.recorderTask!=nil&&[host.capture.status.stringValue containsString:@"Stop recording"],@"Disable driver protects an active recording");
    Check([host applicationShouldTerminate:app]==NSTerminateLater,@"Quit waits for recording finalization");
    Check(host.capture.stoppingRecording&&host.capture.recordingFinished!=nil,@"Quit requests a clean stop and saves completion callback");
    Check([[[NSString alloc] initWithData:[stopReader readDataToEndOfFile] encoding:NSUTF8StringEncoding] isEqual:@"stop\n"],@"Stop sends clean finalization command, not force termination");
    if(argc>9){[host showOutput:nil];[host.output.source selectItemAtIndex:2];[host.output sourceChanged:nil];[host.output.macView selectItemAtIndex:0];[host.output.shuttleView selectItemAtIndex:2];[host.output outputViewsChanged:nil];host.output.audioRouteLabel.stringValue=@"Output: Virtual Shuttle Audio";host.output.readinessLabel.stringValue=@"Stopped";host.output.virtualDisplay.selectedItem.title=@"External display · 2560 × 1440";host.output.listenDevice.selectedItem.title=@"Mac speakers (example)";host.output.showMeters.state=NSControlStateValueOn;host.output.titleSafe.state=NSControlStateValueOn;NSView* v=host.window.contentView;auto* rep=[v bitmapImageRepForCachingDisplayInRect:v.bounds];[v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];[[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@(argv[9]) atomically:YES];}
    if(argc>10){[host.output.macView selectItemAtIndex:2];[host.output.shuttleView selectItemAtIndex:0];[host.output outputViewsChanged:nil];NSView* v=host.window.contentView;auto* rep=[v bitmapImageRepForCachingDisplayInRect:v.bounds];[v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];[[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@(argv[10]) atomically:YES];}
    if(argc>11){[host showOutput:nil];[host.output.source selectItemAtIndex:2];[host.output sourceChanged:nil];[host.output.macView selectItemAtIndex:1];[host.output.shuttleView selectItemAtIndex:0];[host.output outputViewsChanged:nil];host.output.virtualDisplay.selectedItem.title=@"External display";host.output.listenDevice.selectedItem.title=@"Mac speakers (example)";NSView* v=host.window.contentView;auto* rep=[v bitmapImageRepForCachingDisplayInRect:v.bounds];[v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];[[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@(argv[11]) atomically:YES];}
    if(argc>12){[host.output.macView selectItemAtIndex:0];[host.output.shuttleView selectItemAtIndex:1];[host.output.shuttleScope selectItemAtIndex:0];[host.output outputViewsChanged:nil];NSView* v=host.window.contentView;auto* rep=[v bitmapImageRepForCachingDisplayInRect:v.bounds];[v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];[[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@(argv[12]) atomically:YES];}
    if(argc>13){[host.output.source selectItemAtIndex:3];[host.output sourceChanged:nil];[host.output.macView selectItemAtIndex:1];[host.output.macScope selectItemAtIndex:4];[host.output outputViewsChanged:nil];NSView* v=host.window.contentView;auto* rep=[v bitmapImageRepForCachingDisplayInRect:v.bounds];[v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];[[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@(argv[13]) atomically:YES];}

    host.capture.recordingFinished=nil;host.capture.recorderTask=nil;host.capture.recorderInput=nil;
    [host showCapture:nil];CheckControl(host.window.contentView,host.capture.recordingCodec,host.capture,@selector(recordingCodecChanged:),@"Recording codec menu");
    Check(host.capture.recordingCodec.numberOfItems==7,@"Seven recording codec choices");
    [host.capture.resolution selectItemAtIndex:6];[host.capture selectionChanged:nil];
    for(unsigned i=0;i<7;i++)Check([host.capture.recordingCodec itemAtIndex:i].enabled==(i<5),@"Interlaced capture permits ProRes/uncompressed and disables progressive-only codecs");
    [host.capture.recordingCodec selectItemAtIndex:5];[host.capture recordingCodecChanged:host.capture.recordingCodec];Check(!host.capture.recordButton.enabled,@"Incompatible H264 choice cannot start an interlaced recording");
    [host.capture.resolution selectItemAtIndex:4];[host.capture selectionChanged:nil];Check(host.capture.recordButton.enabled&&[host.capture.recordStatus.stringValue containsString:@"H.264"],@"Progressive capture enables H264 without silently changing capture format");
    [host.capture.recordingCodec selectItemAtIndex:6];[host.capture recordingCodecChanged:host.capture.recordingCodec];Check([[[UITestDefaults standardUserDefaults] stringForKey:@"RecordingCodec"] isEqual:@"hevc"],@"Codec preference saves independently of driver settings");
    [host.capture.recordingCodec selectItemAtIndex:0];[host.capture recordingCodecChanged:host.capture.recordingCodec];
    NSString *movie=[NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingString:@".mov"]];[host.capture openSavedRecording:movie];Check(openedMovies.count==0,@"Missing saved file does not open a player");
    [NSData.data writeToFile:movie atomically:YES];[host.capture openSavedRecording:movie];Check(openedMovies.count==0,@"Empty file does not open a player");
    [[@"fake completed recording" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:movie atomically:YES];[host.capture openSavedRecording:movie];Check(openedMovies.count==1&&[openedMovies.lastObject.path isEqual:movie],@"A saved movie opens via the system default-player URL API, not a hard-coded app");[NSFileManager.defaultManager removeItemAtPath:movie error:nil];
    Check(audioWrites==0&&cmioWrites==0&&taskLaunches==0,@"zero audio writes, CMIO writes and helper launches");
    // Exercise Apply against the fake CMIO device, including delayed removal of another client.
    __block unsigned paused=0,finished=0,applied=0;
    CFStringRef ready=CFSTR("{\"standard\":\"PAL\",\"video_input\":\"S-Video\",\"audio_input\":\"Analog RCA\",\"dropout\":\"Hold last frame\",\"output_size\":\"Native\",\"brightness\":0,\"contrast\":100,\"colour\":100,\"sharpness\":0,\"picture_live\":true,\"capture_aspect\":true,\"capture_interlace\":true,\"capturing\":false}");
    testCameraJSON=ready;[host.capture refresh:host.capture.resolution];[host.capture.resolution selectItemAtIndex:5];[host.capture selectionChanged:host.capture.resolution];
    host.capture.pauseOwnPreview=^{++paused;};host.capture.settingsApplied=^(NSDictionary *d){++applied;Check([d[@"output_size"] isEqual:@"1920x1080"],@"Apply forwards the requested raster to preview refresh");};host.capture.settingsFinished=^{++finished;};
    permitSettingsWrite=true;[host.capture apply:nil];[host.capture apply:nil];
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:2];while(host.capture.applyingSettings&&deadline.timeIntervalSinceNow>0)[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.02]];
    Check(paused==1&&finished==1&&applied==1&&cmioWrites==1&&!host.capture.captureDraft,@"Apply pauses/reconnects once, saves format and finishes without relaunch or duplicate writes");
    NSMutableDictionary *busy=[settingsDictionary((__bridge NSString*)ready) mutableCopy];busy[@"capturing"]=@YES;NSString *busyJSON=settingsJSON(busy);testCameraJSON=(__bridge CFStringRef)busyJSON;[host.capture apply:nil];
    deadline=[NSDate dateWithTimeIntervalSinceNow:4];while(host.capture.applyingSettings&&deadline.timeIntervalSinceNow>0)[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.02]];
    Check(paused==2&&finished==2&&cmioWrites==1&&[host.capture.status.stringValue containsString:@"Close other camera previews"],@"An external client blocks format changes with bounded retry and no restart request");
    testCameraJSON=ready;settingsWriteResult=-1;host.capture.captureDraft=YES;[host.capture apply:nil];Check(paused==3&&finished==3&&cmioWrites==2&&host.capture.captureDraft,@"Failed Apply resumes controls and preserves the user's draft");settingsWriteResult=0;permitSettingsWrite=false;
    [host.output applicationWillTerminate:[NSNotification notificationWithName:NSApplicationWillTerminateNotification object:app]];
    method_setImplementation(activate,originalActivate);
    printf("RESULT: %u failures; UI hit testing does not dispatch actual actions.\n",failures);
    return failures?1:0;
}}
