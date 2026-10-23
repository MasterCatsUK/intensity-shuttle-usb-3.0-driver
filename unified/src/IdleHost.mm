// GPL-2.0-or-later. Native idle-screen preferences, applied on the next output start.
#import <ImageIO/ImageIO.h>
@interface IdleHost : NSObject
@property NSView *view;
@property NSWindow *window;
@property NSPopUpButton *screen,*delay,*sizing;
@property NSTextField *mediaLabel;
@property NSImageView *preview;
@property NSTextField *status;
@property NSButton* startupMovie;
@end
@implementation IdleHost
- (instancetype)init{if((self=[super init])){
    self.view=[[SettingsCanvas alloc] initWithFrame:NSMakeRect(0,0,650,500)];
    auto box=[NSBox new];box.title=@"Default output screen";box.frame=NSMakeRect(18,115,614,370);[self.view addSubview:box];
    self.screen=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(36,413,262,30)];[self.screen addItemsWithTitles:@[@"Hold last frame",@"Black",@"Colour bars",@"Picture",@"Movie loop (silent)"]];NSInteger n=[NSUserDefaults.standardUserDefaults integerForKey:@"HDMIIdleScreen"];[self.screen selectItemAtIndex:n>=0&&n<5?n:0];self.screen.target=self;self.screen.action=@selector(screenChanged:);[self.view addSubview:self.screen];
    self.preview=[[NSImageView alloc] initWithFrame:NSMakeRect(320,225,290,198)];self.preview.imageScaling=NSImageScaleProportionallyUpOrDown;self.preview.imageFrameStyle=NSImageFrameGrayBezel;[self.view addSubview:self.preview];
    NSString *path=[NSUserDefaults.standardUserDefaults stringForKey:@"HDMIIdlePicture"];if(path)self.preview.image=[[NSImage alloc] initWithContentsOfFile:path];
    self.mediaLabel=[NSTextField labelWithString:@""];self.mediaLabel.frame=NSMakeRect(320,200,290,20);self.mediaLabel.font=[NSFont systemFontOfSize:11];self.mediaLabel.lineBreakMode=NSLineBreakByTruncatingMiddle;[self.view addSubview:self.mediaLabel];
    NSString *movie=[NSUserDefaults.standardUserDefaults stringForKey:@"HDMIIdleMovie"];if(self.screen.indexOfSelectedItem==4){self.preview.image=nil;self.mediaLabel.stringValue=movie.lastPathComponent?:@"No movie selected";}
    auto choose=[NSButton buttonWithTitle:@"Choose media…" target:self action:@selector(choosePicture:)];choose.frame=NSMakeRect(36,357,262,32);[self.view addSubview:choose];
    auto clear=[NSButton buttonWithTitle:@"Clear media" target:self action:@selector(clearPicture:)];clear.frame=NSMakeRect(36,313,262,32);[self.view addSubview:clear];
    auto delayLabel=[NSTextField labelWithString:@"Show after"];delayLabel.frame=NSMakeRect(36,275,262,22);[self.view addSubview:delayLabel];
    self.delay=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(36,237,262,30)];[self.delay addItemsWithTitles:@[@"Immediately",@"30 seconds",@"1 minute",@"2 minutes",@"5 minutes",@"10 minutes",@"Never"]];
    NSArray *delays=@[@0,@30,@60,@120,@300,@600,@(-1)];id saved=[NSUserDefaults.standardUserDefaults objectForKey:@"HDMIIdleDelaySeconds"];NSUInteger selected=[delays indexOfObject:saved?:@120];[self.delay selectItemAtIndex:selected==NSNotFound?3:selected];self.delay.target=self;self.delay.action=@selector(screenChanged:);self.delay.accessibilityLabel=@"HDMI idle delay";[self.view addSubview:self.delay];
    self.sizing=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(36,185,262,30)];[self.sizing addItemsWithTitles:@[@"Fit — whole picture",@"Fill — crop to frame",@"Stretch to frame"]];NSInteger fit=[NSUserDefaults.standardUserDefaults integerForKey:@"HDMIIdleSizing"];[self.sizing selectItemAtIndex:fit>=0&&fit<3?fit:0];self.sizing.target=self;self.sizing.action=@selector(screenChanged:);self.sizing.accessibilityLabel=@"Idle picture or movie sizing";[self.view addSubview:self.sizing];
    auto note=[NSTextField wrappingLabelWithString:@"Shown after the selected time without new editor video. Playback or scrubbing restores video immediately. Keep output running."];note.font=[NSFont systemFontOfSize:12];note.textColor=NSColor.secondaryLabelColor;note.frame=NSMakeRect(36,130,572,44);[self.view addSubview:note];
    self.startupMovie=[NSButton checkboxWithTitle:@"Play startup video on Shuttle" target:self action:@selector(startupChanged:)];self.startupMovie.frame=NSMakeRect(24,88,602,26);self.startupMovie.state=![NSUserDefaults.standardUserDefaults objectForKey:@"PlayStartupMovie"]||[NSUserDefaults.standardUserDefaults boolForKey:@"PlayStartupMovie"]?NSControlStateValueOn:NSControlStateValueOff;self.startupMovie.toolTip=@"On app launch, play the bundled logo once and hold its last frame until you use an app control. Skipped if the camera or USB device is busy. Uses the saved output format; no audio route is changed.";[self.view addSubview:self.startupMovie];
    self.status=[NSTextField wrappingLabelWithString:@"Changes apply the next time you start output."];self.status.font=[NSFont systemFontOfSize:12];self.status.frame=NSMakeRect(24,24,602,50);[self.view addSubview:self.status];
}return self;}
- (void)startupChanged:(id)sender{[NSUserDefaults.standardUserDefaults setBool:self.startupMovie.state==NSControlStateValueOn forKey:@"PlayStartupMovie"];[NSUserDefaults.standardUserDefaults synchronize];self.status.stringValue=@"Saved for the next app launch.";}
- (void)screenChanged:(id)sender{[NSUserDefaults.standardUserDefaults setInteger:self.screen.indexOfSelectedItem forKey:@"HDMIIdleScreen"];[NSUserDefaults.standardUserDefaults setInteger:[@[@0,@30,@60,@120,@300,@600,@(-1)][self.delay.indexOfSelectedItem] integerValue] forKey:@"HDMIIdleDelaySeconds"];[NSUserDefaults.standardUserDefaults setInteger:self.sizing.indexOfSelectedItem forKey:@"HDMIIdleSizing"];[NSUserDefaults.standardUserDefaults synchronize];self.status.stringValue=@"Saved. Restart output to use this default screen.";}
- (void)clearPicture:(id)sender{[NSUserDefaults.standardUserDefaults removeObjectForKey:@"HDMIIdlePicture"];[NSUserDefaults.standardUserDefaults removeObjectForKey:@"HDMIIdleMovie"];self.preview.image=nil;self.mediaLabel.stringValue=@"";[self.screen selectItemAtIndex:1];[self screenChanged:nil];}
- (void)choosePicture:(id)sender{
    auto panel=[NSOpenPanel openPanel];panel.canChooseDirectories=NO;panel.allowsMultipleSelection=NO;panel.allowedFileTypes=@[@"png",@"jpg",@"jpeg",@"tiff",@"heic",@"mov",@"mp4",@"m4v"];
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response){if(response!=NSModalResponseOK)return;
        CGImageSourceRef source=CGImageSourceCreateWithURL((__bridge CFURLRef)panel.URL,nullptr);
        CGImageRef image=source?CGImageSourceCreateThumbnailAtIndex(source,0,(__bridge CFDictionaryRef)@{(__bridge NSString*)kCGImageSourceCreateThumbnailFromImageAlways:@YES,(__bridge NSString*)kCGImageSourceCreateThumbnailWithTransform:@YES,(__bridge NSString*)kCGImageSourceThumbnailMaxPixelSize:@1920}):nullptr;
        if(source)CFRelease(source);if(!image){
            if([@[@"mov",@"mp4",@"m4v"] containsObject:panel.URL.pathExtension.lowercaseString]){
                [NSUserDefaults.standardUserDefaults setObject:panel.URL.path forKey:@"HDMIIdleMovie"];self.preview.image=nil;self.mediaLabel.stringValue=panel.URL.lastPathComponent;[self.screen selectItemAtIndex:4];[self screenChanged:nil];
            }else self.status.stringValue=@"Could not read that picture.";
            return;
        }
        NSBitmapImageRep *rep=[[NSBitmapImageRep alloc] initWithCGImage:image];CGImageRelease(image);
        NSData *data=[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        NSURL *directory=[[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject URLByAppendingPathComponent:@"Shuttle Camera" isDirectory:YES];
        NSError *error=nil;[NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:&error];
        NSURL *file=[directory URLByAppendingPathComponent:@"Idle Screen.png"];
        if(error||!data.length||data.length>4*1024*1024||![data writeToURL:file options:NSDataWritingAtomic error:&error]){self.status.stringValue=@"Could not save that picture. Try a smaller image.";return;}
        [NSUserDefaults.standardUserDefaults setObject:file.path forKey:@"HDMIIdlePicture"];self.preview.image=[[NSImage alloc] initWithData:data];self.mediaLabel.stringValue=file.lastPathComponent;[self.screen selectItemAtIndex:3];[self screenChanged:nil];
    }];
}
@end
