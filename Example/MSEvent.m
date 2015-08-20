//
//  MSEvent.m
//  Example
//
//  Created by Eric Horacek on 2/26/13.
//  Copyright (c) 2015 Eric Horacek. All rights reserved.
//

#import "MSEvent.h"

@implementation MSEvent

- (NSDate *)day
{
    return [[NSCalendar currentCalendar] startOfDayForDate:self.start];
}

- (id)copyWithZone:(NSZone *)zone
{
    MSEvent *event = [MSEvent new];
    event.remoteID = self.remoteID;
    event.start = self.start;
    event.title = self.title;
    event.location = self.location;
    event.timeToBeDecided = self.timeToBeDecided;
    event.dateToBeDecided = self.dateToBeDecided;
    return event;
}

@end
