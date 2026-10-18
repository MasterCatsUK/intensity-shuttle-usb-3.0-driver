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
    self.standard=[self popup:@[@"PAL",@"NTSC"] at:440 title:@"Standard"];
    self.video=[self popup:@[@"S-Video",@"Composite",@"Component",@"HDMI"] at:396 title:@"Video input"];
    self.audio=[self popup:@[@"Analog RCA",@"Embedded digital"] at:352 title:@"Audio input"];
    self.resolution=[self popup:resolutionTitles(NO) at:308 title:@"Resolution"];
    self.dropout=[self popup:@[@"Hold last frame",@"Black"] at:264 title:@"On video loss"];
    self.formatLabel=[self label:@"" rect:NSMakeRect(24,224,602,24) font:12];self.formatLabel.textColor=NSColor.secondaryLabelColor;
    self.inputLabel=[self label:@"" rect:NSMakeRect(24,191,602,25) font:12];
    auto* apply=[NSButton buttonWithTitle:@"Apply" target:self action:@selector(apply:)];apply.frame=NSMakeRect(24,137,140,34);[self.window.contentView addSubview:apply];
    auto* refresh=[NSButton buttonWithTitle:@"Refresh" target:self action:@selector(refresh:)];refresh.frame=NSMakeRect(174,137,110,34);[self.window.contentView addSubview:refresh];
    auto* hint=[self label:@"Close camera previews before applying changes." rect:NSMakeRect(24,105,602,24) font:12];hint.textColor=NSColor.secondaryLabelColor;
    self.status=[self label:@"" rect:NSMakeRect(24,37,602,52) font:12];
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
    NSInteger index=MAX(0,self.resolution.indexOfSelectedItem);BOOL ntsc=[self.standard.titleOfSelectedItem isEqual:@"NTSC"];
    [self.resolution removeAllItems];[self.resolution addItemsWithTitles:resolutionTitles(ntsc)];[self.resolution selectItemAtIndex:index];
    shuttle::CaptureSettings settings;settings.profile.ntsc=ntsc;settings.outputSize=static_cast<shuttle::OutputSize>(index);
    self.formatLabel.stringValue=[NSString stringWithFormat:@"%u × %u · %@ fps · %@",
        settings.outputWidth(),settings.outputHeight(),ntsc?@"59.94":@"50",index==0?@"native pixels":@"4:3"];
}
- (void)refresh:(id)sender {
    NSDictionary *state=readSettings();NSDictionary *d=state?:defaultSettings();
    [self.standard selectItemWithTitle:d[@"standard"]];[self.video selectItemWithTitle:d[@"video_input"]];
    [self.audio selectItemWithTitle:d[@"audio_input"]];[self.dropout selectItemWithTitle:d[@"dropout"]];
    NSUInteger resolution=[resolutionValues() indexOfObject:d[@"output_size"]?:@"Native"];
    [self.resolution selectItemAtIndex:resolution==NSNotFound?0:resolution];[self selectionChanged:nil];
    self.inputLabel.stringValue=state?([state[@"capturing"] boolValue]?[NSString stringWithFormat:@"Capturing · %@",state[@"detected_standard"]?:@"Unknown"]:@"Camera idle"):@"Camera unavailable · see Help → Driver Setup";
    self.resolution.enabled=state[@"output_size"]!=nil;
    if(state && !state[@"output_size"]) { [self report:@"Update the camera extension to enable the new resolution controls. Close capture windows before updating."];return; }
    [self report:state?@"Ready":@"Set up the camera in Help → Driver Setup."];
}
- (void)apply:(id)sender {
    NSDictionary *d=@{@"standard":self.standard.titleOfSelectedItem,@"video_input":self.video.titleOfSelectedItem,
        @"audio_input":self.audio.titleOfSelectedItem,@"dropout":self.dropout.titleOfSelectedItem,
        @"output_size":resolutionValues()[MAX(0,self.resolution.indexOfSelectedItem)]};
    NSDictionary *state=readSettings();
    if(!state[@"output_size"]) { [self report:@"Update the camera extension before applying resolution settings."];return; }
    if([state[@"capturing"] boolValue]) { [self report:@"Camera is in use. Close all movie recording and camera windows, then apply again."];return; }
    OSStatus rc=writeSettings(d);
    if(rc) { [self report:[NSString stringWithFormat:@"Could not apply settings (%d). Close all camera windows and check that this extension is active.",(int)rc]];return; }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,700*NSEC_PER_MSEC),dispatch_get_main_queue(),^{ [self refresh:nil];[self report:@"Settings applied. Reopen your camera app to use the selected standard and inputs."]; });
}
- (void)report:(NSString *)message { self.status.stringValue=message;fprintf(stdout,"%s\n",message.UTF8String);fflush(stdout); }
- (void)activate:(id)sender {
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
    if(self.commandLine) exit(0);else dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{[self refresh:nil];});
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
