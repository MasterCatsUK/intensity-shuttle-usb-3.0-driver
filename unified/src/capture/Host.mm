// GPL-2.0-or-later. Native capture controls and camera activation.
#import <AppKit/AppKit.h>
#import <AVFoundation/AVFoundation.h>
#import <SystemExtensions/SystemExtensions.h>
#import <CoreMediaIO/CoreMediaIO.h>
#include <vector>
#include "Settings.hpp"
#include "RecordingCodec.hpp"
static NSArray<NSString *> *resolutionValues() { return @[@"Native",@"Square pixels",@"1280x960",@"1440x1080",@"1280x720",@"1920x1080",@"Native interlaced",@"1920x1080 interlaced"]; }
static NSArray<NSString *> *resolutionTitles(BOOL ntsc,BOOL wide=NO) {
    return @[ntsc?@"Native — 720 × 480":@"Native — 720 × 576",
             wide?(ntsc?@"Square pixels — 854 × 480":@"Square pixels — 1024 × 576"):(ntsc?@"Square pixels — 640 × 480":@"Square pixels — 768 × 576"),@"1280 × 960",@"1440 × 1080",@"720p — 1280 × 720",@"1080p — 1920 × 1080",ntsc?@"480i59.94 — 720 × 480":@"576i50 — 720 × 576",ntsc?@"1080i59.94 — 1920 × 1080":@"1080i50 — 1920 × 1080"];
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
@property(strong) NSPopUpButton *standard,*video,*audio,*dropout,*resolution,*aspect,*fieldOrder;
@property NSView *pictureView;
@property NSPopUpButton *recordingCodec;
- (void)recordingCodecChanged:(id)sender;
@property NSSlider *brightness,*contrast,*colour,*sharpness;
@property NSArray<NSTextField*> *pictureValues;
@property NSTextField *pictureStatus;
@property NSButton *pictureApply,*pictureReset,*enablePicture,*livePicture;
@property NSTimer *pictureTimer,*settingsRetry;
@property NSUInteger settingsRetryCount;
@property BOOL captureDraft,applyingSettings;
@property(copy) void (^pauseOwnPreview)(void);
@property(copy) void (^settingsApplied)(NSDictionary*);
@property(copy) void (^settingsFinished)(void);
@property(copy) void (^formatSelectionChanged)(double);
@property(copy) void (^recordingStateChanged)(void);
@property NSTask *recorderTask;
@property NSPipe *recorderInput;
@property NSButton *recordButton,*stopRecordButton;
@property NSTextField *recordStatus;
@property NSString *recordingPath;
@property(copy) void (^recordingFinished)(void);
@property BOOL stoppingRecording;
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
    self.resolution=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(350,388,260,30)];[self.resolution addItemsWithTitles:resolutionTitles(NO)];self.resolution.target=self;self.resolution.action=@selector(selectionChanged:);[v addSubview:self.resolution];
    [self label:@"Input aspect" rect:NSMakeRect(350,357,104,22) font:13];
    self.aspect=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(448,353,162,30)];[self.aspect addItemsWithTitles:@[@"4:3",@"Anamorphic 16:9"]];self.aspect.target=self;self.aspect.action=@selector(selectionChanged:);self.aspect.accessibilityLabel=@"Input aspect";[v addSubview:self.aspect];
    [self label:@"On signal loss" rect:NSMakeRect(350,320,260,20) font:13];
    self.dropout=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(350,283,260,30)];[self.dropout addItemsWithTitles:@[@"Hold last frame",@"Black"]];self.dropout.target=self;self.dropout.action=@selector(selectionChanged:);[v addSubview:self.dropout];
    self.formatLabel=[self label:@"" rect:NSMakeRect(350,232,260,44) font:12];self.formatLabel.textColor=NSColor.secondaryLabelColor;
    self.fieldOrder=field(@"Field order",@[@"Top first",@"Bottom first"],34,266);self.fieldOrder.accessibilityLabel=@"Capture field order";
    self.inputLabel=[self label:@"" rect:NSMakeRect(34,232,270,24) font:12];
    [self label:@"Recording codec" rect:NSMakeRect(24,194,146,22) font:13];
    self.recordingCodec=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(174,190,452,30)];
    for(unsigned i=0;i<shuttle_recording::CodecCount;i++)[self.recordingCodec addItemWithTitle:@(shuttle_recording::Codecs[i].title)];self.recordingCodec.autoenablesItems=NO;self.recordingCodec.target=self;self.recordingCodec.action=@selector(recordingCodecChanged:);self.recordingCodec.accessibilityLabel=@"Recording codec";self.recordingCodec.toolTip=@"Used by the Record button in this app. QuickTime and other apps choose their own recording codec.";
    shuttle_recording::Codec savedCodec=shuttle_recording::Codec::ProRes422;shuttle_recording::parse([NSUserDefaults.standardUserDefaults stringForKey:@"RecordingCodec"].UTF8String,savedCodec);[self.recordingCodec selectItemAtIndex:unsigned(savedCodec)];[v addSubview:self.recordingCodec];
    auto* apply=[NSButton buttonWithTitle:@"Apply" target:self action:@selector(apply:)];apply.frame=NSMakeRect(18,151,140,34);[v addSubview:apply];
    auto* refresh=[NSButton buttonWithTitle:@"Refresh" target:self action:@selector(refresh:)];refresh.frame=NSMakeRect(168,151,110,34);[v addSubview:refresh];
    auto* hint=[self label:@"Apply reconnects the preview. Stop recording before changing format." rect:NSMakeRect(24,117,602,24) font:12];hint.textColor=NSColor.secondaryLabelColor;
    self.status=[self label:@"" rect:NSMakeRect(24,45,602,52) font:12];
    self.recordButton=[NSButton buttonWithTitle:@"Record…" target:self action:@selector(startRecording:)];self.recordButton.frame=NSMakeRect(350,151,126,34);[v addSubview:self.recordButton];
    self.stopRecordButton=[NSButton buttonWithTitle:@"Stop" target:self action:@selector(stopRecording:)];self.stopRecordButton.frame=NSMakeRect(490,151,120,34);self.stopRecordButton.enabled=NO;[v addSubview:self.stopRecordButton];
    self.recordStatus=[self label:@"ProRes 422 + stereo audio. Interlaced modes preserve both fields." rect:NSMakeRect(24,102,602,40) font:12];self.recordStatus.textColor=NSColor.secondaryLabelColor;

    self.pictureView=[[SettingsCanvas alloc] initWithFrame:NSMakeRect(0,0,650,500)];
    NSMutableArray *values=[NSMutableArray array];NSArray *titles=@[@"Brightness",@"Contrast",@"Colour",@"Sharpness"];
    for(unsigned n=0;n<4;++n){CGFloat y=224-n*34;
        auto title=[NSTextField labelWithString:titles[n]];title.frame=NSMakeRect(26,y+3,112,22);[self.pictureView addSubview:title];
        auto slider=[NSSlider sliderWithValue:n==1||n==2?100:0 minValue:n==0?-100:0 maxValue:n==0||n==3?100:200 target:self action:@selector(pictureChanged:)];slider.frame=NSMakeRect(144,y,388,26);slider.accessibilityLabel=titles[n];[self.pictureView addSubview:slider];
        auto value=[NSTextField labelWithString:@""];value.frame=NSMakeRect(542,y+3,66,22);value.alignment=NSTextAlignmentRight;[self.pictureView addSubview:value];[values addObject:value];
        if(n==0)self.brightness=slider;if(n==1)self.contrast=slider;if(n==2)self.colour=slider;if(n==3)self.sharpness=slider;
    }
    self.pictureValues=values;
    self.recordButton.frame=NSMakeRect(18,66,126,32);[self.recordButton removeFromSuperview];[self.pictureView addSubview:self.recordButton];
    self.stopRecordButton.frame=NSMakeRect(154,66,96,32);[self.stopRecordButton removeFromSuperview];[self.pictureView addSubview:self.stopRecordButton];
    self.recordStatus.frame=NSMakeRect(24,14,602,40);[self.recordStatus removeFromSuperview];[self.pictureView addSubview:self.recordStatus];
    self.recordStatus.stringValue=@"ProRes 422 · stereo audio · interlaced fields preserved";
    self.recordButton.toolTip=@"Records the selected codec and applied input format. Uncompressed files are very large; choose a fast drive with sufficient free space.";
    self.pictureReset=[NSButton buttonWithTitle:@"Reset picture" target:self action:@selector(resetPicture:)];self.pictureReset.frame=NSMakeRect(270,66,140,32);[self.pictureView addSubview:self.pictureReset];
    self.livePicture=[NSButton checkboxWithTitle:@"Live adjustments" target:self action:@selector(livePictureChanged:)];self.livePicture.frame=NSMakeRect(434,66,192,32);self.livePicture.state=[NSUserDefaults.standardUserDefaults objectForKey:@"LivePictureControls"]?([NSUserDefaults.standardUserDefaults boolForKey:@"LivePictureControls"]?NSControlStateValueOn:NSControlStateValueOff):NSControlStateValueOn;[self.pictureView addSubview:self.livePicture];
    self.pictureApply=[NSButton buttonWithTitle:@"Apply picture" target:self action:@selector(applyPicture:)];self.pictureApply.frame=NSMakeRect(270,14,140,32);self.pictureApply.hidden=YES;[self.pictureView addSubview:self.pictureApply];
    self.enablePicture=[NSButton buttonWithTitle:@"Enable picture controls…" target:self action:@selector(activate:)];self.enablePicture.frame=NSMakeRect(370,14,256,32);self.enablePicture.hidden=YES;[self.pictureView addSubview:self.enablePicture];
    self.livePicture.enabled=NO;self.pictureApply.enabled=self.pictureReset.enabled=NO;for(NSSlider *slider in @[self.brightness,self.contrast,self.colour,self.sharpness])slider.enabled=NO;
    self.pictureStatus=[NSTextField wrappingLabelWithString:@""];self.pictureStatus.frame=NSMakeRect(24,10,602,44);self.pictureStatus.hidden=YES;[self.pictureView addSubview:self.pictureStatus];
    [self recordingCodecChanged:nil];
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

- (void)startRecording:(id)sender {
    if(self.recorderTask)return;
    if(self.applyingSettings){self.recordStatus.stringValue=@"Wait for capture settings to finish applying.";return;}
    shuttle_recording::Codec selectedCodec=shuttle_recording::Codec(MAX(0,self.recordingCodec.indexOfSelectedItem));
    if(!shuttle_recording::compatible(selectedCodec,self.resolution.indexOfSelectedItem>=6)){self.recordStatus.stringValue=@"Choose an interlaced-compatible codec or a progressive capture format.";return;}
    AVAuthorizationStatus cameraAccess=[AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if(cameraAccess==AVAuthorizationStatusNotDetermined){self.recordButton.enabled=NO;self.recordStatus.stringValue=@"Allow Camera access to record the Shuttle input.";__weak Host *weakSelf=self;[AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted){dispatch_async(dispatch_get_main_queue(),^{Host *host=weakSelf;if(!host)return;host.recordButton.enabled=YES;if(granted)[host startRecording:nil];else host.recordStatus.stringValue=@"Allow Shuttle Camera in System Settings → Privacy & Security → Camera.";});}];return;}
    AVAuthorizationStatus audioAccess=[AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];
    if(audioAccess==AVAuthorizationStatusNotDetermined){self.recordButton.enabled=NO;self.recordStatus.stringValue=@"Allow Microphone access to record Shuttle stereo audio.";__weak Host *weakSelf=self;[AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL granted){dispatch_async(dispatch_get_main_queue(),^{Host *host=weakSelf;if(!host)return;host.recordButton.enabled=YES;if(granted)[host startRecording:nil];else host.recordStatus.stringValue=@"Allow Shuttle Camera in System Settings → Privacy & Security → Microphone.";});}];return;}
    if(audioAccess!=AVAuthorizationStatusAuthorized){self.recordStatus.stringValue=@"Allow Shuttle Camera in System Settings → Privacy & Security → Microphone.";return;}
    if([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo]!=AVAuthorizationStatusAuthorized){self.recordStatus.stringValue=@"Allow Camera access before recording.";return;}
    if(self.captureDraft){self.recordStatus.stringValue=@"Click Apply to save your capture settings before recording.";return;}
    if(!cameraID()){self.recordStatus.stringValue=@"Enable the Shuttle camera first.";return;}
    NSSavePanel *panel=[NSSavePanel savePanel];panel.allowedFileTypes=@[@"mov"];panel.canCreateDirectories=YES;panel.nameFieldStringValue=[NSString stringWithFormat:@"Shuttle %@.mov",[NSDateFormatter localizedStringFromDate:NSDate.date dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterMediumStyle]];panel.message=[NSString stringWithFormat:@"Record %@ with stereo audio in a QuickTime movie.",@(shuttle_recording::info(selectedCodec).title)];
    // Avoid locale-specific slashes in the suggested filename.
    NSDateFormatter *stamp=[NSDateFormatter new];stamp.dateFormat=@"yyyy-MM-dd HH.mm.ss";panel.nameFieldStringValue=[NSString stringWithFormat:@"Shuttle %@.mov",[stamp stringFromDate:NSDate.date]];
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response){
        if(response!=NSModalResponseOK)return;
        if([NSFileManager.defaultManager fileExistsAtPath:panel.URL.path]){self.recordStatus.stringValue=@"Choose a new filename. The existing recording has been kept.";return;}
        NSString *helper=[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Contents/MacOS/ShuttleRecorder"];
        if(![NSFileManager.defaultManager isExecutableFileAtPath:helper]){self.recordStatus.stringValue=@"Recording helper is missing. Reinstall this app.";return;}
        NSTask *task=[NSTask new];self.recorderTask=task;if(self.recordingStateChanged)self.recordingStateChanged();self.recordingPath=panel.URL.path;self.stoppingRecording=NO;
        task.executableURL=[NSURL fileURLWithPath:helper];task.arguments=@[panel.URL.path,@"--codec",@(shuttle_recording::info(selectedCodec).key)];self.recordingCodec.enabled=NO;self.recorderInput=[NSPipe pipe];task.standardInput=self.recorderInput;
        NSPipe *messages=[NSPipe pipe];task.standardOutput=messages;task.standardError=messages;
        self.recordButton.enabled=NO;self.stopRecordButton.enabled=YES;self.recordStatus.stringValue=@"Starting recording…";
        __weak Host *weakSelf=self;
        messages.fileHandleForReading.readabilityHandler=^(NSFileHandle *handle){NSData *data=handle.availableData;if(!data.length){handle.readabilityHandler=nil;return;}NSString *text=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];if(!text)return;dispatch_async(dispatch_get_main_queue(),^{Host *host=weakSelf;if(host.recorderTask!=task)return;if([text containsString:@"ERROR "]){host.recordStatus.stringValue=[text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];}else if([text containsString:@"RECORDING "]&&!host.stoppingRecording){host.recordStatus.stringValue=[NSString stringWithFormat:@"Recording — %@",host.recordingPath.lastPathComponent];}});};
        task.terminationHandler=^(NSTask *finished){dispatch_async(dispatch_get_main_queue(),^{Host *host=weakSelf;if(!host||host.recorderTask!=finished)return;host.recorderTask=nil;host.recordingCodec.enabled=YES;if(host.recordingStateChanged)host.recordingStateChanged();host.recorderInput=nil;host.stoppingRecording=NO;host.recordButton.enabled=YES;host.stopRecordButton.enabled=NO;if(finished.terminationStatus==0){host.recordStatus.stringValue=[NSString stringWithFormat:@"Saved — %@",host.recordingPath.lastPathComponent];if(!host.recordingFinished)[host openSavedRecording:host.recordingPath];}else if(![host.recordStatus.stringValue containsString:@"ERROR "])host.recordStatus.stringValue=@"Recording stopped with an error. Check the partial file before using it.";if(host.recordingFinished){void (^done)(void)=host.recordingFinished;host.recordingFinished=nil;done();}});};
        NSError *error=nil;if(![task launchAndReturnError:&error]){messages.fileHandleForReading.readabilityHandler=nil;self.recorderTask=nil;self.recordingCodec.enabled=YES;if(self.recordingStateChanged)self.recordingStateChanged();self.recorderInput=nil;self.recordButton.enabled=YES;self.stopRecordButton.enabled=NO;self.recordStatus.stringValue=error.localizedDescription;}
    }];
}
- (void)openSavedRecording:(NSString*)path {
    NSDictionary *attributes=[NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];if(![attributes[NSFileType] isEqual:NSFileTypeRegular]||![attributes[NSFileSize] unsignedLongLongValue])return;
    if(![NSWorkspace.sharedWorkspace openURL:[NSURL fileURLWithPath:path]])self.recordStatus.stringValue=@"Saved. No player could open the movie; open it from Finder.";
}
- (void)stopRecording:(id)sender {
    if(!self.recorderTask||self.stoppingRecording)return;self.stoppingRecording=YES;self.stopRecordButton.enabled=NO;self.recordStatus.stringValue=@"Saving recording…";
    @try{[self.recorderInput.fileHandleForWriting writeData:[@"stop\n" dataUsingEncoding:NSUTF8StringEncoding]];[self.recorderInput.fileHandleForWriting closeFile];}@catch(NSException *exception){[self.recorderTask interrupt];}
}

- (void)refreshRecordingCodecs {
    if(!self.recordingCodec)return;BOOL interlaced=self.resolution.indexOfSelectedItem>=6;
    for(unsigned i=0;i<shuttle_recording::CodecCount;i++)[self.recordingCodec itemAtIndex:i].enabled=shuttle_recording::compatible(shuttle_recording::Codec(i),interlaced);
    auto codec=shuttle_recording::Codec(MAX(0,self.recordingCodec.indexOfSelectedItem));BOOL compatible=shuttle_recording::compatible(codec,interlaced);
    if(!self.recorderTask){self.recordButton.enabled=compatible;self.recordStatus.stringValue=compatible?[NSString stringWithFormat:@"%@ · stereo audio%@",@(shuttle_recording::info(codec).title),interlaced?@" · interlaced fields preserved":@""]:@"Choose an interlaced-compatible codec, or select progressive capture.";}
}
- (void)recordingCodecChanged:(id)sender {
    if(self.recorderTask)return;auto codec=shuttle_recording::Codec(MAX(0,self.recordingCodec.indexOfSelectedItem));if(sender)[NSUserDefaults.standardUserDefaults setObject:@(shuttle_recording::info(codec).key) forKey:@"RecordingCodec"];[self refreshRecordingCodecs];
}
- (void)selectionChanged:(id)sender {
    if(sender)self.captureDraft=YES;
    NSInteger index=MAX(0,self.resolution.indexOfSelectedItem);BOOL ntsc=[self.standard.titleOfSelectedItem isEqual:@"NTSC"];
    [self.resolution removeAllItems];[self.resolution addItemsWithTitles:resolutionTitles(ntsc,self.aspect.indexOfSelectedItem==1)];[self.resolution selectItemAtIndex:index];
    shuttle::CaptureSettings settings;settings.profile.ntsc=ntsc;settings.outputSize=static_cast<shuttle::OutputSize>(index);settings.widescreen=self.aspect.indexOfSelectedItem==1;
    if(self.formatSelectionChanged)self.formatSelectionChanged(settings.native()?(settings.widescreen?16./9:4./3):double(settings.outputWidth())/settings.outputHeight());
    self.fieldOrder.enabled=settings.interlaced()&&!self.applyingSettings;[self refreshRecordingCodecs];
    self.formatLabel.stringValue=[NSString stringWithFormat:@"%u × %u · %@ · %@",
        settings.outputWidth(),settings.outputHeight(),settings.interlaced()?(ntsc?@"29.97 fps / 59.94i":@"25 fps / 50i"):(ntsc?@"59.94p":@"50p"),settings.native()?(settings.widescreen?@"16:9 non-square":@"4:3 non-square"):((index==4||index==5||index==7)&&!settings.widescreen?@"4:3 + side bars":settings.widescreen?@"16:9":@"4:3")];
}
- (void)refreshPictureCapabilities {
    NSDictionary *state=readSettings();if(!state)return; // a transient reconnect is not evidence of an old driver
    BOOL wasLive=self.livePicture.enabled,pictureReady=state[@"brightness"]!=nil,liveReady=[state[@"picture_live"] boolValue];
    self.livePicture.enabled=liveReady;self.pictureApply.hidden=liveReady&&self.livePicture.state==NSControlStateValueOn;
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
    [self.fieldOrder selectItemWithTitle:d[@"field_order"]?:@"Top first"];
    [self.aspect selectItemAtIndex:[d[@"input_aspect"] isEqual:@"16:9"]?1:0];
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
    self.livePicture.enabled=liveReady;self.pictureApply.hidden=liveReady&&self.livePicture.state==NSControlStateValueOn;
    for(NSSlider *slider in @[self.brightness,self.contrast,self.colour,self.sharpness])slider.enabled=pictureReady;
    self.pictureApply.enabled=self.pictureReset.enabled=pictureReady;self.enablePicture.hidden=liveReady;
    if(!liveReady)self.pictureStatus.stringValue=state?@"Live adjustments need the updated camera driver. Close camera previews, then click Enable picture controls… and approve if asked.":@"Camera unavailable. Click Enable picture controls… to set it up.";
    if(state && !state[@"output_size"]) { [self report:@"Update the camera extension to enable the new resolution controls. Close capture windows before updating."];return; }
    [self report:state?@"Ready":@"Set up the camera in Help → Driver Setup."];
    if(!liveReady)self.pictureStatus.stringValue=state?@"Live adjustments need the updated camera driver. Close camera previews, then click Enable picture controls… and approve if asked.":@"Camera unavailable. Click Enable picture controls… to set it up.";
}
- (void)setApplyingCapture:(BOOL)value {self.applyingSettings=value;for(NSPopUpButton *field in @[self.standard,self.video,self.audio,self.dropout,self.resolution,self.aspect,self.fieldOrder])field.enabled=!value;if(!value)[self selectionChanged:nil];}
- (void)apply:(id)sender {
    if(self.applyingSettings)return;
    if(self.recorderTask){[self report:@"Stop recording before changing the capture format. Your recording continues unchanged."];return;}
    NSDictionary *d=@{@"standard":self.standard.titleOfSelectedItem,@"video_input":self.video.titleOfSelectedItem,
        @"audio_input":self.audio.titleOfSelectedItem,@"dropout":self.dropout.titleOfSelectedItem,
        @"output_size":resolutionValues()[MAX(0,self.resolution.indexOfSelectedItem)],@"input_aspect":self.aspect.indexOfSelectedItem==1?@"16:9":@"4:3",@"field_order":self.fieldOrder.titleOfSelectedItem,
        @"brightness":@(self.brightness.integerValue),@"contrast":@(self.contrast.integerValue),@"colour":@(self.colour.integerValue),@"sharpness":@(self.sharpness.integerValue)};
    NSDictionary *state=readSettings();
    if(!state[@"output_size"]) { [self report:@"Update the camera extension before applying resolution settings."];return; }
    if(self.resolution.indexOfSelectedItem>=6&&![state[@"capture_interlace"] boolValue]){[self report:@"Enable the updated camera extension in Help → Driver Setup for interlaced capture."];return;}
    if(![state[@"capture_aspect"] boolValue]) { [self report:@"Enable the updated camera extension in Help → Driver Setup to apply aspect and HD capture sizes."];return; }
    if(!state[@"brightness"]) { [self report:@"Enable the updated camera extension in Help → Driver Setup first."];return; }
    [self setApplyingCapture:YES];if(self.pauseOwnPreview)self.pauseOwnPreview();
    [self report:@"Applying settings…"];[self applyConfiguration:d attempt:0];
}
- (void)applyConfiguration:(NSDictionary*)d attempt:(unsigned)attempt {
    NSDictionary *state=readSettings();
    if(!state||[state[@"capturing"] boolValue]){
        if(attempt<15){dispatch_after(dispatch_time(DISPATCH_TIME_NOW,150*NSEC_PER_MSEC),dispatch_get_main_queue(),^{[self applyConfiguration:d attempt:attempt+1];});return;}
        [self setApplyingCapture:NO];[self report:state?@"Close other camera previews, then click Apply. No app restart is needed.":@"Camera unavailable. Click Refresh and try again."];if(self.settingsFinished)self.settingsFinished();return;
    }
    OSStatus rc=writeSettings(d);
    if(rc){[self setApplyingCapture:NO];[self report:[NSString stringWithFormat:@"Could not apply settings (%d). Close other camera previews and try again.",(int)rc]];if(self.settingsFinished)self.settingsFinished();return;}
    self.captureDraft=NO;[NSUserDefaults.standardUserDefaults setObject:d forKey:@"LastKnownCaptureSettings"];
    if(self.settingsApplied)self.settingsApplied(d);
    // The camera publishes a replacement CMIO device when the raster changes.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,700*NSEC_PER_MSEC),dispatch_get_main_queue(),^{[self setApplyingCapture:NO];[self refresh:nil];if(!self.settingsRetry)[self report:@"Settings applied."];if(self.settingsFinished)self.settingsFinished();});
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
- (void)livePictureChanged:(id)sender { self.pictureApply.hidden=self.livePicture.state==NSControlStateValueOn;
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
    if(self.recorderTask||[readSettings()[@"capturing"] boolValue]){[self report:@"Stop recording and close camera previews before disabling the camera driver."];return;}
    auto *request=[OSSystemExtensionRequest deactivationRequestForExtension:ExtensionID queue:dispatch_get_main_queue()];request.delegate=self;
    [OSSystemExtensionManager.sharedManager submitRequest:request];
}
- (OSSystemExtensionReplacementAction)request:(OSSystemExtensionRequest *)request actionForReplacingExtension:(OSSystemExtensionProperties *)old withExtension:(OSSystemExtensionProperties *)ext { return OSSystemExtensionReplacementActionReplace; }
- (void)requestNeedsUserApproval:(OSSystemExtensionRequest *)request { [self report:@"Enable Shuttle Camera Extension in System Settings → General → Login Items & Extensions → Camera Extensions."]; }
- (void)request:(OSSystemExtensionRequest *)request didFinishWithResult:(OSSystemExtensionRequestResult)result {
    [self report:result==OSSystemExtensionRequestWillCompleteAfterReboot?@"macOS accepted the request; restart to finish.":@"macOS completed the request. Click Refresh to update the camera status."];
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
