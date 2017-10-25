//
//  ProgressDialogViewController.h
//  SkyproSampleApp
//
//  Created by Greg Lukins on 3/14/16.
//  Copyright © 2016 Greg Lukins. All rights reserved.
//

#import <UIKit/UIKit.h>

@class ProgressDialogViewController;



@protocol ProgressDialogViewControllerDelegate <NSObject>

- (void)progressDialogViewControllerDidCancel:(ProgressDialogViewController *)controller;
- (void)progressDialogViewControllerIsDone:(ProgressDialogViewController *)controller;

@end



@interface ProgressDialogViewController : UIViewController <UIDocumentInteractionControllerDelegate>

@property (weak, nonatomic) id <ProgressDialogViewControllerDelegate> delegate;
@property (weak, nonatomic) IBOutlet UIProgressView *exportProgress;
@property (weak, nonatomic) IBOutlet UIButton *shareButton;
@property (weak, nonatomic) IBOutlet UILabel *exportLabel;
@property (weak, nonatomic) IBOutlet UIButton *cancelDoneButton;

- (IBAction)cancelButtonPressed:(id)sender;
- (IBAction)shareButtonPressed:(id)sender;
- (void)isDone:(id)sender;

@end
