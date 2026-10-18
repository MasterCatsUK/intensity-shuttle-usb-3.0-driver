// GPL-2.0-or-later. Native capture controls and camera activation.
#import <AppKit/AppKit.h>
#import <SystemExtensions/SystemExtensions.h>
#import <CoreMediaIO/CoreMediaIO.h>
#include <vector>
#include "Settings.hpp"
static NSArray<NSString *> *resolutionValues() { return @[@"Native",@"Square pixels",@"1280x960",@"1440x1080"]; }
static NSArray<NSString *> *resolutionTitles(BOOL ntsc) {
    return @[ntsc?@"Native — 720 × 480":@"Native — 720 × 576",
             ntsc?@"Square pixels — 640 × 480":@"Square pixels — 768 × 576",@"1280 × 960",@"1440 × 1080"];
}
static NSString * const ExtensionID=@"local.shuttle.camera.extension";
static CMIOObjectID cameraID() {
    CMIOObjectPropertyAddress a{kCMIOHardwarePropertyDevices,kCMIOObjectPropertyScopeGlobal,0};UInt32 size=0;
    if(CMIOObjectGetPropertyDataSize(kCMIOObjectSystemObject,&a,0,nullptr,&size)) return 0;
    std::vector<CMIOObjectID> devices(size/sizeof(CMIOObjectID));
    if(CMIOObjectGetPropertyData(kCMIOObjectSystemObject,&a,0,nullptr,size,&size,devices.data())) return 0;
    for(auto d:devices) {
        a={kCMIODevicePropertyDeviceUID,kCMIOObjectPropertyScopeGlobal,0};CFStringRef uid=nullptr;size=sizeof(uid);
        if(CMIOObjectGetPropertyData(d,&a,0,nullptr,size,&size,&uid)) continue;
        bool matches=uid && CFEqual(uid,CFSTR("local.shuttle.camera.pal"));if(uid) CFRelease(uid);if(matches) return d;
    }return 0;
}
static NSDictionary *readSettings() {
    auto device=cameraID();if(!device) return nil;
    CMIOObjectPropertyAddress a{'conf',kCMIOObjectPropertyScopeGlobal,UInt32('0')};
    CFStringRef json=nullptr;UInt32 size=sizeof(json);
    if(CMIOObjectGetPropertyData(device,&a,0,nullptr,size,&size,&json)) return nil;
    return settingsDictionary(CFBridgingRelease(json));
}
static OSStatus writeSettings(NSDictionary *settings) {
    shuttle::CaptureSettings parsed;if(!parseSettings(settings,parsed)) return paramErr;
    auto device=cameraID();if(!device) return kCMIOHardwareBadDeviceError;
    NSString *json=settingsJSON(settings);CFStringRef value=(__bridge CFStringRef)json;
    CMIOObjectPropertyAddress a{'conf',kCMIOObjectPropertyScopeGlobal,UInt32('0')};
    return CMIOObjectSetPropertyData(device,&a,0,nullptr,sizeof(value),&value);
}
@interface SettingsCanvas : NSView
@end
@implementation SettingsCanvas
- (BOOL)isOpaque { return YES; }
- (void)drawRect:(NSRect)rect { [NSColor.windowBackgroundColor setFill];NSRectFill(rect); }
@end
@interface Host : NSObject <NSApplicationDelegate, OSSystemExtensionRequestDelegate>
@property(strong) NSWindow *window;
@property(strong) NSTextField *status,*formatLabel,*inputLabel;
@property(strong) NSPopUpButton *standard,*video,*audio,*dropout,*resolution;
@property NSView *pictureView;
@property NSSlider *brightness,*contrast,*colour,*sharpness;
@property NSArray<NSTextField*> *pictureValues;
@property NSTextField *pictureStatus;
@property NSButton *pictureApply,*pictureReset,*enablePicture,*livePicture;
@property NSTimer *pictureTimer,*settingsRetry;
@property NSUInteger settingsRetryCount;
@property BOOL captureDraft;
@property BOOL commandLine,removeRequested,embedded;
@property(copy) NSString *renderPath;
- (void)report:(NSString *)message;
@end
@implementation Host
- (NSTextField *)label:(NSString *)text rect:(NSRect)rect font:(CGFloat)font {
    NSTextField *label=[NSTextField wrappingLabelWithString:text];label.frame=rect;
    label.font=[NSFont systemFontOfSize:font];[self.window.contentView addSubview:label];return label;
}
- (NSPopUpButton *)popup:(NSArray<NSString *> *)items at:(CGFloat)y title:(NSString *)title {
    [self label:title rect:NSMakeRect(24,y+4,140,24) font:14];
    NSPopUpButton *p=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(174,y,452,30) pullsDown:NO];
    [p addItemsWithTitles:items];p.target=self;p.action=@selector(selectionChanged:);[self.window.contentView addSubview:p];return p;
}
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    if(self.commandLine) { if(self.removeRequested) [self deactivate:nil];else [self activate:nil];return; }
    self.window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,650,500) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable backing:NSBackingStoreBuffered defer:NO];self.window.title=@"Shuttle Camera";
    self.window.contentView=[[SettingsCanvas alloc] initWithFrame:NSMakeRect(0,0,650,500)];
    NSView *v=self.window.contentView;
    auto box=[NSBox new];box.title=@"Input";box.frame=NSMakeRect(18,222,300,264);[v addSubview:box];
    auto formatBox=[NSBox new];formatBox.title=@"Capture";formatBox.frame=NSMakeRect(332,222,300,264);[v addSubview:formatBox];
    auto field=^(NSString *title,NSArray *items,CGFloat x,CGFloat y){
        [self label:title rect:NSMakeRect(x,y+4,104,22) font:13];
        auto p=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(x+104,y,166,30)];[p addItemsWithTitles:items];p.target=self;p.action=@selector(selectionChanged:);[v addSubview:p];return p;
    };
    self.standard=field(@"Standard",@[@"PAL",@"NTSC"],34,416);
    self.video=field(@"Video",@[@"S-Video",@"Composite",@"Component",@"HDMI"],34,366);
    self.audio=field(@"Audio",@[@"Analog RCA",@"Embedded digital"],34,316);
    [self label:@"Resolution" rect:NSMakeRect(350,421,260,20) font:13];
    self.resolution=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(350,383,260,30)];[self.resolution addItemsWithTitles:resolutionTitles(NO)];self.resolution.target=self;self.resolution.action=@selector(selectionChanged:);[v addSubview:self.resolution];
    [self label:@"On signal loss" rect:NSMakeRect(350,341,260,20) font:13];
    self.dropout=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(350,303,260,30)];[self.dropout addItemsWithTitles:@[@"Hold last frame",@"Black"]];self.dropout.target=self;self.dropout.action=@selector(selectionChanged:);[v addSubview:self.dropout];
    self.formatLabel=[self label:@"" rect:NSMakeRect(350,253,260,30) font:12];self.formatLabel.textColor=NSColor.secondaryLabelColor;
    self.inputLabel=[self label:@"" rect:NSMakeRect(34,253,270,30) font:12];
    auto* apply=[NSButton buttonWithTitle:@"Apply" target:self action:@selector(apply:)];apply.frame=NSMakeRect(18,151,140,34);[v addSubview:apply];
    auto* refresh=[NSButton buttonWithTitle:@"Refresh" target:self action:@selector(refresh:)];refresh.frame=NSMakeRect(168,151,110,34);[v addSubview:refresh];
    auto* hint=[self label:@"Close camera previews before applying changes." rect:NSMakeRect(24,117,602,24) font:12];hint.textColor=NSColor.secondaryLabelColor;
    self.status=[self label:@"" rect:NSMakeRect(24,45,602,52) font:12];
    self.pictureView=[[SettingsCanvas alloc] initWithFrame:NSMakeRect(0,0,650,500)];
    auto pictureBox=[NSBox new];pictureBox.title=@"Input picture";pictureBox.frame=NSMakeRect(18,174,614,312);[self.pictureView addSubview:pictureBox];
    NSMutableArray *values=[NSMutableArray array];NSArray *titles=@[@"Brightness",@"Contrast",@"Colour",@"Sharpness"];
    for(unsigned n=0;n<4;++n){CGFloat y=416-n*57;
        auto title=[NSTextField labelWithString:titles[n]];title.frame=NSMakeRect(36,y+3,112,22);[self.pictureView addSubview:title];
        auto slider=[NSSlider sliderWithValue:n==1||n==2?100:0 minValue:n==0?-100:0 maxValue:n==0||n==3?100:200 target:self action:@selector(pictureChanged:)];slider.frame=NSMakeRect(160,y,362,26);slider.accessibilityLabel=titles[n];[self.pictureView addSubview:slider];
        auto value=[NSTextField labelWithString:@""];value.frame=NSMakeRect(542,y+3,66,22);value.alignment=NSTextAlignmentRight;[self.pictureView addSubview:value];[values addObject:value];
        if(n==0)self.brightness=slider;if(n==1)self.contrast=slider;if(n==2)self.colour=slider;if(n==3)self.sharpness=slider;
    }
    self.pictureValues=values;
    auto reset=[NSButton buttonWithTitle:@"Reset picture" target:self action:@selector(resetPicture:)];self.pictureReset=reset;reset.frame=NSMakeRect(36,190,150,30);[self.pictureView addSubview:reset];
    self.livePicture=[NSButton checkboxWithTitle:@"Live adjustments" target:self action:@selector(livePictureChanged:)];self.livePicture.frame=NSMakeRect(318,190,290,30);self.livePicture.state=[NSUserDefaults.standardUserDefaults objectForKey:@"LivePictureControls"]?([NSUserDefaults.standardUserDefaults boolForKey:@"LivePictureControls"]?NSControlStateValueOn:NSControlStateValueOff):NSControlStateValueOn;[self.pictureView addSubview:self.livePicture];
    auto applyPicture=[NSButton buttonWithTitle:@"Apply" target:self action:@selector(applyPicture:)];self.pictureApply=applyPicture;applyPicture.frame=NSMakeRect(18,117,140,34);[self.pictureView addSubview:applyPicture];
    self.enablePicture=[NSButton buttonWithTitle:@"Enable picture controls…" target:self action:@selector(activate:)];self.enablePicture.frame=NSMakeRect(178,117,242,34);[self.pictureView addSubview:self.enablePicture];
    auto note=[NSTextField labelWithString:@"Changes affect captured video, including any recording in progress."];note.font=[NSFont systemFontOfSize:12];note.textColor=NSColor.secondaryLabelColor;note.frame=NSMakeRect(24,82,602,24);[self.pictureView addSubview:note];
    self.livePicture.enabled=NO;self.pictureApply.enabled=self.pictureReset.enabled=NO;for(NSSlider *slider in @[self.brightness,self.contrast,self.colour,self.sharpness])slider.enabled=NO;
    self.pictureStatus=[NSTextField wrappingLabelWithString:@""];self.pictureStatus.frame=NSMakeRect(24,20,602,48);self.pictureStatus.font=[NSFont systemFontOfSize:12];[self.pictureView addSubview:self.pictureStatus];
    NSDictionary *cached=[NSUserDefaults.standardUserDefaults objectForKey:@"LastKnownCaptureSettings"];shuttle::CaptureSettings parsedCache;
    if(parseSettings(cached,parsedCache))[self loadCaptureFields:cached];
    [self refresh:nil];
    if(self.renderPath) {
        [self.window orderFront:nil];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,300*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
            NSView *view=self.window.contentView;[view layoutSubtreeIfNeeded];
            NSBitmapImageRep *rep=[view bitmapImageRepForCachingDisplayInRect:view.bounds];[view cacheDisplayInRect:view.bounds toBitmapImageRep:rep];
            BOOL ok=[[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:self.renderPath atomically:YES];exit(ok?0:1);
        });return;
    }
    if(self.embedded)return;
    [self.window center];[self.window makeKeyAndOrderFront:nil];[NSApp activateIgnoringOtherApps:YES];
}
- (void)selectionChanged:(id)sender {
    if(sender)self.captureDraft=YES;
    NSInteger index=MAX(0,self.resolution.indexOfSelectedItem);BOOL ntsc=[self.standard.titleOfSelectedItem isEqual:@"NTSC"];
    [self.resolution removeAllItems];[self.resolution addItemsWithTitles:resolutionTitles(ntsc)];[self.resolution selectItemAtIndex:index];
    shuttle::CaptureSettings settings;settings.profile.ntsc=ntsc;settings.outputSize=static_cast<shuttle::OutputSize>(index);
    self.formatLabel.stringValue=[NSString stringWithFormat:@"%u × %u · %@ fps · %@",
        settings.outputWidth(),settings.outputHeight(),ntsc?@"59.94":@"50",index==0?@"native pixels":@"4:3"];
}
- (void)refreshPictureCapabilities {
    NSDictionary *state=readSettings();if(!state)return; // a transient reconnect is not evidence of an old driver
    BOOL wasLive=self.livePicture.enabled,pictureReady=state[@"brightness"]!=nil,liveReady=[state[@"picture_live"] boolValue];
    self.livePicture.enabled=liveReady;
    for(NSSlider *slider in @[self.brightness,self.contrast,self.colour,self.sharpness])slider.enabled=pictureReady;
    self.pictureApply.enabled=self.pictureReset.enabled=pictureReady;self.enablePicture.hidden=liveReady;
    if(liveReady&&!wasLive){
        self.brightness.integerValue=[state[@"brightness"] integerValue];self.contrast.integerValue=[state[@"contrast"] integerValue];self.colour.integerValue=[state[@"colour"] integerValue];self.sharpness.integerValue=[state[@"sharpness"] integerValue];[self pictureChanged:nil];
        self.pictureStatus.stringValue=@"Live picture controls are ready.";
    }
}
- (void)loadCaptureFields:(NSDictionary*)d {
    self.brightness.integerValue=[d[@"brightness"] integerValue];self.contrast.integerValue=d[@"contrast"]?[d[@"contrast"] integerValue]:100;
    self.colour.integerValue=d[@"colour"]?[d[@"colour"] integerValue]:100;self.sharpness.integerValue=[d[@"sharpness"] integerValue];[self pictureChanged:nil];
    [self.standard selectItemWithTitle:d[@"standard"]];[self.video selectItemWithTitle:d[@"video_input"]];
    [self.audio selectItemWithTitle:d[@"audio_input"]];[self.dropout selectItemWithTitle:d[@"dropout"]];
    NSUInteger resolution=[resolutionValues() indexOfObject:d[@"output_size"]?:@"Native"];
    [self.resolution selectItemAtIndex:resolution==NSNotFound?0:resolution];[self selectionChanged:nil];
}
- (void)refresh:(id)sender {
    if(sender)self.settingsRetryCount=0;
    NSDictionary *state=readSettings();shuttle::CaptureSettings parsed;
    if(!parseSettings(state,parsed)){
        [self report:self.settingsRetryCount<12?@"Camera reconnecting — keeping your selected settings…":@"Camera unavailable. Your selected settings are retained; click Refresh to reconnect."];
        if(self.settingsRetryCount<12&&!self.settingsRetry){
            ++self.settingsRetryCount;__weak Host *weakSelf=self;
            self.settingsRetry=[NSTimer scheduledTimerWithTimeInterval:0.4 repeats:NO block:^(NSTimer *timer){Host *host=weakSelf;if(host){host.settingsRetry=nil;[host refresh:nil];}}];
        }
        return;
    }
    [self.settingsRetry invalidate];self.settingsRetry=nil;self.settingsRetryCount=0;
    NSMutableDictionary *saved=[defaultSettings() mutableCopy];for(NSString *key in defaultSettings())if(state[key])saved[key]=state[key];
    [NSUserDefaults.standardUserDefaults setObject:saved forKey:@"LastKnownCaptureSettings"];
    if(sender||!self.captureDraft){[self.pictureTimer invalidate];self.pictureTimer=nil;[self loadCaptureFields:state];self.captureDraft=NO;}
    self.inputLabel.stringValue=state?([state[@"capturing"] boolValue]?[NSString stringWithFormat:@"Capturing · %@",state[@"detected_standard"]?:@"Unknown"]:@"Camera idle"):@"Camera unavailable · see Help → Driver Setup";
    self.resolution.enabled=state[@"output_size"]!=nil;
    BOOL pictureReady=state[@"brightness"]!=nil,liveReady=[state[@"picture_live"] boolValue];
    self.livePicture.enabled=liveReady;
    for(NSSlider *slider in @[self.brightness,self.contrast,self.colour,self.sharpness])slider.enabled=pictureReady;
    self.pictureApply.enabled=self.pictureReset.enabled=pictureReady;self.enablePicture.hidden=liveReady;
    if(!liveReady)self.pictureStatus.stringValue=state?@"Live adjustments need the updated camera driver. Close camera previews, then click Enable picture controls… and approve if asked.":@"Camera unavailable. Click Enable picture controls… to set it up.";
    if(state && !state[@"output_size"]) { [self report:@"Update the camera extension to enable the new resolution controls. Close capture windows before updating."];return; }
    [self report:state?@"Ready":@"Set up the camera in Help → Driver Setup."];
    if(!liveReady)self.pictureStatus.stringValue=state?@"Live adjustments need the updated camera driver. Close camera previews, then click Enable picture controls… and approve if asked.":@"Camera unavailable. Click Enable picture controls… to set it up.";
}
- (void)apply:(id)sender {
    NSDictionary *d=@{@"standard":self.standard.titleOfSelectedItem,@"video_input":self.video.titleOfSelectedItem,
        @"audio_input":self.audio.titleOfSelectedItem,@"dropout":self.dropout.titleOfSelectedItem,
        @"output_size":resolutionValues()[MAX(0,self.resolution.indexOfSelectedItem)],
        @"brightness":@(self.brightness.integerValue),@"contrast":@(self.contrast.integerValue),@"colour":@(self.colour.integerValue),@"sharpness":@(self.sharpness.integerValue)};
    NSDictionary *state=readSettings();
    if(!state[@"output_size"]) { [self report:@"Update the camera extension before applying resolution settings."];return; }
    if([state[@"capturing"] boolValue]) { [self report:@"Camera is in use. Close all movie recording and camera windows, then apply again."];return; }
    if(!state[@"brightness"]) { [self report:@"Enable the updated camera extension in Help → Driver Setup first."];return; }
    OSStatus rc=writeSettings(d);
    if(rc) { [self report:[NSString stringWithFormat:@"Could not apply settings (%d). Close all camera windows and check that this extension is active.",(int)rc]];return; }
    self.captureDraft=NO;[NSUserDefaults.standardUserDefaults setObject:d forKey:@"LastKnownCaptureSettings"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,700*NSEC_PER_MSEC),dispatch_get_main_queue(),^{ [self refresh:nil];if(!self.settingsRetry)[self report:@"Settings applied. Reopen your camera app to use the selected standard and inputs."]; });
}
- (void)applyPicture:(id)sender {
    [self.pictureTimer invalidate];self.pictureTimer=nil;
    NSDictionary *state=readSettings();
    if(!state[@"brightness"]){[self report:@"Enable the updated camera extension to use picture controls."];return;}
    if([state[@"capturing"] boolValue]&&![state[@"picture_live"] boolValue]){[self report:@"Enable the updated camera extension for live adjustments, or close the preview before applying."];return;}
    NSMutableDictionary *changes=[defaultSettings() mutableCopy];for(NSString *key in defaultSettings())if(state[key])changes[key]=state[key];
    changes[@"brightness"]=@(self.brightness.integerValue);changes[@"contrast"]=@(self.contrast.integerValue);changes[@"colour"]=@(self.colour.integerValue);changes[@"sharpness"]=@(self.sharpness.integerValue);
    OSStatus rc=writeSettings(changes);
    [self report:rc?[NSString stringWithFormat:@"Picture update failed (%d). Check that the updated camera extension is enabled.",(int)rc]:[state[@"capturing"] boolValue]?@"Picture updated live.":@"Picture settings saved."];
}
- (void)livePictureChanged:(id)sender {
    [NSUserDefaults.standardUserDefaults setBool:self.livePicture.state==NSControlStateValueOn forKey:@"LivePictureControls"];
    [self.pictureTimer invalidate];self.pictureTimer=nil;
    if(self.livePicture.state==NSControlStateValueOn)[self applyPicture:nil];
}
- (void)pictureChanged:(id)sender {
    NSArray *sliders=@[self.brightness,self.contrast,self.colour,self.sharpness];
    for(unsigned n=0;n<4;++n){NSSlider *slider=sliders[n];slider.integerValue=lround(slider.doubleValue);self.pictureValues[n].stringValue=[NSString stringWithFormat:n==0?@"%+ld":@"%ld%%",(long)slider.integerValue];}
    if(sender&&self.livePicture.enabled&&self.livePicture.state==NSControlStateValueOn){
        [self.pictureTimer invalidate];__weak Host *weakSelf=self;
        self.pictureTimer=[NSTimer scheduledTimerWithTimeInterval:0.12 repeats:NO block:^(NSTimer *timer){Host *host=weakSelf;if(host)[host applyPicture:nil];}];
    }
}
- (void)resetPicture:(id)sender { self.brightness.integerValue=0;self.contrast.integerValue=100;self.colour.integerValue=100;self.sharpness.integerValue=0;[self pictureChanged:sender]; }
- (void)report:(NSString *)message { self.pictureStatus.stringValue=message;self.status.stringValue=message;fprintf(stdout,"%s\n",message.UTF8String);fflush(stdout); }
- (void)activate:(id)sender {
    NSDictionary *state=readSettings();
    if(sender==self.enablePicture&&[state[@"picture_live"] boolValue]){
        [self refreshPictureCapabilities];[self report:@"Live picture controls are already enabled. Use the sliders; no driver reload is needed."];return;
    }
    if([state[@"capturing"] boolValue]) { [self report:@"Stop recording and close all camera previews before enabling the updated camera extension."];if(self.commandLine)exit(10);return; }
    if(![NSBundle.mainBundle.bundlePath hasPrefix:@"/Applications/"]) {
        [self report:@"Move Shuttle Camera.app to /Applications first, then open it there."];if(self.commandLine) exit(64);return;
    }
    auto *request=[OSSystemExtensionRequest activationRequestForExtension:ExtensionID queue:dispatch_get_main_queue()];request.delegate=self;
    [self report:@"Requesting activation. macOS may require approval in System Settings → General → Login Items & Extensions → Camera Extensions."];
    [OSSystemExtensionManager.sharedManager submitRequest:request];
}
- (void)deactivate:(id)sender {
    auto *request=[OSSystemExtensionRequest deactivationRequestForExtension:ExtensionID queue:dispatch_get_main_queue()];request.delegate=self;
    [OSSystemExtensionManager.sharedManager submitRequest:request];
}
- (OSSystemExtensionReplacementAction)request:(OSSystemExtensionRequest *)request actionForReplacingExtension:(OSSystemExtensionProperties *)old withExtension:(OSSystemExtensionProperties *)ext { return OSSystemExtensionReplacementActionReplace; }
- (void)requestNeedsUserApproval:(OSSystemExtensionRequest *)request { [self report:@"Enable Shuttle Camera Extension in System Settings → General → Login Items & Extensions → Camera Extensions."]; }
- (void)request:(OSSystemExtensionRequest *)request didFinishWithResult:(OSSystemExtensionRequestResult)result {
    [self report:result==OSSystemExtensionRequestWillCompleteAfterReboot?@"macOS accepted the request; restart to finish.":@"macOS completed the request. Reopen your camera app to use Intensity Shuttle."];
    if(self.commandLine) exit(0);else {
        __weak Host *weakSelf=self;
        for(int delay: {1,3,5})dispatch_after(dispatch_time(DISPATCH_TIME_NOW,delay*NSEC_PER_SEC),dispatch_get_main_queue(),^{[weakSelf refreshPictureCapabilities];});
    }
}
- (void)request:(OSSystemExtensionRequest *)request didFailWithError:(NSError *)error { [self report:[NSString stringWithFormat:@"Activation/deactivation failed: %@",error.localizedDescription]];if(self.commandLine) exit((int)error.code); }
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { return YES; }
@end
int main(int argc,char **argv) { @autoreleasepool {
    if(argc==2 && !strcmp(argv[1],"--get-settings")) { NSDictionary *d=readSettings();if(d) puts(settingsJSON(d).UTF8String);else fputs("Camera settings unavailable\n",stderr);return d?0:1; }
    if(argc==3 && !strcmp(argv[1],"--apply-settings")) { OSStatus rc=writeSettings(settingsDictionary([NSString stringWithUTF8String:argv[2]]));printf("Apply settings: %d\n",(int)rc);return rc?1:0; }
    NSApplication *app=NSApplication.sharedApplication;app.activationPolicy=NSApplicationActivationPolicyRegular;Host *host=[Host new];
    host.commandLine=argc==2 && (!strcmp(argv[1],"--activate") || !strcmp(argv[1],"--deactivate"));host.removeRequested=argc==2 && !strcmp(argv[1],"--deactivate");
    if(argc==3 && !strcmp(argv[1],"--render")) host.renderPath=[NSString stringWithUTF8String:argv[2]];
    if(host.commandLine) app.activationPolicy=NSApplicationActivationPolicyProhibited;
    if(host.renderPath) { app.activationPolicy=NSApplicationActivationPolicyAccessory;app.appearance=[NSAppearance appearanceNamed:NSAppearanceNameAqua]; }
    app.delegate=host;[app run];
}return 0; }
