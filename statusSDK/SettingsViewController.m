//
//  SettingsViewController.m
//  XGPS160 Developers Kit.
//
//  Version 1.1
//  Licensed under the terms of the BSD License, as specified below.

/*
 Copyright (c) 2014 Dual Electronics Corp.
 All rights reserved.
 
 Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
 
 Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
 Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
 Neither the name of the Dual Electronics Corporation nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

/*
 Tab bar icons are freeware from Glyphish. See http://www.glyphish.com for attribution requirements and Creative Commons license terms.
 */

#import "SettingsViewController.h"
#import "AppDelegate.h"
#import "WaitingToConnectView.h"

#define kNoXGPS160MessageView 10

@interface SettingsViewController ()

@end

@implementation SettingsViewController
{
    AppDelegate *d;
}

#pragma mark - General class methods
- (void)setAvailabilityOfUI
{
    if (d.xgps160.deviceSettingsHaveBeenRead == NO)
    {
        self.alwaysRecordChoice.enabled = NO;
        self.memoryChoice.enabled = NO;
        self.updateRateChoice.enabled = NO;
        
        [d.xgps160 readDeviceSettings];
    }
    else
    {
        self.alwaysRecordChoice.enabled = YES;
        self.memoryChoice.enabled = YES;
        self.updateRateChoice.enabled = YES;
        
        if (d.xgps160.alwaysRecordWhenDeviceIsOn) [self.alwaysRecordChoice setSelectedSegmentIndex:0];
        else [self.alwaysRecordChoice setSelectedSegmentIndex:1];
        
        if (d.xgps160.stopRecordingWhenMemoryFull) [self.memoryChoice setSelectedSegmentIndex:1];
        else [self.memoryChoice setSelectedSegmentIndex:0];
        
        // a log update rate value of 255 means the XGPS160 is using the default value of one sample per second.
        if (d.xgps160.logUpdateRate == 1) [self.updateRateChoice setSelectedSegmentIndex:0];
        else if (d.xgps160.logUpdateRate == 2) [self.updateRateChoice setSelectedSegmentIndex:1];
        else if (d.xgps160.logUpdateRate == 10) [self.updateRateChoice setSelectedSegmentIndex:2];
        else if (d.xgps160.logUpdateRate == 255) [self.updateRateChoice setSelectedSegmentIndex:2];
        else if (d.xgps160.logUpdateRate == 50) [self.updateRateChoice setSelectedSegmentIndex:3];
        else if (d.xgps160.logUpdateRate == 200) [self.updateRateChoice setSelectedSegmentIndex:4];
        else [self.updateRateChoice setSelectedSegmentIndex:UISegmentedControlNoSegment];
    }
}

#pragma mark - Initialization & memory management methods
- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Methods to update UI based on device connection status
- (void)displayDeviceNotAttachedMessage
{
    [self.view viewWithTag:kNoXGPS160MessageView].hidden = NO;
}

- (void)dismissDeviceNotAttachedMessage
{
    [self.view viewWithTag:kNoXGPS160MessageView].hidden = YES;
    
    [self setAvailabilityOfUI];
}

- (void)deviceConnected
{
    [self dismissDeviceNotAttachedMessage];
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

#pragma mark - View lifecycle methods
- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    d = (AppDelegate *)[[UIApplication sharedApplication] delegate];
    
    // create the "Waiting to connect" message view
    int scr_width = [[UIScreen mainScreen]bounds].size.width;
    WaitingToConnectView *statusMessage = [[WaitingToConnectView alloc] initWithFrame:CGRectMake(60, 130, scr_width-120, 120)];
    statusMessage.tag = kNoXGPS160MessageView;
    statusMessage.hidden = YES;		// start off with the view hidden
    [self.view addSubview:statusMessage];
}

- (void)viewWillAppear:(BOOL)animated
{
    [d.xgps160 readDeviceSettings];
    [self setAvailabilityOfUI];
    
    // register for notifications from the app delegate that the XGPS160 has disconnected from the iPod/iPad/iPhone
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(setAvailabilityOfUI)
                                                 name:@"DeviceSettingsValueChanged"
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
    
    if (d.xgps160.isConnected == NO) [self displayDeviceNotAttachedMessage];
}

#pragma mark - UI object action methods
- (IBAction)alwaysRecordChoiceChanged:(id)sender
{
    UISegmentedControl *s = (UISegmentedControl *)sender;
    
    if (s.selectedSegmentIndex == 0) [d.xgps160 setAlwaysRecord:YES];
    else [d.xgps160 setAlwaysRecord:NO];
}

- (IBAction)memoryChoiceChanged:(id)sender
{
    UISegmentedControl *s = (UISegmentedControl *)sender;
    
    if (s.selectedSegmentIndex == 0) [d.xgps160 setNewLogDataToOverwriteOldData:YES];
    else [d.xgps160 setNewLogDataToOverwriteOldData:NO];
}

- (IBAction)loggingRateChoiceChanged:(id)sender {
    UISegmentedControl *s = (UISegmentedControl *)sender;
    
    if (s.selectedSegmentIndex == 0) [d.xgps160 setLoggingUpdateRate:1];
    else if (s.selectedSegmentIndex == 1) [d.xgps160 setLoggingUpdateRate:2];
    else if (s.selectedSegmentIndex == 2) [d.xgps160 setLoggingUpdateRate:10];
    else if (s.selectedSegmentIndex == 3) [d.xgps160 setLoggingUpdateRate:50];
    else if (s.selectedSegmentIndex == 4) [d.xgps160 setLoggingUpdateRate:200];
    
}

- (IBAction)startRecordingButtonPressed:(id)sender {
    [d.xgps160 startLoggingNow];
}

- (IBAction)stopRecordingButtonPressed:(id)sender {
    [d.xgps160 stopLoggingNow];
}

@end
