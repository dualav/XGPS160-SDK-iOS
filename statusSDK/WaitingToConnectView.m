//
//  WaitingToConnectView.m
//  statusSDK
//
//  Created by Mr.choi on 2017. 3. 30..
//  Copyright © 2017년 Mr.choi. All rights reserved.
//

#import "WaitingToConnectView.h"

@implementation WaitingToConnectView

@synthesize width;
@synthesize height;

- (id)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        // Initialization code
        width = 118.0;
        height = 14.0;
        [self setBackgroundColor:[UIColor clearColor]];
    }
    return self;
}

- (void)drawRect:(CGRect)rect {
    
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSaveGState(context);
    
    CGFloat radius = 32;
    CGFloat minx = CGRectGetMinX(rect), midx = CGRectGetMidX(rect), maxx = CGRectGetMaxX(rect);
    CGFloat miny = CGRectGetMinY(rect), midy = CGRectGetMidY(rect), maxy = CGRectGetMaxY(rect);
    
    // Start at 1
    CGContextMoveToPoint(context, minx, midy);
    // Add an arc through 2 to 3
    CGContextAddArcToPoint(context, minx, miny, midx, miny, radius);
    // Add an arc through 4 to 5
    CGContextAddArcToPoint(context, maxx, miny, maxx, midy, radius);
    // Add an arc through 6 to 7
    CGContextAddArcToPoint(context, maxx, maxy, midx, maxy, radius);
    // Add an arc through 8 to 9
    CGContextAddArcToPoint(context, minx, maxy, minx, midy, radius);
    // Close the path
    CGContextClosePath(context);
    
    // Fill the path
    CGContextSetRGBFillColor(context, 1.0, 0.0, 0.0, 1.0);
    CGContextDrawPath(context, kCGPathFill);
    
    CGContextRestoreGState(context);
    
    // add the text and the spinner
    int scr_width = [[UIScreen mainScreen]bounds].size.width;
    UILabel *waitingLabel = [[UILabel alloc] initWithFrame:CGRectMake(scr_width/2-150,5,179,53)];
    waitingLabel.backgroundColor = [UIColor clearColor];
    waitingLabel.textColor = [UIColor whiteColor];
    waitingLabel.textAlignment = NSTextAlignmentCenter;
    waitingLabel.font = [UIFont fontWithName:@"Helvetica-Bold" size:16];
    waitingLabel.numberOfLines = 2;
    waitingLabel.text = @"Waiting for the XGPS160...";
    
    /*
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithFrame:CGRectMake(82,66,37,37)];
    spinner.activityIndicatorViewStyle = UIActivityIndicatorViewStyleWhiteLarge;
    [spinner startAnimating];
     */
    UIActivityIndicatorView *indicator = [[UIActivityIndicatorView alloc]initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    indicator.frame = CGRectMake(scr_width/2-90, 60.0, 60, 60.0);
    //indicator.center = [self center];
    [self addSubview:indicator];
    [indicator bringSubviewToFront:self];
    [UIApplication sharedApplication].networkActivityIndicatorVisible = TRUE;
    
    [indicator startAnimating];
    
    [self addSubview:waitingLabel];
    [self addSubview:indicator];
}

@end
