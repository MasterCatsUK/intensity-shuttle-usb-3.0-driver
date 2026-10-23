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
    assert(false&&"Unexpected audio read in UI construction");return -1;
}
static OSStatus TestAudioSize(AudioObjectID,const AudioObjectPropertyAddress*,UInt32,const void*,UInt32*) {assert(false);return -1;}
static OSStatus TestAudioSettable(AudioObjectID,const AudioObjectPropertyAddress*,Boolean*) {assert(false);return -1;}
static OSStatus TestAudioSet(AudioObjectID,const AudioObjectPropertyAddress*,UInt32,const void*,UInt32,const void*) {++audioWrites;assert(false&&"No route actions allowed");return -1;}
static OSStatus TestAudioAdd(AudioObjectID,const AudioObjectPropertyAddress*,dispatch_queue_t,AudioObjectPropertyListenerBlock block) {testListener=[block copy];return 0;}
static OSStatus TestAudioRemove(AudioObjectID,const AudioObjectPropertyAddress*,dispatch_queue_t,AudioObjectPropertyListenerBlock) {testListener=nil;return 0;}
static CFStringRef testCameraJSON=nullptr;
static OSStatus TestCMIOSize(CMIOObjectID,const CMIOObjectPropertyAddress*,UInt32,const void*,UInt32* bytes) {*bytes=testCameraJSON?sizeof(CMIOObjectID):0;return 0;}
static OSStatus TestCMIOGet(CMIOObjectID,const CMIOObjectPropertyAddress* a,UInt32,const void*,UInt32,UInt32* bytes,void* value) {
    if(!testCameraJSON){*bytes=0;return 0;}
    if(a->mSelector==kCMIOHardwarePropertyDevices){*(CMIOObjectID*)value=123;*bytes=sizeof(CMIOObjectID);return 0;}
    CFStringRef text=a->mSelector==kCMIODevicePropertyDeviceUID?CFSTR("local.shuttle.camera.pal"):testCameraJSON;
    *(CFStringRef*)value=(CFStringRef)CFRetain(text);*bytes=sizeof(CFStringRef);return 0;
}
static OSStatus TestCMIOSet(CMIOObjectID,const CMIOObjectPropertyAddress*,UInt32,const void*,UInt32,const void*) {++cmioWrites;assert(false&&"No CMIO actions allowed");return -1;}

@interface UITestDefaults:NSObject
@property NSMutableDictionary* values;
+ (instancetype)standardUserDefaults;
@end
@implementation UITestDefaults
+ (instancetype)standardUserDefaults {static UITestDefaults* defaults;if(!defaults){defaults=[UITestDefaults new];defaults.values=[NSMutableDictionary dictionary];}return defaults;}
- (NSInteger)integerForKey:(NSString*)key{return [self.values[key] integerValue];}
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
@property id standardOutput,standardError;
@property int terminationStatus;
@property(copy) void (^terminationHandler)(UITestTask*);
@end
@implementation UITestTask
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
#include "../src/CombinedHost.mm"
#undef NSWindow
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
    Check([applicationMenu itemWithTitle:@"About Shuttle Camera"].action==@selector(showAbout:),@"About app menu action available");
    auto* quit=[applicationMenu itemWithTitle:@"Quit Shuttle Camera"];Check(quit.action==@selector(terminate:)&&[quit.keyEquivalent isEqual:@"q"]&&quit.target==NSApp,@"Quit uses normal application cleanup and Command-Q");
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
    Check(host.output.source.numberOfItems==6&&!host.output.showTimecode.enabled&&host.output.choose.hidden,@"Desktop source keeps editor-only controls and movie chooser separate");
    [host.output.source selectItemAtIndex:5];[host.output sourceChanged:nil];
    Check(host.output.desktopDisplay.hidden&&!host.output.extendedHint.hidden&&!host.output.sizing.hidden&&[host.output.start.title isEqual:@"Start extended display"],@"Extended display has separate source, sizing and drag-windows hint without creating a display");
    for(NSInteger c=0;c<4;++c){[host.output.connector selectItemAtIndex:c];[host.output.mode selectItemAtIndex:2];[host.output connectorChanged:nil];Check(host.output.mode.indexOfSelectedItem==((c==1||c==2)?0:2),@"connector choice constrains output format without starting USB");}
    [host.output.connector selectItemAtIndex:0];[host.output connectorChanged:nil];
    [host showIdle:nil];CheckControl(host.window.contentView,host.idle.sizing,host.idle,@selector(screenChanged:),@"Idle media sizing");
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
    Check([host.output.outputHelp.stringValue containsString:@"Mercury Transmit"]&&[host.output.outputHelp.stringValue containsString:@"Audio Hardware"],@"Premiere source explains video and independent HDMI audio selection");

    NSString* appPath=argc>1?@(argv[1]):@"/Applications/Shuttle Camera.app";
    NSBundle* bundle=[NSBundle bundleWithPath:appPath];NSURL* executable=bundle.executableURL;
    NSURL* helper=[executable.URLByDeletingLastPathComponent URLByAppendingPathComponent:@"ShuttlePlayback"];
    printf("Read-only installed bundle: %s\nExecutable: %s\nHelper: %s\n",appPath.UTF8String,executable.path.UTF8String,helper.path.UTF8String);
    Check(executable!=nil&&[[NSFileManager defaultManager] isExecutableFileAtPath:executable.path],@"installed bundle executable resolves and is executable");
    Check(helper!=nil&&[[NSFileManager defaultManager] isExecutableFileAtPath:helper.path],@"production helper URL expression resolves an existing executable beside the host");
    [host.output.meterPosition selectItemAtIndex:2];host.output.audioRouteLabel.stringValue=@"Output: System speakers";[host.output.source selectItemAtIndex:2];[host.output sourceChanged:nil];
    if(argc>2){NSView* v=host.window.contentView;auto* rep=[v bitmapImageRepForCachingDisplayInRect:v.bounds];[v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];[[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@(argv[2]) atomically:YES];}
    if(argc>3){[host.capture.aspect selectItemAtIndex:1];[host.capture.resolution selectItemAtIndex:7];[host.capture selectionChanged:nil];[host showCapture:nil];NSView* v=host.window.contentView;auto* rep=[v bitmapImageRepForCachingDisplayInRect:v.bounds];[v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];[[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@(argv[3]) atomically:YES];}
    if(argc>4){[host showOutput:nil];[host.output.source selectItemAtIndex:1];[host.output sourceChanged:nil];[host.output.mode selectItemAtIndex:2];[host.output.sizing selectItemAtIndex:0];host.output.fileLabel.stringValue=@"Example movie.mov";host.output.audioRouteLabel.stringValue=@"Output: System speakers";host.output.loop.state=NSControlStateValueOn;NSView* v=host.window.contentView;auto* rep=[v bitmapImageRepForCachingDisplayInRect:v.bounds];[v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];[[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@(argv[4]) atomically:YES];}
    if(argc>5){[host showOutput:nil];[host.output.source selectItemAtIndex:4];[host.output sourceChanged:nil];host.output.audioRouteLabel.stringValue=@"Output: System speakers";NSView* v=host.window.contentView;auto* rep=[v bitmapImageRepForCachingDisplayInRect:v.bounds];[v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];[[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@(argv[5]) atomically:YES];}
    if(argc>6){[host showPicture:nil];NSView* v=host.window.contentView;auto* rep=[v bitmapImageRepForCachingDisplayInRect:v.bounds];[v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];[[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@(argv[6]) atomically:YES];}
    if(argc>7){[host showIdle:nil];[host.idle.screen selectItemAtIndex:3];host.idle.preview.image=[[NSImage alloc] initWithContentsOfFile:[bundle.resourcePath stringByAppendingPathComponent:@"AppIcon.icns"]];host.idle.mediaLabel.stringValue=@"SVHS logo.png";[host.idle.delay selectItemAtIndex:3];host.idle.status.stringValue=@"Changes apply the next time you start output.";NSView* v=host.window.contentView;auto* rep=[v bitmapImageRepForCachingDisplayInRect:v.bounds];[v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];[[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@(argv[7]) atomically:YES];}
    if(argc>8){[host showOutput:nil];[host.output.source selectItemAtIndex:5];[host.output sourceChanged:nil];[host.output.sizing selectItemAtIndex:2];NSView* v=host.window.contentView;auto* rep=[v bitmapImageRepForCachingDisplayInRect:v.bounds];[v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];[[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@(argv[8]) atomically:YES];}
    if(argc>9){[host showOutput:nil];[host.output.source selectItemAtIndex:3];[host.output sourceChanged:nil];NSView* v=host.window.contentView;auto* rep=[v bitmapImageRepForCachingDisplayInRect:v.bounds];[v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];[[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@(argv[9]) atomically:YES];}
    Check([NSApp.mainMenu itemAtIndex:2].submenu!=nil,@"Help menu retains setup and diagnostics");
    Check(audioWrites==0&&cmioWrites==0&&taskLaunches==0,@"zero audio writes, CMIO writes and helper launches");
    [host.output applicationWillTerminate:[NSNotification notificationWithName:NSApplicationWillTerminateNotification object:app]];
    method_setImplementation(activate,originalActivate);
    printf("RESULT: %u failures; UI hit testing does not dispatch actual actions.\n",failures);
    return failures?1:0;
}}
