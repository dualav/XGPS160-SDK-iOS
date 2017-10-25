//
//  LogDataSampleTableViewController.m
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

#define kNoXGPS160MessageView   100

#import "LogDataSampleTableViewController.h"
#import "AppDelegate.h"
#import "LogDataSampleTableViewCell.h"
#import "LogListTableViewController.h"
#import "WaitingToConnectView.h"

@implementation LogDataSampleTableViewController
{
    AppDelegate *d;
}

#pragma mark - Methods to update UI based on device connection status
- (void)displayDeviceNotAttachedMessage
{
    [self.view viewWithTag:kNoXGPS160MessageView].hidden = NO;
}

- (void)dismissDeviceNotAttachedMessage
{
    [self.view viewWithTag:kNoXGPS160MessageView].hidden = YES;
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

#pragma mark - Initialization & memory management methods
- (id)initWithStyle:(UITableViewStyle)style
{
    self = [super initWithStyle:style];
    if (self) {
        // Custom initialization
        
        // create the "Waiting to connect" message view
        int scr_width = [[UIScreen mainScreen]bounds].size.width;
        WaitingToConnectView *statusMessage = [[WaitingToConnectView alloc] initWithFrame:CGRectMake(60, 130, scr_width-120, 120)];
        statusMessage.tag = kNoXGPS160MessageView;
        statusMessage.hidden = YES;		// start off with the view hidden
        [self.view addSubview:statusMessage];
    }
    return self;
}

#pragma mark - View lifecycle
- (void)viewWillAppear:(BOOL)animated
{
    // It will take a moment or two for the XGPS160 to send the sample data to the app, particularly
    // when the log file is large. So look for a notification from the API that the sample data has
    // all been download into app memory.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(refreshGPSDataTableView)
                                                 name:@"DoneReadingGPSSampleData"
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

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    d = (AppDelegate *)[[UIApplication sharedApplication] delegate];
}

- (void)viewDidAppear:(BOOL)animated
{
    // No need to enter log access mode if we're already in it, e.g. coming back from the detailed log view
    if (d.xgps160.streamingMode == YES) [d.xgps160 enterLogAccessMode];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"XGPS160Connected" object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"XGPS160Disconnected" object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"RefreshUIAfterAwakening" object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"DoneReadingGPSSampleData" object:nil];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Segue methods
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([segue.identifier isEqualToString:@"ExportSegue"]) {
        ProgressDialogViewController *progressDialog = segue.destinationViewController;
        progressDialog.delegate = self;
    }
}

#pragma mark - Table view data source
- (void)refreshGPSDataTableView
{
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    NSInteger count = [d.xgps160.arr_logDataSamples count];
    
    if (count == 0) [self.spinner startAnimating];
    else [self.spinner stopAnimating];
    
    return count;
}


- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    LogDataSampleTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"GPSSampleCell" forIndexPath:indexPath];
    
    NSMutableDictionary *sample = [d.xgps160.arr_logDataSamples objectAtIndex:indexPath.row];
    
    cell.sampleIndexLabel.text = [NSString stringWithFormat:@"#%ld", (long)indexPath.row + 1];
    cell.latitudeLabel.text = [NSString stringWithFormat:@"%.6f˚", [[sample objectForKey:@"lat"] floatValue]];
    cell.longitudeLabel.text = [NSString stringWithFormat:@"%.6f˚", [[sample objectForKey:@"lon"] floatValue]];
    cell.altitudeLabel.text = [NSString stringWithFormat:@"%.0f feet", [[sample objectForKey:@"alt"] floatValue]];
    cell.movementLabel.text = [NSString stringWithFormat:@"%.0f˚ at %ld knots", [[sample objectForKey:@"heading"] floatValue], (long)[[sample objectForKey:@"speed"] intValue]];
    cell.timestampLabel.text = [NSString stringWithFormat:@"%@", [sample objectForKey:@"utc"]];
    
    return cell;
}

#pragma mark - ProgressDialogViewControllerDelegate methods
- (void)progressDialogViewControllerDidCancel:(ProgressDialogViewController *)controller {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)progressDialogViewControllerIsDone:(ProgressDialogViewController *)controller {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
