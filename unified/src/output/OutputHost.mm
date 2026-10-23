#include "ExtendedDisplaySize.hpp"
// GPL-2.0-or-later. Local HDMI output controls, independent of camera activation.
#import <Cocoa/Cocoa.h>
#import <SystemExtensions/SystemExtensions.h>
#import <CoreMediaIO/CoreMediaIO.h>
#import <CoreMedia/CoreMedia.h>
#include "AudioRoute.hpp"
#include "AudioSync.hpp"
#include "Timecode.hpp"
#include "AudioMeters.hpp"
#include "MirrorFrame.hpp"
#include "Scopes.hpp"
#include "FrameSizing.hpp"
#include "../ExtendedDisplay.mm"
#include <vector>
@interface OutputCanvas : NSView
@end
@implementation OutputCanvas
- (BOOL)isOpaque{return YES;}
- (void)drawRect:(NSRect)rect{[NSColor.windowBackgroundColor setFill];NSRectFill(rect);}
@end
@interface OutputHost : NSObject <NSApplicationDelegate,NSWindowDelegate,OSSystemExtensionRequestDelegate> {std::unique_ptr<shuttle_mirror::Feed> _mirror;}
@property BOOL activationOnly;
@property BOOL embedded;
@property NSPopUpButton *monitorTarget,*macView,*shuttleView,*macScope,*shuttleScope;
@property BOOL runningMac,runningShuttle;
@property NSTask* screenTask;
@property NSString* mirrorPath;
@property NSWindow* window;
@property NSPopUpButton* mode,*connector,*sizing,*virtualDisplay,*listenDevice;
@property NSTextField *connectorLabel,*virtualDisplayLabel;
@property NSButton* listen;
@property NSSlider* listenVolume;
@property(copy) AudioObjectPropertyListenerBlock devicesListener;
@property ShuttleExtendedDisplay* extendedDisplay;
@property NSTextField* extendedHint;
@property NSPopUpButton* source;
@property NSPopUpButton* desktopDisplay;
@property NSTextField* desktopLabel;
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
static bool timelineOutputReady(NSInteger mode,BOOL virtualOutput=NO) {
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
        bool matches=uid&&CFEqual(uid,virtualOutput?CFSTR("local.shuttle.output.virtual"):CFSTR("local.shuttle.output.cmio"));if(uid)CFRelease(uid);if(!matches)continue;
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
    // Snapshot the old shared monitor choices once, then keep outputs independent.
    for(NSString* key in @[@"ShowHDMITimecode",@"ShowHDMIAudioMeters",@"ShowHDMITitleSafe",@"ShowHDMIActionSafe",@"HDMITimecodePosition",@"HDMIAudioMeterPosition"]){NSString* virtualKey=[key stringByReplacingOccurrencesOfString:@"HDMI" withString:@"Virtual"];if(![NSUserDefaults.standardUserDefaults objectForKey:virtualKey])[NSUserDefaults.standardUserDefaults setObject:[NSUserDefaults.standardUserDefaults objectForKey:key]?:@0 forKey:virtualKey];}
    [NSUserDefaults.standardUserDefaults synchronize];
    NSInteger legacy=MAX(0,MIN(2,[NSUserDefaults.standardUserDefaults integerForKey:@"FCPOutputDestination"]));
    for(NSString* prefix in @[@"Mac",@"Shuttle"]){BOOL mac=[prefix isEqual:@"Mac"];NSString* key=[prefix stringByAppendingString:@"MonitorMode"],*style=[prefix stringByAppendingString:@"ScopeStyle"];NSInteger old=[NSUserDefaults.standardUserDefaults integerForKey:mac?@"VirtualOutputView":@"HDMIOutputView"];BOOL enabled=mac?legacy!=0:legacy!=1;if(![NSUserDefaults.standardUserDefaults objectForKey:key])[NSUserDefaults.standardUserDefaults setInteger:enabled?(old>0?1:0):2 forKey:key];if(![NSUserDefaults.standardUserDefaults objectForKey:style])[NSUserDefaults.standardUserDefaults setInteger:old>=1&&old<=6?old-1:0 forKey:style];}
    self.window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,650,720) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable backing:NSBackingStoreBuffered defer:NO];
    self.window.title=@"Shuttle Video Output";self.window.delegate=self;
    self.window.contentView=[[OutputCanvas alloc] initWithFrame:NSMakeRect(0,0,650,720)];
    NSView* v=self.window.contentView;
    [v addSubview:label(@"Source",NSMakeRect(24,602,115,24),13)];
    self.source=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(150,599,476,30)];
    [self.source addItemsWithTitles:@[@"Test pattern",@"Movie file",@"Final Cut Pro",@"Premiere Pro",@"Mac desktop",@"Extended display",@"Idle screen"]];self.source.target=self;self.source.action=@selector(sourceChanged:);[v addSubview:self.source];
    NSInteger savedSource=[[NSUserDefaults standardUserDefaults] integerForKey:@"OutputSource"];
    if(savedSource>=0&&savedSource<7)[self.source selectItemAtIndex:savedSource];
    [v addSubview:label(@"Format",NSMakeRect(24,560,115,24),13)];
    self.mode=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(150,557,476,30)];
    [self.mode addItemsWithTitles:@[@"PAL · 576i50",@"1080i50",@"1080p25",@"NTSC · 480i59.94",@"1080i59.94",@"1080p29.97"]];
    self.connectorLabel=label(@"Connection",NSMakeRect(24,518,115,24),13);[v addSubview:self.connectorLabel];
    self.connector=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(150,515,244,30)];[self.connector addItemsWithTitles:@[@"HDMI",@"S-Video",@"Composite",@"Component"]];NSInteger savedConnector=[NSUserDefaults.standardUserDefaults integerForKey:@"OutputConnector"];[self.connector selectItemAtIndex:savedConnector>=0&&savedConnector<4?savedConnector:0];self.connector.target=self;self.connector.action=@selector(connectorChanged:);self.connector.accessibilityLabel=@"Output connector";self.connector.toolTip=@"Choose the connector in use. Compatible outputs may stay active simultaneously. S-Video and Composite require PAL/NTSC; PAL composite playback was tested; other connector/format combinations still need checking.";[v addSubview:self.connector];
    self.virtualDisplayLabel=label(@"Mac display",NSMakeRect(24,518,115,24),13);[v addSubview:self.virtualDisplayLabel];
    self.virtualDisplay=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(150,515,476,30)];self.virtualDisplay.target=self;self.virtualDisplay.action=@selector(virtualDisplayChanged:);self.virtualDisplay.accessibilityLabel=@"Virtual Shuttle display";[v addSubview:self.virtualDisplay];[self refreshVirtualDisplays];
    NSInteger index=[[NSUserDefaults standardUserDefaults] integerForKey:@"OutputMode"];
    if(index>=0&&index<6)[self.mode selectItemAtIndex:index];[v addSubview:self.mode];
    self.choose=[NSButton buttonWithTitle:@"Choose movie…" target:self action:@selector(chooseMovie:)];self.choose.frame=NSMakeRect(24,473,140,30);[v addSubview:self.choose];
    self.fileLabel=label(@"No movie selected",NSMakeRect(174,477,136,24),12);self.fileLabel.lineBreakMode=NSLineBreakByTruncatingMiddle;[v addSubview:self.fileLabel];
    self.loop=[NSButton checkboxWithTitle:@"Loop" target:nil action:nil];self.loop.frame=NSMakeRect(320,475,80,26);self.loop.state=[[NSUserDefaults standardUserDefaults] boolForKey:@"LoopMovie"]?NSControlStateValueOn:NSControlStateValueOff;[v addSubview:self.loop];
    self.desktopLabel=label(@"Display",NSMakeRect(24,478,115,24),13);[v addSubview:self.desktopLabel];
    self.desktopDisplay=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(150,475,250,30)];
    CGDirectDisplayID displays[32];uint32_t count=0;CGGetActiveDisplayList(32,displays,&count);
    for(uint32_t n=0;n<count;++n){auto id=displays[n];[self.desktopDisplay addItemWithTitle:[NSString stringWithFormat:@"Display %u · %zu × %zu%@",n+1,CGDisplayPixelsWide(id),CGDisplayPixelsHigh(id),id==CGMainDisplayID()?@" · Main":@""]];self.desktopDisplay.lastItem.representedObject=@(id);}
    [v addSubview:self.desktopDisplay];
    self.sizing=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(410,475,216,30)];[self.sizing addItemsWithTitles:@[@"Fit",@"Fill",@"Stretch"]];[self.sizing selectItemAtIndex:long(shuttle_output::sizingValue([NSUserDefaults.standardUserDefaults integerForKey:@"PlaybackSizing"]))];self.sizing.accessibilityLabel=@"Video sizing";self.sizing.toolTip=@"Fit keeps the whole image with borders. Fill crops to cover the frame. Stretch fills the frame without preserving aspect ratio and follows desktop resolution changes while output runs.";[v addSubview:self.sizing];
    self.extendedHint=label(@"Drag windows to Shuttle Extended Display.",NSMakeRect(24,477,376,24),12);[v addSubview:self.extendedHint];
    self.start=[NSButton buttonWithTitle:@"Start output" target:self action:@selector(startOutput:)];self.start.frame=NSMakeRect(24,430,190,34);self.start.bezelStyle=NSBezelStyleRounded;[v addSubview:self.start];
    self.stop=[NSButton buttonWithTitle:@"Stop" target:self action:@selector(stopOutput:)];self.stop.frame=NSMakeRect(224,430,100,34);self.stop.enabled=NO;[v addSubview:self.stop];
    self.readinessLabel=label(@"Stopped",NSMakeRect(24,405,602,20),12);self.readinessLabel.textColor=NSColor.secondaryLabelColor;[v addSubview:self.readinessLabel];
    self.outputHelp=label(@"",NSZeroRect,12); // Available through Help, not on the main panel.
    auto* audioTitle=label(@"AUDIO",NSMakeRect(24,374,602,20),11);audioTitle.font=[NSFont boldSystemFontOfSize:11];audioTitle.textColor=NSColor.secondaryLabelColor;[v addSubview:audioTitle];
    self.useHDMIAudio=[NSButton buttonWithTitle:@"Use Shuttle Audio" target:self action:@selector(useHDMIAudio:)];self.useHDMIAudio.frame=NSMakeRect(24,338,190,30);self.useHDMIAudio.toolTip=@"Route editor audio to Virtual Shuttle Audio for HDMI, meters and optional Mac listening. The previous output restores when you stop.";[v addSubview:self.useHDMIAudio];
    self.restoreAudio=[NSButton buttonWithTitle:@"Restore audio" target:self action:@selector(restoreAudio:)];self.restoreAudio.frame=NSMakeRect(224,338,130,30);[v addSubview:self.restoreAudio];
    NSButton* audioSettings=[NSButton buttonWithTitle:@"Sound settings…" target:self action:@selector(openAudioSettings:)];audioSettings.frame=NSMakeRect(476,338,150,30);[v addSubview:audioSettings];
    self.audioRouteLabel=label(@"",NSMakeRect(24,315,602,18),11);self.audioRouteLabel.textColor=NSColor.secondaryLabelColor;self.audioRouteLabel.lineBreakMode=NSLineBreakByTruncatingMiddle;self.audioRouteLabel.toolTip=@"Meters receive the audio routed through Virtual Shuttle Audio. Listen adds the selected Mac speakers/headphones; it does not select the editor audio source.";[v addSubview:self.audioRouteLabel];
    [NSUserDefaults.standardUserDefaults setBool:NO forKey:@"OutputListenEnabled"];
    self.listen=[NSButton checkboxWithTitle:@"Listen on Mac" target:self action:@selector(listenChanged:)];self.listen.frame=NSMakeRect(24,277,120,28);self.listen.toolTip=@"Listen on the selected Mac speakers/headphones as well as the Shuttle. Use Shuttle Audio must route the editor sound first. Meters measure that same audio before listening volume; they keep working with Listen off.";[v addSubview:self.listen];
    self.listenDevice=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(150,276,250,30)];self.listenDevice.target=self;self.listenDevice.action=@selector(listenDeviceChanged:);self.listenDevice.accessibilityLabel=@"Listening speakers or headphones";[v addSubview:self.listenDevice];
    [v addSubview:label(@"Volume",NSMakeRect(410,279,55,20),12)];self.listenVolume=[NSSlider sliderWithValue:[NSUserDefaults.standardUserDefaults objectForKey:@"OutputListenVolume"]?[NSUserDefaults.standardUserDefaults doubleForKey:@"OutputListenVolume"]:.5 minValue:0 maxValue:1 target:self action:@selector(listenChanged:)];self.listenVolume.frame=NSMakeRect(470,277,156,26);self.listenVolume.continuous=YES;self.listenVolume.accessibilityLabel=@"Output listening volume";self.listenVolume.toolTip=@"Local listening only; does not change the meters or Shuttle output level.";[v addSubview:self.listenVolume];[self refreshListeningDevices];
    [v addSubview:label(@"Audio sync",NSMakeRect(24,242,120,24),13)];
    self.audioSyncField=[[NSTextField alloc] initWithFrame:NSMakeRect(150,241,76,26)];
    NSNumberFormatter* syncFormat=[NSNumberFormatter new];syncFormat.allowsFloats=NO;syncFormat.minimum=@(shuttle_output_audio::MinAudioOffsetMS);syncFormat.maximum=@(shuttle_output_audio::MaxAudioOffsetMS);self.audioSyncField.formatter=syncFormat;
    self.audioSyncField.target=self;self.audioSyncField.action=@selector(audioSyncChanged:);self.audioSyncField.integerValue=shuttle_output_audio::clampAudioOffset(int([[NSUserDefaults standardUserDefaults] integerForKey:@"HDMIAudioOffsetMS"]));self.audioSyncField.accessibilityLabel=@"Output audio offset in milliseconds";self.audioSyncField.toolTip=@"−100 to +500 ms. Negative moves sound earlier; positive moves it later. Press Return to apply.";[v addSubview:self.audioSyncField];
    self.audioSyncStepper=[[NSStepper alloc] initWithFrame:NSMakeRect(230,239,20,28)];self.audioSyncStepper.minValue=shuttle_output_audio::MinAudioOffsetMS;self.audioSyncStepper.maxValue=shuttle_output_audio::MaxAudioOffsetMS;self.audioSyncStepper.increment=10;self.audioSyncStepper.integerValue=self.audioSyncField.integerValue;self.audioSyncStepper.valueWraps=NO;self.audioSyncStepper.target=self;self.audioSyncStepper.action=@selector(audioSyncChanged:);[v addSubview:self.audioSyncStepper];
    [v addSubview:label(@"ms  ·  − earlier / + later",NSMakeRect(264,242,255,24),12)];
    self.resetAudioSync=[NSButton buttonWithTitle:@"Reset" target:self action:@selector(resetAudioSync:)];self.resetAudioSync.frame=NSMakeRect(548,239,78,30);[v addSubview:self.resetAudioSync];
    auto* overlayTitle=label(@"OUTPUT VIEWS",NSMakeRect(24,204,602,20),11);overlayTitle.font=[NSFont boldSystemFontOfSize:11];overlayTitle.textColor=NSColor.secondaryLabelColor;[v addSubview:overlayTitle];
    self.showTimecode=[NSButton checkboxWithTitle:@"Timecode" target:self action:@selector(timecodeChanged:)];self.showTimecode.frame=NSMakeRect(24,131,260,26);self.showTimecode.state=[[NSUserDefaults standardUserDefaults] boolForKey:@"ShowHDMITimecode"]?NSControlStateValueOn:NSControlStateValueOff;self.showTimecode.toolTip=@"Show timeline timecode on HDMI. Dashes mean the editor supplied no timecode.";[v addSubview:self.showTimecode];
    self.timecodePosition=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(410,129,216,30)];[self.timecodePosition addItemsWithTitles:@[@"Top left",@"Top right",@"Bottom right",@"Bottom left",@"Top centre",@"Bottom centre"]];[self.timecodePosition selectItemAtIndex:shuttle_sink::savedTimecodePosition([[NSUserDefaults standardUserDefaults] integerForKey:@"HDMITimecodePosition"])];self.timecodePosition.target=self;self.timecodePosition.action=@selector(timecodePositionChanged:);self.timecodePosition.accessibilityLabel=@"Timecode position";[v addSubview:self.timecodePosition];
    self.showMeters=[NSButton checkboxWithTitle:@"L/R audio meters" target:self action:@selector(metersChanged:)];self.showMeters.frame=NSMakeRect(24,95,260,26);self.showMeters.state=[[NSUserDefaults standardUserDefaults] boolForKey:@"ShowHDMIAudioMeters"]?NSControlStateValueOn:NSControlStateValueOff;[v addSubview:self.showMeters];
    self.meterPosition=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(410,93,216,30)];[self.meterPosition addItemsWithTitles:@[@"Top left",@"Top right",@"Bottom right",@"Bottom left",@"Top centre",@"Bottom centre"]];[self.meterPosition selectItemAtIndex:shuttle_output_audio::savedMeterPosition([[NSUserDefaults standardUserDefaults] integerForKey:@"HDMIAudioMeterPosition"])];self.meterPosition.target=self;self.meterPosition.action=@selector(metersChanged:);self.meterPosition.accessibilityLabel=@"Audio meter position";[v addSubview:self.meterPosition];
    self.titleSafe=[NSButton checkboxWithTitle:@"Title safe (80%)" target:self action:@selector(safeZonesChanged:)];self.titleSafe.frame=NSMakeRect(24,55,280,26);self.titleSafe.state=[[NSUserDefaults standardUserDefaults] boolForKey:@"ShowHDMITitleSafe"]?NSControlStateValueOn:NSControlStateValueOff;[v addSubview:self.titleSafe];
    self.actionSafe=[NSButton checkboxWithTitle:@"Action safe (90%)" target:self action:@selector(safeZonesChanged:)];self.actionSafe.frame=NSMakeRect(340,55,286,26);self.actionSafe.state=[[NSUserDefaults standardUserDefaults] boolForKey:@"ShowHDMIActionSafe"]?NSControlStateValueOn:NSControlStateValueOff;[v addSubview:self.actionSafe];
    self.diagnosticsScroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,650,300)];self.diagnosticsScroll.hasVerticalScroller=YES;self.diagnosticsScroll.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
    self.log=[[NSTextView alloc] initWithFrame:self.diagnosticsScroll.bounds];self.log.editable=NO;self.log.font=[NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];self.log.textColor=NSColor.textColor;self.log.backgroundColor=NSColor.textBackgroundColor;self.diagnosticsScroll.documentView=self.log;
    // Two additional rows, with a compact scrollable panel on smaller screens.
    for(NSView* item in v.subviews){if(item==self.showTimecode||item==self.timecodePosition||item==self.showMeters||item==self.meterPosition||item==self.titleSafe||item==self.actionSafe)continue;NSRect r=item.frame;r.origin.y+=80;item.frame=r;}
    [v addSubview:label(@"Mac screen",NSMakeRect(24,249,115,24),13)];
    self.macView=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(150,246,244,30)];
    [v addSubview:label(@"Shuttle output",NSMakeRect(24,213,120,24),13)];
    self.shuttleView=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(150,210,244,30)];
    for(NSPopUpButton* menu in @[self.macView,self.shuttleView]){[menu addItemsWithTitles:@[@"Video",@"Video scopes",@"Off"]];menu.target=self;menu.action=@selector(outputViewsChanged:);menu.autoenablesItems=NO;menu.toolTip=@"Video and scopes change live. Turn off editor external output and Stop before switching a destination on or off.";[v addSubview:menu];}
    self.macView.accessibilityLabel=@"Mac screen view";self.shuttleView.accessibilityLabel=@"Shuttle output view";
    self.macScope=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(410,246,216,30)];self.shuttleScope=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(410,210,216,30)];
    for(NSPopUpButton* menu in @[self.macScope,self.shuttleScope]){[menu addItemsWithTitles:@[@"Four up",@"Waveform · Luma",@"RGB parade",@"RGB overlay",@"Vectorscope",@"Histogram · RGB"]];menu.target=self;menu.action=@selector(outputViewsChanged:);[v addSubview:menu];}
    self.macScope.accessibilityLabel=@"Mac screen scope type";self.shuttleScope.accessibilityLabel=@"Shuttle output scope type";
    [v addSubview:label(@"Video overlays",NSMakeRect(24,170,120,24),13)];self.monitorTarget=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(150,167,476,30)];[self.monitorTarget addItemsWithTitles:@[@"Shuttle output",@"Mac screen"]];self.monitorTarget.target=self;self.monitorTarget.action=@selector(monitorTargetChanged:);self.monitorTarget.accessibilityLabel=@"Video overlay destination";[v addSubview:self.monitorTarget];
    [self loadOutputChoices];
    [self connectorChanged:nil];[self sourceChanged:nil];
    [self beginAudioRouteMonitoring];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(screenParametersChanged:) name:NSApplicationDidChangeScreenParametersNotification object:nil];
    __weak OutputHost* deviceOwner=self;self.devicesListener=^(UInt32,const AudioObjectPropertyAddress*){dispatch_async(dispatch_get_main_queue(),^{[deviceOwner refreshListeningDevices];});};
    AudioObjectPropertyAddress deviceAddress{kAudioHardwarePropertyDevices,kAudioObjectPropertyScopeGlobal,0};AudioObjectAddPropertyListenerBlock(kAudioObjectSystemObject,&deviceAddress,dispatch_get_main_queue(),self.devicesListener);
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
    if(self.previousMediaAudioUID.length)[self outputMessage:@"A previous audio output was saved by an earlier session. Click Restore audio to recover it, or Use Shuttle Audio to use that saved route for this session. Audio has not been changed at startup."];
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
- (BOOL)editorSource{return self.source.indexOfSelectedItem==2||self.source.indexOfSelectedItem==3;}
- (BOOL)macEnabled{return [self editorSource]&&self.macView.indexOfSelectedItem!=2;}
- (BOOL)shuttleEnabled{return self.shuttleView.indexOfSelectedItem!=2;}
- (BOOL)virtualDestination {return [self macEnabled];}
- (BOOL)bothDestinations {return [self macEnabled]&&[self shuttleEnabled];}
- (NSString*)syncKey {return [self virtualDestination]&&![self bothDestinations]?@"VirtualAudioOffsetMS":@"HDMIAudioOffsetMS";}
- (NSString*)monitorKey:(NSString*)key {
    if(self.monitorTarget.indexOfSelectedItem!=1)return key;
    return [key stringByReplacingOccurrencesOfString:@"HDMI" withString:@"Virtual"];
}
- (void)monitorTargetChanged:(id)sender {
    auto* defaults=NSUserDefaults.standardUserDefaults;
    auto flag=^(NSString* key){NSString* selected=[self monitorKey:key];return [defaults objectForKey:selected]?[defaults boolForKey:selected]:[defaults boolForKey:key];};
    auto position=^(NSString* key){NSString* selected=[self monitorKey:key];return [defaults objectForKey:selected]?[defaults integerForKey:selected]:[defaults integerForKey:key];};
    self.showTimecode.state=flag(@"ShowHDMITimecode");self.showMeters.state=flag(@"ShowHDMIAudioMeters");self.titleSafe.state=flag(@"ShowHDMITitleSafe");self.actionSafe.state=flag(@"ShowHDMIActionSafe");
    [self.timecodePosition selectItemAtIndex:shuttle_sink::savedTimecodePosition(position(@"HDMITimecodePosition"))];[self.meterPosition selectItemAtIndex:shuttle_output_audio::savedMeterPosition(position(@"HDMIAudioMeterPosition"))];
    [self updateOverlayAvailability];
}
- (void)loadOutputChoices {
    auto* d=NSUserDefaults.standardUserDefaults;
    [self.macView selectItemAtIndex:[self editorSource]?MAX(0,MIN(2,[d integerForKey:@"MacMonitorMode"])):2];[self.shuttleView selectItemAtIndex:MAX(0,MIN(2,[d integerForKey:@"ShuttleMonitorMode"]))];
    [self.macScope selectItemAtIndex:MAX(0,MIN(5,[d integerForKey:@"MacScopeStyle"]))];[self.shuttleScope selectItemAtIndex:MAX(0,MIN(5,[d integerForKey:@"ShuttleScopeStyle"]))];
}
- (void)outputViewsChanged:(id)sender {
    if(self.task&&([self macEnabled]!=self.runningMac||[self shuttleEnabled]!=self.runningShuttle)){[self loadOutputChoices];[self outputMessage:@"Stop output before switching a screen on or off. Video and scopes can change while running."];return;}
    auto* d=NSUserDefaults.standardUserDefaults;
    if([self editorSource])[d setInteger:self.macView.indexOfSelectedItem forKey:@"MacMonitorMode"];
    [d setInteger:self.shuttleView.indexOfSelectedItem forKey:@"ShuttleMonitorMode"];
    [d setInteger:self.macScope.indexOfSelectedItem forKey:@"MacScopeStyle"];[d setInteger:self.shuttleScope.indexOfSelectedItem forKey:@"ShuttleScopeStyle"];
    if([self editorSource])[d setInteger:self.macView.indexOfSelectedItem==1?self.macScope.indexOfSelectedItem+1:0 forKey:@"VirtualOutputView"];
    [d setInteger:self.shuttleView.indexOfSelectedItem==1?self.shuttleScope.indexOfSelectedItem+1:0 forKey:@"HDMIOutputView"];[d synchronize];
    [self destinationChanged:nil];
}
- (void)updateOverlayAvailability {
    BOOL macVideo=[self macEnabled]&&self.macView.indexOfSelectedItem==0,shuttleVideo=[self shuttleEnabled]&&self.shuttleView.indexOfSelectedItem==0;
    self.monitorTarget.autoenablesItems=NO;[self.monitorTarget itemAtIndex:0].enabled=shuttleVideo;[self.monitorTarget itemAtIndex:1].enabled=macVideo;
    self.monitorTarget.enabled=macVideo||shuttleVideo;
    BOOL video=self.monitorTarget.indexOfSelectedItem==1?macVideo:shuttleVideo;
    for(NSControl* control in @[self.showMeters,self.titleSafe,self.actionSafe,self.meterPosition])control.enabled=video;
    self.showTimecode.enabled=self.timecodePosition.enabled=video&&[self editorSource];
    self.macView.enabled=[self editorSource]&&(!self.task||self.runningMac);self.shuttleView.enabled=!self.task||self.runningShuttle;
    [self.macView itemAtIndex:2].enabled=!self.task;[self.shuttleView itemAtIndex:2].enabled=!self.task;
    self.macScope.hidden=self.macView.indexOfSelectedItem!=1;self.shuttleScope.hidden=self.shuttleView.indexOfSelectedItem!=1;
    self.start.enabled=!self.task&&([self macEnabled]||[self shuttleEnabled]);
}
- (void)clearMirror {
    _mirror.reset();if(self.mirrorPath){unlink(self.mirrorPath.fileSystemRepresentation);self.mirrorPath=nil;}
    if(self.screenTask.running)[self.screenTask terminate];self.screenTask=nil;
}
- (void)screenParametersChanged:(NSNotification*)note {[self refreshVirtualDisplays];}
- (void)refreshVirtualDisplays {
    NSString* saved=[NSUserDefaults.standardUserDefaults stringForKey:@"VirtualOutputDisplayUUID"];NSNumber* previous=self.virtualDisplay.selectedItem.representedObject;
    [self.virtualDisplay removeAllItems];NSInteger selection=-1;
    for(NSScreen* screen in NSScreen.screens){CGDirectDisplayID display=[screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue];
        [self.virtualDisplay addItemWithTitle:[NSString stringWithFormat:@"%@ · %zu × %zu%@",screen.localizedName,CGDisplayPixelsWide(display),CGDisplayPixelsHigh(display),display==CGMainDisplayID()?@" · Main":@""]];self.virtualDisplay.lastItem.representedObject=@(display);
        CFUUIDRef uuid=CGDisplayCreateUUIDFromDisplayID(display);NSString* text=uuid?CFBridgingRelease(CFUUIDCreateString(nullptr,uuid)):nil;if(uuid)CFRelease(uuid);
        if((saved.length&&[saved isEqual:text])||(!saved.length&&[previous isEqual:@(display)]))selection=self.virtualDisplay.numberOfItems-1;
    }
    if(selection>=0)[self.virtualDisplay selectItemAtIndex:selection];else if(self.virtualDisplay.numberOfItems>1)[self.virtualDisplay selectItemAtIndex:1];
}
- (void)virtualDisplayChanged:(id)sender {
    NSNumber* selected=self.virtualDisplay.selectedItem.representedObject;if(!selected)return;
    CFUUIDRef uuid=CGDisplayCreateUUIDFromDisplayID(selected.unsignedIntValue);if(uuid){NSString* text=CFBridgingRelease(CFUUIDCreateString(nullptr,uuid));CFRelease(uuid);[NSUserDefaults.standardUserDefaults setObject:text forKey:@"VirtualOutputDisplayUUID"];}[NSUserDefaults.standardUserDefaults synchronize];
}
- (void)refreshListeningDevices {
    using namespace shuttle_audio_route;
    NSString* saved=[NSUserDefaults.standardUserDefaults stringForKey:@"OutputListenDeviceUID"];
    OSStatus status=0;auto defaultDevice=mediaOutput(status);NSString* defaultUID=status?nil:uid(defaultDevice,status);if([defaultUID isEqual:HDMIUID])defaultUID=self.previousMediaAudioUID?:[NSUserDefaults.standardUserDefaults stringForKey:PreviousUIDPreference];
    AudioObjectPropertyAddress a{kAudioHardwarePropertyDevices,kAudioObjectPropertyScopeGlobal,0};UInt32 bytes=0;
    if(AudioObjectGetPropertyDataSize(kAudioObjectSystemObject,&a,0,nullptr,&bytes)||bytes>1024*1024)return;
    std::vector<AudioDeviceID> devices(bytes/sizeof(AudioDeviceID));if(AudioObjectGetPropertyData(kAudioObjectSystemObject,&a,0,nullptr,&bytes,devices.data()))return;
    [self.listenDevice removeAllItems];NSInteger selected=-1,fallback=-1;
    for(auto device:devices){a={kAudioDevicePropertyStreams,kAudioDevicePropertyScopeOutput,0};UInt32 streams=0;if(AudioObjectGetPropertyDataSize(device,&a,0,nullptr,&streams)||!streams)continue;
        NSString* value=uid(device,status);if(status||!value.length||[value isEqual:HDMIUID])continue;
        a={kAudioDevicePropertyDeviceIsAlive,kAudioObjectPropertyScopeGlobal,0};UInt32 alive=0,size=sizeof(alive);if(AudioObjectGetPropertyData(device,&a,0,nullptr,&size,&alive)||!alive)continue;
        [self.listenDevice addItemWithTitle:name(device)];self.listenDevice.lastItem.representedObject=value;
        if([saved isEqual:value])selected=self.listenDevice.numberOfItems-1;if([defaultUID isEqual:value])fallback=self.listenDevice.numberOfItems-1;
    }
    if(selected<0&&saved.length&&self.listen.state==NSControlStateValueOn){self.listen.state=NSControlStateValueOff;[self outputMessage:@"Listening stopped: selected speakers/headphones disconnected. Choose a device and enable Listen again."];}
    if(selected<0&&fallback>=0)selected=fallback;if(selected>=0)[self.listenDevice selectItemAtIndex:selected];
    BOOL available=self.listenDevice.numberOfItems>0;self.listen.enabled=available;self.listenDevice.enabled=available;self.listenVolume.enabled=available;
    if(!available){self.listen.state=NSControlStateValueOff;[NSUserDefaults.standardUserDefaults setBool:NO forKey:@"OutputListenEnabled"];}
    else [self listenDeviceChanged:nil];
}
- (void)listenDeviceChanged:(id)sender {NSString* value=self.listenDevice.selectedItem.representedObject;if(value)[NSUserDefaults.standardUserDefaults setObject:value forKey:@"OutputListenDeviceUID"];[self listenChanged:nil];}
- (void)listenChanged:(id)sender {
    [NSUserDefaults.standardUserDefaults setBool:self.listen.state==NSControlStateValueOn&&self.listenDevice.selectedItem.representedObject!=nil forKey:@"OutputListenEnabled"];
    [NSUserDefaults.standardUserDefaults setDouble:self.listenVolume.doubleValue forKey:@"OutputListenVolume"];[NSUserDefaults.standardUserDefaults synchronize];
}
- (void)destinationChanged:(id)sender {
    BOOL mac=[self macEnabled],shuttle=[self shuttleEnabled],both=mac&&shuttle;
    self.sizing.hidden=self.source.indexOfSelectedItem!=1&&self.source.indexOfSelectedItem!=4&&self.source.indexOfSelectedItem!=5&&!mac;
    self.connector.hidden=self.connectorLabel.hidden=!shuttle;self.virtualDisplay.hidden=self.virtualDisplayLabel.hidden=!mac;
    self.virtualDisplay.frame=both?NSMakeRect(150,555,244,30):NSMakeRect(150,595,476,30);self.virtualDisplayLabel.frame=both?NSMakeRect(24,558,115,24):NSMakeRect(24,598,115,24);
    self.connector.enabled=!self.task&&shuttle;
    if(mac&&!shuttle){self.mode.autoenablesItems=NO;for(NSMenuItem* item in self.mode.itemArray)item.enabled=YES;}else [self connectorChanged:nil];
    self.audioSyncField.integerValue=shuttle_output_audio::clampAudioOffset(int([NSUserDefaults.standardUserDefaults integerForKey:[self syncKey]]));self.audioSyncStepper.integerValue=self.audioSyncField.integerValue;
    BOOL macVideo=mac&&self.macView.indexOfSelectedItem==0,shuttleVideo=shuttle&&self.shuttleView.indexOfSelectedItem==0;
    if((self.monitorTarget.indexOfSelectedItem==1&&!macVideo)||(self.monitorTarget.indexOfSelectedItem==0&&!shuttleVideo)){if(shuttleVideo)[self.monitorTarget selectItemAtIndex:0];else if(macVideo)[self.monitorTarget selectItemAtIndex:1];}
    [self monitorTargetChanged:nil];
}
- (void)connectorChanged:(id)sender {
    auto target=static_cast<shuttle_output::Connector>(self.connector.indexOfSelectedItem);
    [self.mode selectItemAtIndex:shuttle_output::compatibleMode(target,unsigned(MAX(0,self.mode.indexOfSelectedItem)))];
    self.mode.autoenablesItems=NO;for(unsigned n=0;n<6;++n)[self.mode itemAtIndex:n].enabled=shuttle_output::connectorSupports(target,n);
    [NSUserDefaults.standardUserDefaults setInteger:self.connector.indexOfSelectedItem forKey:@"OutputConnector"];
}
- (void)sourceChanged:(id)sender {
    NSInteger source=self.source.indexOfSelectedItem;[NSUserDefaults.standardUserDefaults setInteger:source forKey:@"OutputSource"];
    [self loadOutputChoices];[self destinationChanged:nil];
    self.outputHelp.stringValue=source==2?@"Choose Video, Video scopes or Off separately for Mac screen and Shuttle output. Start and wait for Ready. In Final Cut select Virtual Shuttle if Mac screen is on, or Intensity Shuttle — HDMI Output for Shuttle-only; then enable Window → A/V Output. Use Shuttle Audio feeds meters/sound; Listen on Mac adds local speakers.":source==3?@"Choose Video, Video scopes or Off for each screen. Start Premiere output, then enable the existing Shuttle Mercury Transmit video device in Premiere Playback settings. Virtual Shuttle Audio feeds both meter sets and device sound; Listen on Mac adds local speakers.":source==6?@"Show the chosen idle screen continuously.":source==5?@"Create Shuttle Extended Display and arrange it in macOS Displays. Screen-recording permission is required.":source==4?@"Choose a Mac display to mirror to the Shuttle. Allow screen recording when asked.":@"Stop camera previews before hardware output. Choose a movie or test pattern and start output.";
    self.choose.enabled=!self.task;self.loop.enabled=source==1&&!self.task;
    self.desktopDisplay.hidden=self.desktopLabel.hidden=source!=4;self.extendedHint.hidden=source!=5;self.sizing.hidden=source!=1&&source!=4&&source!=5&&![self virtualDestination];
    self.start.title=source==5?@"Start extended display":source==4?@"Start mirroring":source==2?@"Start Final Cut":source==3?@"Start Premiere":@"Start output";
    self.choose.hidden=self.fileLabel.hidden=self.loop.hidden=source!=1;self.source.toolTip=self.outputHelp.stringValue;
    self.audioSyncField.enabled=source>=2&&source<=5;self.audioSyncStepper.enabled=source>=2&&source<=5;self.resetAudioSync.enabled=source>=2&&source<=5;
    [self updateOverlayAvailability];
    if(!self.task)self.readinessLabel.stringValue=[self macEnabled]||[self shuttleEnabled]?@"Stopped":@"Both outputs are off";
}
- (void)audioSyncChanged:(id)sender {
    NSInteger requested=sender==self.audioSyncStepper?self.audioSyncStepper.integerValue:self.audioSyncField.integerValue;
    int value=shuttle_output_audio::clampAudioOffset(int(requested));
    self.audioSyncField.integerValue=value;self.audioSyncStepper.integerValue=value;
    [[NSUserDefaults standardUserDefaults] setInteger:value forKey:[self syncKey]];
    if(![[NSUserDefaults standardUserDefaults] synchronize]){[self outputMessage:@"Could not save the audio sync setting. Try again."];return;}
    [self outputMessage:[NSString stringWithFormat:@"Output audio sync: %+d ms — %@.",value,value<0?@"sound earlier":value>0?@"sound later":@"no adjustment"]];
}
- (void)resetAudioSync:(id)sender {self.audioSyncField.integerValue=0;[self audioSyncChanged:self.audioSyncField];}
- (void)timecodeChanged:(id)sender {
    BOOL enabled=self.showTimecode.state==NSControlStateValueOn;
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:[self monitorKey:@"ShowHDMITimecode"]];
    if(![[NSUserDefaults standardUserDefaults] synchronize]){[self outputMessage:@"Could not save the timecode setting. Try again."];return;}
    [self outputMessage:enabled?@"Output timecode overlay enabled. Dashes mean the editor supplied no valid timecode.":@"Output timecode overlay disabled."];
}
- (void)timecodePositionChanged:(id)sender {
    [[NSUserDefaults standardUserDefaults] setInteger:self.timecodePosition.indexOfSelectedItem+1 forKey:[self monitorKey:@"HDMITimecodePosition"]];
    if(![[NSUserDefaults standardUserDefaults] synchronize]){[self outputMessage:@"Could not save the timecode position. Try again."];return;}
    [self outputMessage:[NSString stringWithFormat:@"Output timecode position: %@.",self.timecodePosition.titleOfSelectedItem]];
}
- (void)metersChanged:(id)sender {
    [[NSUserDefaults standardUserDefaults] setBool:self.showMeters.state==NSControlStateValueOn forKey:[self monitorKey:@"ShowHDMIAudioMeters"]];
    [[NSUserDefaults standardUserDefaults] setInteger:self.meterPosition.indexOfSelectedItem+1 forKey:[self monitorKey:@"HDMIAudioMeterPosition"]];
    if(![[NSUserDefaults standardUserDefaults] synchronize]){[self outputMessage:@"Could not save the audio meter settings. Try again."];return;}
    [self outputMessage:self.showMeters.state==NSControlStateValueOn?[NSString stringWithFormat:@"Output L/R audio meters enabled — %@.",self.meterPosition.titleOfSelectedItem]:@"Output L/R audio meters disabled."];
}
- (void)safeZonesChanged:(id)sender {
    [[NSUserDefaults standardUserDefaults] setBool:self.titleSafe.state==NSControlStateValueOn forKey:[self monitorKey:@"ShowHDMITitleSafe"]];
    [[NSUserDefaults standardUserDefaults] setBool:self.actionSafe.state==NSControlStateValueOn forKey:[self monitorKey:@"ShowHDMIActionSafe"]];
    if(![[NSUserDefaults standardUserDefaults] synchronize]){[self outputMessage:@"Could not save the safe-zone settings. Try again."];return;}
    [self outputMessage:[NSString stringWithFormat:@"Output guides — title safe: %@; action safe: %@.",self.titleSafe.state==NSControlStateValueOn?@"on":@"off",self.actionSafe.state==NSControlStateValueOn?@"on":@"off"]];
}
- (void)chooseMovie:(id)sender {
    NSOpenPanel* panel=[NSOpenPanel openPanel];panel.canChooseDirectories=NO;panel.allowsMultipleSelection=NO;
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response){if(response==NSModalResponseOK){self.movie=panel.URL.path;self.fileLabel.stringValue=self.movie.lastPathComponent;[self.source selectItemAtIndex:1];[self sourceChanged:nil];}}];
}
- (void)setRunning:(BOOL)running {
    if(running){self.runningMac=[self macEnabled];self.runningShuttle=[self shuttleEnabled];}
    self.virtualDisplay.enabled=!running;self.connector.enabled=self.sizing.enabled=!running;self.desktopDisplay.enabled=!running;self.mode.enabled=!running;self.source.enabled=!running;self.choose.enabled=!running;self.loop.enabled=!running&&self.source.indexOfSelectedItem==1;self.start.enabled=!running;self.stop.enabled=running||self.managesMediaAudio;[self updateOverlayAvailability];
}
- (void)checkTimelineReadiness:(NSTimer*)timer {
    if(!self.task.running){[timer invalidate];self.readinessTimer=nil;return;}
    if(self.source.indexOfSelectedItem==3){if(self.readinessDeadline.timeIntervalSinceNow<=0){[timer invalidate];self.readinessTimer=nil;self.startupFailed=YES;[self outputMessage:@"Premiere output did not become ready. Check Diagnostics, the selected screen and any active capture clients."];[self stopOutput:nil];}return;}
    if(timelineOutputReady(self.mode.indexOfSelectedItem,[self virtualDestination])){
        [timer invalidate];self.readinessTimer=nil;
        self.readinessLabel.stringValue=[self macEnabled]?@"Ready for Final Cut — select Virtual Shuttle":@"Ready for Final Cut — select Intensity Shuttle";
        [self outputMessage:[self virtualDestination]?@"Ready for Final Cut. Select Virtual Shuttle and enable Window → A/V Output. Keep Shuttle Video open.":@"Ready for Final Cut. Select Intensity Shuttle — HDMI Output and enable Window → A/V Output. Keep Shuttle Video open."];
    }else if(self.readinessDeadline.timeIntervalSinceNow<=0){
        [timer invalidate];self.readinessTimer=nil;
        self.startupFailed=YES;
        self.readinessLabel.stringValue=@"Final Cut output is unavailable — Help → Diagnostics.";
        [self outputMessage:@"Output driver13 is required. Use Help → Driver Setup → Enable Final Cut Outputs, then retry. If macOS just replaced it, allow the old service to stop and activate again. Leave Final Cut A/V Output off until Ready appears."];
        [self stopOutput:nil];
    }
}
- (NSString*)outputExecutable{return [self macEnabled]&&![self shuttleEnabled]?@"ShuttleScreenOutput":@"ShuttlePlayback";}
- (NSArray*)outputArguments {
    NSString* mode=@[@"576i50",@"1080i50",@"1080p25",@"480i5994",@"1080i5994",@"1080p2997"][self.mode.indexOfSelectedItem];
    if([self bothDestinations])return @[self.source.indexOfSelectedItem==3?@"--premiere-dual":@"--virtual-sink",mode,self.mirrorPath?:@""];
    if([self macEnabled]){NSArray* values=@[[@(self.mode.indexOfSelectedItem) stringValue],[self.virtualDisplay.selectedItem.representedObject stringValue]?:@""];return self.source.indexOfSelectedItem==3?[@[@"--premiere"] arrayByAddingObjectsFromArray:values]:values;}
    return self.source.indexOfSelectedItem==6?@[@"--idle",mode,@"live"]:self.source.indexOfSelectedItem==5?@[@"--desktop",mode,[@(self.extendedDisplay.displayID) stringValue]]:self.source.indexOfSelectedItem==4?@[@"--desktop",mode,[self.desktopDisplay.selectedItem.representedObject stringValue]?:@""]:self.source.indexOfSelectedItem==3?@[@"--premiere",mode,@"live"]:self.source.indexOfSelectedItem==2?@[@"--sink",mode,@"live"]:self.source.indexOfSelectedItem==1?@[self.loop.state==NSControlStateValueOn?@"--loop":@"--play",mode,self.movie?:@""]:@[@"--bars",mode,@"30"];
}
- (void)startOutput:(id)sender {
    if(self.task)return;
    if(![self macEnabled]&&![self shuttleEnabled]){self.readinessLabel.stringValue=@"Both outputs are off";return;}
    self.startupFailed=NO;
    if([self virtualDestination]&&!self.virtualDisplay.selectedItem.representedObject){[self outputMessage:@"Cannot start Virtual Shuttle: choose an available Mac display."];return;}
    if([self virtualDestination])[self virtualDisplayChanged:nil];
    if(self.source.indexOfSelectedItem==4||self.source.indexOfSelectedItem==5){
        if(self.source.indexOfSelectedItem==4&&!self.desktopDisplay.selectedItem.representedObject){[self outputMessage:@"No connected display is available."];return;}
        if(!CGPreflightScreenCaptureAccess()){CGRequestScreenCaptureAccess();self.readinessLabel.stringValue=@"Allow screen recording in System Settings, then reopen Shuttle Camera.";return;}
    }
    if(self.source.indexOfSelectedItem==1&&!self.movie){[self chooseMovie:nil];return;}
    if(self.source.indexOfSelectedItem>=2&&self.source.indexOfSelectedItem<=5){[self.window makeFirstResponder:nil];[self audioSyncChanged:self.audioSyncField];}
    if(self.source.indexOfSelectedItem==5){
        auto size=shuttle_output::extendedDisplaySize(shuttle_output::Mode(self.mode.indexOfSelectedItem));unsigned w=size.width,h=size.height;
        self.extendedDisplay=[ShuttleExtendedDisplay new];NSString *error=nil;if(![self.extendedDisplay startWidth:w height:h error:&error]){self.extendedDisplay=nil;self.readinessLabel.stringValue=error?:@"Extended display unavailable.";return;}
    }
    // The USB sender brings the CMIO device online, never the other way round.
    [[NSUserDefaults standardUserDefaults] setInteger:self.sizing.indexOfSelectedItem forKey:@"PlaybackSizing"];
    [[NSUserDefaults standardUserDefaults] setInteger:self.mode.indexOfSelectedItem forKey:@"OutputMode"];
    [[NSUserDefaults standardUserDefaults] setBool:self.loop.state==NSControlStateValueOn forKey:@"LoopMovie"];
    NSString* mode=@[@"576i50",@"1080i50",@"1080p25",@"480i5994",@"1080i5994",@"1080p2997"][self.mode.indexOfSelectedItem];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self clearMirror];
    if([self bothDestinations]){
        self.mirrorPath=[NSTemporaryDirectory() stringByAppendingPathComponent:[@"Shuttle-" stringByAppendingString:[NSUUID.UUID.UUIDString stringByAppendingString:@".frames"]]];
        try{_mirror.reset(new shuttle_mirror::Feed(self.mirrorPath.fileSystemRepresentation,true,unsigned(self.mode.indexOfSelectedItem)));}
        catch(const std::exception& e){[self outputMessage:@(e.what())];[self clearMirror];return;}
        self.screenTask=[NSTask new];self.screenTask.executableURL=[[NSBundle.mainBundle.executableURL URLByDeletingLastPathComponent] URLByAppendingPathComponent:@"ShuttleScreenOutput"];
        self.screenTask.arguments=@[@"--tap",[@(self.mode.indexOfSelectedItem) stringValue],[self.virtualDisplay.selectedItem.representedObject stringValue],self.mirrorPath];
        NSPipe* screenLog=NSPipe.pipe;self.screenTask.standardOutput=screenLog;self.screenTask.standardError=screenLog;
        __weak OutputHost* owner=self;screenLog.fileHandleForReading.readabilityHandler=^(NSFileHandle* handle){NSData* data=handle.availableData;if(!data.length){handle.readabilityHandler=nil;return;}NSString* text=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];if(text)dispatch_async(dispatch_get_main_queue(),^{[owner handleOutputText:text];});};
        self.screenTask.terminationHandler=^(NSTask* task){dispatch_async(dispatch_get_main_queue(),^{OutputHost* host=owner;if(host.screenTask==task){host.screenTask=nil;if(host.task.running){host.startupFailed=task.terminationStatus!=0;[host outputMessage:task.terminationStatus==0?@"Mac screen stopped; stopping the paired Shuttle output.":@"Mac screen failed; stopping the paired Shuttle output."];[host stopOutput:nil];}}});};
        NSError* error=nil;if(![self.screenTask launchAndReturnError:&error]){[self outputMessage:error.localizedDescription];[self clearMirror];return;}
    }
    self.task=[NSTask new];self.task.executableURL=[[NSBundle mainBundle].executableURL.URLByDeletingLastPathComponent URLByAppendingPathComponent:[self outputExecutable]];
    self.task.arguments=[self outputArguments];
    NSPipe* pipe=[NSPipe pipe];self.task.standardOutput=pipe;self.task.standardError=pipe;self.log.string=self.source.indexOfSelectedItem==2?@"Starting timeline output…\nUse Shuttle Audio routes editor sound to the receiver and meters. Listen selects local speakers. Stop restores the saved Mac output unless you choose another device.\n":@"Starting output…\n";
    __weak OutputHost* weakSelf=self;
    pipe.fileHandleForReading.readabilityHandler=^(NSFileHandle* h){NSData* data=h.availableData;if(!data.length){h.readabilityHandler=nil;return;}NSString* text=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];if(text)dispatch_async(dispatch_get_main_queue(),^{OutputHost* host=weakSelf;if(host){[host handleOutputText:text];}});};
    self.task.terminationHandler=^(NSTask* task){dispatch_async(dispatch_get_main_queue(),^{OutputHost* host=weakSelf;if(!host||host.task!=task)return;[host.readinessTimer invalidate];host.readinessTimer=nil;[host.log.textStorage appendAttributedString:[[NSAttributedString alloc] initWithString:task.terminationStatus==0?@"Output stopped.\n":@"Output ended; open Help → Diagnostics.\n"]];host.task=nil;[host clearMirror];[host.extendedDisplay stop];host.extendedDisplay=nil;host.readinessLabel.stringValue=!host.startupFailed&&task.terminationStatus==0?@"Output is stopped.":@"Output failed — Help → Diagnostics.";[host restorePreviousAudio:@"Output ended" explicit:NO];[host setRunning:NO];});};
    NSError* error=nil;if(![self.task launchAndReturnError:&error]){self.log.string=error.localizedDescription;self.task=nil;[self clearMirror];[self.extendedDisplay stop];self.extendedDisplay=nil;self.readinessLabel.stringValue=@"Output could not start — Help → Diagnostics.";[self restorePreviousAudio:@"Output could not start" explicit:NO];return;}[self setRunning:YES];
    self.readinessLabel.stringValue=self.source.indexOfSelectedItem==3?@"Starting…":self.source.indexOfSelectedItem==2?@"Starting…":@"Running";
    if(self.source.indexOfSelectedItem==2||self.source.indexOfSelectedItem==3){
        self.readinessDeadline=[NSDate dateWithTimeIntervalSinceNow:8];
        self.readinessTimer=[NSTimer scheduledTimerWithTimeInterval:0.2 repeats:YES block:^(NSTimer* timer){[weakSelf checkTimelineReadiness:timer];}];
    }
}
- (void)handleOutputText:(NSString*)text {
    [self.log.textStorage appendAttributedString:[[NSAttributedString alloc] initWithString:text attributes:@{NSForegroundColorAttributeName:NSColor.textColor}]];
    if(self.log.string.length>32768)[self.log.textStorage deleteCharactersInRange:NSMakeRange(0,self.log.string.length-24576)];[self.log scrollRangeToVisible:NSMakeRange(self.log.string.length,0)];
    if((self.source.indexOfSelectedItem==4||self.source.indexOfSelectedItem==5)&&[self.log.string containsString:@"Desktop mirror ready"])self.readinessLabel.stringValue=self.source.indexOfSelectedItem==5?@"Extended display running":@"Mirroring desktop";
    if(self.source.indexOfSelectedItem==3&&([self.log.string containsString:@"Premiere USB ready"]||[self.log.string containsString:@"Premiere Mac ready"])){[self.readinessTimer invalidate];self.readinessTimer=nil;self.readinessLabel.stringValue=@"Ready for Premiere";}
}
- (void)stopOutput:(id)sender {[self.readinessTimer invalidate];self.readinessTimer=nil;if(self.task.running){if(!self.startupFailed)self.readinessLabel.stringValue=@"Stopping output…";[self.task terminate];}[self restorePreviousAudio:@"Output stopped" explicit:NO];}
- (void)outputMessage:(NSString*)message{puts(message.UTF8String);fflush(stdout);if(self.log)[self handleOutputText:[message stringByAppendingString:@"\n"]];if([message hasPrefix:@"Could not"]||[message hasPrefix:@"Cannot"]){self.readinessLabel.stringValue=message;self.readinessLabel.toolTip=message;}}
- (void)activateOutput:(id)sender{
    [self outputMessage:@"Requesting A/V output driver activation. If asked, enable Shuttle Video Output Extension in System Settings → Camera Extensions."];
    OSSystemExtensionRequest* request=[OSSystemExtensionRequest activationRequestForExtension:@"local.shuttle.output.extension" queue:dispatch_get_main_queue()];request.delegate=self;[[OSSystemExtensionManager sharedManager] submitRequest:request];
}
- (OSSystemExtensionReplacementAction)request:(OSSystemExtensionRequest*)request actionForReplacingExtension:(OSSystemExtensionProperties*)oldExtension withExtension:(OSSystemExtensionProperties*)newExtension{return OSSystemExtensionReplacementActionReplace;}
- (void)requestNeedsUserApproval:(OSSystemExtensionRequest*)request{[self outputMessage:@"macOS is waiting for approval of Shuttle Video Output Extension in System Settings → General → Login Items & Extensions → Camera Extensions."];}
- (void)deactivateOutput:(id)sender {if([NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.FinalCut"].count||[NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.adobe.PremierePro.25"].count){[self outputMessage:@"Quit Final Cut and Premiere before disabling the output driver."];return;}if(self.task){[self outputMessage:@"Stop output before disabling its driver."];return;}auto request=[OSSystemExtensionRequest deactivationRequestForExtension:@"local.shuttle.output.extension" queue:dispatch_get_main_queue()];request.delegate=self;[OSSystemExtensionManager.sharedManager submitRequest:request];}
- (void)request:(OSSystemExtensionRequest*)request didFinishWithResult:(OSSystemExtensionRequestResult)result{[self outputMessage:result==OSSystemExtensionRequestCompleted?@"A/V output driver request completed.":@"A/V output driver request will complete after restarting the Mac."];if(self.activationOnly)exit(0);}
- (void)request:(OSSystemExtensionRequest*)request didFailWithError:(NSError*)error{[self outputMessage:error.localizedDescription];if(self.activationOnly)exit(1);}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)app{return YES;}
- (void)applicationWillTerminate:(NSNotification*)note {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [NSUserDefaults.standardUserDefaults setBool:NO forKey:@"OutputListenEnabled"];[NSUserDefaults.standardUserDefaults synchronize];
    if(self.devicesListener){AudioObjectPropertyAddress a{kAudioHardwarePropertyDevices,kAudioObjectPropertyScopeGlobal,0};AudioObjectRemovePropertyListenerBlock(kAudioObjectSystemObject,&a,dispatch_get_main_queue(),self.devicesListener);self.devicesListener=nil;}
    [self.readinessTimer invalidate];self.readinessTimer=nil;
    [self restorePreviousAudio:@"Shuttle Camera quit" explicit:NO];
    if(self.audioRouteListener){auto address=shuttle_audio_route::mediaOutputAddress();AudioObjectRemovePropertyListenerBlock(kAudioObjectSystemObject,&address,dispatch_get_main_queue(),self.audioRouteListener);self.audioRouteListener=nil;}
    if(self.task.running){[self.task terminate];[self.task waitUntilExit];}[self clearMirror];
    [self.extendedDisplay stop];self.extendedDisplay=nil;
}
@end
int main(int argc,const char**argv){@autoreleasepool {NSApplication* app=[NSApplication sharedApplication];app.activationPolicy=NSApplicationActivationPolicyRegular;if(argc==3&&!strcmp(argv[1],"--render")){app.activationPolicy=NSApplicationActivationPolicyAccessory;app.appearance=[NSAppearance appearanceNamed:NSAppearanceNameAqua];}OutputHost* host=[OutputHost new];app.delegate=host;[app run];}return 0;}
