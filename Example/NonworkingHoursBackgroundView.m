//
//  NonworkingHoursBackgroundView.m
//  Example
//
//  Created by Sergey Konovorotskiy on 8/26/15.
//  Copyright (c) 2015 Eric Horacek. All rights reserved.
//

#import "NonworkingHoursBackgroundView.h"

@implementation NonworkingHoursBackgroundView

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithHexString:@"f7f7f7"];
    }
    return self;
}

@end
