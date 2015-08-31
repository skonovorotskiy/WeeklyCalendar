//
//  MSCalendarViewController.h
//  Example
//
//  Created by Eric Horacek on 2/26/13.
//  Copyright (c) 2015 Eric Horacek. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface MSCalendarViewController : UICollectionViewController

/*! Number of colums visible at the moment.
 Default is 7*/
@property (nonatomic) NSUInteger numberOfVisibleDays;

@property (nonatomic, strong) NSDateComponents *startWorkingDay; // hours and minutes
@property (nonatomic, strong) NSDateComponents *endWorkingDay; // hours and minutes

@end
