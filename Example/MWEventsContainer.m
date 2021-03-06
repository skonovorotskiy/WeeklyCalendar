//
//  MWEventsContainer.m
//  WeeklyCalendar
//
//  Created by Sergey Konovorotskiy on 5/14/15.
//
//

#import "MWEventsContainer.h"

@interface MWEventsContainer ()

@property (nonatomic, strong) NSMutableDictionary *dictionaty;

@end

@implementation MWEventsContainer

- (instancetype)init
{
    self = [super init];
    if (self) {
        _dictionaty = [NSMutableDictionary new];
    }
    return self;
}

- (void)addEvent:(id)event forDate:(NSDate *)date
{
    NSNumber *dayOfYear = [self dayNumberForDate:date];
    NSMutableArray *mutableArray = self.dictionaty[dayOfYear];
    if (!mutableArray) {
        mutableArray = [NSMutableArray new];
        self.dictionaty[dayOfYear] = mutableArray;
    }
    [mutableArray addObject:event];
    if (self.sortDescriptor) {
        [mutableArray sortUsingDescriptors:@[self.sortDescriptor]];
    }
}

- (void)removeEvent:(id)event withDate:(NSDate *)date
{
    NSMutableArray *events = self.dictionaty[[self dayNumberForDate:date]];
    [events removeObject:event];
}

- (NSArray *)eventsForDay:(NSDate *)day
{
    NSMutableArray *events = self.dictionaty[[self dayNumberForDate:day]];
    if (events.count) {
        return events;
    }
    return nil;
}

- (NSArray *)allEvents
{
    NSArray *allEvents = [self.dictionaty.allValues  valueForKeyPath:@"@distinctUnionOfArrays.self"];
    return allEvents;
}

#pragma mark - private

- (NSNumber *)dayNumberForDate:(NSDate *)date
{
    NSDateComponents *components = [[NSCalendar currentCalendar] components:(NSCalendarUnitWeekday | NSCalendarUnitWeekOfYear | NSCalendarUnitYear) fromDate:date];
    NSInteger day = components.weekday + (components.weekOfYear * 7) + ((components.year - 2000) * 366);
    return @(day);
}

- (NSInteger)indexForEvent:(id)event withDate:(NSDate *)date
{
    NSMutableArray *events = self.dictionaty[[self dayNumberForDate:date]];
    return [events indexOfObject:event];
}

@end
