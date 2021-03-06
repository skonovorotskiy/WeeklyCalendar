//
//  MSAppDelegate.m
//  Example
//
//  Created by Eric Horacek on 2/26/13.
//  Copyright (c) 2015 Eric Horacek. All rights reserved.
//

#import "MSAppDelegate.h"
#import "MSCalendarViewController.h"
#import "MSEvent.h"

@interface MSAppDelegate ()

@end

@implementation MSAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    MSCalendarViewController *calendarViewController = [[MSCalendarViewController alloc] init];
    calendarViewController.startWorkingDay = [self dateComponentsWithHours:10 minutes:0];
    calendarViewController.endWorkingDay = [self dateComponentsWithHours:19 minutes:30];
    MSEvent *event = [calendarViewController addNewEvent];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [calendarViewController highlightEvent:event];
        [calendarViewController scrollToWorkingHoursAnimated:YES];
    });

    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.rootViewController = calendarViewController;
    self.window.backgroundColor = [UIColor whiteColor];
    [self.window makeKeyAndVisible];
    return YES;
}

- (NSDateComponents *)dateComponentsWithHours:(NSInteger)hours minutes:(NSInteger)minutes
{
    NSDateComponents *components = [NSDateComponents new];
    components.hour = hours;
    components.minute = minutes;
    return components;
}

@end
