/*
 * Copyright (C) LiveFoundry Inc 2012
 *
 * All rights reserved. Any use, copying, modification, distribution and selling
 * of this software and it's documentation for any purposes without authors' written
 * permission is hereby prohibited.
 */

#import <UIKit/UIKit.h>
#import <MessageUI/MFMailComposeViewController.h>

#import "AddLive/AddLiveAPI.h"

@interface ALViewController : UIViewController

<UIActionSheetDelegate,
 MFMailComposeViewControllerDelegate,
 UITableViewDelegate, UITableViewDataSource,
 ALServiceListener>

@property (assign) IBOutlet UIScrollView *scrollView;
@property (assign) IBOutlet UIView *contentView;
@property (assign) IBOutlet UIButton *buttonConnectDisconnect;
@property (assign) IBOutlet UISwitch *switchSpeaker;
@property (assign) IBOutlet UISwitch *switchPublishVideo;
@property (assign) IBOutlet UISwitch *switchPublishAudio;
@property (assign) IBOutlet UILabel *labelStatus;
@property (assign) IBOutlet UITextField *textFieldURL;
@property (assign) IBOutlet UILabel *labelUplinkStats;
@property (assign) IBOutlet UIButton *buttonNs;
@property (assign) IBOutlet UIButton *buttonCamera;
@property (assign) IBOutlet UITableView *tableViewDownlinkStats;
@property (assign) IBOutlet ALVideoView *viewVideo0;
@property (assign) IBOutlet ALVideoView *viewVideo1;

- (IBAction) onConnectDisconnect;
- (IBAction) onPublishVideo;
- (IBAction) onPublishAudio;
- (IBAction) onLogs;
- (IBAction) onKill;
- (IBAction) onSpeaker;
- (IBAction) onNS;
- (IBAction) onCamera;
- (IBAction) onSwipeLeft;
- (IBAction) onSwipeRight;

- (void) becomeActive;
- (void) resignActive;
- (void) enterForeground;
- (void) enterBackground;

@end
