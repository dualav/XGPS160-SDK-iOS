//
//  ProgressDialogViewController.m
//  SkyproSampleApp
//
//  Created by Greg Lukins on 3/14/16.
//  Copyright © 2016 Greg Lukins. All rights reserved.
//

#import "ProgressDialogViewController.h"
#import "AppDelegate.h"

@interface ProgressDialogViewController()

@property AppDelegate *d;
@property UIDocumentInteractionController *controller;
@property FILE *fp;
@property NSMutableString *gpxString;
@property NSString *fileNameWithPath;
@property NSString *fileName;

@end

@implementation ProgressDialogViewController

#pragma mark - GPX string creation
- (void)createBogusGPXString {
    [_gpxString appendString:@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>"];
    [_gpxString appendString:@"<gpx version=\"1.0\">"];
    [_gpxString appendString:@"  <name>Example gpx</name>"];
    [_gpxString appendString:@"  <wpt lat=\"46.57638889\" lon=\"8.89263889\">"];
    [_gpxString appendString:@"    <ele>2372</ele>"];
    [_gpxString appendString:@"    <name>LAGORETICO</name>"];
    [_gpxString appendString:@"  </wpt>"];
    [_gpxString appendString:@"  <trk><name>Example gpx</name><number>1</number><trkseg>"];
    [_gpxString appendString:@"    <trkpt lat=\"46.57608333\" lon=\"8.89241667\"><ele>2376</ele><time>2007-10-14T10:09:57Z</time></trkpt>"];
    [_gpxString appendString:@"    <trkpt lat=\"46.57619444\" lon=\"8.89252778\"><ele>2375</ele><time>2007-10-14T10:10:52Z</time></trkpt>"];
    [_gpxString appendString:@"    <trkpt lat=\"46.57641667\" lon=\"8.89266667\"><ele>2372</ele><time>2007-10-14T10:12:39Z</time></trkpt>"];
    [_gpxString appendString:@"    <trkpt lat=\"46.57650000\" lon=\"8.89280556\"><ele>2373</ele><time>2007-10-14T10:13:12Z</time></trkpt>"];
    [_gpxString appendString:@"    <trkpt lat=\"46.57638889\" lon=\"8.89302778\"><ele>2374</ele><time>2007-10-14T10:13:20Z</time></trkpt>"];
    [_gpxString appendString:@"    <trkpt lat=\"46.57652778\" lon=\"8.89322222\"><ele>2375</ele><time>2007-10-14T10:13:48Z</time></trkpt>"];
    [_gpxString appendString:@"    <trkpt lat=\"46.57661111\" lon=\"8.89344444\"><ele>2376</ele><time>2007-10-14T10:14:08Z</time></trkpt>"];
    [_gpxString appendString:@"  </trkseg></trk>"];
    [_gpxString appendString:@"</gpx>"];
}

- (void)createGPXString {
    NSString *trackPoint;
    
    NSInteger sizeOfTrack = [_d.xgps160.arr_logDataSamples count];
    NSInteger index=0;
    
    // create the GPX string header
    _gpxString = [NSMutableString stringWithString:@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"];
    [_gpxString appendString:@"<gpx version=\"1.0\">\n"];
    [_gpxString appendFormat:@"  <trk><name>%@</name><trkseg>\n", _fileName];
    
    // add the trackpoint data
    for (NSDictionary *sample in _d.xgps160.arr_logDataSamples) {
        trackPoint = [NSString stringWithFormat:@"    <trkpt lat=\"%.6f\" lon=\"%.6f\"><ele>%ld</ele><time>%@</time></trkpt>\n",
                      [[sample objectForKey:@"lat"] floatValue],
                      [[sample objectForKey:@"lon"] floatValue],
                      [[sample objectForKey:@"alt"] integerValue],
                      [sample objectForKey:@"titleText"]];
        [_gpxString appendFormat:@"%@", trackPoint];
        trackPoint = @"";
        
        // update progress bar
        self.exportProgress.progress = (float)index / (float)sizeOfTrack;
        index++;
    }
    
    // properly terminate GPX file
    [_gpxString appendString:@"  </trkseg></trk>\n"];
    [_gpxString appendString:@"</gpx>"];
    
    NSLog(@"GPX String:\n%@", _gpxString);
}

#pragma mark - GPX file creation
- (void)createGPXLogFile {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    dateFormatter.dateFormat = @"yy.dd.MM-HH.mm";
    NSString *dateString = [dateFormatter stringFromDate:[NSDate date]];
    
    _fileName = [NSString stringWithFormat:@"%@-XGPS160.gpx", dateString];
    _fileNameWithPath = [documentsDirectory stringByAppendingPathComponent:_fileName];
    //NSLog(@"Filename with path =\n%@", fileNameWithPath);
}

- (void)writeGPXLogFile
{
    _fp=fopen([_fileNameWithPath UTF8String], "w");
    if (_fp == NULL) { printf("can't open file.\n"); exit(0); }
    fprintf(_fp, "%s", [_gpxString UTF8String]);
    fclose(_fp);
}

#pragma mark - GPX string sharing
- (void)shareGPXString {
    _controller = [UIDocumentInteractionController interactionControllerWithURL:[NSURL fileURLWithPath:_fileNameWithPath]];
    _controller.delegate=self;
    if (![_controller presentOptionsMenuFromRect:self.view.frame inView:self.view animated:YES]) {
        
        UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:nil
                                                            message:@"You don't have an app installed that can handle GPX files."
                                                           delegate:self
                                                  cancelButtonTitle:@"OK"
                                                  otherButtonTitles:nil, nil];
        [alertView show];
    }
}

#pragma mark - View lifecycle
- (void)viewWillAppear:(BOOL)animated {
    
    self.shareButton.enabled = NO;
    [self.cancelDoneButton setTitle:@"Cancel" forState:UIControlStateNormal];
    self.exportLabel.text = @"Exporting...";
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    _d = (AppDelegate *)[[UIApplication sharedApplication] delegate];
    
    _controller = [[UIDocumentInteractionController alloc] init];
    
    _gpxString = [[NSMutableString alloc] initWithCapacity:[_d.xgps160.arr_logDataSamples count]];
}

- (void)viewDidAppear:(BOOL)animated {
    [self createGPXLogFile];        // do this first to define the filename - it's used to name the GPX string
    [self createGPXString];
    [self writeGPXLogFile];
    self.exportLabel.text = @"Exporting complete.";
    
    self.shareButton.enabled = YES;
    
    [self.cancelDoneButton setTitle:@"Done" forState:UIControlStateNormal];
    
}

#pragma mark - Delegate methods
- (IBAction)cancelButtonPressed:(id)sender {
    
    [self.delegate progressDialogViewControllerDidCancel:self];
    
}

- (IBAction)shareButtonPressed:(id)sender {
    [self shareGPXString];
}

- (void)isDone:(id)sender {
    
    [self.delegate progressDialogViewControllerIsDone:self];
}

#pragma mark - UIDocumentInteractionControllerDelegate methods
- (UIViewController *)documentInteractionControllerViewControllerForPreview:(UIDocumentInteractionController *)controller {
    
    return  (UIViewController *)self;
}

- (void)documentInteractionController:(UIDocumentInteractionController *)controller willBeginSendingToApplication:(NSString *)application {
    
    //NSLog(@"Starting to send GPX file to %@", application);
}

- (void)documentInteractionController:(UIDocumentInteractionController *)controller didEndSendingToApplication:(NSString *)application {
    
    //NSLog(@"GPX file sent.");
}

@end
