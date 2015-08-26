//
//  MSCalendarViewController.m
//  Example
//
//  Created by Eric Horacek on 2/26/13.
//  Copyright (c) 2015 Eric Horacek. All rights reserved.
//

#import "MSCalendarViewController.h"
#import "MSCollectionViewCalendarLayout.h"
#import "MSEvent.h"
// Collection View Reusable Views
#import "MSGridline.h"
#import "MSTimeRowHeaderBackground.h"
#import "MSDayColumnHeaderBackground.h"
#import "MSEventCell.h"
#import "MSDayColumnHeader.h"
#import "MSTimeRowHeader.h"
#import "MSCurrentTimeIndicator.h"
#import "MSCurrentTimeGridline.h"
#import "MWEventsContainer.h"
#import "TimeRowMinutesHeader.h"
#import "NonworkingHoursBackgroundView.h"

NSString * const MSEventCellReuseIdentifier = @"MSEventCellReuseIdentifier";
NSString * const MSDayColumnHeaderReuseIdentifier = @"MSDayColumnHeaderReuseIdentifier";
NSString * const MSTimeRowHeaderReuseIdentifier = @"MSTimeRowHeaderReuseIdentifier";
NSString * const MSTimeRowMinutesHeaderReuseIdentifier = @"MSTimeRowMinutesHeaderReuseIdentifier";

@interface MSCalendarViewController () <MSCollectionViewDelegateCalendarLayout, NSFetchedResultsControllerDelegate>

@property (nonatomic, strong) MSCollectionViewCalendarLayout *collectionViewCalendarLayout;
@property (nonatomic, readonly) CGFloat layoutSectionWidth;
@property (nonatomic, strong) MWEventsContainer *eventsContainer;

@end

@implementation MSCalendarViewController

- (id)init
{
    self.collectionViewCalendarLayout = [[MSCollectionViewCalendarLayout alloc] init];
    self.collectionViewCalendarLayout.delegate = self;
    self = [super initWithCollectionViewLayout:self.collectionViewCalendarLayout];
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.collectionView.directionalLockEnabled = YES;
    self.collectionView.backgroundColor = [UIColor whiteColor];
    
    [self.collectionView registerClass:MSEventCell.class forCellWithReuseIdentifier:MSEventCellReuseIdentifier];
    [self.collectionView registerClass:MSDayColumnHeader.class forSupplementaryViewOfKind:MSCollectionElementKindDayColumnHeader withReuseIdentifier:MSDayColumnHeaderReuseIdentifier];
    [self.collectionView registerClass:MSTimeRowHeader.class forSupplementaryViewOfKind:MSCollectionElementKindTimeRowHeader withReuseIdentifier:MSTimeRowHeaderReuseIdentifier];
    [self.collectionView registerClass:TimeRowMinutesHeader.class forSupplementaryViewOfKind:MSCollectionElementKindTimeRowHeaderMinutes withReuseIdentifier:MSTimeRowMinutesHeaderReuseIdentifier];
    
    self.collectionViewCalendarLayout.sectionWidth = self.layoutSectionWidth;
    self.collectionViewCalendarLayout.startWorkingDay = self.startWorkingDay;
    self.collectionViewCalendarLayout.endWorkingDay = self.endWorkingDay;
    
    // These are optional. If you don't want any of the decoration views, just don't register a class for them.
    [self.collectionViewCalendarLayout registerClass:MSCurrentTimeIndicator.class forDecorationViewOfKind:MSCollectionElementKindCurrentTimeIndicator];
    [self.collectionViewCalendarLayout registerClass:MSCurrentTimeGridline.class forDecorationViewOfKind:MSCollectionElementKindCurrentTimeHorizontalGridline];
    [self.collectionViewCalendarLayout registerClass:MSGridline.class forDecorationViewOfKind:MSCollectionElementKindVerticalGridline];
    [self.collectionViewCalendarLayout registerClass:MSGridline.class forDecorationViewOfKind:MSCollectionElementKindHorizontalGridline];
    [self.collectionViewCalendarLayout registerClass:MSTimeRowHeaderBackground.class forDecorationViewOfKind:MSCollectionElementKindTimeRowHeaderBackground];
    [self.collectionViewCalendarLayout registerClass:MSDayColumnHeaderBackground.class forDecorationViewOfKind:MSCollectionElementKindDayColumnHeaderBackground];
    [self.collectionViewCalendarLayout registerClass:NonworkingHoursBackgroundView.class forDecorationViewOfKind:MSCollectionElementKindNonworkingHoursBackground];
    
    self.eventsContainer = [MWEventsContainer new];
    self.eventsContainer.sortDescriptor = [[NSSortDescriptor alloc] initWithKey:@keypath(MSEvent.new, start) ascending:YES];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];

    [self.collectionViewCalendarLayout scrollCollectionViewToClosetSectionToCurrentTimeAnimated:NO];
}

- (void)willTransitionToTraitCollection:(UITraitCollection *)newCollection withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
    // Ensure that collection view properly rotates between layouts
    [self.collectionView.collectionViewLayout invalidateLayout];
    [self.collectionViewCalendarLayout invalidateLayoutCache];

    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        self.collectionViewCalendarLayout.sectionWidth = self.layoutSectionWidth;

    } completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        [self.collectionView reloadData];
    }];
}

- (BOOL)prefersStatusBarHidden
{
    return YES;
}

#pragma mark - MSCalendarViewController

- (CGFloat)layoutSectionWidth
{
    return 138.0;
}

#pragma mark - NSFetchedResultsControllerDelegate

- (void)controllerDidChangeContent:(NSFetchedResultsController *)controller
{
    [self.collectionViewCalendarLayout invalidateLayoutCache];
    [self.collectionView reloadData];
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView
{
    return 20;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    NSArray *eventsForDay = [self.eventsContainer eventsForDay:[self dateForSection:section]];
    return eventsForDay.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    MSEventCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:MSEventCellReuseIdentifier forIndexPath:indexPath];
    cell.event = [self eventForIndexPath:indexPath];
    cell.alpha = 1.0;
    return cell;
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView viewForSupplementaryElementOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)indexPath
{
    UICollectionReusableView *view;
    if (kind == MSCollectionElementKindDayColumnHeader) {
        MSDayColumnHeader *dayColumnHeader = [collectionView dequeueReusableSupplementaryViewOfKind:kind withReuseIdentifier:MSDayColumnHeaderReuseIdentifier forIndexPath:indexPath];
        NSDate *day = [self.collectionViewCalendarLayout dateForDayColumnHeaderAtIndexPath:indexPath];
        NSDate *currentDay = [self currentTimeComponentsForCollectionView:self.collectionView layout:self.collectionViewCalendarLayout];

        NSDate *startOfDay = [[NSCalendar currentCalendar] startOfDayForDate:day];
        NSDate *startOfCurrentDay = [[NSCalendar currentCalendar] startOfDayForDate:currentDay];

        dayColumnHeader.day = day;
        dayColumnHeader.currentDay = [startOfDay isEqualToDate:startOfCurrentDay];

        view = dayColumnHeader;
    }
    else if (kind == MSCollectionElementKindTimeRowHeader) {
        MSTimeRowHeader *timeRowHeader = [collectionView dequeueReusableSupplementaryViewOfKind:kind withReuseIdentifier:MSTimeRowHeaderReuseIdentifier forIndexPath:indexPath];
        timeRowHeader.time = [self.collectionViewCalendarLayout dateForTimeRowHeaderAtIndexPath:indexPath];
        view = timeRowHeader;
    }
    else if (kind == MSCollectionElementKindTimeRowHeaderMinutes) {
        TimeRowMinutesHeader *timeRowMinutesHeader = [collectionView dequeueReusableSupplementaryViewOfKind:kind
                                                                                        withReuseIdentifier:MSTimeRowMinutesHeaderReuseIdentifier
                                                                                               forIndexPath:indexPath];
        NSString *text = nil;
        NSInteger remainder = indexPath.row % 3;
        if (remainder == 0) {
            text = @":15";
        }
        else if (remainder == 1) {
            text = @":30";
        }
        else if (remainder == 2) {
            text = @":45";
        }
        timeRowMinutesHeader.title.text = text;
        view = timeRowMinutesHeader;
    }
    return view;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath
{
    
}

- (NSDate *)dateForSection:(NSInteger)section
{
    NSDate *date = [[NSCalendar currentCalendar] startOfDayForDate:[NSDate dateWithTimeIntervalSinceNow:(section * 86400)]]; // 86400 - seconds per 24 hours
    return date;
}

- (NSInteger)sectionForDate:(NSDate *)date
{
    NSDate *startOfToday = [[NSCalendar currentCalendar] startOfDayForDate:[NSDate date]];
    return roundf([date timeIntervalSinceDate:startOfToday] / 86400); // 86400 - seconds per 24 hours
}

- (MSEvent *)eventForIndexPath:(NSIndexPath *)indexPath
{
    NSArray *events = [self.eventsContainer eventsForDay:[self dateForSection:indexPath.section]];
    MSEvent *event = events[indexPath.row];
    return event;
}

#pragma mark - MSCollectionViewCalendarLayout

- (NSDate *)collectionView:(UICollectionView *)collectionView layout:(MSCollectionViewCalendarLayout *)collectionViewCalendarLayout dayForSection:(NSInteger)section
{
    return [self dateForSection:section];
}

- (NSDate *)collectionView:(UICollectionView *)collectionView layout:(MSCollectionViewCalendarLayout *)collectionViewCalendarLayout startTimeForItemAtIndexPath:(NSIndexPath *)indexPath
{
    MSEvent *event = [self eventForIndexPath:indexPath];
    return event.start;
}

- (NSDate *)collectionView:(UICollectionView *)collectionView layout:(MSCollectionViewCalendarLayout *)collectionViewCalendarLayout endTimeForItemAtIndexPath:(NSIndexPath *)indexPath
{
    MSEvent *event = [self eventForIndexPath:indexPath];
    return [event.start dateByAddingTimeInterval:(60 * 60 * 3)];
}

- (NSDate *)currentTimeComponentsForCollectionView:(UICollectionView *)collectionView layout:(MSCollectionViewCalendarLayout *)collectionViewCalendarLayout
{
    return [NSDate date];
}

- (void)collectionView:(UICollectionView *)collectionView itemAtIndexPath:(NSIndexPath *)indexPath willMoveToDate:(NSDate *)date
{
    MSEvent *event = [self eventForIndexPath:indexPath];
    if (event) {
        [self.eventsContainer removeEvent:event withDate:event.day];
        event.start = date;
        [self.eventsContainer addEvent:event forDate:event.day];
    }
}

- (NSIndexPath *)collectionView:(UICollectionView *)collectionView createNewItemWithDate:(NSDate *)date
{
    static int i = 5;
    MSEvent *event = [MSEvent new];
    event.remoteID = @(i);
    event.start = date;
    event.title = [NSString stringWithFormat:@"Event%d", i];
    event.location = [NSString stringWithFormat:@"Event%d location", i++];
    [self.eventsContainer addEvent:event forDate:event.day];
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:[self.eventsContainer indexForEvent:event withDate:event.day] inSection:[self sectionForDate:event.day]];
    return indexPath;
}

- (void)collectionView:(UICollectionView *)collectionView removeItemAtIndexPath:(NSIndexPath *)indexPath
{
    MSEvent *event = [self eventForIndexPath:indexPath];
    if (event) {
        [self.eventsContainer removeEvent:event withDate:event.day];
    }
}

@end
