// GPL-2.0-or-later. Shuttle Player, 19 October 2026.
#import <Cocoa/Cocoa.h>
#import <AVFoundation/AVFoundation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include "PlayerIPC.hpp"
#include "FrameSizing.hpp"
#include <memory>
#include <cmath>
#include <csignal>
#include <chrono>

@class Player;
@interface ScrubSlider : NSSlider
@property(weak) Player* owner;
@end
@interface Player : NSObject<NSApplicationDelegate,NSWindowDelegate> {
    std::unique_ptr<player::Mapping> mapping;
    uint64_t previewGeneration;
    player::PreviewClock previewClock;
    double previewStatsStart;unsigned previewStatsFrames;
}
@property NSWindow* window;
@property NSImageView* image;
@property NSStackView* transportControls;
@property NSView* transportBar;
@property(nonatomic,strong) dispatch_queue_t logQueue;
@property NSTextField *fileLabel,*status,*elapsed,*total;
@property NSButton *openButton,*playButton,*stopButton,*loopButton;
@property NSPopUpButton *mode,*sizing,*connector;
@property ScrubSlider* scrub;
@property NSSlider* volume;
@property NSURL* movie;
@property AVAssetImageGenerator* thumbnail;
@property double duration;
@property NSTask* task;
@property NSPipe *input,*output;
@property NSTimer* timer;
@property NSTimer* handoverTimer;
@property NSDate* handoverDeadline;
@property BOOL handover;
@property NSString *channelPath,*log,*logPath;
@property BOOL paused,ready,scrubbing,stopping,quitting;
@property double lastSeek;
@property NSUInteger thumbnailRequest;
@property NSApplicationTerminateReply terminationReply;
- (void)seek:(id)sender;
- (void)command:(NSString*)line;
- (void)tick:(id)sender;
- (void)refresh;
@end
@implementation ScrubSlider
- (void)mouseDown:(NSEvent*)event {
    BOOL resume=self.owner.task&&!self.owner.paused;
    self.owner.scrubbing=YES;[self.owner command:@"pause 1"];
    [super mouseDown:event];
    self.owner.lastSeek=0;[self.owner seek:self];self.owner.scrubbing=NO;
    if(resume)[self.owner command:@"pause 0"];
}
@end
static NSTextField* label(NSString* text){NSTextField* l=[NSTextField labelWithString:text];l.lineBreakMode=NSLineBreakByTruncatingMiddle;return l;}
static NSButton* button(NSString* title,id target,SEL action){NSButton* b=[NSButton buttonWithTitle:title target:target action:action];b.bezelStyle=NSBezelStyleRounded;return b;}
static NSImage* symbol(NSString* name,NSString* description,CGFloat size){
    NSImage* image=[NSImage imageWithSystemSymbolName:name accessibilityDescription:description];
    return [image imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:size weight:NSFontWeightRegular]];
}
static NSButton* iconButton(NSString* name,NSString* text,id target,SEL action,BOOL large=NO){
    NSButton* b=button(@"",target,action);b.bordered=NO;b.imagePosition=NSImageOnly;b.imageScaling=NSImageScaleProportionallyDown;
    b.image=symbol(name,text,large?28:21);b.toolTip=text;[b setAccessibilityLabel:text];
    [b.widthAnchor constraintEqualToConstant:large?52:44].active=YES;[b.heightAnchor constraintEqualToConstant:44].active=YES;
    return b;
}
static NSStackView* row(NSArray<NSView*>* views){NSStackView* s=[NSStackView stackViewWithViews:views];s.orientation=NSUserInterfaceLayoutOrientationHorizontal;s.spacing=10;s.alignment=NSLayoutAttributeCenterY;return s;}
static NSString* timeText(double sec){long s=long(std::max(0.,std::isfinite(sec)?sec:0));return [NSString stringWithFormat:@"%02ld:%02ld:%02ld",s/3600,s/60%60,s%60];}
@implementation Player
- (void)applicationDidFinishLaunching:(NSNotification*)note {
    signal(SIGPIPE,SIG_IGN);self.log=@"";self.paused=YES;self.logQueue=dispatch_queue_create("local.shuttle.player.log",DISPATCH_QUEUE_SERIAL);
    self.window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,840,680) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    self.window.title=@"Shuttle Player";self.window.minSize=NSMakeSize(740,600);self.window.delegate=self;[self.window center];
    NSView* root=self.window.contentView;
    self.openButton=button(@"Open video…",self,@selector(open:));self.fileLabel=label(@"Choose a movie to get started");
    self.fileLabel.font=[NSFont systemFontOfSize:14 weight:NSFontWeightMedium];[self.fileLabel setContentCompressionResistancePriority:200 forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView* fileRow=row(@[self.openButton,self.fileLabel]);
    self.image=[NSImageView new];self.image.imageScaling=NSImageScaleProportionallyUpOrDown;self.image.wantsLayer=YES;self.image.layer.backgroundColor=NSColor.blackColor.CGColor;self.image.layer.cornerRadius=8;self.image.toolTip=@"Preview of the video sent to the Shuttle. Sound plays through the Shuttle outputs.";
    self.elapsed=label(@"00:00:00");self.total=label(@"00:00:00");self.elapsed.font=self.total.font=[NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightRegular];
    self.scrub=[ScrubSlider sliderWithValue:0 minValue:0 maxValue:1 target:self action:@selector(seek:)];self.scrub.owner=self;self.scrub.continuous=YES;self.scrub.toolTip=@"Drag to scrub through the movie";[self.scrub setAccessibilityLabel:@"Movie position"];
    NSStackView* timeline=row(@[self.elapsed,self.scrub,self.total]);
    NSButton* back=iconButton(@"gobackward.10",@"Back 10 seconds",self,@selector(back:));NSButton* forward=iconButton(@"goforward.10",@"Forward 10 seconds",self,@selector(forward:));
    self.playButton=iconButton(@"play.fill",@"Play",self,@selector(play:),YES);self.playButton.keyEquivalent=@" ";self.stopButton=iconButton(@"stop.fill",@"Stop",self,@selector(stop:));
    self.loopButton=iconButton(@"repeat",@"Loop",self,@selector(loopChanged:));[self.loopButton setButtonType:NSButtonTypePushOnPushOff];
    NSUserDefaults* prefs=NSUserDefaults.standardUserDefaults;[prefs registerDefaults:@{@"Loop":@YES,@"Volume":@1,@"Mode":@2,@"Sizing":@2,@"Connector":@0}];
    self.loopButton.state=[prefs boolForKey:@"Loop"]?NSControlStateValueOn:NSControlStateValueOff;
    self.volume=[NSSlider sliderWithValue:[prefs doubleForKey:@"Volume"] minValue:0 maxValue:1 target:self action:@selector(volumeChanged:)];self.volume.continuous=YES;self.volume.toolTip=@"Shuttle playback volume — leaves Mac sound settings unchanged";[self.volume setAccessibilityLabel:@"Shuttle volume"];
    self.loopButton.contentTintColor=self.loopButton.state==NSControlStateValueOn?NSColor.controlAccentColor:NSColor.labelColor;
    NSView* transport=[NSView new];self.transportBar=transport;
    self.transportControls=row(@[self.stopButton,back,self.playButton,forward,self.loopButton]);self.transportControls.spacing=8;self.transportControls.translatesAutoresizingMaskIntoConstraints=NO;[transport addSubview:self.transportControls];
    NSImageView* speaker=[NSImageView new];speaker.image=symbol(@"speaker.wave.2.fill",@"Volume",16);
    [speaker.widthAnchor constraintEqualToConstant:20].active=YES;
    NSStackView* volumeControls=row(@[speaker,self.volume]);volumeControls.spacing=6;volumeControls.translatesAutoresizingMaskIntoConstraints=NO;[transport addSubview:volumeControls];
    [NSLayoutConstraint activateConstraints:@[[transport.heightAnchor constraintEqualToConstant:48],[self.transportControls.centerXAnchor constraintEqualToAnchor:transport.centerXAnchor],[self.transportControls.centerYAnchor constraintEqualToAnchor:transport.centerYAnchor],[volumeControls.trailingAnchor constraintEqualToAnchor:transport.trailingAnchor],[volumeControls.centerYAnchor constraintEqualToAnchor:transport.centerYAnchor]]];
    self.connector=[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];[self.connector addItemsWithTitles:@[@"HDMI",@"S-Video",@"Composite",@"Component"]];[self.connector selectItemAtIndex:std::max(0L,std::min(3L,[prefs integerForKey:@"Connector"]))];self.connector.target=self;self.connector.action=@selector(connectionChanged:);
    self.mode=[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];[self.mode addItemsWithTitles:@[@"PAL · 576i50",@"1080i50",@"1080p25",@"NTSC · 480i59.94",@"1080i59.94",@"1080p29.97"]];[self.mode selectItemAtIndex:std::max(0L,std::min(5L,[prefs integerForKey:@"Mode"]))];self.mode.target=self;self.mode.action=@selector(settingsChanged:);
    self.sizing=[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];[self.sizing addItemsWithTitles:@[@"Fit",@"Fill",@"Stretch"]];[self.sizing selectItemAtIndex:std::max(0L,std::min(2L,[prefs integerForKey:@"Sizing"]))];self.sizing.target=self;self.sizing.action=@selector(settingsChanged:);
    NSStackView* settings=row(@[label(@"Connection"),self.connector,label(@"Format"),self.mode,label(@"Scaling"),self.sizing]);
    self.status=label(@"Open a video, then press Play.");self.status.textColor=NSColor.secondaryLabelColor;self.status.font=[NSFont systemFontOfSize:12];
    NSStackView* stack=[NSStackView stackViewWithViews:@[fileRow,self.image,timeline,transport,settings,self.status]];stack.orientation=NSUserInterfaceLayoutOrientationVertical;stack.alignment=NSLayoutAttributeLeading;stack.spacing=14;stack.translatesAutoresizingMaskIntoConstraints=NO;[root addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[stack.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:20],[stack.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-20],[stack.topAnchor constraintEqualToAnchor:root.topAnchor constant:20],[stack.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-20],[self.image.heightAnchor constraintGreaterThanOrEqualToConstant:260],[self.volume.widthAnchor constraintEqualToConstant:100],[self.scrub.widthAnchor constraintGreaterThanOrEqualToConstant:350]]];
    for(NSView* v in @[fileRow,self.image,timeline,transport,settings,self.status])[v.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active=YES;
    [self.image setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationVertical];[self.image setContentCompressionResistancePriority:1 forOrientation:NSLayoutConstraintOrientationVertical];
    // Read only: start with the Camera app's saved output standard/connection.
    // Player overrides remain local; never inherit its burn-in overlays or audio route.
    CFStringRef cameraDomain=CFSTR("local.shuttle.camera");CFPreferencesAppSynchronize(cameraDomain);
    id cameraMode=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("OutputMode"),cameraDomain));
    id cameraConnector=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("OutputConnector"),cameraDomain));
    if([cameraMode isKindOfClass:NSNumber.class]&&[cameraMode integerValue]>=0&&[cameraMode integerValue]<6)[self.mode selectItemAtIndex:[cameraMode integerValue]];
    else {
        id capture=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("LastKnownCaptureSettings"),cameraDomain));
        if([capture isKindOfClass:NSDictionary.class]&&[capture[@"standard"] isEqual:@"NTSC"])[self.mode selectItemAtIndex:3];
        else if([capture isKindOfClass:NSDictionary.class]&&[capture[@"standard"] isEqual:@"PAL"])[self.mode selectItemAtIndex:0];
    }
    if([cameraConnector isKindOfClass:NSNumber.class]&&[cameraConnector integerValue]>=0&&[cameraConnector integerValue]<4)[self.connector selectItemAtIndex:[cameraConnector integerValue]];
    self.mode.toolTip=@"Starts with Shuttle Camera’s saved output format. Changes here apply to Player only.";
    [self connectionChanged:nil];[self buildMenu];[self refresh];
    self.timer=[NSTimer timerWithTimeInterval:1.0/60.0 target:self selector:@selector(tick:) userInfo:nil repeats:YES];self.timer.tolerance=.001;
    [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
    if([NSProcessInfo.processInfo.arguments containsObject:@"--ui-test"]){
        NSCAssert(self.mode.numberOfItems==6&&self.sizing.numberOfItems==3,@"menus");
        NSCAssert(self.window.minSize.width>=740&&self.scrub.continuous&&[self.scrub isKindOfClass:ScrubSlider.class],@"layout/scrub");
        NSCAssert(!self.task&&!self.playButton.enabled&&!self.stopButton.enabled,@"safe initial state");
        [root layoutSubtreeIfNeeded];
        NSCAssert(std::abs(NSMidX(self.transportControls.frame)-NSMidX(self.transportBar.bounds))<1,@"centred controls");
        NSCAssert(self.playButton.image&&self.stopButton.image&&self.loopButton.image&&self.playButton.title.length==0,@"native transport icons");
        NSCAssert(self.timer.timeInterval<.02,@"full-rate preview refresh");
        puts("PASS: UI menus, scrub bar and safe initial state; no USB started.");[NSApp terminate:nil];return;
    }
    [self.window makeKeyAndOrderFront:nil];[NSApp activateIgnoringOtherApps:YES];
}
- (void)buildMenu {
    NSMenu* main=[NSMenu new];NSMenuItem* appItem=[NSMenuItem new];[main addItem:appItem];NSMenu* app=[NSMenu new];appItem.submenu=app;
    NSMenuItem* about=[app addItemWithTitle:@"About Shuttle Player" action:@selector(about:) keyEquivalent:@""];about.target=self;
    [app addItem:NSMenuItem.separatorItem];[app addItemWithTitle:@"Hide Shuttle Player" action:@selector(hide:) keyEquivalent:@"h"];[app addItem:NSMenuItem.separatorItem];[app addItemWithTitle:@"Quit Shuttle Player" action:@selector(terminate:) keyEquivalent:@"q"];
    NSMenuItem* fileItem=[NSMenuItem new];[main addItem:fileItem];NSMenu* file=[[NSMenu alloc] initWithTitle:@"File"];fileItem.submenu=file;[file addItemWithTitle:@"Open Video…" action:@selector(open:) keyEquivalent:@"o"].target=self;
    NSMenuItem* helpItem=[NSMenuItem new];[main addItem:helpItem];NSMenu* help=[[NSMenu alloc] initWithTitle:@"Help"];helpItem.submenu=help;[help addItemWithTitle:@"Shuttle Player Help" action:@selector(help:) keyEquivalent:@"?"].target=self;
    [help addItemWithTitle:@"Playback Diagnostics" action:@selector(diagnostics:) keyEquivalent:@""].target=self;
    [help addItemWithTitle:@"Licence" action:@selector(licence:) keyEquivalent:@""].target=self;NSApp.mainMenu=main;
}
- (void)about:(id)sender {[NSApp orderFrontStandardAboutPanelWithOptions:@{NSAboutPanelOptionApplicationName:@"Shuttle Player",NSAboutPanelOptionApplicationVersion:@"0.1.1",NSAboutPanelOptionVersion:@"2",NSAboutPanelOptionCredits:[[NSAttributedString alloc] initWithString:@"Video and stereo audio playback for Intensity Shuttle USB 3.0.\nIndependent community software. GPL-2.0-or-later; no warranty.\nIntel builds are experimental and untested on hardware."]}];}
- (void)help:(id)sender {NSURL* url=[NSBundle.mainBundle URLForResource:@"Read Me" withExtension:@"html"];if(url)[NSWorkspace.sharedWorkspace openURL:url];}
- (void)diagnostics:(id)sender {if(self.logPath.length)[NSWorkspace.sharedWorkspace openURL:[NSURL fileURLWithPath:self.logPath]];else [self message:@"No playback log yet. Open a video and press Play first."];}
- (void)licence:(id)sender {NSURL* url=[NSBundle.mainBundle URLForResource:@"COPYING" withExtension:nil];if(url)[NSWorkspace.sharedWorkspace openURL:url];}
- (void)message:(NSString*)text {NSAlert* a=[NSAlert new];a.messageText=@"Shuttle Player";a.informativeText=text;[a beginSheetModalForWindow:self.window completionHandler:nil];}
- (void)open:(id)sender {
    if(self.task){[self message:@"Click Stop before choosing another video."];return;}
    NSOpenPanel* panel=[NSOpenPanel openPanel];panel.canChooseDirectories=NO;panel.allowsMultipleSelection=NO;panel.allowedContentTypes=@[UTTypeMovie,UTTypeVideo,UTTypeAudiovisualContent];
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response){if(response==NSModalResponseOK)[self loadMovie:panel.URL];}];
}
- (void)loadMovie:(NSURL*)url {
    [self.thumbnail cancelAllCGImageGeneration];self.thumbnail=nil;self.movie=url;self.duration=0;self.fileLabel.stringValue=url.lastPathComponent;self.fileLabel.toolTip=url.path;self.image.image=nil;self.status.stringValue=@"Reading video…";[self refresh];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{@autoreleasepool{
        AVURLAsset* asset=[AVURLAsset URLAssetWithURL:url options:nil];double duration=CMTimeGetSeconds(asset.duration);BOOL valid=[asset tracksWithMediaType:AVMediaTypeVideo].count&&std::isfinite(duration)&&duration>0;
        CGImageRef thumb=nullptr;
        if(valid){AVAssetImageGenerator* g=[[AVAssetImageGenerator alloc] initWithAsset:asset];g.appliesPreferredTrackTransform=YES;g.maximumSize=CGSizeMake(800,450);thumb=[g copyCGImageAtTime:kCMTimeZero actualTime:nil error:nil];}
        NSImage* image=thumb?[[NSImage alloc] initWithCGImage:thumb size:NSZeroSize]:nil;if(thumb)CGImageRelease(thumb);
        dispatch_async(dispatch_get_main_queue(),^{if(![self.movie isEqual:url])return;
            if(!valid){self.movie=nil;self.status.stringValue=@"This file has no readable video.";[self refresh];return;}
            self.thumbnail=[[AVAssetImageGenerator alloc] initWithAsset:asset];self.thumbnail.appliesPreferredTrackTransform=YES;self.thumbnail.maximumSize=CGSizeMake(800,450);self.duration=duration;self.scrub.maxValue=duration;self.scrub.doubleValue=0;self.total.stringValue=timeText(duration);self.elapsed.stringValue=timeText(0);self.image.image=image;self.status.stringValue=@"Ready — press Play to send video and sound to the Shuttle.";[self refresh];
        });
    }});
}
- (void)connectionChanged:(id)sender {
    auto c=shuttle_output::Connector(self.connector.indexOfSelectedItem);unsigned m=unsigned(self.mode.indexOfSelectedItem);
    [self.mode selectItemAtIndex:shuttle_output::compatibleMode(c,m)];
    for(NSMenuItem* item in self.mode.itemArray)item.enabled=shuttle_output::connectorSupports(c,unsigned(item.tag));
    // Tags are set explicitly; autoenablesItems must not override compatibility.
    self.mode.menu.autoenablesItems=NO;
    for(NSUInteger n=0;n<self.mode.numberOfItems;++n){NSMenuItem* item=[self.mode itemAtIndex:n];item.tag=n;item.enabled=shuttle_output::connectorSupports(c,unsigned(n));}
    [self settingsChanged:nil];
}
- (void)settingsChanged:(id)sender {NSUserDefaults* p=NSUserDefaults.standardUserDefaults;[p setInteger:self.mode.indexOfSelectedItem forKey:@"Mode"];[p setInteger:self.sizing.indexOfSelectedItem forKey:@"Sizing"];[p setInteger:self.connector.indexOfSelectedItem forKey:@"Connector"];}
- (void)loopChanged:(id)sender {self.loopButton.contentTintColor=self.loopButton.state==NSControlStateValueOn?NSColor.controlAccentColor:NSColor.labelColor;[NSUserDefaults.standardUserDefaults setBool:self.loopButton.state==NSControlStateValueOn forKey:@"Loop"];[self command:[NSString stringWithFormat:@"loop %d",self.loopButton.state==NSControlStateValueOn]];}
- (void)volumeChanged:(id)sender {[NSUserDefaults.standardUserDefaults setDouble:self.volume.doubleValue forKey:@"Volume"];[self command:[NSString stringWithFormat:@"volume %.5f",self.volume.doubleValue]];}
- (void)play:(id)sender {
    if(self.stopping||self.handover)return;
    if(!self.task&&self.movie&&self.duration>0){
        NSArray<NSRunningApplication*>* cameras=[NSRunningApplication runningApplicationsWithBundleIdentifier:@"local.shuttle.camera"];
        if(cameras.count){
            self.handover=YES;self.handoverDeadline=[NSDate dateWithTimeIntervalSinceNow:20];
            self.status.stringValue=@"Stopping Shuttle Camera and finishing any recording…";
            for(NSRunningApplication* camera in cameras)[camera terminate];
            [self refresh];__weak Player* weak=self;
            self.handoverTimer=[NSTimer scheduledTimerWithTimeInterval:.15 repeats:YES block:^(NSTimer* timer){
                Player* owner=weak;if(!owner){[timer invalidate];return;}
                if(![NSRunningApplication runningApplicationsWithBundleIdentifier:@"local.shuttle.camera"].count){
                    [timer invalidate];owner.handoverTimer=nil;owner.handover=NO;[owner play:nil];
                }else if(owner.handoverDeadline.timeIntervalSinceNow<=0){
                    [timer invalidate];owner.handoverTimer=nil;owner.handover=NO;
                    owner.status.stringValue=@"Shuttle Camera has not finished stopping.";[owner refresh];
                    [owner message:@"Shuttle Camera is still finishing or needs attention. Stop its recording/output and try Play again. No recording has been force-killed."];
                }
            }];return;
        }
    }
    if(self.task){self.paused=!self.paused;[self command:self.paused?@"pause 1":@"pause 0"];self.status.stringValue=self.paused?@"Paused":@"Playing through Shuttle";[self refresh];return;}
    if(!self.movie||self.duration<=0)return;
    NSString* path=[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"shuttle-player-%@.preview",NSUUID.UUID.UUIDString]];
    try{mapping.reset(new player::Mapping(path.fileSystemRepresentation,true));}catch(const std::exception& e){[self message:@(e.what())];return;}
    self.channelPath=path;previewGeneration=0;previewClock.reset();previewStatsStart=0;previewStatsFrames=0;self.log=@"";
    NSURL* cache=[[NSFileManager defaultManager] URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
    cache=[cache URLByAppendingPathComponent:@"local.shuttle.player" isDirectory:YES];[[NSFileManager defaultManager] createDirectoryAtURL:cache withIntermediateDirectories:YES attributes:nil error:nil];
    self.logPath=[cache URLByAppendingPathComponent:@"LastPlayback.log"].path;self.input=[NSPipe pipe];self.output=[NSPipe pipe];self.ready=NO;self.paused=NO;
    NSTask* task=[NSTask new];self.task=task;task.executableURL=[NSBundle.mainBundle.executableURL.URLByDeletingLastPathComponent URLByAppendingPathComponent:@"ShuttlePlayerOutput"];
    NSArray* modes=@[@"576i50",@"1080i50",@"1080p25",@"480i5994",@"1080i5994",@"1080p2997"];
    task.arguments=@[modes[self.mode.indexOfSelectedItem],self.movie.path,[NSString stringWithFormat:@"%ld",self.sizing.indexOfSelectedItem],path,[NSString stringWithFormat:@"%.5f",self.volume.doubleValue]];NSMutableDictionary* env=[NSProcessInfo.processInfo.environment mutableCopy];env[@"SHUTTLE_TRACE_FIFO"]=@"1";task.environment=env;task.standardInput=self.input;task.standardOutput=self.output;task.standardError=self.output;
    __weak Player* weak=self;
    self.output.fileHandleForReading.readabilityHandler=^(NSFileHandle* handle){NSData* data=handle.availableData;if(!data.length){handle.readabilityHandler=nil;return;}NSString* text=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]?:@"";dispatch_async(dispatch_get_main_queue(),^{Player* owner=weak;if(owner.task!=task)return;[owner appendLog:text];if([owner.log containsString:@"PLAYER_READY"]&&!owner.ready){owner.ready=YES;owner.status.stringValue=owner.paused?@"Paused":@"Playing through Shuttle";}});};
    task.terminationHandler=^(NSTask* ended){dispatch_async(dispatch_get_main_queue(),^{Player* owner=weak;if(owner.task!=ended)return;BOOL expected=owner.stopping||owner.quitting;owner.output.fileHandleForReading.readabilityHandler=nil;@try{[owner.input.fileHandleForWriting closeFile];}@catch(NSException* e){}owner.task=nil;owner.input=nil;owner.output=nil;owner.ready=NO;owner.stopping=NO;owner.paused=YES;
        owner->mapping.reset();[[NSFileManager defaultManager] removeItemAtPath:owner.channelPath error:nil];owner.channelPath=nil;
        owner.scrub.doubleValue=0;owner.elapsed.stringValue=timeText(0);
        owner.status.stringValue=ended.terminationStatus==0?@"Stopped — Shuttle is available for capture or other output.":@"Output stopped. Check the Shuttle connection and close other capture/output apps.";
        [owner refresh];if(ended.terminationStatus&&!expected)[owner message:owner.log.length?owner.log:@"The Shuttle output could not start."];
        if(owner.quitting)[NSApp replyToApplicationShouldTerminate:YES];
    });};
    NSError* error=nil;if(![task launchAndReturnError:&error]){self.output.fileHandleForReading.readabilityHandler=nil;self.task=nil;mapping.reset();[[NSFileManager defaultManager] removeItemAtPath:path error:nil];self.channelPath=nil;[self message:error.localizedDescription];[self refresh];return;}
    [self command:[NSString stringWithFormat:@"seek %.6f",self.scrub.doubleValue]];[self loopChanged:nil];[self command:@"pause 0"];self.status.stringValue=@"Starting Shuttle output…";[self refresh];
}
- (void)appendLog:(NSString*)text {
    self.log=[self.log stringByAppendingString:text];if(self.log.length>8192)self.log=[self.log substringFromIndex:self.log.length-8192];
    NSString* snapshot=self.log;NSString* path=self.logPath;
    if(path.length)dispatch_async(self.logQueue,^{[snapshot writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];});
}
- (void)command:(NSString*)line {
    if(!self.task.running)return;
    @try{[self.input.fileHandleForWriting writeData:[[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding]];}@catch(NSException* e){}
}
- (void)stop:(id)sender {
    if(self.handover){[self.handoverTimer invalidate];self.handoverTimer=nil;self.handover=NO;self.status.stringValue=@"Handover cancelled.";[self refresh];return;}
    if(!self.task)return;self.stopping=YES;self.status.stringValue=@"Stopping output…";[self command:@"stop"];[self.task terminate];[self refresh];
    NSTask* stopped=self.task;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,8*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(self.task==stopped&&stopped.running)kill(stopped.processIdentifier,SIGKILL);});
}
- (void)seek:(id)sender {
    self.elapsed.stringValue=timeText(self.scrub.doubleValue);
    double now=NSDate.timeIntervalSinceReferenceDate;if(self.scrubbing&&now-self.lastSeek<.15)return;self.lastSeek=now;
    [self command:[NSString stringWithFormat:@"seek %.6f",self.scrub.doubleValue]];
    if(!self.task&&self.thumbnail){
        AVAssetImageGenerator* generator=self.thumbnail;NSUInteger request=++self.thumbnailRequest;[generator cancelAllCGImageGeneration];
        CMTime time=CMTimeMakeWithSeconds(std::min(self.scrub.doubleValue,std::max(0.,self.duration-.04)),600000);
        [generator generateCGImagesAsynchronouslyForTimes:@[[NSValue valueWithCMTime:time]] completionHandler:^(CMTime requested,CGImageRef cg,CMTime actual,AVAssetImageGeneratorResult result,NSError* error){
            if(result!=AVAssetImageGeneratorSucceeded||!cg)return;
            NSImage* image=[[NSImage alloc] initWithCGImage:cg size:NSZeroSize];
            dispatch_async(dispatch_get_main_queue(),^{if(self.thumbnail==generator&&!self.task&&self.thumbnailRequest==request)self.image.image=image;});
        }];
    }
}
- (void)back:(id)sender {self.scrub.doubleValue=std::max(0.,self.scrub.doubleValue-10);self.lastSeek=0;[self seek:nil];}
- (void)forward:(id)sender {self.scrub.doubleValue=std::min(self.duration,self.scrub.doubleValue+10);self.lastSeek=0;[self seek:nil];}
- (void)refresh {
    BOOL active=self.task!=nil||self.handover;self.openButton.enabled=!active;self.mode.enabled=self.sizing.enabled=self.connector.enabled=!active;
    self.playButton.enabled=self.duration>0&&!self.stopping&&!self.handover;BOOL playing=active&&!self.paused;
    self.playButton.image=symbol(playing?@"pause.fill":@"play.fill",playing?@"Pause":@"Play",28);
    [self.playButton setAccessibilityLabel:playing?@"Pause":@"Play"];self.playButton.toolTip=playing?@"Pause (Space)":@"Play (Space)";self.stopButton.enabled=active&&!self.stopping;self.scrub.enabled=self.duration>0&&!self.stopping&&!self.handover;
}
- (void)tick:(id)sender {
    if(!mapping||!mapping->lock())return;auto& channel=*mapping->data;
    if(!channel.published||!channel.rateNom||!channel.rateDen){mapping->unlock();return;}
    uint64_t nowNS=std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now().time_since_epoch()).count();
    uint64_t wanted=previewClock.choose(channel.published,channel.rateNom,channel.rateDen,nowNS);
    const uint64_t oldest=channel.published>=player::PreviewFrames?channel.published-player::PreviewFrames+1:1;
    // A publication can be skipped if the reader holds its nonblocking lock.
    // Hold the preceding frame until the next due frame; never show a future one.
    while(wanted>=oldest&&channel.frames[(wanted-1)%player::PreviewFrames].generation!=wanted)--wanted;
    if(wanted<oldest||wanted==previewGeneration){mapping->unlock();return;}
    auto& p=channel.frames[(wanted-1)%player::PreviewFrames];
    if(p.width>player::Width||p.height>player::Height||!p.width||!p.height){mapping->unlock();return;}
    NSBitmapImageRep* rep=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nil pixelsWide:p.width pixelsHigh:p.height bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:p.width*4 bitsPerPixel:32];
    if(rep)memcpy(rep.bitmapData,p.pixels,size_t(p.width)*p.height*4);
    double position=p.position;BOOL ended=p.ended;double fps=double(channel.rateNom)/channel.rateDen;previewGeneration=wanted;mapping->unlock();
    if(rep){NSImage* image=[[NSImage alloc] initWithSize:rep.size];[image addRepresentation:rep];self.image.image=image;++previewStatsFrames;}
    double now=double(nowNS)/1e9;if(!previewStatsStart)previewStatsStart=now;
    if(now-previewStatsStart>=5){[self appendLog:[NSString stringWithFormat:@"Preview: %.2f frames/s (target %.2f); display uses buffered output frames.\n",double(previewStatsFrames)/(now-previewStatsStart),fps]];previewStatsFrames=0;previewStatsStart=now;}
    if(!self.scrubbing){self.scrub.doubleValue=position;NSString* elapsed=timeText(position);if(![self.elapsed.stringValue isEqual:elapsed])self.elapsed.stringValue=elapsed;}
    if(ended&&!self.paused){self.paused=YES;self.status.stringValue=@"Finished — press Play to replay, or Stop to release the Shuttle.";[self refresh];}
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)app{return YES;}
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication*)app {
    [self.handoverTimer invalidate];self.handoverTimer=nil;self.handover=NO;
    if(!self.task)return NSTerminateNow;self.quitting=YES;[self stop:nil];return NSTerminateLater;
}
@end
int main(int argc,char**argv){@autoreleasepool{NSApplication* app=NSApplication.sharedApplication;[app setActivationPolicy:[NSProcessInfo.processInfo.arguments containsObject:@"--ui-test"]?NSApplicationActivationPolicyProhibited:NSApplicationActivationPolicyRegular];Player* delegate=[Player new];app.delegate=delegate;[app run];}}
