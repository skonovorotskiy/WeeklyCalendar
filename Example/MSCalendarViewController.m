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
#import "NSDate+MWWeeklyCalendar.h"
#import "CGHelper.h"
#import "NSDate+Utilities.h"

#define kNumberOfRealPages      3
#define kNumberOfVirtualPages   (kNumberOfRealPages + 2)
#define D_DAY		86400

NSString * const MSEventCellReuseIdentifier = @"MSEventCellReuseIdentifier";
NSString * const MSDayColumnHeaderReuseIdentifier = @"MSDayColumnHeaderReuseIdentifier";
NSString * const MSTimeRowHeaderReuseIdentifier = @"MSTimeRowHeaderReuseIdentifier";
NSString * const MSTimeRowMinutesHeaderReuseIdentifier = @"MSTimeRowMinutesHeaderReuseIdentifier";

@interface MSCalendarViewController () <MSCollectionViewDelegateCalendarLayout, NSFetchedResultsControllerDelegate>
{
    NSInteger _todaysDayIndex;
}
@property (nonatomic, strong) MSCollectionViewCalendarLayout *collectionViewCalendarLayout;
@property (nonatomic, readonly) CGFloat layoutSectionWidth;
@property (nonatomic, strong) MWEventsContainer *eventsContainer;
@property (nonatomic, strong) id selectedEvent;

@end

@implementation MSCalendarViewController

- (id)init
{
    self.collectionViewCalendarLayout = [[MSCollectionViewCalendarLayout alloc] init];
    self.collectionViewCalendarLayout.delegate = self;
    self = [super initWithCollectionViewLayout:self.collectionViewCalendarLayout];
    if (self) {
        self.numberOfVisibleDays = 7;
        _todaysDayIndex = (kNumberOfVirtualPages / 2) * self.numberOfVisibleDays  + [[NSDate date] dateComponents].weekday - 1;
        self.eventsContainer = [MWEventsContainer new];
    }
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
    
    self.collectionView.showsHorizontalScrollIndicator = NO;
    
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
    
    self.eventsContainer.sortDescriptor = [[NSSortDescriptor alloc] initWithKey:@keypath(MSEvent.new, start) ascending:YES];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.collectionView  setContentOffset:CGPointMake( (self->_todaysDayIndex / self->_numberOfVisibleDays) * [self pageWidth], self.collectionView.contentOffset.y) animated:YES];
    });
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

-(void)scrollToDate:(NSDate*)targetDate animated:(BOOL)animated
{

}

#pragma mark - UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    static CGFloat lastContentOffsetX = FLT_MIN;
    if (FLT_MIN == lastContentOffsetX) {
        lastContentOffsetX = scrollView.contentOffset.x;
        return;
    }
    CGFloat currentOffsetX = scrollView.contentOffset.x;
    CGFloat currentOffsetY = scrollView.contentOffset.y;
    CGFloat oneDayPageWidth = self.dayColumnWidth;
    CGFloat pageWidth = oneDayPageWidth * self.numberOfVisibleDays;
    CGFloat offset = pageWidth * kNumberOfRealPages;
    
    // the first page(showing the last item) is visible and user is still scrolling to the left
    if (currentOffsetX < pageWidth && lastContentOffsetX > currentOffsetX) {
        lastContentOffsetX = currentOffsetX + offset;
        scrollView.contentOffset = (CGPoint){lastContentOffsetX, currentOffsetY};
        _todaysDayIndex += kNumberOfRealPages * self.numberOfVisibleDays;
    }
    // the last page (showing the first item) is visible and the user is still scrolling to the right
    else if (currentOffsetX > offset && lastContentOffsetX < currentOffsetX) {
        lastContentOffsetX = currentOffsetX - offset;
        scrollView.contentOffset = (CGPoint){lastContentOffsetX, currentOffsetY};
        _todaysDayIndex -= kNumberOfRealPages * self.numberOfVisibleDays;
    }
    else {
        lastContentOffsetX = currentOffsetX;
    }
    [self reloadCollectionView];
}

- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView withVelocity:(CGPoint)velocity targetContentOffset:(inout CGPoint *)targetContentOffset
{

}

- (void)getPagingOffsetsForOffset:(CGFloat)offset forPageWidth:(CGFloat)pageWidth leftOffset:(out CGFloat*)leftOffset rigthOffset:(out CGFloat*)rightOffset
{
    int fullPages = (int)( offset / pageWidth );
    if (leftOffset){
        *leftOffset = fullPages * pageWidth;
    }
    
    if (rightOffset){
        *rightOffset = (fullPages + 1) * pageWidth;
    }
}

#pragma mark - MSCalendarViewController

- (CGFloat)layoutSectionWidth
{
    return 138.0;
}

- (CGFloat)pageWidth
{
    return self.dayColumnWidth * self.numberOfVisibleDays;
}

- (CGFloat)dayColumnWidth
{
    return roundTo1Px( self.collectionView.frame.size.width / self.numberOfVisibleDays );
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
    return _numberOfVisibleDays * kNumberOfVirtualPages;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    NSArray *eventsForDay = [self.eventsContainer eventsForDay:[self dateForSection:section]];
    return eventsForDay.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    MSEventCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:MSEventCellReuseIdentifier forIndexPath:indexPath];
    MSEvent *event = [self eventForIndexPath:indexPath];
    BOOL cellSelected = (self.selectedEvent == event);
    [cell setCellSelected:cellSelected animated:NO];
    cell.event = event;
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
    id currentEvent = [self eventForIndexPath:indexPath];
    MSEventCell *lastSelectedCell = nil;
    NSIndexPath *lastSelectedEventIndexPath = nil;
    id lastSelectedEvent = self.selectedEvent;
    if (lastSelectedEvent) {
        lastSelectedEventIndexPath = [self indexPathForEvent:lastSelectedEvent];
    }
    if (lastSelectedEventIndexPath) {
        lastSelectedCell = (MSEventCell *)[collectionView cellForItemAtIndexPath:lastSelectedEventIndexPath];
    }
    if (lastSelectedEvent == currentEvent) {
        [lastSelectedCell setCellSelected:NO animated:YES];
        self.selectedEvent = nil;
    }
    else {
        if (lastSelectedEvent) {
            [lastSelectedCell setCellSelected:NO animated:YES];
        }
        self.selectedEvent = currentEvent;
        MSEventCell *newSelectedCell = (MSEventCell *)[collectionView cellForItemAtIndexPath:indexPath];
        [newSelectedCell setCellSelected:YES animated:YES];
    }
}

- (NSDate *)dateForSection:(NSInteger)section
{
    NSInteger daysAfterToday = section - _todaysDayIndex;
    NSDate *date = [[NSCalendar currentCalendar] startOfDayForDate:[NSDate dateWithTimeIntervalSinceNow:(daysAfterToday * D_DAY)]];
    return date;
}

- (NSInteger)sectionForDate:(NSDate *)date
{
    NSDate *startOfToday = [[NSCalendar currentCalendar] startOfDayForDate:[NSDate date]];
    return roundf([date timeIntervalSinceDate:startOfToday] / D_DAY) + _todaysDayIndex;
}

- (MSEvent *)eventForIndexPath:(NSIndexPath *)indexPath
{
    NSArray *events = [self.eventsContainer eventsForDay:[self dateForSection:indexPath.section]];
    MSEvent *event = events[indexPath.row];
    return event;
}

- (NSIndexPath *)indexPathForEvent:(MSEvent *)event
{
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:[self.eventsContainer indexForEvent:event withDate:event.day] inSection:[self sectionForDate:event.day]];
    return indexPath;
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
    return [event.start dateByAddingTimeInterval:(60 * 60 * 1)];
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
    MSEvent *event = [self eventForDate:date];
    [self.eventsContainer addEvent:event forDate:event.day];
    return [self indexPathForEvent:event];
}

- (void)collectionView:(UICollectionView *)collectionView removeItemAtIndexPath:(NSIndexPath *)indexPath
{
    MSEvent *event = [self eventForIndexPath:indexPath];
    if (event) {
        [self.eventsContainer removeEvent:event withDate:event.day];
    }
}

#pragma mark - Public methods

- (void) addNewEvent
{
    NSDateComponents *currentDateComponents = [[NSDate date] dateComponents];
    float step = 15;
    float roundedMinutes = ceilf(currentDateComponents.minute / step) * step;
    currentDateComponents.minute = roundedMinutes;
    NSDate *roundedDate = [[NSCalendar currentCalendar] dateFromComponents:currentDateComponents];
    
    MSEvent *event = [self eventForDate:roundedDate];
    [self.eventsContainer addEvent:event forDate:event.day];
    
    [self reloadCollectionView];
}

- (void) highlightEvent:(MSEvent *)event
{
    dispatch_async(dispatch_get_main_queue(), ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSIndexPath *indexPath = [self indexPathForEvent:event];
            MSEventCell *cell = (MSEventCell*)[self.collectionView cellForItemAtIndexPath:indexPath];
            [cell setCellSelected:YES animated:YES];
        });
    });
}

#pragma mark - Private methods

- (MSEvent *) eventForDate:(NSDate *)date
{
    static int i = 5;
    MSEvent *event = [MSEvent new];
    event.remoteID = @(i);
    event.start = date;
    event.title = [NSString stringWithFormat:@"Event%d", i];
    event.location = [NSString stringWithFormat:@"Event%d location", i++];
    return event;
}

- (void) reloadCollectionView
{
    [self.collectionViewCalendarLayout invalidateLayoutCache];
    [self.collectionView reloadData];
}

@end
