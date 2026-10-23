// GPL-2.0-or-later. One host app for capture, playback and extension activation.
#define main ShuttleCaptureHostMain
#include "capture/Host.mm"
#undef main
#include "capture/Preview.mm"
#include "capture/AudioMonitor.mm"
#define main ShuttleOutputHostMain
#include "output/OutputHost.mm"
#undef main
#include "IdleHost.mm"
#include "StartupOutput.mm"
@interface NavigationButton : NSControl
@property(copy) NSString* title;
@property(nonatomic) BOOL selected;
@end
@implementation NavigationButton
- (BOOL)isOpaque{return NO;}
- (BOOL)isAccessibilityElement{return YES;}
- (void)drawRect:(NSRect)dirty {
    [(self.selected?NSColor.controlAccentColor:NSColor.controlBackgroundColor) setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds,1,1) xRadius:7 yRadius:7] fill];
    NSMutableParagraphStyle* paragraph=[NSMutableParagraphStyle new];paragraph.alignment=NSTextAlignmentCenter;
    NSDictionary* style=@{NSFontAttributeName:self.selected?[NSFont boldSystemFontOfSize:14]:[NSFont systemFontOfSize:14],NSForegroundColorAttributeName:self.selected?NSColor.whiteColor:NSColor.labelColor,NSParagraphStyleAttributeName:paragraph};
    [self.title drawInRect:NSMakeRect(3,(self.bounds.size.height-19)/2,self.bounds.size.width-6,19) withAttributes:style];
}
- (BOOL)acceptsFirstResponder{return YES;}
- (void)mouseDown:(NSEvent*)event{[self.window makeFirstResponder:self];[self sendAction:self.action to:self.target];}
- (void)keyDown:(NSEvent*)event{NSString* key=event.charactersIgnoringModifiers;if([key isEqual:@" "]||[key isEqual:@"\r"])[self sendAction:self.action to:self.target];else [super keyDown:event];}
- (void)setSelected:(BOOL)value{_selected=value;self.needsDisplay=YES;}
- (NSString*)accessibilityRole{return NSAccessibilityButtonRole;}
- (NSString*)accessibilityLabel{return self.title;}
- (BOOL)accessibilityPerformPress{[self sendAction:self.action to:self.target];return YES;}
@end
@interface CombinedHost : NSObject <NSApplicationDelegate,NSWindowDelegate>
@property Host* capture;
@property BOOL allowStartupMovie;
@property ShuttleStartupOutput* startup;
@property CapturePreview *preview;
@property CaptureAudioMonitor *monitor;
@property BOOL resumePreviewAfterApply;
@property NSButton *previewButton;
@property BOOL previewAllowed;
@property IdleHost* idle;
@property OutputHost* output;
@property NSWindow* window;
@property NSTabView* tabs;
@property NavigationButton* captureButton;
@property NavigationButton* outputButton;
@property NavigationButton* pictureButton;
@property NavigationButton* idleButton;
@property NSInteger renderTab;
@property NSString* renderPath;
@property BOOL renderOutput;
@property NSWindow* diagnosticsWindow;
@property NSView* outputSettingsView;
@property NSScrollView* outputScroll;
@end
@implementation CombinedHost
- (void)applicationDidFinishLaunching:(NSNotification*)note {
    self.capture=[Host new];self.capture.embedded=YES;[self.capture applicationDidFinishLaunching:note];
    self.output=[OutputHost new];self.output.embedded=YES;[self.output applicationDidFinishLaunching:note];
    NSView* captureView=self.capture.window.contentView;NSView* outputView=self.output.window.contentView;
    self.window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,690,590) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable backing:NSBackingStoreBuffered defer:NO];
    self.window.title=@"Shuttle Video";self.window.delegate=self;
    self.window.contentView=[[SettingsCanvas alloc] initWithFrame:NSMakeRect(0,0,690,590)];
    self.tabs=[[NSTabView alloc] initWithFrame:NSMakeRect(12,12,666,516)];self.tabs.tabViewType=NSNoTabsNoBorder;
    self.captureButton=[[NavigationButton alloc] initWithFrame:NSMakeRect(198,542,138,30)];self.captureButton.title=@"Input Settings";self.captureButton.target=self;self.captureButton.action=@selector(showCapture:);
    self.outputButton=[[NavigationButton alloc] initWithFrame:NSMakeRect(348,542,138,30)];self.outputButton.title=@"Output Settings";self.outputButton.target=self;self.outputButton.action=@selector(showOutput:);
    self.pictureButton=[[NavigationButton alloc] initWithFrame:NSMakeRect(48,542,138,30)];self.pictureButton.title=@"Capture";self.pictureButton.target=self;self.pictureButton.action=@selector(showPicture:);
    self.idleButton=[[NavigationButton alloc] initWithFrame:NSMakeRect(498,542,138,30)];self.idleButton.title=@"Idle Settings";self.idleButton.target=self;self.idleButton.action=@selector(showIdle:);
    self.idle=[IdleHost new];self.idle.window=self.window;
    auto* captureTab=[[NSTabViewItem alloc] initWithIdentifier:@"capture"];captureTab.label=@"Capture";
    auto* outputTab=[[NSTabViewItem alloc] initWithIdentifier:@"output"];outputTab.label=@"Video Output";
    auto* captureContainer=[[SettingsCanvas alloc] initWithFrame:NSMakeRect(0,0,650,500)];
    auto* outputContainer=[[SettingsCanvas alloc] initWithFrame:NSMakeRect(0,0,650,500)];
    [captureView removeFromSuperview];[outputView removeFromSuperview];
    captureView.frame=NSMakeRect(8,8,650,500);outputView.frame=NSMakeRect(0,0,650,720);self.outputSettingsView=outputView;
    captureView.autoresizingMask=NSViewMinYMargin;outputView.autoresizingMask=NSViewNotSizable;
    [captureContainer addSubview:captureView];self.outputScroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(8,8,650,640)];self.outputScroll.hasVerticalScroller=YES;self.outputScroll.autohidesScrollers=YES;self.outputScroll.documentView=outputView;[outputContainer addSubview:self.outputScroll];captureTab.view=captureContainer;outputTab.view=outputContainer;
    [self.window.contentView addSubview:self.tabs];
    auto pictureTab=[[NSTabViewItem alloc] initWithIdentifier:@"picture"];pictureTab.label=@"Picture";pictureTab.view=self.capture.pictureView;
    auto idleTab=[[NSTabViewItem alloc] initWithIdentifier:@"idle"];idleTab.label=@"Idle Screen";idleTab.view=self.idle.view;
    [self.tabs addTabViewItem:pictureTab];[self.tabs addTabViewItem:captureTab];[self.tabs addTabViewItem:outputTab];[self.tabs addTabViewItem:idleTab];
    self.preview=[CapturePreview new];[self.capture.pictureView addSubview:self.preview.view];[self.capture.pictureView addSubview:self.preview.message];
    self.previewButton=[NSButton buttonWithTitle:@"Show input" target:self action:@selector(togglePreview:)];self.previewButton.frame=NSMakeRect(498,254,126,28);[self.capture.pictureView addSubview:self.previewButton];
    self.monitor=[CaptureAudioMonitor new];self.preview.metersView=self.monitor.meters;for(NSView *control in @[self.monitor.meters,self.monitor.listen,self.monitor.volume,self.monitor.status])[self.capture.pictureView addSubview:control];
    __weak CombinedHost *weakSelf=self;
    self.capture.pauseOwnPreview=^{CombinedHost *host=weakSelf;host.resumePreviewAfterApply=host.preview.wantsPreview;[host.preview stop];[host.monitor stop];};
    self.capture.settingsApplied=^(NSDictionary *d){CombinedHost *host=weakSelf;[host.capture loadCaptureFields:d];};
    self.capture.settingsFinished=^{CombinedHost *host=weakSelf;if(host.resumePreviewAfterApply&&[host.tabs.selectedTabViewItem.identifier isEqual:@"picture"]){[host.preview start];[host.monitor start];}host.resumePreviewAfterApply=NO;};
    self.capture.formatSelectionChanged=^(double aspect){[weakSelf.preview setPreviewAspect:aspect];};
    self.capture.recordingStateChanged=^{[weakSelf updateMonitor];};
    NSButton *enableDriver=[NSButton buttonWithTitle:@"Enable camera" target:self.capture action:@selector(activate:)];enableDriver.frame=NSMakeRect(350,151,126,34);[captureView addSubview:enableDriver];
    NSButton *disableDriver=[NSButton buttonWithTitle:@"Disable camera" target:self action:@selector(disableCamera:)];disableDriver.frame=NSMakeRect(482,151,144,34);[captureView addSubview:disableDriver];
    [self.capture selectionChanged:nil];
    [self.window.contentView addSubview:self.pictureButton];[self.window.contentView addSubview:self.idleButton];
    [self.window.contentView addSubview:self.captureButton];[self.window.contentView addSubview:self.outputButton];
    // All handlers present sheets and activation messages in this one window.
    self.capture.window=self.window;self.output.window=self.window;
    [self buildMenu];
    if(self.renderTab==2)[self showPicture:nil];else if(self.renderTab==3)[self showIdle:nil];else if(self.renderTab==1)[self showCapture:nil];else if(self.renderOutput)[self showOutput:nil];else [self showPicture:nil];
    [self.window center];[self.window makeKeyAndOrderFront:nil];
    if(self.renderPath){dispatch_after(dispatch_time(DISPATCH_TIME_NOW,300*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        NSView* v=self.window.contentView;[v layoutSubtreeIfNeeded];auto* rep=[v bitmapImageRepForCachingDisplayInRect:v.bounds];[v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];
        BOOL ok=[[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:self.renderPath atomically:YES];exit(ok?0:1);
    });}else [NSApp activateIgnoringOtherApps:YES];
    if(self.allowStartupMovie&&!self.renderPath&&(![NSUserDefaults.standardUserDefaults objectForKey:@"PlayStartupMovie"]||[NSUserDefaults.standardUserDefaults boolForKey:@"PlayStartupMovie"])){
        self.startup=[ShuttleStartupOutput new];((ShuttleApplication*)NSApp).startupOutput=self.startup;
        self.startup.message=^(NSString* text){CombinedHost* host=weakSelf;[host.output.log.textStorage appendAttributedString:[[NSAttributedString alloc] initWithString:text]];};
        NSURL* movie=[NSBundle.mainBundle URLForResource:@"Startup" withExtension:@"m4v"];
        NSURL* helper=[NSBundle.mainBundle.executableURL.URLByDeletingLastPathComponent URLByAppendingPathComponent:@"ShuttlePlayback"];
        NSString* mode=@[@"576i50",@"1080i50",@"1080p25",@"480i5994",@"1080i5994",@"1080p2997"][self.output.mode.indexOfSelectedItem];
        [self.startup startMovie:movie helper:helper mode:mode];
    }
}
- (void)buildMenu {
    NSMenu* main=[NSMenu new];
    NSMenuItem* application=[NSMenuItem new];application.title=@"Shuttle Video";[main addItem:application];NSMenu* appMenu=[[NSMenu alloc] initWithTitle:@"Shuttle Video"];application.submenu=appMenu;
    NSMenuItem* about=[appMenu addItemWithTitle:@"About Shuttle Video" action:@selector(showAbout:) keyEquivalent:@""];about.target=self;
    [appMenu addItem:NSMenuItem.separatorItem];
    [appMenu addItemWithTitle:@"Hide Shuttle Video" action:@selector(hide:) keyEquivalent:@"h"];
    [appMenu addItemWithTitle:@"Show All" action:@selector(unhideAllApplications:) keyEquivalent:@""];
    [appMenu addItem:NSMenuItem.separatorItem];
    NSMenuItem* quit=[appMenu addItemWithTitle:@"Quit Shuttle Video" action:@selector(terminate:) keyEquivalent:@"q"];quit.target=NSApp;
    NSMenuItem* edit=[NSMenuItem new];edit.title=@"Edit";[main addItem:edit];edit.submenu=[[NSMenu alloc] initWithTitle:@"Edit"];
    [edit.submenu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
    [edit.submenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [edit.submenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    [edit.submenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    NSMenuItem* help=[NSMenuItem new];help.title=@"Help";[main addItem:help];help.submenu=[[NSMenu alloc] initWithTitle:@"Help"];
    NSMenuItem* setup=[help.submenu addItemWithTitle:@"Output Setup…" action:@selector(showOutputHelp:) keyEquivalent:@""];setup.target=self;
    NSMenuItem* diagnostics=[help.submenu addItemWithTitle:@"Diagnostics…" action:@selector(showDiagnostics:) keyEquivalent:@""];diagnostics.target=self;
    [help.submenu addItem:NSMenuItem.separatorItem];
    NSMenuItem* drivers=[help.submenu addItemWithTitle:@"Driver Setup" action:nil keyEquivalent:@""];drivers.submenu=[[NSMenu alloc] initWithTitle:@"Driver Setup"];
    NSMenuItem* camera=[drivers.submenu addItemWithTitle:@"Enable Camera" action:@selector(activate:) keyEquivalent:@""];camera.target=self.capture;
    NSMenuItem* output=[drivers.submenu addItemWithTitle:@"Enable Final Cut Outputs" action:@selector(activateOutput:) keyEquivalent:@""];output.target=self.output;
    NSMenuItem* remove=[drivers.submenu addItemWithTitle:@"Disable Camera" action:@selector(deactivate:) keyEquivalent:@""];remove.target=self;remove.action=@selector(disableCamera:);
    NSMenuItem* removeOutput=[drivers.submenu addItemWithTitle:@"Disable Output Driver" action:@selector(disableOutput:) keyEquivalent:@""];removeOutput.target=self;
    NSApp.mainMenu=main;NSApp.helpMenu=help.submenu;
}
- (void)disableCamera:(id)sender {if(self.capture.recorderTask){[self.capture report:@"Stop recording before disabling the camera driver."];return;}[self.preview stop];[self.monitor stop];self.previewAllowed=NO;self.previewButton.title=@"Show input";[self.capture deactivate:sender];}
- (void)disableOutput:(id)sender {if(self.output.task){[self.output outputMessage:@"Stop output and turn off editor A/V Output or Mercury Transmit before disabling the output driver."];return;}[self.output deactivateOutput:sender];}
- (void)updateMonitor {if(self.capture.recorderTask||self.preview.wantsPreview)[self.monitor start];else [self.monitor stop];}
- (void)showAbout:(id)sender {
    NSString* version=[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"]?:@"0.1.54";
    NSAttributedString* credits=[[NSAttributedString alloc] initWithString:@"Capture, recording and timeline monitoring\nfor Mac displays and Intensity Shuttle USB 3." attributes:@{NSForegroundColorAttributeName:NSColor.labelColor}];
    [NSApp orderFrontStandardAboutPanelWithOptions:@{NSAboutPanelOptionApplicationName:@"Shuttle Video",NSAboutPanelOptionApplicationVersion:version,NSAboutPanelOptionCredits:credits}];
}
- (void)showOutputHelp:(id)sender {
    NSAlert* alert=[NSAlert new];alert.messageText=@"Video output";
    NSInteger source=self.output.source.indexOfSelectedItem;
    alert.informativeText=source==1?@"Choose a movie and HDMI format, then click Start output. Enable Loop to repeat the movie.":source==0?@"Choose an HDMI format and click Start output to show a 30-second test pattern.":self.output.outputHelp.stringValue;
    [alert addButtonWithTitle:@"OK"];[alert beginSheetModalForWindow:self.window completionHandler:nil];
}
- (void)showDiagnostics:(id)sender {
    if(!self.diagnosticsWindow){self.diagnosticsWindow=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,650,300) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];self.diagnosticsWindow.title=@"Shuttle Diagnostics";self.diagnosticsWindow.releasedWhenClosed=NO;self.diagnosticsWindow.contentView=self.output.diagnosticsScroll;[self.diagnosticsWindow center];}
    [self.diagnosticsWindow makeKeyAndOrderFront:nil];
}
- (void)selectPanel:(NSUInteger)index {
    CGFloat desired=index==2?MIN(810.,MAX(590.,NSScreen.mainScreen.visibleFrame.size.height-40)):590;CGFloat delta=desired-self.window.contentView.bounds.size.height;
    if(std::abs(delta)>.5){NSRect frame=self.window.frame;frame.origin.y-=delta;frame.size.height+=delta;[self.window setFrame:frame display:YES];}
    self.tabs.frame=NSMakeRect(12,12,666,desired-74);
    for(NSControl* item in @[self.captureButton,self.outputButton,self.pictureButton,self.idleButton]){NSRect f=item.frame;f.origin.y=desired-48;item.frame=f;}
    self.outputSettingsView.frame=NSMakeRect(0,0,650,720);self.outputScroll.frame=NSMakeRect(8,8,650,desired-90);[self.outputScroll.contentView scrollToPoint:NSMakePoint(0,MAX(0.,720-self.outputScroll.contentView.bounds.size.height))];[self.outputScroll reflectScrolledClipView:self.outputScroll.contentView];
    [self.tabs selectTabViewItemAtIndex:index];self.captureButton.selected=index==1;self.outputButton.selected=index==2;self.pictureButton.selected=index==0;self.idleButton.selected=index==3;if(index==0&&self.previewAllowed&&!self.capture.applyingSettings){[self.preview start];self.previewButton.title=@"Stop preview";}else{if(index==0&&self.previewAllowed&&self.capture.applyingSettings)self.resumePreviewAfterApply=YES;[self.preview stop];self.previewButton.title=@"Show input";}[self updateMonitor]; }
- (void)showCapture:(id)sender{[self selectPanel:1];}
- (void)showOutput:(id)sender{[self selectPanel:2];}
- (void)showPicture:(id)sender{if(sender)self.previewAllowed=YES;[self.capture refreshPictureCapabilities];[self selectPanel:0];}
- (void)togglePreview:(id)sender{if(self.preview.wantsPreview){[self.preview stop];self.previewAllowed=NO;self.previewButton.title=@"Show input";}else{self.previewAllowed=YES;[self.preview start];self.previewButton.title=@"Stop preview";}[self updateMonitor];}
- (void)showIdle:(id)sender{[self selectPanel:3];}
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication*)app {
    if(self.startup.task){[self.startup stopThen:^{[app replyToApplicationShouldTerminate:YES];}];return NSTerminateLater;}
    if(!self.capture.recorderTask)return NSTerminateNow;
    self.capture.recordingFinished=^{[app replyToApplicationShouldTerminate:YES];};[self.capture stopRecording:nil];return NSTerminateLater;
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)app{return YES;}
- (void)applicationWillTerminate:(NSNotification*)note{[self.startup stopThen:nil];[self.preview stop];[self.monitor stop];[self.output applicationWillTerminate:note];}
@end
int main(int argc,char**argv){@autoreleasepool{
    if(argc==2&&!strcmp(argv[1],"--activate-output")){NSApplication* app=NSApplication.sharedApplication;app.activationPolicy=NSApplicationActivationPolicyProhibited;OutputHost* host=[OutputHost new];host.activationOnly=YES;app.delegate=host;[app run];return 0;}
    if((argc==2&&(!strcmp(argv[1],"--get-settings")||!strcmp(argv[1],"--activate")||!strcmp(argv[1],"--deactivate")))||(argc==3&&!strcmp(argv[1],"--apply-settings")))return ShuttleCaptureHostMain(argc,argv);
    NSApplication* app=[ShuttleApplication sharedApplication];app.activationPolicy=NSApplicationActivationPolicyRegular;CombinedHost* host=[CombinedHost new];host.allowStartupMovie=argc==1;
    if(argc==3&&(!strcmp(argv[1],"--render-input")||!strcmp(argv[1],"--render-capture")||!strcmp(argv[1],"--render-output")||!strcmp(argv[1],"--render-picture")||!strcmp(argv[1],"--render-idle"))){host.renderPath=@(argv[2]);host.renderOutput=!strcmp(argv[1],"--render-output");host.renderTab=!strcmp(argv[1],"--render-picture")?2:!strcmp(argv[1],"--render-idle")?3:!strcmp(argv[1],"--render-input")?1:0;app.activationPolicy=NSApplicationActivationPolicyAccessory;app.appearance=[NSAppearance appearanceNamed:NSAppearanceNameAqua];}
    host.previewAllowed=NO;app.delegate=host;[app run];
}return 0;}
