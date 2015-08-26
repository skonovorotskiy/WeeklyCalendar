//
//  TimeRowMinutesHeader.m
//  Example
//
//  Created by Sergey Konovorotskiy on 8/26/15.
//  Copyright (c) 2015 Eric Horacek. All rights reserved.
//

#import "TimeRowMinutesHeader.h"

@interface TimeRowMinutesHeader ()

@property (nonatomic, strong) UILabel *title;

@end

@implementation TimeRowMinutesHeader

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.title = [UILabel new];
        self.title.backgroundColor = [UIColor clearColor];
        self.title.font = [UIFont systemFontOfSize:12.0];
        [self addSubview:self.title];
        
        [self.title makeConstraints:^(MASConstraintMaker *make) {
            make.centerY.equalTo(self.centerY);
            make.right.equalTo(self.right).offset(-5.0);
        }];
    }
    return self;
}

@end
