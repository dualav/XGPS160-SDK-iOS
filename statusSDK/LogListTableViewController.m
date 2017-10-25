//
//  LogListTableViewController.m
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

#import "LogListTableViewController.h"
#import "AppDelegate.h"
#import "LogListEntryTableViewCell.h"
#import "WaitingToConnectView.h"

#define kNoXGPS160MessageView   100

@interface LogListTableViewController ()

@end

@implementation LogListTableViewController
{
    AppDelegate *d;
    NSUInteger _selectedIndex;
    NSInteger _lastSelectedIndex;
}

#pragma mark - General class methods
- (void)stopStreaming
{
    [d.xgps160 enterLogAccessMode];
}

- (void)setTableTitleText
{
    unsigned long num = [d.xgps160.arr_logListEntries count];
    NSLog(@"%s. # of log list entries = %lu.", __FUNCTION__, num);
    if (num == 0) self.topTitleBar.title = @"No Trips in Memory";
    else if (num == 1) self.topTitleBar.title = @"1 Trip in Memory";
    else self.topTitleBar.title = [NSString stringWithFormat:@"%lu Trips in Memory", num];
}

- (void)refreshLogEntryTableView
{
    [self setTableTitleText];
    [self.tableView reloadData];
}

- (void)refreshInvoked:(id)sender forState:(UIControlState)state
{
    self.topTitleBar.title = @"Reloading Recorded Trips...";
    [d.xgps160.arr_logListEntries removeAllObjects];
    [self.tableView reloadData];
    [d.xgps160 getListOfRecordedLogs];
    [self refreshLogEntryTableView];
    [self.refreshControl endRefreshing];
}

#pragma mark - Methods to update UI based on device connection status
- (void)displayDeviceNotAttachedMessage
{
    [self.view viewWithTag:kNoXGPS160MessageView].hidden = NO;
}

- (void)dismissDeviceNotAttachedMessage
{
    [self.view viewWithTag:kNoXGPS160MessageView].hidden = YES;
    [self stopStreaming];
}

- (void)deviceConnected
{
    [self dismissDeviceNotAttachedMessage];
    [self stopStreaming];
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
        
        // create the "Waiting to connect" message view
        int scr_width = [[UIScreen mainScreen]bounds].size.width;
        WaitingToConnectView *statusMessage = [[WaitingToConnectView alloc] initWithFrame:CGRectMake(60, 130, scr_width-120, 120)];
        statusMessage.tag = kNoXGPS160MessageView;
        statusMessage.hidden = YES;		// start off with the view hidden
        [self.view addSubview:statusMessage];
    }
    return self;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - View lifecycle methods
- (void)viewWillAppear:(BOOL)animated
{
    // register for notifications from the app delegate that the device has connected to the iPod/iPad/iPhone
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(deviceConnected)
                                                 name:@"XGPS160Connected"
                                               object:nil];
    
    // register for notifications from the app delegate that the device has disconnected from the iPod/iPad/iPhone
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(deviceDisconnected)
                                                 name:@"XGPS160Disconnected"
                                               object:nil];
    
    // register for notifications from the XGPS160 API that the device is done reading the log list entries
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(refreshLogEntryTableView)
                                                 name:@"DoneReadingLogListEntries"
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
    
    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(refreshInvoked:forState:) forControlEvents:UIControlEventValueChanged];
    
    self.navigationItem.rightBarButtonItem = self.editButtonItem;
    
    // create the "Waiting to connect" message view
    int scr_width = [[UIScreen mainScreen]bounds].size.width;
    WaitingToConnectView *statusMessage = [[WaitingToConnectView alloc] initWithFrame:CGRectMake(60, 130, scr_width-120, 120)];
    statusMessage.tag = kNoXGPS160MessageView;
    statusMessage.hidden = YES;		// start off with the view hidden
    [self.view addSubview:statusMessage];
    
    d = (AppDelegate *)[[UIApplication sharedApplication] delegate];
    
    _selectedIndex = 0;
    _lastSelectedIndex = -1;
}

- (void)viewDidAppear:(BOOL)animated
{
    // No need to enter log access mode if we're already in it, e.g. coming back from the detailed log view
    if (d.xgps160.streamingMode == YES)
    {
        [d.xgps160 enterLogAccessMode];
        //[self setTableTitleText];
    }
}

- (void)viewWillDisappear:(BOOL)animated
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"XGPS160Connected" object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"XGPS160Disconnected" object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"RefreshUIAfterAwakening" object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"DoneReadingLogListEntries" object:nil];
}

#pragma mark - Table view data source
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    NSInteger count = [d.xgps160.arr_logListEntries count];
    
    if (count == 0) {
        self.topTitleBar.title = @"Loading Trips...";
        [self.spinner startAnimating];
    }
    else {
        [self setTableTitleText];
        [self.spinner stopAnimating];
    }
    
    return count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *CellIdentifier = @"LogListEntryCell";
    LogListEntryTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier forIndexPath:indexPath];
    
    NSDictionary *logListEntry = [d.xgps160.arr_logListEntries objectAtIndex:indexPath.row];
    
    cell.logListIndexLabel.text = [NSString stringWithFormat:@"#%ld", ((long)indexPath.row + 1)];
    cell.dateAndTimeLabel.text = [NSString stringWithFormat:@"%@ %@", [logListEntry objectForKey:@"humanFriendlyStartDate"], [logListEntry objectForKey:@"humanFriendlyStartTime"]];
    cell.durationLabel.text = [logListEntry objectForKey:@"humanFriendlyDuration"];
    cell.numberOfGPSSamplesLabel.text = [NSString stringWithFormat:@"%d", [[logListEntry objectForKey:@"countEntry"] intValue]];
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    _selectedIndex = indexPath.row;
    if (_selectedIndex == _lastSelectedIndex) return;
    
    NSDictionary *logListEntry = [d.xgps160.arr_logListEntries objectAtIndex:_selectedIndex];
    _lastSelectedIndex = _selectedIndex;
    
    [d.xgps160 getGPSSampleDataForLogListItem:logListEntry];
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated {
    [super setEditing:editing animated:animated];
    [self.tableView setEditing:editing animated:YES];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    return YES;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return UITableViewCellEditingStyleDelete;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (editingStyle == UITableViewCellEditingStyleDelete)
    {
        NSDictionary *logListEntry = [d.xgps160.arr_logListEntries objectAtIndex:indexPath.row];
        
        [d.xgps160 deleteGPSSampleDataForLogListItem:logListEntry];
        [self.tableView beginUpdates];
        [self.tableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationFade];
        [self.tableView endUpdates];
        [self setTableTitleText];
    }
}

#pragma mark - Segue unwind method
- (IBAction)unwindToLogListViewController:(UIStoryboardSegue *)unwindSegue
{
}

@end
