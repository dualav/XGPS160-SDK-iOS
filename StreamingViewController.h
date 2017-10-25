//
//  StreamingViewController.h
//  statusSDK
//
//  Created by Mr.choi on 2017. 3. 30..
//  Copyright © 2017년 Mr.choi. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface StreamingViewController : UIViewController
@property (nonatomic, retain) IBOutlet UILabel *connectionStatusLabel;
@property (nonatomic, retain) IBOutlet UILabel *batteryStatusLabel;
@property (nonatomic, retain) IBOutlet UILabel *latitudeLabel;
@property (nonatomic, retain) IBOutlet UILabel *longitudeLabel;
@property (nonatomic, retain) IBOutlet UILabel *altitudeLabel;
@property (nonatomic, retain) IBOutlet UILabel *headingLabel;
@property (nonatomic, retain) IBOutlet UILabel *speedLabel;
@property (nonatomic, retain) IBOutlet UILabel *utcTimeLabel;
@property (nonatomic, retain) IBOutlet UILabel *waasInUseLabel;
@property (nonatomic, retain) IBOutlet UILabel *gpsSatsInViewLabel;
@property (nonatomic, retain) IBOutlet UILabel *gpsSatsInUseLabel;
@property (nonatomic, retain) IBOutlet UILabel *glonassSatsInViewLabel;
@property (nonatomic, retain) IBOutlet UILabel *glonassSatsInUseLabel;
@property (weak, nonatomic) IBOutlet UIView *sview;
@property (weak, nonatomic) IBOutlet UIScrollView *mScroll;
@end
