//
//  MWEventsContainer.h
//  WeeklyCalendar
//
//  Created by Sergey Konovorotskiy on 5/14/15.
//
//

#import <Foundation/Foundation.h>

@interface MWEventsContainer : NSObject

@property (nonatomic, strong) NSSortDescriptor *sortDescriptor;

- (void)addEvent:(id)event forDate:(NSDate *)date;
- (void)removeEvent:(id)event withDate:(NSDate *)date;
- (NSArray *)eventsForDay:(NSDate *)day;
- (NSArray *)allEvents;

@end
