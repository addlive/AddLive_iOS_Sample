/*
 * Copyright (C) LiveFoundry Inc 2012
 *
 * All rights reserved. Any use, copying, modification, distribution and selling
 * of this software and it's documentation for any purposes without authors' written
 * permission is hereby prohibited.
 */

#import <UIKit/UIKit.h>
#import <MessageUI/MFMailComposeViewController.h>

@interface CdoViewController : UIViewController
<UIActionSheetDelegate, MFMailComposeViewControllerDelegate>

@property (assign) IBOutlet UIButton *buttonConnectDisconnect;
@property (assign) IBOutlet UILabel *labelStatus;
@property (assign) IBOutlet UITextField *textFieldURL;
@property (assign) IBOutlet UILabel *labelUplinkStats;
@property (assign) IBOutlet UIButton *buttonAec;
@property (assign) IBOutlet UIButton *buttonNs;
@property (assign) IBOutlet UIButton *buttonAgc;
@property (assign) IBOutlet UITableView *tableViewDownlinkStats;

- (IBAction) onConnectDisconnect;
- (IBAction) onLogs;
- (IBAction) onKill;
- (IBAction) onSpeaker;
- (IBAction) onAEC:(id) sender;
- (IBAction) onNS:(id) sender;
- (IBAction) onAGC:(id) sender;

- (void) resume;

@end
