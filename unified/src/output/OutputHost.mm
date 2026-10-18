// GPL-2.0-or-later. Local HDMI output controls, independent of camera activation.
#import <Cocoa/Cocoa.h>
#import <SystemExtensions/SystemExtensions.h>
#import <CoreMediaIO/CoreMediaIO.h>
#import <CoreMedia/CoreMedia.h>
#include "AudioRoute.hpp"
#include "AudioSync.hpp"
#include "Timecode.hpp"
#include "AudioMeters.hpp"
@interface OutputCanvas : NSView
@end
@implementation OutputCanvas
- (BOOL)isOpaque{return YES;}
- (void)drawRect:(NSRect)rect{[NSColor.windowBackgroundColor setFill];NSRectFill(rect);}
@end
@interface OutputHost : NSObject <NSApplicationDelegate,NSWindowDelegate,OSSystemExtensionRequestDelegate>
@property BOOL activationOnly;
@property BOOL embedded;
@property NSWindow* window;
@property NSPopUpButton* mode;
@property NSPopUpButton* source;
@property NSButton* choose;
@property NSButton* start;
@property NSButton* stop;
@property NSButton* loop;
@property NSButton* useHDMIAudio;
@property NSButton* restoreAudio;
@property NSTextField* audioRouteLabel;
@property NSTextField* readinessLabel;
@property NSTextField* outputHelp;
@property NSTextField* audioSyncField;
@property NSStepper* audioSyncStepper;
@property NSButton* resetAudioSync;
@property NSButton* showTimecode;
@property NSPopUpButton* timecodePosition;
@property NSButton* showMeters;
@property NSPopUpButton* meterPosition;
@property NSButton* titleSafe;
@property NSButton* actionSafe;
@property NSTimer* readinessTimer;
@property NSDate* readinessDeadline;
@property BOOL startupFailed;
@property NSString* previousMediaAudioUID;
@property NSString* lastReportedAudioUID;
@property BOOL managesMediaAudio;
@property(copy) AudioObjectPropertyListenerBlock audioRouteListener;
@property NSTextField* fileLabel;
@property NSTextView* log;
@property NSScrollView* diagnosticsScroll;
@property NSString* movie;
@property NSTask* task;
@end
static NSTextField* label(NSString* text,NSRect rect,CGFloat size) {
    auto* l=[NSTextField labelWithString:text];l.frame=rect;l.font=[NSFont systemFontOfSize:size];return l;
}
// Read-only: the extension publishes one format only after USB is ready.
// Starting the sender must not depend on an already published CMIO device.
static bool timelineOutputReady(NSInteger mode) {
    if(mode<0||mode>=6)return false;
    CMIOObjectPropertyAddress a{kCMIOHardwarePropertyDevices,kCMIOObjectPropertyScopeGlobal,0};
    UInt32 bytes=0;
    if(CMIOObjectGetPropertyDataSize(kCMIOObjectSystemObject,&a,0,nullptr,&bytes)||bytes>1024*1024||bytes%sizeof(CMIOObjectID))return false;
    NSMutableData* list=[NSMutableData dataWithLength:bytes];
    if(CMIOObjectGetPropertyData(kCMIOObjectSystemObject,&a,0,nullptr,bytes,&bytes,list.mutableBytes))return false;
    for(unsigned n=0;n<bytes/sizeof(CMIOObjectID);++n){
        auto device=static_cast<CMIOObjectID*>(list.mutableBytes)[n];CFStringRef uid=nullptr;UInt32 size=sizeof(uid);
        a={kCMIODevicePropertyDeviceUID,kCMIOObjectPropertyScopeGlobal,0};
        if(CMIOObjectGetPropertyData(device,&a,0,nullptr,size,&size,&uid))continue;
        bool matches=uid&&CFEqual(uid,CFSTR("local.shuttle.output.cmio"));if(uid)CFRelease(uid);if(!matches)continue;
        CMIOObjectID stream=0;size=sizeof(stream);a={kCMIODevicePropertyStreams,kCMIODevicePropertyScopeOutput,0};
        if(CMIOObjectGetPropertyData(device,&a,0,nullptr,size,&size,&stream)||size!=sizeof(stream)||!stream)return false;
        CFArrayRef formats=nullptr;size=sizeof(formats);a={kCMIOStreamPropertyFormatDescriptions,kCMIOObjectPropertyScopeGlobal,0};
        if(CMIOObjectGetPropertyData(stream,&a,0,nullptr,size,&size,&formats)||!formats)return false;
        bool ready=false;
        if(CFArrayGetCount(formats)==1){
            auto format=static_cast<CMFormatDescriptionRef>(CFArrayGetValueAtIndex(formats,0));
            auto name=static_cast<CFStringRef>(CMFormatDescriptionGetExtension(format,kCMFormatDescriptionExtension_FormatName));
            NSArray* names=@[@"576i50",@"1080i50",@"1080p25",@"480i59.94",@"1080i59.94",@"1080p29.97"];
            ready=name&&CFEqual(name,(__bridge CFStringRef)names[mode]);
        }
        CFRelease(formats);return ready;
    }
    return false;
}
@implementation OutputHost
- (void)applicationDidFinishLaunching:(NSNotification*)note {
    if(self.activationOnly){[self activateOutput:nil];return;}
    self.window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,650,500) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable backing:NSBackingStoreBuffered defer:NO];
    self.window.title=@"Shuttle Video Output";self.window.delegate=self;
    self.window.contentView=[[OutputCanvas alloc] initWithFrame:NSMakeRect(0,0,650,500)];
    NSView* v=self.window.contentView;
    [v addSubview:label(@"Source",NSMakeRect(24,453,115,24),13)];
    self.source=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(150,450,476,30)];
    [self.source addItemsWithTitles:@[@"Test pattern",@"Movie file",@"Final Cut Pro",@"Premiere Pro"]];self.source.target=self;self.source.action=@selector(sourceChanged:);[v addSubview:self.source];
    NSInteger savedSource=[[NSUserDefaults standardUserDefaults] integerForKey:@"OutputSource"];
    if(savedSource>=0&&savedSource<4)[self.source selectItemAtIndex:savedSource];
    [v addSubview:label(@"HDMI format",NSMakeRect(24,413,115,24),13)];
    self.mode=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(150,410,476,30)];
    [self.mode addItemsWithTitles:@[@"PAL · 576i50",@"1080i50",@"1080p25",@"NTSC · 480i59.94",@"1080i59.94",@"1080p29.97"]];
    NSInteger index=[[NSUserDefaults standardUserDefaults] integerForKey:@"OutputMode"];
    if(index>=0&&index<6)[self.mode selectItemAtIndex:index];[v addSubview:self.mode];
    self.choose=[NSButton buttonWithTitle:@"Choose movie…" target:self action:@selector(chooseMovie:)];self.choose.frame=NSMakeRect(24,368,140,30);[v addSubview:self.choose];
    self.fileLabel=label(@"No movie selected",NSMakeRect(174,372,310,24),12);self.fileLabel.lineBreakMode=NSLineBreakByTruncatingMiddle;[v addSubview:self.fileLabel];
    self.loop=[NSButton checkboxWithTitle:@"Loop" target:nil action:nil];self.loop.frame=NSMakeRect(516,370,110,26);self.loop.state=[[NSUserDefaults standardUserDefaults] boolForKey:@"LoopMovie"]?NSControlStateValueOn:NSControlStateValueOff;[v addSubview:self.loop];
    self.start=[NSButton buttonWithTitle:@"Start output" target:self action:@selector(startOutput:)];self.start.frame=NSMakeRect(24,326,190,34);self.start.bezelStyle=NSBezelStyleRounded;[v addSubview:self.start];
    self.stop=[NSButton buttonWithTitle:@"Stop" target:self action:@selector(stopOutput:)];self.stop.frame=NSMakeRect(224,326,100,34);self.stop.enabled=NO;[v addSubview:self.stop];
    self.readinessLabel=label(@"Stopped",NSMakeRect(24,300,602,20),12);self.readinessLabel.textColor=NSColor.secondaryLabelColor;[v addSubview:self.readinessLabel];
    self.outputHelp=label(@"",NSZeroRect,12); // Available through Help, not on the main panel.
    auto* audioTitle=label(@"AUDIO",NSMakeRect(24,270,602,20),11);audioTitle.font=[NSFont boldSystemFontOfSize:11];audioTitle.textColor=NSColor.secondaryLabelColor;[v addSubview:audioTitle];
    self.useHDMIAudio=[NSButton buttonWithTitle:@"Use HDMI audio" target:self action:@selector(useHDMIAudio:)];self.useHDMIAudio.frame=NSMakeRect(24,236,140,30);self.useHDMIAudio.toolTip=@"Use Shuttle HDMI for Mac media sound. The previous output restores when you stop.";[v addSubview:self.useHDMIAudio];
    self.restoreAudio=[NSButton buttonWithTitle:@"Restore audio" target:self action:@selector(restoreAudio:)];self.restoreAudio.frame=NSMakeRect(174,236,130,30);[v addSubview:self.restoreAudio];
    NSButton* audioSettings=[NSButton buttonWithTitle:@"Sound settings…" target:self action:@selector(openAudioSettings:)];audioSettings.frame=NSMakeRect(476,236,150,30);[v addSubview:audioSettings];
    self.audioRouteLabel=label(@"",NSMakeRect(24,215,602,18),11);self.audioRouteLabel.textColor=NSColor.secondaryLabelColor;self.audioRouteLabel.lineBreakMode=NSLineBreakByTruncatingMiddle;[v addSubview:self.audioRouteLabel];
    [v addSubview:label(@"Audio sync",NSMakeRect(24,181,120,24),13)];
    self.audioSyncField=[[NSTextField alloc] initWithFrame:NSMakeRect(150,180,76,26)];
    NSNumberFormatter* syncFormat=[NSNumberFormatter new];syncFormat.allowsFloats=NO;syncFormat.minimum=@(shuttle_output_audio::MinAudioOffsetMS);syncFormat.maximum=@(shuttle_output_audio::MaxAudioOffsetMS);self.audioSyncField.formatter=syncFormat;
    self.audioSyncField.target=self;self.audioSyncField.action=@selector(audioSyncChanged:);self.audioSyncField.integerValue=shuttle_output_audio::clampAudioOffset(int([[NSUserDefaults standardUserDefaults] integerForKey:@"HDMIAudioOffsetMS"]));self.audioSyncField.accessibilityLabel=@"HDMI audio offset in milliseconds";self.audioSyncField.toolTip=@"−100 to +500 ms. Negative moves sound earlier; positive moves it later. Press Return to apply.";[v addSubview:self.audioSyncField];
    self.audioSyncStepper=[[NSStepper alloc] initWithFrame:NSMakeRect(230,178,20,28)];self.audioSyncStepper.minValue=shuttle_output_audio::MinAudioOffsetMS;self.audioSyncStepper.maxValue=shuttle_output_audio::MaxAudioOffsetMS;self.audioSyncStepper.increment=10;self.audioSyncStepper.integerValue=self.audioSyncField.integerValue;self.audioSyncStepper.valueWraps=NO;self.audioSyncStepper.target=self;self.audioSyncStepper.action=@selector(audioSyncChanged:);[v addSubview:self.audioSyncStepper];
    [v addSubview:label(@"ms  ·  − earlier / + later",NSMakeRect(264,181,255,24),12)];
    self.resetAudioSync=[NSButton buttonWithTitle:@"Reset" target:self action:@selector(resetAudioSync:)];self.resetAudioSync.frame=NSMakeRect(548,178,78,30);[v addSubview:self.resetAudioSync];
    auto* overlayTitle=label(@"HDMI OVERLAYS",NSMakeRect(24,140,602,20),11);overlayTitle.font=[NSFont boldSystemFontOfSize:11];overlayTitle.textColor=NSColor.secondaryLabelColor;[v addSubview:overlayTitle];
    self.showTimecode=[NSButton checkboxWithTitle:@"Timecode" target:self action:@selector(timecodeChanged:)];self.showTimecode.frame=NSMakeRect(24,103,260,26);self.showTimecode.state=[[NSUserDefaults standardUserDefaults] boolForKey:@"ShowHDMITimecode"]?NSControlStateValueOn:NSControlStateValueOff;self.showTimecode.toolTip=@"Show timeline timecode on HDMI. Dashes mean the editor supplied no timecode.";[v addSubview:self.showTimecode];
    self.timecodePosition=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(410,101,216,30)];[self.timecodePosition addItemsWithTitles:@[@"Top left",@"Top right",@"Bottom right",@"Bottom left",@"Top centre",@"Bottom centre"]];[self.timecodePosition selectItemAtIndex:shuttle_sink::savedTimecodePosition([[NSUserDefaults standardUserDefaults] integerForKey:@"HDMITimecodePosition"])];self.timecodePosition.target=self;self.timecodePosition.action=@selector(timecodePositionChanged:);self.timecodePosition.accessibilityLabel=@"Timecode position";[v addSubview:self.timecodePosition];
    self.showMeters=[NSButton checkboxWithTitle:@"L/R audio meters" target:self action:@selector(metersChanged:)];self.showMeters.frame=NSMakeRect(24,67,260,26);self.showMeters.state=[[NSUserDefaults standardUserDefaults] boolForKey:@"ShowHDMIAudioMeters"]?NSControlStateValueOn:NSControlStateValueOff;[v addSubview:self.showMeters];
    self.meterPosition=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(410,65,216,30)];[self.meterPosition addItemsWithTitles:@[@"Top left",@"Top right",@"Bottom right",@"Bottom left",@"Top centre",@"Bottom centre"]];[self.meterPosition selectItemAtIndex:shuttle_output_audio::savedMeterPosition([[NSUserDefaults standardUserDefaults] integerForKey:@"HDMIAudioMeterPosition"])];self.meterPosition.target=self;self.meterPosition.action=@selector(metersChanged:);self.meterPosition.accessibilityLabel=@"Audio meter position";[v addSubview:self.meterPosition];
    self.titleSafe=[NSButton checkboxWithTitle:@"Title safe (80%)" target:self action:@selector(safeZonesChanged:)];self.titleSafe.frame=NSMakeRect(24,28,280,26);self.titleSafe.state=[[NSUserDefaults standardUserDefaults] boolForKey:@"ShowHDMITitleSafe"]?NSControlStateValueOn:NSControlStateValueOff;[v addSubview:self.titleSafe];
    self.actionSafe=[NSButton checkboxWithTitle:@"Action safe (90%)" target:self action:@selector(safeZonesChanged:)];self.actionSafe.frame=NSMakeRect(340,28,286,26);self.actionSafe.state=[[NSUserDefaults standardUserDefaults] boolForKey:@"ShowHDMIActionSafe"]?NSControlStateValueOn:NSControlStateValueOff;[v addSubview:self.actionSafe];
    self.diagnosticsScroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,650,300)];self.diagnosticsScroll.hasVerticalScroller=YES;self.diagnosticsScroll.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
    self.log=[[NSTextView alloc] initWithFrame:self.diagnosticsScroll.bounds];self.log.editable=NO;self.log.font=[NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];self.log.textColor=NSColor.textColor;self.log.backgroundColor=NSColor.textBackgroundColor;self.diagnosticsScroll.documentView=self.log;
    [self sourceChanged:nil];
    [self beginAudioRouteMonitoring];
    if(self.embedded)return;
    [self.window center];[self.window makeKeyAndOrderFront:nil];[NSApp activateIgnoringOtherApps:YES];
    if(NSProcessInfo.processInfo.arguments.count==3 && [NSProcessInfo.processInfo.arguments[1] isEqual:@"--render"]) {
        NSString* path=NSProcessInfo.processInfo.arguments[2];dispatch_after(dispatch_time(DISPATCH_TIME_NOW,300*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
            auto* rep=[v bitmapImageRepForCachingDisplayInRect:v.bounds];[v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];
            BOOL ok=[[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];exit(ok?0:1);
        });
    }
}
- (void)openAudioSettings:(id)sender {[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.Sound-Settings.extension"]];}
- (void)beginAudioRouteMonitoring {
    using namespace shuttle_audio_route;
    NSString* saved=[[NSUserDefaults standardUserDefaults] stringForKey:PreviousUIDPreference];
    if(saved.length&&![saved isEqual:HDMIUID])self.previousMediaAudioUID=saved;
    // A saved route after a crash is offered for explicit recovery. Launching
    // or merely quitting a new session never adopts/restores that old route.
    __weak OutputHost* weakSelf=self;
    self.audioRouteListener=^(UInt32 count,const AudioObjectPropertyAddress* addresses){
        OutputHost* host=weakSelf;if(!host)return;
        OSStatus status=0;AudioDeviceID current=mediaOutput(status);NSString* currentUID=status?nil:uid(current,status);
        if(host.managesMediaAudio&&currentUID.length&&![currentUID isEqual:HDMIUID]){
            [host clearSavedAudioRoute];
            [host outputMessage:@"Mac audio output changed outside Shuttle Camera. Keeping that selection; automatic audio restoration is cancelled."];
        }
        [host refreshAudioRoute];
    };
    auto address=mediaOutputAddress();
    OSStatus status=AudioObjectAddPropertyListenerBlock(kAudioObjectSystemObject,&address,dispatch_get_main_queue(),self.audioRouteListener);
    if(status){self.audioRouteListener=nil;[self outputMessage:[NSString stringWithFormat:@"Could not watch Mac audio-output changes: %@. Current output is still checked before restoration.",errorText(status)]];}
    [self refreshAudioRoute];
    if(self.previousMediaAudioUID.length)[self outputMessage:@"A previous audio output was saved by an earlier session. Click Restore audio to recover it, or Use HDMI audio to use that saved route for this session. Audio has not been changed at startup."];
}
- (void)refreshAudioRoute {
    using namespace shuttle_audio_route;
    OSStatus status=0;AudioDeviceID current=mediaOutput(status);NSString* currentUID=status?nil:uid(current,status);
    if(status||!currentUID.length){self.audioRouteLabel.stringValue=[NSString stringWithFormat:@"Mac media audio: cannot read output (%@)",errorText(status)];}
    else {
        NSString* title=name(current);
        self.audioRouteLabel.stringValue=[NSString stringWithFormat:@"Output: %@%@",title,self.managesMediaAudio?@"":@""];
        if(![currentUID isEqual:self.lastReportedAudioUID]){self.lastReportedAudioUID=currentUID;[self outputMessage:[NSString stringWithFormat:@"Mac media audio output: %@.",title]];}
    }
    self.restoreAudio.enabled=self.previousMediaAudioUID.length>0;
    self.stop.enabled=self.task.running||self.managesMediaAudio;
}
- (void)clearSavedAudioRoute {
    self.previousMediaAudioUID=nil;self.managesMediaAudio=NO;
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:shuttle_audio_route::PreviousUIDPreference];
    [[NSUserDefaults standardUserDefaults] synchronize];
}
- (void)useHDMIAudio:(id)sender {
    using namespace shuttle_audio_route;
    OSStatus status=0;AudioDeviceID hdmi=outputForUID(HDMIUID,status);
    if(hdmi==kAudioObjectUnknown){[self outputMessage:[NSString stringWithFormat:@"Cannot use Shuttle HDMI audio: %@. Check that the Shuttle audio driver is available in Sound settings.",errorText(status)]];[self refreshAudioRoute];return;}
    AudioDeviceID current=mediaOutput(status);NSString* currentUID=status?nil:uid(current,status);
    if(status||!currentUID.length){[self outputMessage:[NSString stringWithFormat:@"Cannot remember the current audio output: %@. Audio was not changed.",errorText(status)]];[self refreshAudioRoute];return;}
    if([currentUID isEqual:HDMIUID]){
        self.managesMediaAudio=self.previousMediaAudioUID.length>0;
        [self outputMessage:self.managesMediaAudio?@"HDMI audio is already selected. Its saved previous output will restore on Stop.":@"HDMI audio is already selected. No earlier output was saved; use Sound settings to choose another device."];
        [self refreshAudioRoute];return;
    }
    // Save before the only explicit switch so a crash leaves a recovery UID.
    self.previousMediaAudioUID=currentUID;
    NSUserDefaults* defaults=[NSUserDefaults standardUserDefaults];[defaults setObject:currentUID forKey:PreviousUIDPreference];
    if(![defaults synchronize]){[self clearSavedAudioRoute];[self outputMessage:@"Could not save the previous audio output. Audio was not changed."];[self refreshAudioRoute];return;}
    self.managesMediaAudio=YES;
    status=setMediaOutput(hdmi);
    if(status){[self clearSavedAudioRoute];[self outputMessage:[NSString stringWithFormat:@"Could not select HDMI audio: %@.",errorText(status)]];}
    else [self outputMessage:[NSString stringWithFormat:@"HDMI audio selected by your click. Other Mac media audio may also use the Shuttle. Previous output: %@. Stop or Restore audio returns to it unless you select another output.",name(current)]];
    [self refreshAudioRoute];
}
- (void)restoreAudio:(id)sender {[self restorePreviousAudio:@"Restore audio" explicit:YES];}
- (void)restorePreviousAudio:(NSString*)reason explicit:(BOOL)explicitRecovery {
    using namespace shuttle_audio_route;
    if(!self.previousMediaAudioUID.length||(!self.managesMediaAudio&&!explicitRecovery))return;
    OSStatus status=0;AudioDeviceID current=mediaOutput(status);NSString* currentUID=status?nil:uid(current,status);
    if(status||!currentUID.length){[self outputMessage:[NSString stringWithFormat:@"%@: could not check current audio output (%@). Saved output retained for Restore audio.",reason,errorText(status)]];return;}
    if(![currentUID isEqual:HDMIUID]){[self clearSavedAudioRoute];[self outputMessage:@"Keeping your current Mac audio output; it is no longer the Shuttle HDMI route."];[self refreshAudioRoute];return;}
    AudioDeviceID previous=outputForUID(self.previousMediaAudioUID,status);
    if(previous==kAudioObjectUnknown){[self outputMessage:[NSString stringWithFormat:@"%@: previous audio output is unavailable (%@). Choose an output in Sound settings, or reconnect it and click Restore audio.",reason,errorText(status)]];[self refreshAudioRoute];return;}
    // Recheck immediately before writing: do not replace a later user choice.
    current=mediaOutput(status);currentUID=status?nil:uid(current,status);
    if(status||![currentUID isEqual:HDMIUID]){if(!status)[self clearSavedAudioRoute];[self outputMessage:@"Audio restoration skipped because the current output changed or could not be checked."];[self refreshAudioRoute];return;}
    status=setMediaOutput(previous);
    if(status)[self outputMessage:[NSString stringWithFormat:@"%@: could not restore the previous audio output (%@). Click Restore audio to retry.",reason,errorText(status)]];
    else {[self clearSavedAudioRoute];[self outputMessage:[NSString stringWithFormat:@"%@: restored Mac media audio to %@.",reason,name(previous)]];}
    [self refreshAudioRoute];
}
- (void)sourceChanged:(id)sender {
    NSInteger source=self.source.indexOfSelectedItem;
    [[NSUserDefaults standardUserDefaults] setInteger:source forKey:@"OutputSource"];
    self.outputHelp.stringValue=source==3?@"Start Premiere output here before enabling Mercury Transmit.\nIn Premiere Settings → Playback, select Intensity Shuttle — HDMI Output.\nFor sound, select Intensity Shuttle — HDMI Audio in Audio Hardware.\nDisable Mercury Transmit before stopping output here.":@"Close Shuttle camera windows before output. Stop output before capturing.\nFor timeline sound, click Use HDMI audio before opening Final Cut.\nStart Final Cut output here and wait for Ready before enabling A/V Output.\nTurn off Final Cut’s A/V Output before stopping output here.";
    self.choose.enabled=!self.task;self.loop.enabled=source==1&&!self.task;
    self.start.title=source==2?@"Start Final Cut":source==3?@"Start Premiere":@"Start output";
    self.choose.hidden=self.fileLabel.hidden=self.loop.hidden=source!=1;
    self.source.toolTip=self.outputHelp.stringValue;
    self.audioSyncField.enabled=source>=2;self.audioSyncStepper.enabled=source>=2;self.resetAudioSync.enabled=source>=2;
    self.showTimecode.enabled=source>=2;
    self.timecodePosition.enabled=source>=2;
    if(!self.task)self.readinessLabel.stringValue=@"Stopped";
}
- (void)audioSyncChanged:(id)sender {
    NSInteger requested=sender==self.audioSyncStepper?self.audioSyncStepper.integerValue:self.audioSyncField.integerValue;
    int value=shuttle_output_audio::clampAudioOffset(int(requested));
    self.audioSyncField.integerValue=value;self.audioSyncStepper.integerValue=value;
    [[NSUserDefaults standardUserDefaults] setInteger:value forKey:@"HDMIAudioOffsetMS"];
    if(![[NSUserDefaults standardUserDefaults] synchronize]){[self outputMessage:@"Could not save the audio sync setting. Try again."];return;}
    [self outputMessage:[NSString stringWithFormat:@"Final Cut HDMI audio sync: %+d ms — %@.",value,value<0?@"sound earlier":value>0?@"sound later":@"no adjustment"]];
}
- (void)resetAudioSync:(id)sender {self.audioSyncField.integerValue=0;[self audioSyncChanged:self.audioSyncField];}
- (void)timecodeChanged:(id)sender {
    BOOL enabled=self.showTimecode.state==NSControlStateValueOn;
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:@"ShowHDMITimecode"];
    if(![[NSUserDefaults standardUserDefaults] synchronize]){[self outputMessage:@"Could not save the timecode setting. Try again."];return;}
    [self outputMessage:enabled?@"HDMI timecode overlay enabled. Dashes mean the editor supplied no valid timecode.":@"HDMI timecode overlay disabled."];
}
- (void)timecodePositionChanged:(id)sender {
    [[NSUserDefaults standardUserDefaults] setInteger:self.timecodePosition.indexOfSelectedItem+1 forKey:@"HDMITimecodePosition"];
    if(![[NSUserDefaults standardUserDefaults] synchronize]){[self outputMessage:@"Could not save the timecode position. Try again."];return;}
    [self outputMessage:[NSString stringWithFormat:@"HDMI timecode position: %@.",self.timecodePosition.titleOfSelectedItem]];
}
- (void)metersChanged:(id)sender {
    [[NSUserDefaults standardUserDefaults] setBool:self.showMeters.state==NSControlStateValueOn forKey:@"ShowHDMIAudioMeters"];
    [[NSUserDefaults standardUserDefaults] setInteger:self.meterPosition.indexOfSelectedItem+1 forKey:@"HDMIAudioMeterPosition"];
    if(![[NSUserDefaults standardUserDefaults] synchronize]){[self outputMessage:@"Could not save the audio meter settings. Try again."];return;}
    [self outputMessage:self.showMeters.state==NSControlStateValueOn?[NSString stringWithFormat:@"HDMI L/R audio meters enabled — %@.",self.meterPosition.titleOfSelectedItem]:@"HDMI L/R audio meters disabled."];
}
- (void)safeZonesChanged:(id)sender {
    [[NSUserDefaults standardUserDefaults] setBool:self.titleSafe.state==NSControlStateValueOn forKey:@"ShowHDMITitleSafe"];
    [[NSUserDefaults standardUserDefaults] setBool:self.actionSafe.state==NSControlStateValueOn forKey:@"ShowHDMIActionSafe"];
    if(![[NSUserDefaults standardUserDefaults] synchronize]){[self outputMessage:@"Could not save the safe-zone settings. Try again."];return;}
    [self outputMessage:[NSString stringWithFormat:@"HDMI guides — title safe: %@; action safe: %@.",self.titleSafe.state==NSControlStateValueOn?@"on":@"off",self.actionSafe.state==NSControlStateValueOn?@"on":@"off"]];
}
- (void)chooseMovie:(id)sender {
    NSOpenPanel* panel=[NSOpenPanel openPanel];panel.canChooseDirectories=NO;panel.allowsMultipleSelection=NO;
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response){if(response==NSModalResponseOK){self.movie=panel.URL.path;self.fileLabel.stringValue=self.movie.lastPathComponent;[self.source selectItemAtIndex:1];[self sourceChanged:nil];}}];
}
- (void)setRunning:(BOOL)running {
    self.mode.enabled=!running;self.source.enabled=!running;self.choose.enabled=!running;self.loop.enabled=!running&&self.source.indexOfSelectedItem==1;self.start.enabled=!running;self.stop.enabled=running||self.managesMediaAudio;
}
- (void)checkTimelineReadiness:(NSTimer*)timer {
    if(!self.task.running){[timer invalidate];self.readinessTimer=nil;return;}
    if(self.source.indexOfSelectedItem==3){if(self.readinessDeadline.timeIntervalSinceNow<=0){[timer invalidate];self.readinessTimer=nil;self.startupFailed=YES;[self outputMessage:@"Premiere USB output did not become ready. Check the USB connection and close capture clients."];[self stopOutput:nil];}return;}
    if(timelineOutputReady(self.mode.indexOfSelectedItem)){
        [timer invalidate];self.readinessTimer=nil;
        self.readinessLabel.stringValue=@"Ready for Final Cut";
        [self outputMessage:@"Ready for Final Cut. Select Intensity Shuttle — HDMI Output and enable Window → A/V Output. Keep Shuttle Camera open."];
    }else if(self.readinessDeadline.timeIntervalSinceNow<=0){
        [timer invalidate];self.readinessTimer=nil;
        self.startupFailed=YES;
        self.readinessLabel.stringValue=@"Final Cut output is unavailable — Help → Diagnostics.";
        [self outputMessage:@"The output driver did not become ready. Check Enable A/V output driver. Leave Final Cut’s A/V Output off until Ready appears."];
        [self stopOutput:nil];
    }
}
- (void)startOutput:(id)sender {
    if(self.task)return;
    self.startupFailed=NO;
    if(self.source.indexOfSelectedItem==1&&!self.movie){[self chooseMovie:nil];return;}
    if(self.source.indexOfSelectedItem>=2){[self.window makeFirstResponder:nil];[self audioSyncChanged:self.audioSyncField];}
    // The USB sender brings the CMIO device online, never the other way round.
    [[NSUserDefaults standardUserDefaults] setInteger:self.mode.indexOfSelectedItem forKey:@"OutputMode"];
    [[NSUserDefaults standardUserDefaults] setBool:self.loop.state==NSControlStateValueOn forKey:@"LoopMovie"];
    NSString* mode=@[@"576i50",@"1080i50",@"1080p25",@"480i5994",@"1080i5994",@"1080p2997"][self.mode.indexOfSelectedItem];
    self.task=[NSTask new];self.task.executableURL=[[NSBundle mainBundle].executableURL.URLByDeletingLastPathComponent URLByAppendingPathComponent:@"ShuttlePlayback"];
    self.task.arguments=self.source.indexOfSelectedItem==3?@[@"--premiere",mode,@"live"]:self.source.indexOfSelectedItem==2?@[@"--sink",mode,@"live"]:self.source.indexOfSelectedItem==1?@[self.loop.state==NSControlStateValueOn?@"--loop":@"--play",mode,self.movie]:@[@"--bars",mode,@"30"];
    NSPipe* pipe=[NSPipe pipe];self.task.standardOutput=pipe;self.task.standardError=pipe;self.log.string=self.source.indexOfSelectedItem==2?@"Starting timeline output…\nUse HDMI audio sends Mac media sound to the Shuttle. Stop restores the saved output unless you select another device.\n":@"Starting output…\n";
    __weak OutputHost* weakSelf=self;
    pipe.fileHandleForReading.readabilityHandler=^(NSFileHandle* h){NSData* data=h.availableData;if(!data.length){h.readabilityHandler=nil;return;}NSString* text=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];if(text)dispatch_async(dispatch_get_main_queue(),^{OutputHost* host=weakSelf;if(host){[host handleOutputText:text];}});};
    self.task.terminationHandler=^(NSTask* task){dispatch_async(dispatch_get_main_queue(),^{OutputHost* host=weakSelf;if(!host||host.task!=task)return;[host.readinessTimer invalidate];host.readinessTimer=nil;[host.log.textStorage appendAttributedString:[[NSAttributedString alloc] initWithString:task.terminationStatus==0?@"Output stopped.\n":@"Output ended; open Help → Diagnostics.\n"]];host.task=nil;host.readinessLabel.stringValue=!host.startupFailed&&task.terminationStatus==0?@"Output is stopped.":@"Output failed — Help → Diagnostics.";[host restorePreviousAudio:@"Output ended" explicit:NO];[host setRunning:NO];});};
    NSError* error=nil;if(![self.task launchAndReturnError:&error]){self.log.string=error.localizedDescription;self.task=nil;self.readinessLabel.stringValue=@"Output could not start — Help → Diagnostics.";[self restorePreviousAudio:@"Output could not start" explicit:NO];return;}[self setRunning:YES];
    self.readinessLabel.stringValue=self.source.indexOfSelectedItem==3?@"Starting…":self.source.indexOfSelectedItem==2?@"Starting…":@"Running";
    if(self.source.indexOfSelectedItem>=2){
        self.readinessDeadline=[NSDate dateWithTimeIntervalSinceNow:8];
        self.readinessTimer=[NSTimer scheduledTimerWithTimeInterval:0.2 repeats:YES block:^(NSTimer* timer){[weakSelf checkTimelineReadiness:timer];}];
    }
}
- (void)handleOutputText:(NSString*)text {
    [self.log.textStorage appendAttributedString:[[NSAttributedString alloc] initWithString:text attributes:@{NSForegroundColorAttributeName:NSColor.textColor}]];
    if(self.log.string.length>32768)[self.log.textStorage deleteCharactersInRange:NSMakeRange(0,self.log.string.length-24576)];[self.log scrollRangeToVisible:NSMakeRange(self.log.string.length,0)];
    if(self.source.indexOfSelectedItem==3&&[self.log.string containsString:@"Premiere USB ready"]){[self.readinessTimer invalidate];self.readinessTimer=nil;self.readinessLabel.stringValue=@"Ready for Premiere";}
}
- (void)stopOutput:(id)sender {[self.readinessTimer invalidate];self.readinessTimer=nil;if(self.task.running){if(!self.startupFailed)self.readinessLabel.stringValue=@"Stopping output…";[self.task terminate];}[self restorePreviousAudio:@"Output stopped" explicit:NO];}
- (void)outputMessage:(NSString*)message{puts(message.UTF8String);fflush(stdout);if(self.log)[self handleOutputText:[message stringByAppendingString:@"\n"]];if([message hasPrefix:@"Could not"]||[message hasPrefix:@"Cannot"]){self.readinessLabel.stringValue=message;self.readinessLabel.toolTip=message;}}
- (void)activateOutput:(id)sender{
    [self outputMessage:@"Requesting A/V output driver activation. If asked, enable Shuttle HDMI Output Extension in System Settings → Camera Extensions."];
    OSSystemExtensionRequest* request=[OSSystemExtensionRequest activationRequestForExtension:@"local.shuttle.output.extension" queue:dispatch_get_main_queue()];request.delegate=self;[[OSSystemExtensionManager sharedManager] submitRequest:request];
}
- (OSSystemExtensionReplacementAction)request:(OSSystemExtensionRequest*)request actionForReplacingExtension:(OSSystemExtensionProperties*)oldExtension withExtension:(OSSystemExtensionProperties*)newExtension{return OSSystemExtensionReplacementActionReplace;}
- (void)requestNeedsUserApproval:(OSSystemExtensionRequest*)request{[self outputMessage:@"macOS is waiting for approval of Shuttle HDMI Output Extension in System Settings → General → Login Items & Extensions → Camera Extensions."];}
- (void)request:(OSSystemExtensionRequest*)request didFinishWithResult:(OSSystemExtensionRequestResult)result{[self outputMessage:result==OSSystemExtensionRequestCompleted?@"A/V output driver activation completed.":@"A/V output driver activation will complete after restarting the Mac."];if(self.activationOnly)exit(0);}
- (void)request:(OSSystemExtensionRequest*)request didFailWithError:(NSError*)error{[self outputMessage:error.localizedDescription];if(self.activationOnly)exit(1);}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)app{return YES;}
- (void)applicationWillTerminate:(NSNotification*)note {
    [self.readinessTimer invalidate];self.readinessTimer=nil;
    [self restorePreviousAudio:@"Shuttle Camera quit" explicit:NO];
    if(self.audioRouteListener){auto address=shuttle_audio_route::mediaOutputAddress();AudioObjectRemovePropertyListenerBlock(kAudioObjectSystemObject,&address,dispatch_get_main_queue(),self.audioRouteListener);self.audioRouteListener=nil;}
    if(self.task.running){[self.task terminate];[self.task waitUntilExit];}
}
@end
int main(int argc,const char**argv){@autoreleasepool {NSApplication* app=[NSApplication sharedApplication];app.activationPolicy=NSApplicationActivationPolicyRegular;if(argc==3&&!strcmp(argv[1],"--render")){app.activationPolicy=NSApplicationActivationPolicyAccessory;app.appearance=[NSAppearance appearanceNamed:NSAppearanceNameAqua];}OutputHost* host=[OutputHost new];app.delegate=host;[app run];}return 0;}
