// GPL-2.0-or-later. Fake tasks; no subprocess, USB, defaults or audio writes.
#import <Cocoa/Cocoa.h>
#include <cassert>
static unsigned launches=0,terminations=0;
static bool failLaunch=false;
@interface StartupFakeTask:NSObject
@property BOOL running;
@property NSURL* executableURL;
@property NSArray* arguments;
@property id standardOutput,standardError;
@property(copy) void (^terminationHandler)(StartupFakeTask*);
@end
@implementation StartupFakeTask
- (BOOL)launchAndReturnError:(NSError**)error{++launches;if(failLaunch){if(error)*error=[NSError errorWithDomain:@"offline" code:1 userInfo:nil];return NO;}self.running=YES;return YES;}
- (void)terminate{++terminations;self.running=NO;} // completion is deliberately deferred
@end
#define NSTask StartupFakeTask
#include "../unified/src/StartupOutput.mm"
#undef NSTask
@interface ActionProbe:NSObject
@property unsigned calls;
- (void)run:(id)sender;
@end
@implementation ActionProbe
- (void)run:(id)sender{++self.calls;}
@end
static void finish(ShuttleStartupOutput* output){auto task=output.task;assert(task);task.terminationHandler(task);NSDate* until=[NSDate dateWithTimeIntervalSinceNow:.1];while(output.task&&until.timeIntervalSinceNow>0)[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.001]];assert(!output.task);}
int main(int argc,char**argv){@autoreleasepool{
 ShuttleApplication* app=[ShuttleApplication sharedApplication];assert([app isKindOfClass:ShuttleApplication.class]);
 NSURL* movie=[NSURL fileURLWithPath:@(argv[1])];NSURL* helper=[NSURL fileURLWithPath:@"/usr/bin/true"];
 auto output=[ShuttleStartupOutput new];app.startupOutput=output;[output startMovie:movie helper:helper mode:@"1080p25"];assert((launches==1&&output.task.running&&[output.task.arguments isEqual:@[@"--startup",@"1080p25",movie.path]]));
 auto probe=[ActionProbe new];[app sendAction:@selector(run:) to:probe from:nil];assert(terminations==1&&probe.calls==0&&output.task); // no race with cancellation
 [app sendAction:@selector(run:) to:probe from:nil];assert(terminations==1&&probe.calls==0);finish(output);assert(probe.calls==2); // exactly once per action
 [app sendAction:@selector(run:) to:probe from:nil];assert(probe.calls==3&&terminations==1);
 [output startMovie:movie helper:helper mode:@"576i50"];__block bool quit=false;[output stopThen:^{quit=true;}];assert(!quit);finish(output);assert(quit&&terminations==2);
 [output startMovie:[NSURL fileURLWithPath:@"/nonexistent-startup.m4v"] helper:helper mode:@"1080p25"];assert(!output.task&&launches==2);
 failLaunch=true;[output startMovie:movie helper:helper mode:@"1080p25"];assert(!output.task&&launches==3);__block bool proceeded=false;[output stopThen:^{proceeded=true;}];assert(proceeded);
 puts("PASS: custom application routes actions exactly once after asynchronous startup USB release; one termination despite repeated actions, deferred quit, missing asset and launch failure; all subprocesses are fake.");
}}
