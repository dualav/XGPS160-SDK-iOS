//
//  StreamingViewController.m
//  statusSDK
//
//  Created by Mr.choi on 2017. 3. 30..
//  Copyright © 2017년 Mr.choi. All rights reserved.
//

#import "StreamingViewController.h"
#import "WaitingToConnectView.h"
#import "AppDelegate.h"

// These constants are for the UI only - no relation to the XGPS device
#define kNoXGPS160MessageView	99                  // Arbitrary value: this number can be anything
#define kFontSize			16                      // Font size for the UILabels
#define kStartingIndexForSatNumberLabels    100     // This number can be anything but 0.
#define kStartingIndexForSatSNRLabels       200     // Can't be zero and must be at least 12 more than kStartingIndexForSatNumberLabels.

@interface StreamingViewController ()

@end

@implementation StreamingViewController
{
    AppDelegate *d;
    char shifter;
    BOOL connectedFlasher;
}

#pragma mark - Memory management methods
- (void)didReceiveMemoryWarning
{
    // Releases the view if it doesn't have a superview.
    [super didReceiveMemoryWarning];
    
    // Release any cached data, images, etc that aren't in use.
}

#pragma mark - General class methods
- (void)updateUIWithNewDeviceData
{
    // update the device labels
    if (d.xgps160.isConnected == NO)
    {
        self.connectionStatusLabel.font = [UIFont fontWithName:@"Helvetica-BoldOblique" size:kFontSize];
        self.connectionStatusLabel.textColor = [UIColor redColor];
        self.connectionStatusLabel.text = @"Not connected";
        self.batteryStatusLabel.text = @"";
    }
    else
    {
        self.connectionStatusLabel.font = [UIFont fontWithName:@"Helvetica-Bold" size:kFontSize];
        self.connectionStatusLabel.textColor = [UIColor greenColor];
        
        // animate the Connected label
        if (connectedFlasher)
        {
            self.connectionStatusLabel.text = @"Connected";
            connectedFlasher = NO;
        }
        else
        {
            self.connectionStatusLabel.text = @"Connected •";
            connectedFlasher = YES;
        }
        
        if (d.xgps160.isCharging)
        {
            // animate the Charging label
            switch (shifter) {
                case 0:
                    self.batteryStatusLabel.text = @"Charging";
                    shifter++;
                    break;
                case 1:
                    self.batteryStatusLabel.text = @"Charging.";
                    shifter++;
                    break;
                case 2:
                    self.batteryStatusLabel.text = @"Charging..";
                    shifter++;
                    break;
                case 3:
                    self.batteryStatusLabel.text = @"Charging...";
                    shifter = 0;
                    break;
                default:
                    break;
            }
        }
        else self.batteryStatusLabel.text = [NSString stringWithFormat:@"%.0f%%", d.xgps160.batteryVoltage * 100.0f];
    }
}

- (void)updateUIWithNewPositionData
{
    // update the position labels
    if (d.xgps160.isConnected == NO)
    {
        self.latitudeLabel.text = @"";
        self.longitudeLabel.text = @"";
        self.altitudeLabel.text = @"";
        self.headingLabel.text = @"";
        self.speedLabel.text = @"";
        self.utcTimeLabel.text = @"";
        self.waasInUseLabel.text = @"";
        self.gpsSatsInViewLabel.text = @"";
        self.gpsSatsInUseLabel.text = @"";
        self.glonassSatsInViewLabel.text = @"";
        self.glonassSatsInUseLabel.text = @"";
    }
    else if ([d.xgps160.fixType intValue] > 1) // 1 = Fix not available, 2 = 2D fix, 3 = 3D fix
    {
        self.latitudeLabel.font = [UIFont fontWithName:@"Helvetica-Bold" size:kFontSize];
        self.latitudeLabel.text = [NSString stringWithFormat:@"%.5f˚", [d.xgps160.lat floatValue]];
        
        self.longitudeLabel.font = [UIFont fontWithName:@"Helvetica-Bold" size:kFontSize];
        self.longitudeLabel.text = [NSString stringWithFormat:@"%.5f˚", [d.xgps160.lon floatValue]];
        
        self.utcTimeLabel.font = [UIFont fontWithName:@"Helvetica-Bold" size:kFontSize];
        self.utcTimeLabel.text = [d.xgps160.utc substringToIndex:([d.xgps160.utc length] - 1)];
        
        self.utcTimeLabel.font = [UIFont fontWithName:@"Helvetica-Bold" size:kFontSize];
        self.waasInUseLabel.text = (d.xgps160.waasInUse)?@"Yes":@"No";
        
        self.gpsSatsInUseLabel.font = [UIFont fontWithName:@"Helvetica-Bold" size:kFontSize];
        self.gpsSatsInUseLabel.text = [NSString stringWithFormat:@"%d", [d.xgps160.numOfGPSSatInUse intValue]];
        
        self.gpsSatsInViewLabel.font = [UIFont fontWithName:@"Helvetica-Bold" size:kFontSize];
        self.gpsSatsInViewLabel.text = [NSString stringWithFormat:@"%d", [d.xgps160.numOfGPSSatInView intValue]];
        
        self.glonassSatsInUseLabel.font = [UIFont fontWithName:@"Helvetica-Bold" size:kFontSize];
        self.glonassSatsInUseLabel.text = [NSString stringWithFormat:@"%d", [d.xgps160.numOfGLONASSSatInUse intValue]];
        
        self.glonassSatsInViewLabel.font = [UIFont fontWithName:@"Helvetica-Bold" size:kFontSize];
        self.glonassSatsInViewLabel.text = [NSString stringWithFormat:@"%d", [d.xgps160.numOfGLONASSSatInView intValue]];
        
        if ([d.xgps160.fixType intValue] == 3)	// 3D: This means the altitude is valid
        {
            self.altitudeLabel.font = [UIFont fontWithName:@"Helvetica-Bold" size:kFontSize];
            self.altitudeLabel.text = [NSString stringWithFormat:@"%.0f m", [d.xgps160.alt floatValue]];
        }
        else
        {
            self.altitudeLabel.font = [UIFont fontWithName:@"Helvetica-BoldOblique" size:kFontSize];
            self.altitudeLabel.text = @"Waiting for 1 more satellite";
        }
        
        if (d.xgps160.speedAndCourseIsValid)
        {
            self.speedLabel.font = [UIFont fontWithName:@"Helvetica-Bold" size:kFontSize];
            self.speedLabel.text = [NSString stringWithFormat:@"%.0f kph", [d.xgps160.speedKph floatValue]];
            
            // only show a heading if moving
            self.headingLabel.font = [UIFont fontWithName:@"Helvetica-Bold" size:kFontSize];
            if ([d.xgps160.speedKph floatValue] > 1.6)
                self.headingLabel.text = [NSString stringWithFormat:@"%.0f˚", [d.xgps160.trackTrue floatValue]];
            else self.headingLabel.text = @"---";
        }
        else
        {
            self.speedLabel.font = [UIFont fontWithName:@"Helvetica-Bold" size:kFontSize];
            self.speedLabel.text = @"---";
            
            self.headingLabel.font = [UIFont fontWithName:@"Helvetica-Bold" size:kFontSize];
            self.headingLabel.text = @"---";
        }
    }
    else
    {
        self.latitudeLabel.font = [UIFont fontWithName:@"Helvetica-BoldOblique" size:kFontSize];
        self.latitudeLabel.text = @"Waiting for sat data";
        
        self.longitudeLabel.font = [UIFont fontWithName:@"Helvetica-BoldOblique" size:kFontSize];
        self.longitudeLabel.text = @"Waiting for sat data";
        
        self.altitudeLabel.font = [UIFont fontWithName:@"Helvetica-BoldOblique" size:kFontSize];
        self.altitudeLabel.text = @"Waiting for sat data";
        
        self.headingLabel.font = [UIFont fontWithName:@"Helvetica-BoldOblique" size:kFontSize];
        self.headingLabel.text = @"Waiting for sat data";
        
        self.speedLabel.font = [UIFont fontWithName:@"Helvetica-BoldOblique" size:kFontSize];
        self.speedLabel.text = @"Waiting for sat data";
        
        self.utcTimeLabel.font = [UIFont fontWithName:@"Helvetica-BoldOblique" size:kFontSize];
        self.utcTimeLabel.text = @"Waiting for sat data";
        
        self.waasInUseLabel.font = [UIFont fontWithName:@"Helvetica-BoldOblique" size:kFontSize];
        self.waasInUseLabel.text = @"Waiting for sat data";
        
        self.gpsSatsInUseLabel.font = [UIFont fontWithName:@"Helvetica-BoldOblique" size:kFontSize];
        self.gpsSatsInUseLabel.text = @"Waiting for sat data";
        
        self.gpsSatsInViewLabel.font = [UIFont fontWithName:@"Helvetica-BoldOblique" size:kFontSize];
        self.gpsSatsInViewLabel.text = @"Waiting for sat data";
        
        self.glonassSatsInUseLabel.font = [UIFont fontWithName:@"Helvetica-BoldOblique" size:kFontSize];
        self.glonassSatsInUseLabel.text = @"Waiting for sat data";
        
        self.glonassSatsInViewLabel.font = [UIFont fontWithName:@"Helvetica-BoldOblique" size:kFontSize];
        self.glonassSatsInViewLabel.text = @"Waiting for sat data";
    }
    
}

#pragma mark - Methods to update UI based on device connection status
- (void)displayDeviceNotAttachedMessage
{
    [self updateUIWithNewDeviceData];
    [self updateUIWithNewPositionData];
    [self.view viewWithTag:kNoXGPS160MessageView].hidden = NO;
}

- (void)dismissDeviceNotAttachedMessage
{
    [self.view viewWithTag:kNoXGPS160MessageView].hidden = YES;
}

- (void)deviceConnected
{
    [self dismissDeviceNotAttachedMessage];
    
    // go back to streaming mode
    d = (AppDelegate *)[[UIApplication sharedApplication] delegate];
    [d.xgps160 exitLogAccessMode];
}

- (void)deviceDisconnected
{
    [self displayDeviceNotAttachedMessage];
}

- (void)refreshUIAfterAwakening
{
    if (d.xgps160.isConnected == NO) [self displayDeviceNotAttachedMessage];
    else [self dismissDeviceNotAttachedMessage];
}

#pragma mark - View lifecycle
- (void)viewDidLoad
{
    d = (AppDelegate *)[[UIApplication sharedApplication] delegate];
    shifter = 0;
    connectedFlasher = NO;
    
    CGRect newFrame = self.sview.frame;
    
    self.mScroll.contentSize = newFrame.size;
    
    // create the "Waiting to connect" message view
    int scr_width = [[UIScreen mainScreen]bounds].size.width;
    WaitingToConnectView *statusMessage = [[WaitingToConnectView alloc] initWithFrame:CGRectMake(60, 130, scr_width-120, 120)];
    statusMessage.tag = kNoXGPS160MessageView;
    statusMessage.hidden = YES;		// start off with the view hidden
    [self.view addSubview:statusMessage];
    
}

- (void)viewWillAppear:(BOOL)animated
{
    // Register for notifications that the XGPS160 device data (battery level, charging status, etc.) has been updated.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(updateUIWithNewDeviceData)
                                                 name:@"DeviceDataUpdated"
                                               object:nil];
    
    // Register for notifications that the position data has been updated.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(updateUIWithNewPositionData)
                                                 name:@"PositionDataUpdated"
                                               object:nil];
    
    // register for notifications from the app delegate that the XGPS160 has connected to the iPod/iPad/iPhone
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(deviceConnected)
                                                 name:@"XGPS160Connected"
                                               object:nil];
    
    // register for notifications from the app delegate that the XGPS160 has disconnected from the iPod/iPad/iPhone
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(deviceDisconnected)
                                                 name:@"XGPS160Disconnected"
                                               object:nil];
    
    // Listen for notification from the app delegate that the app has resumed becuase the UI may need to
    // update itself if the device status changed while the iPod/iPad/iPhone was asleep.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(refreshUIAfterAwakening)
                                                 name:@"RefreshUIAfterAwakening"
                                               object:nil];
    
    // enter streaming mode
    d = (AppDelegate *)[[UIApplication sharedApplication] delegate];
    [d.xgps160 exitLogAccessMode];
}

- (void)viewDidAppear:(BOOL)animated
{
    // ViewDidAppear is called every time the tab is selected to display the view.
    if (d.xgps160.isConnected == NO) [self displayDeviceNotAttachedMessage];
    else [d.xgps160 exitLogAccessMode];
}


- (void)viewWillDisappear:(BOOL)animated
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"DeviceDataUpdated" object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"PositionDataUpdated" object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"XGPS160Connected" object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"XGPS160Disconnected" object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"RefreshUIAfterAwakening" object:nil];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    // Return YES for supported orientations
    return (interfaceOrientation == UIInterfaceOrientationPortrait);
}

@end
