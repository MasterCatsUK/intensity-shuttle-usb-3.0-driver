// GPL-2.0-or-later. One host app for capture, playback and extension activation.
#define main ShuttleCaptureHostMain
#include "capture/Host.mm"
#undef main
#define main ShuttleOutputHostMain
#include "output/OutputHost.mm"
#undef main
@interface NavigationButton : NSControl
@property(copy) NSString* title;
@property(nonatomic) BOOL selected;
@end
@implementation NavigationButton
- (BOOL)isOpaque{return NO;}
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
@property OutputHost* output;
@property NSWindow* window;
@property NSTabView* tabs;
@property NavigationButton* captureButton;
@property NavigationButton* outputButton;
@property NSString* renderPath;
@property BOOL renderOutput;
@property NSWindow* diagnosticsWindow;
@end
@implementation CombinedHost
- (void)applicationDidFinishLaunching:(NSNotification*)note {
    self.capture=[Host new];self.capture.embedded=YES;[self.capture applicationDidFinishLaunching:note];
    self.output=[OutputHost new];self.output.embedded=YES;[self.output applicationDidFinishLaunching:note];
    NSView* captureView=self.capture.window.contentView;NSView* outputView=self.output.window.contentView;
    self.window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,690,590) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable backing:NSBackingStoreBuffered defer:NO];
    self.window.title=@"Shuttle Camera";self.window.delegate=self;
    self.window.contentView=[[SettingsCanvas alloc] initWithFrame:NSMakeRect(0,0,690,590)];
    self.tabs=[[NSTabView alloc] initWithFrame:NSMakeRect(12,12,666,516)];self.tabs.tabViewType=NSNoTabsNoBorder;
    self.captureButton=[[NavigationButton alloc] initWithFrame:NSMakeRect(168,542,150,30)];self.captureButton.title=@"Capture";self.captureButton.target=self;self.captureButton.action=@selector(showCapture:);
    self.outputButton=[[NavigationButton alloc] initWithFrame:NSMakeRect(328,542,190,30)];self.outputButton.title=@"Video Output";self.outputButton.target=self;self.outputButton.action=@selector(showOutput:);
    auto* captureTab=[[NSTabViewItem alloc] initWithIdentifier:@"capture"];captureTab.label=@"Capture";
    auto* outputTab=[[NSTabViewItem alloc] initWithIdentifier:@"output"];outputTab.label=@"Video Output";
    auto* captureContainer=[[SettingsCanvas alloc] initWithFrame:NSMakeRect(0,0,650,500)];
    auto* outputContainer=[[SettingsCanvas alloc] initWithFrame:NSMakeRect(0,0,650,500)];
    [captureView removeFromSuperview];[outputView removeFromSuperview];
    captureView.frame=NSMakeRect(8,8,650,500);outputView.frame=NSMakeRect(8,8,650,500);
    captureView.autoresizingMask=NSViewMinYMargin;outputView.autoresizingMask=NSViewMinYMargin;
    [captureContainer addSubview:captureView];[outputContainer addSubview:outputView];captureTab.view=captureContainer;outputTab.view=outputContainer;
    [self.tabs addTabViewItem:captureTab];[self.tabs addTabViewItem:outputTab];[self.window.contentView addSubview:self.tabs];
    [self.window.contentView addSubview:self.captureButton];[self.window.contentView addSubview:self.outputButton];
    // All handlers present sheets and activation messages in this one window.
    self.capture.window=self.window;self.output.window=self.window;
    [self buildMenu];
    if(self.renderOutput)[self showOutput:nil];else [self showCapture:nil];
    [self.window center];[self.window makeKeyAndOrderFront:nil];
    if(self.renderPath){dispatch_after(dispatch_time(DISPATCH_TIME_NOW,300*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        NSView* v=self.window.contentView;[v layoutSubtreeIfNeeded];auto* rep=[v bitmapImageRepForCachingDisplayInRect:v.bounds];[v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];
        BOOL ok=[[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:self.renderPath atomically:YES];exit(ok?0:1);
    });}else [NSApp activateIgnoringOtherApps:YES];
}
- (void)buildMenu {
    NSMenu* main=[NSMenu new];
    NSMenuItem* application=[NSMenuItem new];application.title=@"Shuttle Camera";[main addItem:application];NSMenu* appMenu=[[NSMenu alloc] initWithTitle:@"Shuttle Camera"];application.submenu=appMenu;
    NSMenuItem* about=[appMenu addItemWithTitle:@"About Shuttle Camera" action:@selector(showAbout:) keyEquivalent:@""];about.target=self;
    [appMenu addItem:NSMenuItem.separatorItem];
    [appMenu addItemWithTitle:@"Hide Shuttle Camera" action:@selector(hide:) keyEquivalent:@"h"];
    [appMenu addItemWithTitle:@"Show All" action:@selector(unhideAllApplications:) keyEquivalent:@""];
    [appMenu addItem:NSMenuItem.separatorItem];
    NSMenuItem* quit=[appMenu addItemWithTitle:@"Quit Shuttle Camera" action:@selector(terminate:) keyEquivalent:@"q"];quit.target=NSApp;
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
    NSMenuItem* output=[drivers.submenu addItemWithTitle:@"Enable HDMI Output" action:@selector(activateOutput:) keyEquivalent:@""];output.target=self.output;
    NSMenuItem* remove=[drivers.submenu addItemWithTitle:@"Disable Camera" action:@selector(deactivate:) keyEquivalent:@""];remove.target=self.capture;
    NSApp.mainMenu=main;NSApp.helpMenu=help.submenu;
}
- (void)showAbout:(id)sender {
    NSString* version=[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"]?:@"0.1.31";
    NSAttributedString* credits=[[NSAttributedString alloc] initWithString:@"Capture, playback and HDMI output\nfor the Intensity Shuttle USB 3." attributes:@{NSForegroundColorAttributeName:NSColor.labelColor}];
    [NSApp orderFrontStandardAboutPanelWithOptions:@{NSAboutPanelOptionApplicationName:@"Shuttle Camera",NSAboutPanelOptionApplicationVersion:version,NSAboutPanelOptionCredits:credits}];
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
- (void)showCapture:(id)sender{[self.tabs selectTabViewItemAtIndex:0];self.captureButton.selected=YES;self.outputButton.selected=NO;}
- (void)showOutput:(id)sender{[self.tabs selectTabViewItemAtIndex:1];self.outputButton.selected=YES;self.captureButton.selected=NO;}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)app{return YES;}
- (void)applicationWillTerminate:(NSNotification*)note{[self.output applicationWillTerminate:note];}
@end
int main(int argc,char**argv){@autoreleasepool{
    if(argc==2&&!strcmp(argv[1],"--activate-output")){NSApplication* app=NSApplication.sharedApplication;app.activationPolicy=NSApplicationActivationPolicyProhibited;OutputHost* host=[OutputHost new];host.activationOnly=YES;app.delegate=host;[app run];return 0;}
    if((argc==2&&(!strcmp(argv[1],"--get-settings")||!strcmp(argv[1],"--activate")||!strcmp(argv[1],"--deactivate")))||(argc==3&&!strcmp(argv[1],"--apply-settings")))return ShuttleCaptureHostMain(argc,argv);
    NSApplication* app=NSApplication.sharedApplication;app.activationPolicy=NSApplicationActivationPolicyRegular;CombinedHost* host=[CombinedHost new];
    if(argc==3&&(!strcmp(argv[1],"--render-capture")||!strcmp(argv[1],"--render-output"))){host.renderPath=@(argv[2]);host.renderOutput=!strcmp(argv[1],"--render-output");app.activationPolicy=NSApplicationActivationPolicyAccessory;app.appearance=[NSAppearance appearanceNamed:NSAppearanceNameAqua];}
    app.delegate=host;[app run];
}return 0;}
