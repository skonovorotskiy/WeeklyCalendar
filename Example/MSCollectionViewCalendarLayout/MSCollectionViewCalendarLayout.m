//
//  MSCollectionViewCalendarLayout.m
//  MSCollectionViewCalendarLayout
//
//  Created by Eric Horacek on 2/18/13.
//  Copyright (c) 2015 Eric Horacek. All rights reserved.
//
//  This code is distributed under the terms and conditions of the MIT license.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

#import "MSCollectionViewCalendarLayout.h"

struct TouchInfo {
    CGPoint point;
    CFAbsoluteTime time;
    CGVector velocity;
};

NSString * const MSCollectionElementKindTimeRowHeader = @"MSCollectionElementKindTimeRow";
NSString * const MSCollectionElementKindTimeRowHeaderMinutes = @"MSCollectionElementKindTimeRowMinutes";
NSString * const MSCollectionElementKindDayColumnHeader = @"MSCollectionElementKindDayHeader";
NSString * const MSCollectionElementKindTimeRowHeaderBackground = @"MSCollectionElementKindTimeRowHeaderBackground";
NSString * const MSCollectionElementKindDayColumnHeaderBackground = @"MSCollectionElementKindDayColumnHeaderBackground";
NSString * const MSCollectionElementKindCurrentTimeIndicator = @"MSCollectionElementKindCurrentTimeIndicator";
NSString * const MSCollectionElementKindCurrentTimeHorizontalGridline = @"MSCollectionElementKindCurrentTimeHorizontalGridline";
NSString * const MSCollectionElementKindVerticalGridline = @"MSCollectionElementKindVerticalGridline";
NSString * const MSCollectionElementKindHorizontalGridline = @"MSCollectionElementKindHorizontalGridline";
NSString * const MSCollectionElementKindNonworkingHoursBackground = @"MSCollectionElementKindNonworkingHoursBackground";

NSUInteger const MSCollectionMinOverlayZ = 1000.0; // Allows for 900 items in a section without z overlap issues
NSUInteger const MSCollectionMinCellZ = 100.0;  // Allows for 100 items in a section's background
NSUInteger const MSCollectionMinBackgroundZ = 0.0;

static NSString * const kLXCollectionViewKeyPath = @"collectionView";

@interface UICollectionViewCell (LXReorderableCollectionViewFlowLayout)

- (UIView *)LX_snapshotView;

@end

@implementation UICollectionViewCell (LXReorderableCollectionViewFlowLayout)

- (UIView *)LX_snapshotView {
    if ([self respondsToSelector:@selector(snapshotViewAfterScreenUpdates:)]) {
        return [self snapshotViewAfterScreenUpdates:YES];
    } else {
        UIGraphicsBeginImageContextWithOptions(self.bounds.size, self.isOpaque, 0.0f);
        [self.layer renderInContext:UIGraphicsGetCurrentContext()];
        UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        return [[UIImageView alloc] initWithImage:image];
    }
}

@end

@interface MSTimerWeakTarget : NSObject
@property (nonatomic, weak) id target;
@property (nonatomic, assign) SEL selector;
- (SEL)fireSelector;
@end

@implementation MSTimerWeakTarget
- (id)initWithTarget:(id)target selector:(SEL)selector
{
    self = [super init];
    if (self) {
        self.target = target;
        self.selector = selector;
    }
    return self;
}
- (void)fire:(NSTimer*)timer
{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    [self.target performSelector:self.selector withObject:timer];
#pragma clang diagnostic pop
}
- (SEL)fireSelector
{
    return @selector(fire:);
}
@end

@interface MSCollectionViewCalendarLayout () <UIGestureRecognizerDelegate>
{
    struct TouchInfo _addingEventTouchInfo;
}

// Minute Timer
@property (nonatomic, strong) NSTimer *minuteTimer;

// Minute Height
@property (nonatomic, readonly) CGFloat minuteHeight;

// Caches
@property (nonatomic, assign) BOOL needsToPopulateAttributesForAllSections;
@property (nonatomic, strong) NSCache *cachedDayDateComponents;
@property (nonatomic, strong) NSCache *cachedStartTimeDateComponents;
@property (nonatomic, strong) NSCache *cachedEndTimeDateComponents;
@property (nonatomic, strong) NSCache *cachedCurrentDateComponents;
@property (nonatomic, assign) CGFloat cachedMaxColumnHeight;
@property (nonatomic, assign) NSInteger cachedEarliestHour;
@property (nonatomic, assign) NSInteger cachedLatestHour;
@property (nonatomic, strong) NSMutableDictionary *cachedColumnHeights;
@property (nonatomic, strong) NSMutableDictionary *cachedEarliestHours;
@property (nonatomic, strong) NSMutableDictionary *cachedLatestHours;

// Registered Decoration Classes
@property (nonatomic, strong) NSMutableDictionary *registeredDecorationClasses;

// Attributes
@property (nonatomic, strong) NSMutableArray *allAttributes;
@property (nonatomic, strong) NSMutableDictionary *itemAttributes;
@property (nonatomic, strong) NSMutableDictionary *dayColumnHeaderAttributes;
@property (nonatomic, strong) NSMutableDictionary *dayColumnHeaderBackgroundAttributes;
@property (nonatomic, strong) NSMutableDictionary *timeRowHeaderAttributes;
@property (nonatomic, strong) NSMutableDictionary *timeRowHeaderMinutesAttributes;
@property (nonatomic, strong) NSMutableDictionary *timeRowHeaderBackgroundAttributes;
@property (nonatomic, strong) NSMutableDictionary *horizontalGridlineAttributes;
@property (nonatomic, strong) NSMutableDictionary *verticalGridlineAttributes;
@property (nonatomic, strong) NSMutableDictionary *currentTimeIndicatorAttributes;
@property (nonatomic, strong) NSMutableDictionary *currentTimeHorizontalGridlineAttributes;
@property (nonatomic, strong) NSMutableDictionary *nonWorkingHoursBackgroundAttributes;

@property (strong, nonatomic) NSIndexPath *selectedItemIndexPath;
@property (strong, nonatomic) UIView *currentView;
@property (assign, nonatomic) CGPoint currentViewCenter;

@end

@implementation MSCollectionViewCalendarLayout

#pragma mark - NSObject

- (void)dealloc
{
    [self.minuteTimer invalidate];
    self.minuteTimer = nil;
    
    [self tearDownCollectionView];
    [self removeObserver:self forKeyPath:kLXCollectionViewKeyPath];
}

- (id)init
{
    self = [super init];
    if (self) {
        [self initialize];
    }
    return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (self) {
        [self initialize];
    }
    return self;
}

- (void)setDefaults {
    _scrollingSpeed = 300.0f;
    _scrollingTriggerEdgeInsets = UIEdgeInsetsMake(50.0f, 50.0f, 50.0f, 50.0f);
}

#pragma mark - UICollectionViewLayout

- (void)prepareForCollectionViewUpdates:(NSArray *)updateItems
{
    [self invalidateLayoutCache];
    
    // Update the layout with the new items
    [self prepareLayout];
    
    [super prepareForCollectionViewUpdates:updateItems];
}

- (void)finalizeCollectionViewUpdates
{
    // This is a hack to prevent the error detailed in :
    // http://stackoverflow.com/questions/12857301/uicollectionview-decoration-and-supplementary-views-can-not-be-moved
    // If this doesn't happen, whenever the collection view has batch updates performed on it, we get multiple instantiations of decoration classes
    for (UIView *subview in self.collectionView.subviews) {
        for (Class decorationViewClass in self.registeredDecorationClasses.allValues) {
            if ([subview isKindOfClass:decorationViewClass]) {
                [subview removeFromSuperview];
            }
        }
    }
    [self.collectionView reloadData];
}

- (void)registerClass:(Class)viewClass forDecorationViewOfKind:(NSString *)decorationViewKind
{
    [super registerClass:viewClass forDecorationViewOfKind:decorationViewKind];
    self.registeredDecorationClasses[decorationViewKind] = viewClass;
}

- (void)prepareLayout
{
    [super prepareLayout];
    
    if (self.needsToPopulateAttributesForAllSections) {
        [self prepareSectionLayoutForSections:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, self.collectionView.numberOfSections)]];
        self.needsToPopulateAttributesForAllSections = NO;
    }
    
    BOOL needsToPopulateAllAttribtues = (self.allAttributes.count == 0);
    if (needsToPopulateAllAttribtues) {
        [self.allAttributes addObjectsFromArray:[self.dayColumnHeaderAttributes allValues]];
        [self.allAttributes addObjectsFromArray:[self.dayColumnHeaderBackgroundAttributes allValues]];
        [self.allAttributes addObjectsFromArray:[self.timeRowHeaderAttributes allValues]];
        [self.allAttributes addObjectsFromArray:[self.timeRowHeaderMinutesAttributes allValues]];
        [self.allAttributes addObjectsFromArray:[self.timeRowHeaderBackgroundAttributes allValues]];
        [self.allAttributes addObjectsFromArray:[self.verticalGridlineAttributes allValues]];
        [self.allAttributes addObjectsFromArray:[self.horizontalGridlineAttributes allValues]];
        [self.allAttributes addObjectsFromArray:[self.itemAttributes allValues]];
        [self.allAttributes addObjectsFromArray:[self.currentTimeIndicatorAttributes allValues]];
        [self.allAttributes addObjectsFromArray:[self.currentTimeHorizontalGridlineAttributes allValues]];
        [self.allAttributes addObjectsFromArray:[self.nonWorkingHoursBackgroundAttributes allValues]];
    }
}

- (void)prepareSectionLayoutForSections:(NSIndexSet *)sectionIndexes
{
    if (self.collectionView.numberOfSections == 0) {
        return;
    }
    
    BOOL needsToPopulateItemAttributes = (self.itemAttributes.count == 0);
    BOOL needsToPopulateVerticalGridlineAttributes = (self.verticalGridlineAttributes.count == 0);
    
    NSInteger earliestHour = [self earliestHour];
    NSInteger latestHour = [self latestHour];
    
    CGFloat sectionWidth = (self.sectionMargin.left + self.sectionWidth + self.sectionMargin.right);
    CGFloat sectionHeight = nearbyintf((self.hourHeight * (latestHour - earliestHour)) + (self.sectionMargin.top + self.sectionMargin.bottom));
    CGFloat calendarGridMinX = (self.timeRowHeaderWidth + self.contentMargin.left);
    CGFloat calendarGridMinY = (self.dayColumnHeaderHeight + self.contentMargin.top);
    CGFloat calendarContentMinX = (self.timeRowHeaderWidth + self.contentMargin.left + self.sectionMargin.left);
    CGFloat calendarContentMinY = (self.dayColumnHeaderHeight + self.contentMargin.top + self.sectionMargin.top);
    CGFloat calendarGridWidth = (self.collectionViewContentSize.width - self.timeRowHeaderWidth - self.contentMargin.right);
    
    // Nonworking Hours
    UICollectionViewLayoutAttributes *topNonworkingHoursBackgroundAttributes = [self layoutAttributesForDecorationViewAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0] ofKind:MSCollectionElementKindNonworkingHoursBackground withItemCache:self.nonWorkingHoursBackgroundAttributes];
    CGFloat topNonWorkingHoursHeight = self.hourHeight * (self.startWorkingDay.hour + (self.startWorkingDay.minute / 60.) - earliestHour);
    topNonworkingHoursBackgroundAttributes.frame = CGRectMake(self.collectionView.contentOffset.x,
                                                              self.contentMargin.top + self.sectionMargin.top + 1,
                                                              calendarGridWidth + self.contentMargin.right,
                                                              self.contentMargin.top + self.sectionMargin.top + topNonWorkingHoursHeight);
    topNonworkingHoursBackgroundAttributes.zIndex = [self zIndexForElementKind:MSCollectionElementKindNonworkingHoursBackground];
    
    UICollectionViewLayoutAttributes *bottomNonworkingHoursBackgroundAttributes = [self layoutAttributesForDecorationViewAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:0] ofKind:MSCollectionElementKindNonworkingHoursBackground withItemCache:self.nonWorkingHoursBackgroundAttributes];
    CGFloat bottomNonWorkingHoursHeight = self.hourHeight * (latestHour - (self.endWorkingDay.hour + (self.endWorkingDay.minute / 60.)));
    bottomNonworkingHoursBackgroundAttributes.frame = CGRectMake(self.collectionView.contentOffset.x,
                                                                 self.sectionMargin.top + self.sectionMargin.bottom + sectionHeight - bottomNonWorkingHoursHeight,
                                                                 calendarGridWidth + self.contentMargin.right,
                                                                 bottomNonWorkingHoursHeight + self.sectionMargin.bottom + self.contentMargin.bottom);
    bottomNonworkingHoursBackgroundAttributes.zIndex = [self zIndexForElementKind:MSCollectionElementKindNonworkingHoursBackground];
    
    // Time Row Header
    CGFloat timeRowHeaderMinX = fmaxf(self.collectionView.contentOffset.x, 0.0);
    BOOL timeRowHeaderFloating = ((timeRowHeaderMinX != 0) || self.displayHeaderBackgroundAtOrigin);;
    
    // Time Row Header Background
    NSIndexPath *timeRowHeaderBackgroundIndexPath = [NSIndexPath indexPathForRow:0 inSection:0];
    UICollectionViewLayoutAttributes *timeRowHeaderBackgroundAttributes = [self layoutAttributesForDecorationViewAtIndexPath:timeRowHeaderBackgroundIndexPath ofKind:MSCollectionElementKindTimeRowHeaderBackground withItemCache:self.timeRowHeaderBackgroundAttributes];
    // Frame
    CGFloat timeRowHeaderBackgroundHeight = self.collectionView.frame.size.height;
    CGFloat timeRowHeaderBackgroundWidth = self.collectionView.frame.size.width;
    CGFloat timeRowHeaderBackgroundMinX = (timeRowHeaderMinX - timeRowHeaderBackgroundWidth + self.timeRowHeaderWidth);
    CGFloat timeRowHeaderBackgroundMinY = self.collectionView.contentOffset.y;
    timeRowHeaderBackgroundAttributes.frame = CGRectMake(timeRowHeaderBackgroundMinX, timeRowHeaderBackgroundMinY, timeRowHeaderBackgroundWidth, timeRowHeaderBackgroundHeight);
    
    // Floating
    timeRowHeaderBackgroundAttributes.hidden = !timeRowHeaderFloating;
    timeRowHeaderBackgroundAttributes.zIndex = [self zIndexForElementKind:MSCollectionElementKindTimeRowHeaderBackground floating:timeRowHeaderFloating];
    
    // Current Time Indicator
    NSIndexPath *currentTimeIndicatorIndexPath = [NSIndexPath indexPathForRow:0 inSection:0];
    UICollectionViewLayoutAttributes *currentTimeIndicatorAttributes = [self layoutAttributesForDecorationViewAtIndexPath:currentTimeIndicatorIndexPath ofKind:MSCollectionElementKindCurrentTimeIndicator withItemCache:self.currentTimeIndicatorAttributes];
    
    // Current Time Horizontal Gridline
    NSIndexPath *currentTimeHorizontalGridlineIndexPath = [NSIndexPath indexPathForRow:0 inSection:0];
    UICollectionViewLayoutAttributes *currentTimeHorizontalGridlineAttributes = [self layoutAttributesForDecorationViewAtIndexPath:currentTimeHorizontalGridlineIndexPath ofKind:MSCollectionElementKindCurrentTimeHorizontalGridline withItemCache:self.currentTimeHorizontalGridlineAttributes];
    currentTimeHorizontalGridlineAttributes.zIndex = [self zIndexForElementKind:MSCollectionElementKindCurrentTimeHorizontalGridline];
    
    // The current time is within the day
    NSDateComponents *currentTimeDateComponents = [self currentTimeDateComponents];
    BOOL currentTimeIndicatorVisible = ((currentTimeDateComponents.hour >= earliestHour) && (currentTimeDateComponents.hour < latestHour));
    currentTimeIndicatorAttributes.hidden = !currentTimeIndicatorVisible;
    currentTimeHorizontalGridlineAttributes.hidden = !currentTimeIndicatorVisible;
    
    if (currentTimeIndicatorVisible) {
        // The y value of the current time
        CGFloat timeY = (calendarContentMinY + nearbyintf(((currentTimeDateComponents.hour - earliestHour) * self.hourHeight) + (currentTimeDateComponents.minute * self.minuteHeight)));
        
        CGFloat currentTimeIndicatorMinY = (timeY - nearbyintf(self.currentTimeIndicatorSize.height / 2.0));
        CGFloat currentTimeIndicatorMinX = (fmaxf(self.collectionView.contentOffset.x, 0.0) + (self.timeRowHeaderWidth - self.currentTimeIndicatorSize.width));
        currentTimeIndicatorAttributes.frame = (CGRect){{currentTimeIndicatorMinX, currentTimeIndicatorMinY}, self.currentTimeIndicatorSize};
        currentTimeIndicatorAttributes.zIndex = [self zIndexForElementKind:MSCollectionElementKindCurrentTimeIndicator floating:timeRowHeaderFloating];
        
        CGFloat currentTimeHorizontalGridlineMinY = (timeY - nearbyintf(self.currentTimeHorizontalGridlineHeight / 2.0));
        CGFloat currentTimeHorizontalGridlineXOffset = (calendarGridMinX + self.sectionMargin.left);
        CGFloat currentTimeHorizontalGridlineMinX = fmaxf(currentTimeHorizontalGridlineXOffset, self.collectionView.contentOffset.x + currentTimeHorizontalGridlineXOffset);
        CGFloat currentTimehorizontalGridlineWidth = fminf(calendarGridWidth, self.collectionView.frame.size.width);
        currentTimeHorizontalGridlineAttributes.frame = CGRectMake(currentTimeHorizontalGridlineMinX, currentTimeHorizontalGridlineMinY, currentTimehorizontalGridlineWidth, self.currentTimeHorizontalGridlineHeight);
        currentTimeHorizontalGridlineAttributes.zIndex = [self zIndexForElementKind:MSCollectionElementKindCurrentTimeHorizontalGridline];
    }
    
    // Day Column Header
    CGFloat dayColumnHeaderMinY = fmaxf(self.collectionView.contentOffset.y, 0.0);
    BOOL dayColumnHeaderFloating = ((dayColumnHeaderMinY != 0) || self.displayHeaderBackgroundAtOrigin);
    
    // Day Column Header Background
    NSIndexPath *dayColumnHeaderBackgroundIndexPath = [NSIndexPath indexPathForRow:0 inSection:0];
    UICollectionViewLayoutAttributes *dayColumnHeaderBackgroundAttributes = [self layoutAttributesForDecorationViewAtIndexPath:dayColumnHeaderBackgroundIndexPath ofKind:MSCollectionElementKindDayColumnHeaderBackground withItemCache:self.dayColumnHeaderBackgroundAttributes];
    // Frame
    CGFloat dayColumnHeaderBackgroundHeight = (self.dayColumnHeaderHeight + ((self.collectionView.contentOffset.y < 0.0) ? ABS(self.collectionView.contentOffset.y) : 0.0));
    dayColumnHeaderBackgroundAttributes.frame = (CGRect){self.collectionView.contentOffset, {self.collectionView.frame.size.width, dayColumnHeaderBackgroundHeight}};
    // Floating
    dayColumnHeaderBackgroundAttributes.hidden = !dayColumnHeaderFloating;
    dayColumnHeaderBackgroundAttributes.zIndex = [self zIndexForElementKind:MSCollectionElementKindDayColumnHeaderBackground floating:dayColumnHeaderFloating];
    
    // Time Row Headers
    NSUInteger timeRowHeaderIndex = 0;
    for (NSInteger hour = earliestHour; hour <= latestHour; hour++) {
        NSIndexPath *timeRowHeaderIndexPath = [NSIndexPath indexPathForItem:timeRowHeaderIndex inSection:0];
        UICollectionViewLayoutAttributes *timeRowHeaderAttributes = [self layoutAttributesForSupplementaryViewAtIndexPath:timeRowHeaderIndexPath ofKind:MSCollectionElementKindTimeRowHeader withItemCache:self.timeRowHeaderAttributes];
        CGFloat titleRowHeaderMinY = (calendarContentMinY + (self.hourHeight * (hour - earliestHour)) - nearbyintf(self.hourHeight / 2.0));
        timeRowHeaderAttributes.frame = CGRectMake(timeRowHeaderMinX, titleRowHeaderMinY, self.timeRowHeaderWidth, self.hourHeight);
        timeRowHeaderAttributes.zIndex = [self zIndexForElementKind:MSCollectionElementKindTimeRowHeader floating:timeRowHeaderFloating];
        CGFloat titleHeight = 20;
        CGRect titleFrame = timeRowHeaderAttributes.frame;
        titleFrame.size.height = titleHeight;
        titleFrame.origin.y = timeRowHeaderAttributes.center.y - (titleHeight / 2);
        timeRowHeaderAttributes.hidden = CGRectIntersectsRect(titleFrame, currentTimeIndicatorAttributes.frame);
        timeRowHeaderIndex++;
    }
    
    NSUInteger timeRowHeaderMinutesIndex = 0;
    for (NSInteger i = earliestHour; i < latestHour * 3; ++i) {
        NSIndexPath *timeRowHeaderMinutesIndexPath = [NSIndexPath indexPathForItem:timeRowHeaderMinutesIndex inSection:0];
        UICollectionViewLayoutAttributes *timeRowHeaderMinutesAttributes = [self layoutAttributesForSupplementaryViewAtIndexPath:timeRowHeaderMinutesIndexPath ofKind:MSCollectionElementKindTimeRowHeaderMinutes withItemCache:self.timeRowHeaderMinutesAttributes];
        CGFloat titleRowHeaderMinY = calendarContentMinY + (self.hourHeight * (int)(i / 3)) - nearbyintf(self.hourHeight / 2.0);
        titleRowHeaderMinY += ((i % 3) + 1) * nearbyintf(self.hourHeight / 4.0);
        timeRowHeaderMinutesAttributes.frame = CGRectMake(timeRowHeaderMinX, titleRowHeaderMinY, self.timeRowHeaderWidth, self.hourHeight);
        timeRowHeaderMinutesAttributes.zIndex = [self zIndexForElementKind:MSCollectionElementKindTimeRowHeader floating:timeRowHeaderFloating];
        if (self.currentView) {
            CGFloat titleHeight = 20;
            CGRect titleFrame = timeRowHeaderMinutesAttributes.frame;
            titleFrame.size.height = titleHeight;
            titleFrame.origin.y = timeRowHeaderMinutesAttributes.center.y - (titleHeight / 2);
            timeRowHeaderMinutesAttributes.hidden = CGRectIntersectsRect(titleFrame, currentTimeIndicatorAttributes.frame) || CGRectGetMinY(titleFrame) >= self.currentView.frame.origin.y || CGRectGetMaxY(titleFrame) <= self.currentView.frame.origin.y;
        }
        else {
            timeRowHeaderMinutesAttributes.hidden = YES;
        }
        timeRowHeaderMinutesIndex++;
    }
    
    [sectionIndexes enumerateIndexesUsingBlock:^(NSUInteger section, BOOL *stop) {
        
        CGFloat sectionMinX = (calendarContentMinX + (sectionWidth * section));
        
        // Day Column Header
        UICollectionViewLayoutAttributes *dayColumnHeaderAttributes = [self layoutAttributesForSupplementaryViewAtIndexPath:[NSIndexPath indexPathForItem:0 inSection:section] ofKind:MSCollectionElementKindDayColumnHeader withItemCache:self.dayColumnHeaderAttributes];
        dayColumnHeaderAttributes.frame = CGRectMake(sectionMinX, dayColumnHeaderMinY, self.sectionWidth, self.dayColumnHeaderHeight);
        dayColumnHeaderAttributes.zIndex = [self zIndexForElementKind:MSCollectionElementKindDayColumnHeader floating:dayColumnHeaderFloating];
        
        if (needsToPopulateVerticalGridlineAttributes) {
            // Vertical Gridline
            NSIndexPath *verticalGridlineIndexPath = [NSIndexPath indexPathForItem:0 inSection:section];
            UICollectionViewLayoutAttributes *horizontalGridlineAttributes = [self layoutAttributesForDecorationViewAtIndexPath:verticalGridlineIndexPath ofKind:MSCollectionElementKindVerticalGridline withItemCache:self.verticalGridlineAttributes];
            CGFloat horizontalGridlineMinX = nearbyintf(sectionMinX - self.sectionMargin.left - (self.verticalGridlineWidth / 2.0));
            horizontalGridlineAttributes.frame = CGRectMake(horizontalGridlineMinX, calendarGridMinY, self.verticalGridlineWidth, sectionHeight);
            horizontalGridlineAttributes.zIndex = [self zIndexForElementKind:MSCollectionElementKindVerticalGridline];
        }
        
        if (needsToPopulateItemAttributes) {
            // Items
            NSMutableArray *sectionItemAttributes = [NSMutableArray new];
            for (NSInteger item = 0; item < [self.collectionView numberOfItemsInSection:section]; item++) {
                
                NSIndexPath *itemIndexPath = [NSIndexPath indexPathForItem:item inSection:section];
                UICollectionViewLayoutAttributes *itemAttributes = [self layoutAttributesForCellAtIndexPath:itemIndexPath withItemCache:self.itemAttributes];
                [sectionItemAttributes addObject:itemAttributes];
                
                NSDateComponents *itemStartTime = [self startTimeForIndexPath:itemIndexPath];
                NSDateComponents *itemEndTime = [self endTimeForIndexPath:itemIndexPath];
                
                CGFloat startHourY = ((itemStartTime.hour - earliestHour) * self.hourHeight);
                CGFloat startMinuteY = (itemStartTime.minute * self.minuteHeight);
                
                CGFloat endHourY;
                if (itemEndTime.day != itemStartTime.day) {
                    endHourY = (([[NSCalendar currentCalendar] maximumRangeOfUnit:NSCalendarUnitHour].length - earliestHour) * self.hourHeight) + (itemEndTime.hour * self.hourHeight);
                } else {
                    endHourY = ((itemEndTime.hour - earliestHour) * self.hourHeight);
                }
                CGFloat endMinuteY = (itemEndTime.minute * self.minuteHeight);
                
                CGFloat itemMinY = nearbyintf(startHourY + startMinuteY + calendarContentMinY + self.cellMargin.top);
                CGFloat itemMaxY = nearbyintf(endHourY + endMinuteY + calendarContentMinY - self.cellMargin.bottom);
                CGFloat itemMinX = nearbyintf(sectionMinX + self.cellMargin.left);
                CGFloat itemMaxX = nearbyintf(itemMinX + (self.sectionWidth - (self.cellMargin.left + self.cellMargin.right)));
                itemAttributes.frame = CGRectMake(itemMinX, itemMinY, (itemMaxX - itemMinX), (itemMaxY - itemMinY));
                
                itemAttributes.zIndex = [self zIndexForElementKind:nil];
            }
            [self adjustItemsForOverlap:sectionItemAttributes inSection:section sectionMinX:sectionMinX];
        }
    }];
    
    // Horizontal Gridlines
    NSUInteger horizontalGridlineIndex = 0;
    for (NSInteger hour = earliestHour; hour <= latestHour; hour++) {
        NSIndexPath *horizontalGridlineIndexPath = [NSIndexPath indexPathForItem:horizontalGridlineIndex inSection:0];
        UICollectionViewLayoutAttributes *horizontalGridlineAttributes = [self layoutAttributesForDecorationViewAtIndexPath:horizontalGridlineIndexPath ofKind:MSCollectionElementKindHorizontalGridline withItemCache:self.horizontalGridlineAttributes];
        CGFloat horizontalGridlineMinY = nearbyintf(calendarContentMinY + (self.hourHeight * (hour - earliestHour))) - (self.horizontalGridlineHeight / 2.0);
        
        CGFloat horizontalGridlineXOffset = (calendarGridMinX + self.sectionMargin.left);
        CGFloat horizontalGridlineMinX = fmaxf(horizontalGridlineXOffset, self.collectionView.contentOffset.x + horizontalGridlineXOffset);
        CGFloat horizontalGridlineWidth = fminf(calendarGridWidth, self.collectionView.frame.size.width);
        horizontalGridlineAttributes.frame = CGRectMake(horizontalGridlineMinX, horizontalGridlineMinY, horizontalGridlineWidth, self.horizontalGridlineHeight);
        horizontalGridlineAttributes.zIndex = [self zIndexForElementKind:MSCollectionElementKindHorizontalGridline];
        horizontalGridlineIndex++;
    }
}

- (void)adjustItemsForOverlap:(NSArray *)sectionItemAttributes inSection:(NSUInteger)section sectionMinX:(CGFloat)sectionMinX
{
    NSMutableSet *adjustedAttributes = [NSMutableSet new];
    NSUInteger sectionZ = MSCollectionMinCellZ;
    
    for (UICollectionViewLayoutAttributes *itemAttributes in sectionItemAttributes) {
        
        // If an item's already been adjusted, move on to the next one
        if ([adjustedAttributes containsObject:itemAttributes]) {
            continue;
        }
        
        // Find the other items that overlap with this item
        NSMutableArray *overlappingItems = [NSMutableArray new];
        CGRect itemFrame = itemAttributes.frame;
        [overlappingItems addObjectsFromArray:[sectionItemAttributes filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(UICollectionViewLayoutAttributes *layoutAttributes, NSDictionary *bindings) {
            if ((layoutAttributes != itemAttributes)) {
                return CGRectIntersectsRect(itemFrame, layoutAttributes.frame);
            } else {
                return NO;
            }
        }]]];
        
        // If there's items overlapping, we need to adjust them
        if (overlappingItems.count) {
            
            // Add the item we're adjusting to the overlap set
            [overlappingItems insertObject:itemAttributes atIndex:0];
            
            // Find the minY and maxY of the set
            CGFloat minY = CGFLOAT_MAX;
            CGFloat maxY = CGFLOAT_MIN;
            for (UICollectionViewLayoutAttributes *overlappingItemAttributes in overlappingItems) {
                if (CGRectGetMinY(overlappingItemAttributes.frame) < minY) {
                    minY = CGRectGetMinY(overlappingItemAttributes.frame);
                }
                if (CGRectGetMaxY(overlappingItemAttributes.frame) > maxY) {
                    maxY = CGRectGetMaxY(overlappingItemAttributes.frame);
                }
            }
            
            // Determine the number of divisions needed (maximum number of currently overlapping items)
            NSInteger divisions = 1;
            for (CGFloat currentY = minY; currentY <= maxY; currentY += 1.0) {
                NSInteger numberItemsForCurrentY = 0;
                for (UICollectionViewLayoutAttributes *overlappingItemAttributes in overlappingItems) {
                    if ((currentY >= CGRectGetMinY(overlappingItemAttributes.frame)) && (currentY < CGRectGetMaxY(overlappingItemAttributes.frame))) {
                        numberItemsForCurrentY++;
                    }
                }
                if (numberItemsForCurrentY > divisions) {
                    divisions = numberItemsForCurrentY;
                }
            }
            
            // Adjust the items to have a width of the section size divided by the number of divisions needed
            CGFloat divisionWidth = nearbyintf(self.sectionWidth / divisions);
            
            NSMutableArray *dividedAttributes = [NSMutableArray array];
            for (UICollectionViewLayoutAttributes *divisionAttributes in overlappingItems) {
                
                CGFloat itemWidth = (divisionWidth - self.cellMargin.left - self.cellMargin.right);
                
                // It it hasn't yet been adjusted, perform adjustment
                if (![adjustedAttributes containsObject:divisionAttributes]) {
                    
                    CGRect divisionAttributesFrame = divisionAttributes.frame;
                    divisionAttributesFrame.origin.x = (sectionMinX + self.cellMargin.left);
                    divisionAttributesFrame.size.width = itemWidth;
                    
                    // Horizontal Layout
                    NSInteger adjustments = 1;
                    for (UICollectionViewLayoutAttributes *dividedItemAttributes in dividedAttributes) {
                        if (CGRectIntersectsRect(dividedItemAttributes.frame, divisionAttributesFrame)) {
                            divisionAttributesFrame.origin.x = sectionMinX + ((divisionWidth * adjustments) + self.cellMargin.left);
                            adjustments++;
                        }
                    }
                    
                    // Stacking (lower items stack above higher items, since the title is at the top)
                    divisionAttributes.zIndex = sectionZ;
                    sectionZ ++;
                    
                    divisionAttributes.frame = divisionAttributesFrame;
                    [dividedAttributes addObject:divisionAttributes];
                    [adjustedAttributes addObject:divisionAttributes];
                }
            }
        }
    }
}

- (CGSize)collectionViewContentSize
{
    CGFloat height = [self maxSectionHeight];
    CGFloat width = (self.timeRowHeaderWidth + self.contentMargin.left + ((self.sectionMargin.left + self.sectionWidth + self.sectionMargin.right) * self.collectionView.numberOfSections) + self.contentMargin.right);
    return CGSizeMake(width, height);
}

- (UICollectionViewLayoutAttributes *)layoutAttributesForItemAtIndexPath:(NSIndexPath *)indexPath
{
    return self.itemAttributes[indexPath];
}

- (UICollectionViewLayoutAttributes *)layoutAttributesForSupplementaryViewOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)indexPath
{
    if (kind == MSCollectionElementKindDayColumnHeader) {
        return self.dayColumnHeaderAttributes[indexPath];
    }
    else if (kind == MSCollectionElementKindTimeRowHeader) {
        return self.timeRowHeaderAttributes[indexPath];
    }
    else if (kind == MSCollectionElementKindTimeRowHeaderMinutes) {
        return self.timeRowHeaderMinutesAttributes[indexPath];
    }
    return nil;
}

- (UICollectionViewLayoutAttributes *)layoutAttributesForDecorationViewOfKind:(NSString *)decorationViewKind atIndexPath:(NSIndexPath *)indexPath
{
    if (decorationViewKind == MSCollectionElementKindCurrentTimeIndicator) {
        return self.currentTimeIndicatorAttributes[indexPath];
    }
    else if (decorationViewKind == MSCollectionElementKindCurrentTimeHorizontalGridline) {
        return self.currentTimeHorizontalGridlineAttributes[indexPath];
    }
    else if (decorationViewKind == MSCollectionElementKindVerticalGridline) {
        return self.verticalGridlineAttributes[indexPath];
    }
    else if (decorationViewKind == MSCollectionElementKindHorizontalGridline) {
        return self.horizontalGridlineAttributes[indexPath];
    }
    else if (decorationViewKind == MSCollectionElementKindTimeRowHeaderBackground) {
        return self.timeRowHeaderBackgroundAttributes[indexPath];
    }
    else if (decorationViewKind == MSCollectionElementKindDayColumnHeader) {
        return self.dayColumnHeaderBackgroundAttributes[indexPath];
    }
    else if (decorationViewKind == MSCollectionElementKindNonworkingHoursBackground) {
        return self.nonWorkingHoursBackgroundAttributes[indexPath];
    }
    return nil;
}

- (NSArray *)layoutAttributesForElementsInRect:(CGRect)rect
{
    NSMutableIndexSet *visibleSections = [NSMutableIndexSet indexSet];
    [[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, self.collectionView.numberOfSections)] enumerateIndexesUsingBlock:^(NSUInteger section, BOOL *stop) {
        CGRect sectionRect = [self rectForSection:section];
        if (CGRectIntersectsRect(sectionRect, rect)) {
            [visibleSections addIndex:section];
        }
    }];
    
    // Update layout for only the visible sections
    [self prepareSectionLayoutForSections:visibleSections];
    
    // Return the visible attributes (rect intersection)
    return [self.allAttributes filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(UICollectionViewLayoutAttributes *layoutAttributes, NSDictionary *bindings) {
        return CGRectIntersectsRect(rect, layoutAttributes.frame);
    }]];
}

- (BOOL)shouldInvalidateLayoutForBoundsChange:(CGRect)newBounds
{
    // Required for sticky headers
    return YES;
}

#pragma mark - MSCollectionViewCalendarLayout

- (void)initialize
{
    self.needsToPopulateAttributesForAllSections = YES;
    self.cachedDayDateComponents = [NSCache new];
    self.cachedStartTimeDateComponents = [NSCache new];
    self.cachedEndTimeDateComponents = [NSCache new];
    self.cachedCurrentDateComponents = [NSCache new];
    self.cachedMaxColumnHeight = CGFLOAT_MIN;
    self.cachedEarliestHour = NSIntegerMax;
    self.cachedLatestHour = NSIntegerMin;
    self.cachedColumnHeights = [NSMutableDictionary new];
    self.cachedEarliestHours = [NSMutableDictionary new];
    self.cachedLatestHours = [NSMutableDictionary new];
    
    self.registeredDecorationClasses = [NSMutableDictionary new];
    
    self.allAttributes = [NSMutableArray new];
    self.itemAttributes = [NSMutableDictionary new];
    self.dayColumnHeaderAttributes = [NSMutableDictionary new];
    self.dayColumnHeaderBackgroundAttributes = [NSMutableDictionary new];
    self.timeRowHeaderAttributes = [NSMutableDictionary new];
    self.timeRowHeaderMinutesAttributes = [NSMutableDictionary new];
    self.timeRowHeaderBackgroundAttributes = [NSMutableDictionary new];
    self.verticalGridlineAttributes = [NSMutableDictionary new];
    self.horizontalGridlineAttributes = [NSMutableDictionary new];
    self.currentTimeIndicatorAttributes = [NSMutableDictionary new];
    self.currentTimeHorizontalGridlineAttributes = [NSMutableDictionary new];
    self.nonWorkingHoursBackgroundAttributes = [NSMutableDictionary new];
    
    self.hourHeight = 80.0;
    self.sectionWidth = 100.0;
    self.dayColumnHeaderHeight = 60.0;
    self.timeRowHeaderWidth = 56.0;
    self.currentTimeIndicatorSize = CGSizeMake(self.timeRowHeaderWidth, 10.0);
    self.currentTimeHorizontalGridlineHeight = 1.0;
    self.verticalGridlineWidth = (([[UIScreen mainScreen] scale] == 2.0) ? 0.5 : 1.0);
    self.horizontalGridlineHeight = (([[UIScreen mainScreen] scale] == 2.0) ? 0.5 : 1.0);;
    self.sectionMargin = UIEdgeInsetsMake(30.0, 0.0, 30.0, 0.0);
    self.cellMargin = UIEdgeInsetsMake(0.0, 0.0, 0.0, 0.0);
    self.contentMargin = UIEdgeInsetsMake(30.0, 0.0, 30.0, 30.0);
    
    self.displayHeaderBackgroundAtOrigin = YES;
    self.headerLayoutType = MSHeaderLayoutTypeDayColumnAboveTimeRow;
    
    // Invalidate layout on minute ticks (to update the position of the current time indicator)
    NSDate *oneMinuteInFuture = [[NSDate date] dateByAddingTimeInterval:60];
    NSDateComponents *components = [[NSCalendar currentCalendar] components:(NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute) fromDate:oneMinuteInFuture];
    NSDate *nextMinuteBoundary = [[NSCalendar currentCalendar] dateFromComponents:components];
    
    // This needs to be a weak reference, otherwise we get a retain cycle
    MSTimerWeakTarget *timerWeakTarget = [[MSTimerWeakTarget alloc] initWithTarget:self selector:@selector(minuteTick:)];
    self.minuteTimer = [[NSTimer alloc] initWithFireDate:nextMinuteBoundary interval:60 target:timerWeakTarget selector:timerWeakTarget.fireSelector userInfo:nil repeats:YES];
    [[NSRunLoop currentRunLoop] addTimer:self.minuteTimer forMode:NSDefaultRunLoopMode];
    
    // Useful in multiple scenarios: one common scenario being when the Notification Center drawer is pulled down
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleApplicationWillResignActive:) name: UIApplicationWillResignActiveNotification object:nil];
    [self addObserver:self forKeyPath:kLXCollectionViewKeyPath options:NSKeyValueObservingOptionNew context:nil];
}

- (void)setupCollectionView {
    _longPressGestureRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                                                action:@selector(handleLongPressGesture:)];
    _longPressGestureRecognizer.delegate = self;
    
    // Links the default long press gesture recognizer to the custom long press gesture recognizer we are creating now
    // by enforcing failure dependency so that they doesn't clash.
    for (UIGestureRecognizer *gestureRecognizer in self.collectionView.gestureRecognizers) {
        if ([gestureRecognizer isKindOfClass:[UILongPressGestureRecognizer class]]) {
            [gestureRecognizer requireGestureRecognizerToFail:_longPressGestureRecognizer];
        }
    }
    
    [self.collectionView addGestureRecognizer:_longPressGestureRecognizer];
    
    _panGestureRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self
                                                                    action:@selector(handlePanGesture:)];
    _panGestureRecognizer.delegate = self;
    [self.collectionView addGestureRecognizer:_panGestureRecognizer];
    [self setDefaults];
}

- (void)tearDownCollectionView {
    // Tear down long press gesture
    if (_longPressGestureRecognizer) {
        UIView *view = _longPressGestureRecognizer.view;
        if (view) {
            [view removeGestureRecognizer:_longPressGestureRecognizer];
        }
        _longPressGestureRecognizer.delegate = nil;
        _longPressGestureRecognizer = nil;
    }
    
    // Tear down pan gesture
    if (_panGestureRecognizer) {
        UIView *view = _panGestureRecognizer.view;
        if (view) {
            [view removeGestureRecognizer:_panGestureRecognizer];
        }
        _panGestureRecognizer.delegate = nil;
        _panGestureRecognizer = nil;
    }
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationWillResignActiveNotification object:nil];
}

#pragma mark Minute Updates

- (void)minuteTick:(id)sender
{
    // Invalidate cached current date componets (since the minute's changed!)
    [self.cachedCurrentDateComponents removeAllObjects];
    [self invalidateLayout];
}

#pragma mark - Layout

- (UICollectionViewLayoutAttributes *)layoutAttributesForDecorationViewAtIndexPath:(NSIndexPath *)indexPath ofKind:(NSString *)kind withItemCache:(NSMutableDictionary *)itemCache
{
    UICollectionViewLayoutAttributes *layoutAttributes;
    if (self.registeredDecorationClasses[kind] && !(layoutAttributes = itemCache[indexPath])) {
        layoutAttributes = [UICollectionViewLayoutAttributes layoutAttributesForDecorationViewOfKind:kind withIndexPath:indexPath];
        itemCache[indexPath] = layoutAttributes;
    }
    return layoutAttributes;
}

- (UICollectionViewLayoutAttributes *)layoutAttributesForSupplementaryViewAtIndexPath:(NSIndexPath *)indexPath ofKind:(NSString *)kind withItemCache:(NSMutableDictionary *)itemCache
{
    UICollectionViewLayoutAttributes *layoutAttributes;
    if (!(layoutAttributes = itemCache[indexPath])) {
        layoutAttributes = [UICollectionViewLayoutAttributes layoutAttributesForSupplementaryViewOfKind:kind withIndexPath:indexPath];
        itemCache[indexPath] = layoutAttributes;
    }
    return layoutAttributes;
}

- (UICollectionViewLayoutAttributes *)layoutAttributesForCellAtIndexPath:(NSIndexPath *)indexPath withItemCache:(NSMutableDictionary *)itemCache
{
    UICollectionViewLayoutAttributes *layoutAttributes;
    if (!(layoutAttributes = itemCache[indexPath])) {
        layoutAttributes = [UICollectionViewLayoutAttributes layoutAttributesForCellWithIndexPath:indexPath];
        itemCache[indexPath] = layoutAttributes;
    }
    return layoutAttributes;
}

- (void)invalidateLayoutCache
{
    self.needsToPopulateAttributesForAllSections = YES;
    
    // Invalidate cached Components
    [self.cachedDayDateComponents removeAllObjects];
    [self.cachedStartTimeDateComponents removeAllObjects];
    [self.cachedEndTimeDateComponents removeAllObjects];
    [self.cachedCurrentDateComponents removeAllObjects];
    
    // Invalidate cached interface sizing values
    self.cachedEarliestHour = NSIntegerMax;
    self.cachedLatestHour = NSIntegerMin;
    self.cachedMaxColumnHeight = CGFLOAT_MIN;
    [self.cachedColumnHeights removeAllObjects];
    [self.cachedEarliestHours removeAllObjects];
    [self.cachedLatestHours removeAllObjects];
    
    // Invalidate cached item attributes
    [self.itemAttributes removeAllObjects];
    [self.verticalGridlineAttributes removeAllObjects];
    [self.horizontalGridlineAttributes removeAllObjects];
    [self.dayColumnHeaderAttributes removeAllObjects];
    [self.dayColumnHeaderBackgroundAttributes removeAllObjects];
    [self.timeRowHeaderAttributes removeAllObjects];
    [self.timeRowHeaderMinutesAttributes removeAllObjects];
    [self.timeRowHeaderBackgroundAttributes removeAllObjects];
    [self.allAttributes removeAllObjects];
}

#pragma mark Dates

- (NSDate *)dateForTimeRowHeaderAtIndexPath:(NSIndexPath *)indexPath
{
    NSInteger earliestHour = [self earliestHour];
    NSDateComponents *dateComponents = [self dayForSection:indexPath.section];
    dateComponents.hour = (earliestHour + indexPath.item);
    return [[NSCalendar currentCalendar] dateFromComponents:dateComponents];
}

- (NSDate *)dateForDayColumnHeaderAtIndexPath:(NSIndexPath *)indexPath
{
    NSDate *day = [self.delegate collectionView:self.collectionView layout:self dayForSection:indexPath.section];
    return [[NSCalendar currentCalendar] startOfDayForDate:day];
}

#pragma mark Scrolling

- (void)scrollCollectionViewToClosetSectionToCurrentTimeAnimated:(BOOL)animated
{
    if (self.collectionView.numberOfSections != 0) {
        NSInteger closestSectionToCurrentTime = [self closestSectionToCurrentTime];
        CGRect currentTimeHorizontalGridlineattributesFrame = [self.currentTimeHorizontalGridlineAttributes[[NSIndexPath indexPathForItem:0 inSection:0]] frame];
            CGFloat yOffset;
        if (!CGRectEqualToRect(currentTimeHorizontalGridlineattributesFrame, CGRectZero)) {
            yOffset = nearbyintf(CGRectGetMinY(currentTimeHorizontalGridlineattributesFrame) - (CGRectGetHeight(self.collectionView.frame) / 2.0));
        } else {
            yOffset = 0.0;
        }
        CGFloat xOffset = self.contentMargin.left + ((self.sectionMargin.left + self.sectionWidth + self.sectionMargin.right) * closestSectionToCurrentTime);
        CGPoint contentOffset = CGPointMake(xOffset, yOffset);
        // Prevent the content offset from forcing the scroll view content off its bounds
        if (contentOffset.y > (self.collectionView.contentSize.height - self.collectionView.frame.size.height)) {
            contentOffset.y = (self.collectionView.contentSize.height - self.collectionView.frame.size.height);
        }
        if (contentOffset.y < 0.0) {
            contentOffset.y = 0.0;
        }
        if (contentOffset.x > (self.collectionView.contentSize.width - self.collectionView.frame.size.width)) {
            contentOffset.x = (self.collectionView.contentSize.width - self.collectionView.frame.size.width);
        }
        if (contentOffset.x < 0.0) {
            contentOffset.x = 0.0;
        }
        [self.collectionView setContentOffset:contentOffset animated:animated];
    }
}

- (NSInteger)closestSectionToCurrentTime
{
    NSDate *currentTime = [self.delegate currentTimeComponentsForCollectionView:self.collectionView layout:self];
    NSDate *startOfCurrentDay = [[NSCalendar currentCalendar] startOfDayForDate:currentTime];
    
    NSTimeInterval minTimeInterval = CGFLOAT_MAX;
    NSInteger closestSection = NSIntegerMax;
    for (NSInteger section = 0; section < self.collectionView.numberOfSections; section++) {
        NSDate *sectionDayDate = [self.delegate collectionView:self.collectionView layout:self dayForSection:section];
        NSTimeInterval timeInterval = [startOfCurrentDay timeIntervalSinceDate:sectionDayDate];
        if ((timeInterval <= 0) && ABS(timeInterval) < minTimeInterval) {
            minTimeInterval = ABS(timeInterval);
            closestSection = section;
        }
    }
    return ((closestSection != NSIntegerMax) ? closestSection : 0);
}

#pragma mark Section Sizing

- (CGRect)rectForSection:(NSInteger)section
{
    CGFloat calendarGridMinX = (self.timeRowHeaderWidth + self.contentMargin.left);
    CGFloat sectionWidth = (self.sectionMargin.left + self.sectionWidth + self.sectionMargin.right);
    CGFloat sectionMinX = (calendarGridMinX + self.sectionMargin.left + (sectionWidth * section));
    CGRect sectionRect = CGRectMake(sectionMinX, 0.0, sectionWidth, self.collectionViewContentSize.height);
    return sectionRect;
}

- (CGFloat)maxSectionHeight
{
    if (self.cachedMaxColumnHeight != CGFLOAT_MIN) {
        return self.cachedMaxColumnHeight;
    }
    CGFloat maxSectionHeight = 0.0;
    for (NSInteger section = 0; section < self.collectionView.numberOfSections; section++) {
        
        NSInteger earliestHour = [self earliestHour];
        NSInteger latestHour = [self latestHourForSection:section];
        CGFloat sectionColumnHeight;
        if ((earliestHour != NSDateComponentUndefined) && (latestHour != NSDateComponentUndefined)) {
            sectionColumnHeight = (self.hourHeight * (latestHour - earliestHour));
        } else {
            sectionColumnHeight = 0.0;
        }
        
        if (sectionColumnHeight > maxSectionHeight) {
            maxSectionHeight = sectionColumnHeight;
        }
    }
    CGFloat headerAdjustedMaxColumnHeight = (self.dayColumnHeaderHeight + self.contentMargin.top + self.sectionMargin.top + maxSectionHeight + self.sectionMargin.bottom + self.contentMargin.bottom);
    if (maxSectionHeight != 0.0) {
        self.cachedMaxColumnHeight = headerAdjustedMaxColumnHeight;
        return headerAdjustedMaxColumnHeight;
    } else {
        return headerAdjustedMaxColumnHeight;
    }
}

- (CGFloat)stackedSectionHeight
{
    return [self stackedSectionHeightUpToSection:self.collectionView.numberOfSections];
}

- (CGFloat)stackedSectionHeightUpToSection:(NSInteger)upToSection
{
    if (self.cachedColumnHeights[@(upToSection)]) {
        return [self.cachedColumnHeights[@(upToSection)] integerValue];
    }
    CGFloat stackedSectionHeight = 0.0;
    for (NSInteger section = 0; section < upToSection; section++) {
        CGFloat sectionColumnHeight = [self sectionHeight:section];
        stackedSectionHeight += sectionColumnHeight;
    }
    CGFloat headerAdjustedStackedColumnHeight = (stackedSectionHeight + ((self.dayColumnHeaderHeight + self.contentMargin.top + self.contentMargin.bottom) * upToSection));
    if (stackedSectionHeight != 0.0) {
        self.cachedColumnHeights[@(upToSection)] = @(headerAdjustedStackedColumnHeight);
        return headerAdjustedStackedColumnHeight;
    } else {
        return headerAdjustedStackedColumnHeight;
    }
}

- (CGFloat)sectionHeight:(NSInteger)section
{
    NSInteger earliestHour = [self earliestHourForSection:section];
    NSInteger latestHour = [self latestHourForSection:section];
    
    if ((earliestHour != NSDateComponentUndefined) && (latestHour != NSDateComponentUndefined)) {
        return (self.hourHeight * (latestHour - earliestHour));
    } else {
        return 0.0;
    }
}

- (CGFloat)minuteHeight
{
    return (self.hourHeight / 60.0);
}

#pragma mark Z Index

- (CGFloat)zIndexForElementKind:(NSString *)elementKind
{
    return [self zIndexForElementKind:elementKind floating:NO];
}

- (CGFloat)zIndexForElementKind:(NSString *)elementKind floating:(BOOL)floating
{
    // Current Time Indicator
    if (elementKind == MSCollectionElementKindCurrentTimeIndicator) {
        return (MSCollectionMinOverlayZ + ((self.headerLayoutType == MSHeaderLayoutTypeTimeRowAboveDayColumn) ? (floating ? 9.0 : 4.0) : (floating ? 7.0 : 2.0)));
    }
    // Time Row Header
    else if (elementKind == MSCollectionElementKindTimeRowHeader) {
        return (MSCollectionMinOverlayZ + ((self.headerLayoutType == MSHeaderLayoutTypeTimeRowAboveDayColumn) ? (floating ? 8.0 : 3.0) : (floating ? 6.0 : 1.0)));
    }
    // Time Row Header Background
    else if (elementKind == MSCollectionElementKindTimeRowHeaderBackground) {
        return (MSCollectionMinOverlayZ + ((self.headerLayoutType == MSHeaderLayoutTypeTimeRowAboveDayColumn) ? (floating ? 7.0 : 2.0) : (floating ? 5.0 : 0.0)));
    }
    // Day Column Header
    else if (elementKind == MSCollectionElementKindDayColumnHeader) {
        return (MSCollectionMinOverlayZ + ((self.headerLayoutType == MSHeaderLayoutTypeTimeRowAboveDayColumn) ? (floating ? 6.0 : 1.0) : (floating ? 9.0 : 4.0)));
    }
    // Day Column Header Background
    else if (elementKind == MSCollectionElementKindDayColumnHeaderBackground) {
        return (MSCollectionMinOverlayZ + ((self.headerLayoutType == MSHeaderLayoutTypeTimeRowAboveDayColumn) ? (floating ? 5.0 : 0.0) : (floating ? 8.0 : 3.0)));
    }
    // Cell
    else if (elementKind == nil) {
        return MSCollectionMinCellZ;
    }
    // Current Time Horizontal Gridline
    else if (elementKind == MSCollectionElementKindCurrentTimeHorizontalGridline) {
        return (MSCollectionMinBackgroundZ + 3.0);
    }
    // Vertical Gridline
    else if (elementKind == MSCollectionElementKindVerticalGridline) {
        return (MSCollectionMinBackgroundZ + 2.0);
    }
    // Horizontal Gridline
    else if (elementKind == MSCollectionElementKindHorizontalGridline) {
        return MSCollectionMinBackgroundZ + 1.0;
    }
    else if (elementKind == MSCollectionElementKindNonworkingHoursBackground) {
        return MSCollectionMinBackgroundZ;
    }
    return CGFLOAT_MIN;
}

#pragma mark Hours

- (NSInteger)earliestHour
{
    return 0;
    if (self.cachedEarliestHour != NSIntegerMax) {
        return self.cachedEarliestHour;
    }
    NSInteger earliestHour = NSIntegerMax;
    for (NSInteger section = 0; section < self.collectionView.numberOfSections; section++) {
        CGFloat sectionEarliestHour = [self earliestHourForSection:section];
        if ((sectionEarliestHour < earliestHour) && (sectionEarliestHour != NSDateComponentUndefined)) {
            earliestHour = sectionEarliestHour;
        }
    }
    if (earliestHour != NSIntegerMax) {
        self.cachedEarliestHour = earliestHour;
        return earliestHour;
    } else {
        return 0;
    }
}

- (NSInteger)latestHour
{
    return 24;
    if (self.cachedLatestHour != NSIntegerMin) {
        return self.cachedLatestHour;
    }
    NSInteger latestHour = NSIntegerMin;
    for (NSInteger section = 0; section < self.collectionView.numberOfSections; section++) {
        CGFloat sectionLatestHour = [self latestHourForSection:section];
        if ((sectionLatestHour > latestHour) && (sectionLatestHour != NSDateComponentUndefined)) {
            latestHour = sectionLatestHour;
        }
    }
    if (latestHour != NSIntegerMin) {
        self.cachedLatestHour = latestHour;
        return latestHour;
    } else {
        return 0;
    }
}

- (NSInteger)earliestHourForSection:(NSInteger)section
{
    return 0;
    if (self.cachedEarliestHours[@(section)]) {
        return [self.cachedEarliestHours[@(section)] integerValue];
    }
    NSInteger earliestHour = NSIntegerMax;
    for (NSInteger item = 0; item < [self.collectionView numberOfItemsInSection:section]; item++) {
        NSIndexPath *itemIndexPath = [NSIndexPath indexPathForItem:item inSection:section];
        NSDateComponents *itemStartTime = [self startTimeForIndexPath:itemIndexPath];
        if (itemStartTime.hour < earliestHour) {
            earliestHour = itemStartTime.hour;
        }
    }
    if (earliestHour != NSIntegerMax) {
        self.cachedEarliestHours[@(section)] = @(earliestHour);
        return earliestHour;
    } else {
        return 0;
    }
}

- (NSInteger)latestHourForSection:(NSInteger)section
{
    return 24;
    if (self.cachedLatestHours[@(section)]) {
        return [self.cachedLatestHours[@(section)] integerValue];
    }
    NSInteger latestHour = NSIntegerMin;
    for (NSInteger item = 0; item < [self.collectionView numberOfItemsInSection:section]; item++) {
        NSIndexPath *itemIndexPath = [NSIndexPath indexPathForItem:item inSection:section];
        NSDateComponents *itemEndTime = [self endTimeForIndexPath:itemIndexPath];
        NSInteger itemEndTimeHour;
        if ([self dayForSection:section].day == itemEndTime.day) {
            itemEndTimeHour = (itemEndTime.hour + ((itemEndTime.minute > 0) ? 1 : 0));
        } else {
            itemEndTimeHour = [[NSCalendar currentCalendar] maximumRangeOfUnit:NSCalendarUnitHour].length + (itemEndTime.hour + ((itemEndTime.minute > 0) ? 1 : 0));;
        }
        if (itemEndTimeHour > latestHour) {
            latestHour = itemEndTimeHour;
        }
    }
    if (latestHour != NSIntegerMin) {
        self.cachedLatestHours[@(section)] = @(latestHour);
        return latestHour;
    } else {
        return 0;
    }
}

#pragma mark Delegate Wrappers

- (NSDateComponents *)dayForSection:(NSInteger)section
{
    if ([self.cachedDayDateComponents objectForKey:@(section)]) {
        return [self.cachedDayDateComponents objectForKey:@(section)];
    }
    
    NSDate *day = [self.delegate collectionView:self.collectionView layout:self dayForSection:section];
    NSDate *startOfDay = [[NSCalendar currentCalendar] startOfDayForDate:day];
    
    NSDateComponents *dayDateComponents = [[NSCalendar currentCalendar] components:(NSCalendarUnitDay | NSCalendarUnitMonth | NSCalendarUnitYear | NSCalendarUnitEra) fromDate:startOfDay];
    
    [self.cachedDayDateComponents setObject:dayDateComponents forKey:@(section)];
    return dayDateComponents;
}

- (NSDateComponents *)startTimeForIndexPath:(NSIndexPath *)indexPath
{
    if ([self.cachedStartTimeDateComponents objectForKey:indexPath]) {
        return [self.cachedStartTimeDateComponents objectForKey:indexPath];
    }
    
    NSDate *date = [self.delegate collectionView:self.collectionView layout:self startTimeForItemAtIndexPath:indexPath];
    NSDateComponents *itemStartTimeDateComponents = [[NSCalendar currentCalendar] components:(NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute) fromDate:date];
    
    [self.cachedStartTimeDateComponents setObject:itemStartTimeDateComponents forKey:indexPath];
    return itemStartTimeDateComponents;
}

- (NSDateComponents *)endTimeForIndexPath:(NSIndexPath *)indexPath
{
    if ([self.cachedEndTimeDateComponents objectForKey:indexPath]) {
        return [self.cachedEndTimeDateComponents objectForKey:indexPath];
    }
    
    NSDate *date = [self.delegate collectionView:self.collectionView layout:self endTimeForItemAtIndexPath:indexPath];
    NSDateComponents *itemEndTime = [[NSCalendar currentCalendar] components:(NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute) fromDate:date];
    
    [self.cachedEndTimeDateComponents setObject:itemEndTime forKey:indexPath];
    return itemEndTime;
}

- (NSDateComponents *)currentTimeDateComponents
{
    if ([self.cachedCurrentDateComponents objectForKey:@(0)]) {
        return [self.cachedCurrentDateComponents objectForKey:@(0)];
    }
    
    NSDate *date = [self.delegate currentTimeComponentsForCollectionView:self.collectionView layout:self];
    NSDateComponents *currentTime = [[NSCalendar currentCalendar] components:(NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute) fromDate:date];
    
    [self.cachedCurrentDateComponents setObject:currentTime forKey:@(0)];
    return currentTime;
}

#pragma mark - Notifications

- (void)handleApplicationWillResignActive:(NSNotification *)notification
{
    self.panGestureRecognizer.enabled = NO;
    self.panGestureRecognizer.enabled = YES;
}

#pragma mark - Key-Value Observing methods

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if ([keyPath isEqualToString:kLXCollectionViewKeyPath]) {
        if (self.collectionView != nil) {
            [self setupCollectionView];
        }
        else {
            [self tearDownCollectionView];
        }
    }
}

#pragma mark - UIGestureRecognizerDelegate methods

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer
{
    if ([self.panGestureRecognizer isEqual:gestureRecognizer]) {
        return (self.selectedItemIndexPath != nil);
    }
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
    if ([self.longPressGestureRecognizer isEqual:gestureRecognizer]) {
        return [self.panGestureRecognizer isEqual:otherGestureRecognizer];
    }
    
    if ([self.panGestureRecognizer isEqual:gestureRecognizer]) {
        return [self.longPressGestureRecognizer isEqual:otherGestureRecognizer];
    }
    
    return NO;
}

- (void)handleLongPressGesture:(UILongPressGestureRecognizer *)gestureRecognizer
{
    switch(gestureRecognizer.state) {
        case UIGestureRecognizerStateBegan: {
            [self longPressGestureBegan:gestureRecognizer];
        } break;
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateEnded: {
            [self longPressGestureEnded];
        } break;
            
        default: break;
    }
}

- (void)handlePanGesture:(UIPanGestureRecognizer *)gestureRecognizer
{
    switch (gestureRecognizer.state) {
         case UIGestureRecognizerStateBegan:
        case UIGestureRecognizerStateChanged: {
            [self panGestureChanged:gestureRecognizer];
        } break;
        default: {
        } break;
    }
}

#pragma mark -

- (void)fillAddingEventTouchInfoWithPoint:(CGPoint)point
{
    CFAbsoluteTime time = CFAbsoluteTimeGetCurrent();
    if (_addingEventTouchInfo.time){
        CFTimeInterval timeInterval = time - _addingEventTouchInfo.time;
        _addingEventTouchInfo.velocity = CGVectorMake((point.x - _addingEventTouchInfo.point.x) / timeInterval,
                                                      (point.y - _addingEventTouchInfo.point.y) / timeInterval);
//        CGVector velocity = _addingEventTouchInfo.velocity;
//        CGFloat velocityVectorLength = sqrt(velocity.dx * velocity.dx + velocity.dy * velocity.dy);
//        if (velocityVectorLength > 5000) {
//            
//        }
//        NSLog(@"X=%f Y=%f TimeInt=%f Vel=%f", point.x, point.y, timeInterval, velocityVectorLength);
        _addingEventTouchInfo.point = point;
    }
    _addingEventTouchInfo.time = time;
}

- (void)removeCurerntEventAnimated
{
    CGVector velocity = _addingEventTouchInfo.velocity;
    NSIndexPath *currentIndexPath = self.selectedItemIndexPath;
    if (currentIndexPath) {
        self.selectedItemIndexPath = nil;
        CGRect targetRect = self.currentView.frame;
        NSTimeInterval duration = 0.3;
        targetRect.origin.x += velocity.dx * duration;
        targetRect.origin.y += velocity.dy * duration;
        [UIView animateWithDuration:duration animations:^{
            self.currentView.frame = targetRect;
            self.currentView.alpha = 0.f;
        } completion:^(BOOL finished) {
            self.currentViewCenter = CGPointZero;

            [self.currentView removeFromSuperview];
            self.currentView = nil;
            [self invalidateLayout];
            [self invalidateLayoutCache];
        }];
    }
}

- (void)longPressGestureBegan:(UIGestureRecognizer *)gestureRecognizer
{
    CGPoint locationInCollectionView = [gestureRecognizer locationInView:self.collectionView];
    NSIndexPath *currentIndexPath = [self.collectionView indexPathForItemAtPoint:locationInCollectionView];
    UICollectionViewCell *collectionViewCell = [self.collectionView cellForItemAtIndexPath:currentIndexPath];
    if (!currentIndexPath) {
        [self invalidateLayoutCache];
        currentIndexPath = [self.delegate collectionView:self.collectionView createNewItemWithDate:[self dateForPoint:locationInCollectionView]];
        [self.collectionView reloadData];
        
//        currentIndexPath = [self.collectionView indexPathForItemAtPoint:locationInCollectionView];
        if (currentIndexPath) {
            self.selectedItemIndexPath = currentIndexPath;
            UICollectionViewLayoutAttributes *layoutAttributes = [self layoutAttributesForItemAtIndexPath:currentIndexPath];
            collectionViewCell.frame = layoutAttributes.frame;
            dispatch_async(dispatch_get_main_queue(), ^{
                UICollectionViewCell *cell = [self.collectionView cellForItemAtIndexPath:currentIndexPath];
                [self startMovingCell:cell];
            });
        }
    }
    else if (collectionViewCell) {
        self.selectedItemIndexPath = currentIndexPath;
        [self startMovingCell:collectionViewCell];
    }
}

- (void)startMovingCell:(UICollectionViewCell *)collectionViewCell
{
    self.currentView = [[UIView alloc] initWithFrame:
                        CGRectMake([self rectForSection:self.selectedItemIndexPath.section].origin.x,
                                   collectionViewCell.frame.origin.y,
                                   [self sectionWidth],
                                   collectionViewCell.frame.size.height)];
    UICollectionViewCell *collectionViewCell2 = [collectionViewCell copy];
    [UIView animateWithDuration:0.3 animations:^{
        collectionViewCell.alpha = 0.5;
    }];
    collectionViewCell2.frame = self.currentView.frame;
    UIView *imageView = [collectionViewCell2 LX_snapshotView];
    imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    imageView.alpha = 0.0f;
    
    [self.currentView addSubview:imageView];
    [self.collectionView addSubview:self.currentView];
    self.currentViewCenter = self.currentView.center;
    
    __weak typeof(self) weakSelf = self;
    [UIView animateWithDuration:0.3
                          delay:0.0
                        options:UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
                         __strong typeof(self) strongSelf = weakSelf;
                         if (strongSelf) {
                             strongSelf.currentView.transform = CGAffineTransformMakeScale(1.1f, 1.1f);
                             imageView.alpha = 1.0f;
                         }
                     }
                     completion:nil];
    
    [self invalidateLayout];
}

- (void)longPressGestureEnded
{
    NSIndexPath *currentIndexPath = self.selectedItemIndexPath;
    if (currentIndexPath) {
        [self removeCurrentView];
    }
}

- (void)removeCurrentView
{
    NSIndexPath *currentIndexPath = self.selectedItemIndexPath;
    
    if (currentIndexPath) {
        UICollectionViewCell *collectionViewCell = [self.collectionView cellForItemAtIndexPath:currentIndexPath];
        if (collectionViewCell.alpha == 0.5) {
            [UIView animateWithDuration:0.3 animations:^{
                collectionViewCell.alpha = 0.0;
            }];
        }
        
        self.selectedItemIndexPath = nil;
        self.currentViewCenter = CGPointZero;
        
        __weak typeof(self) weakSelf = self;
        [UIView animateWithDuration:0.3
                              delay:0.0
                            options:UIViewAnimationOptionBeginFromCurrentState
                         animations:^{
                             __strong typeof(self) strongSelf = weakSelf;
                             if (strongSelf) {
                                 strongSelf.currentView.transform = CGAffineTransformMakeScale(1.0f, 1.0f);
                             }
                         }
                         completion:^(BOOL finished) {
                             __strong typeof(self) strongSelf = weakSelf;
                             if (strongSelf) {
                                 [strongSelf didMoveItemAtIndexPath:currentIndexPath];
                                 
                                 [strongSelf.currentView removeFromSuperview];
                                 strongSelf.currentView = nil;
                                 [strongSelf invalidateLayout];
                                 [strongSelf invalidateLayoutCache];
                             }
                         }];
    }
}

- (void)panGestureChanged:(UIPanGestureRecognizer *)gestureRecognizer
{
    NSIndexPath *currentIndexPath = self.selectedItemIndexPath;
    if (currentIndexPath) {
        CGPoint locationInCollectionView = [gestureRecognizer locationInView:self.collectionView];
        [self fillAddingEventTouchInfoWithPoint:locationInCollectionView];
        CGVector velocity = _addingEventTouchInfo.velocity;
        CGFloat velocityVectorLength = sqrt(velocity.dx * velocity.dx + velocity.dy * velocity.dy);
        if (velocityVectorLength > 5000) {
            if ([self.delegate respondsToSelector:@selector(collectionView:removeItemAtIndexPath:)]) {
                [self.delegate collectionView:self.collectionView removeItemAtIndexPath:currentIndexPath];
                [self invalidateLayoutCache];
                [self.collectionView reloadData];
                [self removeCurerntEventAnimated];
            }
            return;
        }
        
        CGPoint panTranslationInCollectionView = [gestureRecognizer translationInView:self.collectionView];
        CGFloat calendarContentMinX = (self.timeRowHeaderWidth + self.contentMargin.left + self.sectionMargin.left);
        NSInteger newSection = floorf((self.currentViewCenter.x + panTranslationInCollectionView.x - calendarContentMinX) / self.sectionWidth);
        if (newSection < 0) newSection = 0;
        self.currentView.center = CGPointMake(CGRectGetMidX([self rectForSection:newSection]), self.currentViewCenter.y + panTranslationInCollectionView.y);
        
#warning !!!
        [self invalidateLayoutCache];
        [self.collectionView reloadData];
        
        
        CGPoint viewCenter = self.currentView.center;
        if (viewCenter.y < (CGRectGetMinY(self.collectionView.bounds) + self.scrollingTriggerEdgeInsets.top)) {
            
        }
        else if (viewCenter.y > (CGRectGetMaxY(self.collectionView.bounds) - self.scrollingTriggerEdgeInsets.bottom)) {
            
        }
        else {
            
        }
    }
}

- (void)didMoveItemAtIndexPath:(NSIndexPath *)indexPath
{
    NSDate *newDate = [self dateForPoint:CGPointMake(self.currentView.center.x, self.currentView.frame.origin.y)];
    
    if ([self.delegate respondsToSelector:@selector(collectionView:itemAtIndexPath:willMoveToDate:)]) {
        [self.delegate collectionView:self.collectionView itemAtIndexPath:indexPath willMoveToDate:newDate];
        [self.collectionView reloadData];
    }
}

- (NSDate *)dateForPoint:(CGPoint)point
{
    CGFloat calendarContentMinX = (self.timeRowHeaderWidth + self.contentMargin.left + self.sectionMargin.left);
    NSInteger section = floorf((point.x - calendarContentMinX) / self.sectionWidth);
    NSDate *day = [self.delegate collectionView:self.collectionView layout:self dayForSection:section];
    NSDate *startOfDay = [[NSCalendar currentCalendar] startOfDayForDate:day];
    CGFloat calendarContentMinY = (self.dayColumnHeaderHeight + self.contentMargin.top + self.sectionMargin.top);
    CGFloat height = [self sectionHeight:section];
    NSInteger earlier = [self earliestHourForSection:section];
    NSInteger latest = [self latestHourForSection:section];
    CGFloat pointsPerHour = height / (latest - earlier);
    NSTimeInterval timeInterval = (point.y - calendarContentMinY) / pointsPerHour * 3600;
    NSDate *date = [startOfDay dateByAddingTimeInterval:timeInterval];
    return date;
}

@end
