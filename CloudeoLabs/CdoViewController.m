/*
 * Copyright (C) Cloudeo Ltd 2012
 *
 * All rights reserved. Any use, copying, modification, distribution and selling
 * of this software and it's documentation for any purposes without authors' written
 * permission is hereby prohibited.
 */

#import "CdoViewController.h"
#import "Cloudeo/CdoAPI.h"
#import "Reachability.h"

#import <CommonCrypto/CommonDigest.h>

#include <asl.h>
#include <time.h>

//

NSString* LOG_RECEIVER_EMAIL = @"dev@addlive.com";
NSString* LOG_EMAIL_SUBJECT = @"CloudeoSDK iOS - Logs";
NSString* LOG_FILE_TEMPLATE = @"cloudeo_log.XXXXXX";
NSString* LOG_FILE_EMAIL = @"cloudeo_log.txt";
char* LOG_KEY_SENDER = "CloudeoSDK";

int CDO_SAMPLES_APP_ID = 1;
NSString* CDO_SAMPLES_SECRET = @"CloudeoTestAccountSecret";

//

@interface CdoViewController ()

{
    enum State
    {
        INIT,
        INIT_SERVICE_LISTENER,
	INIT_APPLICATION_ID,
        DISCONNECTED,
        CONNECTED
    };

    enum Sheet
    {
        SHEET_AEC,
        SHEET_NS,
        SHEET_AGC
    };
    
    CdoAPI*                  _api;
    enum State               _state;
    NSMutableDictionary*     _downlinkStats;
    NSMutableArray*          _downlinkStatsRow;
    NSArray*                 _aecModes;
    NSArray*                 _nsModes;
    NSArray*                 _agcModes;
    CdoConnectionDescriptor* _connectionDescriptor;
    bool                     _speakerState;
    Reachability*            _reachability;
    NetworkStatus            _networkStatus;
    UIAlertView*             _alert;
}

// actions
- (void) connect;
- (void) disconnect;
- (void) setAudioProperty:(NSInteger) index 
			 :(NSString*) enable :(NSString*) mode;

// responses
- (void) onInit:(CdoError*) err;
- (void) onConnect:(CdoError*) err;
- (void) onDisconnect:(CdoError*) err;
- (void) onSetAudioProperty:(CdoError*) err;
- (void) onSpeakerResponse:(CdoError*) err;

// service listeners
- (void) connectionLost:(CdoConnectionLostEvent*) event;
- (void) userEvent:(CdoUserStateChangedEvent*) event;
- (void) mediaStream:(CdoUserStateChangedEvent*) event;
- (void) mediaStats:(CdoMediaStatsEvent*) event;
- (void) message:(CdoMessageEvent*) event;
- (void) mediaConnTypeChanged:(CdoMediaConnTypeChangedEvent*) event;
- (void) echo:(CdoEchoEvent*) event;

// action sheets
- (void) aecSheetClickedAtIndex:(NSInteger) index;
- (void) nsSheetClickedAtIndex:(NSInteger) index;
- (void) agcSheetClickedAtIndex:(NSInteger) index;

//
+ (char*) createTempFilename:(NSString*) template;
+ (void)  writeLog:(NSFileHandle*) fh;
- (void)  prepareEmail:(NSString*) filename;
- (void)  onReachabilityChanged:(NSNotification*) note;

@end

@implementation CdoViewController

@synthesize buttonConnectDisconnect;
@synthesize labelStatus;
@synthesize textFieldURL;
@synthesize labelUplinkStats;
@synthesize buttonAec;
@synthesize buttonNs;
@synthesize buttonAgc;
@synthesize tableViewDownlinkStats;

- (void) viewDidLoad
{
    [super viewDidLoad];

    // connection type notification. onReachabilityChanged is called

    _reachability = [[Reachability reachabilityForInternetConnection] retain];  

    _networkStatus = [_reachability currentReachabilityStatus];

    [[NSNotificationCenter defaultCenter] addObserver:self 
     selector:@selector(onReachabilityChanged:)
     name:kReachabilityChangedNotification object:nil];

    [_reachability startNotifier];

    // setup sheets for audio processing selection

    _aecModes = [[NSArray alloc] initWithObjects:
                 @"Disabled",
                 @"Quiet Earpiece or Headset",
                 @"Earpiece",
                 @"Loud Earpiece",
                 @"Speakerphone", 
                 @"Loud Speakerphone",
                 nil];
    
    _nsModes = [[NSArray alloc] initWithObjects:
                @"Disabled",
                @"Default", 
                @"Conference",
                @"Low Suppression",
                @"Moderate Suppression",
                @"High Suppression",
                @"Very High Suppression",
                nil];

    _agcModes = [[NSArray alloc] initWithObjects:
                 @"Disabled",
                 @"Default",
                 @"Adaptive Analog",
                 @"Adaptive Digital",
                 @"Fixed Digital",
                 nil];
    
    // initialize variables to default state

    _state = INIT;
    _speakerState = false;
    
    _downlinkStats = [[NSMutableDictionary alloc] init];
    _downlinkStatsRow = [[NSMutableArray alloc] init];

    [labelStatus setText:@"Initializing ..."];
    labelStatus.textColor = [UIColor cyanColor];

    // initialize Cloudeo API. Cloudeo API calls back to onInit

    _api = [[CdoAPI alloc] init];

    CdoInitOptions* options = [[CdoInitOptions alloc] init];

    CdoResponder* responder =
        [[CdoResponder alloc] init:@selector(onInit:):self];

    [_api initPlatform:options:responder];

    NSLog(@"viewDidLoad");
}

- (void) viewDidUnload
{
    [super viewDidUnload];

    [_api releasePlatform];
    _api = 0;
    
    NSLog(@"viewDidUnload");
}

- (BOOL) shouldAutorotateToInterfaceOrientation
:(UIInterfaceOrientation)interfaceOrientation
{
    return NO;

#if 0    
    if ([[UIDevice currentDevice] userInterfaceIdiom] 
	== UIUserInterfaceIdiomPhone)
    {
        return
            (interfaceOrientation != UIInterfaceOrientationPortraitUpsideDown);
    }
    else
    {
        return YES;
    }
#endif    
}

- (BOOL) shouldAutorotate
{
    return NO; // TODO
}

// called when connect/disconnect was pressed
- (IBAction) onConnectDisconnect
{
    if (_state == DISCONNECTED)
        [self connect];
    else
        [self disconnect];
}

// called when logs button was pressed
- (IBAction) onLogs
{
    // write log to temp. file
    
    char* cfilename =
        [CdoViewController createTempFilename:LOG_FILE_TEMPLATE];
    
    int fd = mkstemp(cfilename);
    if (fd < 0)
    {
        NSLog(@"Failed to open file for writing: %s", cfilename);
        return;
    }

    NSString* filename =
        [[NSFileManager defaultManager]
         stringWithFileSystemRepresentation:cfilename
         length:strlen(cfilename)];

    free(cfilename);

    NSFileHandle* fh = [[NSFileHandle alloc]
                        initWithFileDescriptor:fd
                        closeOnDealloc:YES];

    [CdoViewController writeLog:fh];

    // attach file to email

    [self prepareEmail:filename];

    if (! [[NSFileManager defaultManager] removeItemAtPath:filename error:nil])
      NSLog(@"cannot delete file");
}

// called when kill button was pressed
- (IBAction) onKill
{
    exit(0);
}

// called when speaker button was pressed
- (IBAction) onSpeaker
{
    if (_api == nil)
        return;
    
    CdoResponder* responder =
        [[CdoResponder alloc] init:@selector(onSpeakerResponse:):self];

    [_api setProperty:@"global.dev.audio.enableSpeaker"
     :[NSString stringWithFormat:@"%d", _speakerState]
     :responder];
}

// called when AEC button pressed (disabled)
- (IBAction) onAEC:(id) sender
{
    UIActionSheet* popupQuery = [[UIActionSheet alloc] 
                                 initWithTitle:@"AEC" 
                                 delegate:self 
                                 cancelButtonTitle:nil
                                 destructiveButtonTitle:nil
                                 otherButtonTitles:nil];

    for (int i=0; i<[_aecModes count]; i++)
        [popupQuery addButtonWithTitle:[_aecModes objectAtIndex:i]];
        
    popupQuery.actionSheetStyle = UIActionSheetStyleBlackTranslucent;
    popupQuery.tag = SHEET_AEC;
    
    [popupQuery showInView:self.view];
    [popupQuery release];
}

// called when NS button pressed
- (IBAction) onNS:(id) sender
{
    UIActionSheet* popupQuery = [[UIActionSheet alloc] 
                                 initWithTitle:@"NS" 
                                 delegate:self
                                 cancelButtonTitle:nil
                                 destructiveButtonTitle:nil
                                 otherButtonTitles:nil];

    for (int i=0; i<[_nsModes count]; i++)
        [popupQuery addButtonWithTitle:[_nsModes objectAtIndex:i]];
    
    popupQuery.actionSheetStyle = UIActionSheetStyleBlackTranslucent;
    popupQuery.tag = SHEET_NS;
    
    [popupQuery showInView:self.view];
    [popupQuery release];
}

// called when AGC button pressed
- (IBAction) onAGC:(id) sender
{
    UIActionSheet* popupQuery = [[UIActionSheet alloc] 
                                 initWithTitle:@"AGC" 
                                 delegate:self 
                                 cancelButtonTitle:nil
                                 destructiveButtonTitle:nil
                                 otherButtonTitles:nil];

    for (int i=0; i<[_agcModes count]; i++)
        [popupQuery addButtonWithTitle:[_agcModes objectAtIndex:i]];

    popupQuery.actionSheetStyle = UIActionSheetStyleBlackTranslucent;
    popupQuery.tag = SHEET_AGC;
    
    [popupQuery showInView:self.view];
    [popupQuery release];
}

// actions

// helper for to hash encode and converting to hex a given string
static NSString* sha256Hex(NSString* in)
{
    const char* cstr = [in cStringUsingEncoding:NSUTF8StringEncoding];
    NSData* data = [NSData dataWithBytes:cstr length:in.length];
    
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];

    CC_SHA256(data.bytes, data.length, digest);

    NSMutableString* out =
        [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
 
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++)
        [out appendFormat:@"%02x", digest[i]];

    return out;
}

- (void) connect
{
    [labelStatus setText:@"Connecting ..."];
    labelStatus.textColor = [UIColor cyanColor];

    // prepare connection descriptor (token, scopdId, url, autopublishAudio)

    char token[8];
    srand(time(0));
    int userId = 1 + (rand() % 10000);
    sprintf(token, "%d", userId);

    NSString* scopeId =
        [[[textFieldURL text] componentsSeparatedByString: @"/"]
         objectAtIndex:1];

    CdoConnectionDescriptor* desc = [[CdoConnectionDescriptor alloc] init];
    desc->url = [textFieldURL text];
    desc->token = [NSString stringWithCString:token
                   encoding:[NSString defaultCStringEncoding]];
    desc->autopublishAudio = true;

    // prepare authentication (userId, expires, salt, signature)

    desc->authDetails->userId = userId;
    desc->authDetails->expires = time(0) + 5 * 60;
    desc->authDetails->salt = @"Some random string salt";

    NSMutableString* signature = [[NSMutableString alloc] init];
    [signature appendFormat:@"%d%@%d%@%lld%@", CDO_SAMPLES_APP_ID, scopeId, 
	       userId, desc->authDetails->salt, desc->authDetails->expires,
	       CDO_SAMPLES_SECRET];
    desc->authDetails->signature = sha256Hex(signature);

    // 

    CdoResponder* responder =
        [[CdoResponder alloc] init:@selector(onConnect:):self];
    
    [_api connect:desc:responder]; // response to onConnect

    //

    buttonConnectDisconnect.enabled = NO;
    textFieldURL.enabled = NO;
}

- (void) disconnect
{
    [labelStatus setText:@"Disconnecting ..."];
    labelStatus.textColor = [UIColor cyanColor];

    //

    CdoResponder* responder =
        [[CdoResponder alloc] init:@selector(onDisconnect:):self];

    NSString* scopeId =
        [[[textFieldURL text] componentsSeparatedByString: @"/"]
         objectAtIndex:1];
    
    [_api disconnect:scopeId:responder]; // response to onDisconnect

    //

    buttonConnectDisconnect.enabled = NO;
}

- (void) setAudioProperty:(NSInteger) index 
			 :(NSString*) enable :(NSString*) mode
{
    NSString* prefix = @"global.dev.audio.";
    
    CdoResponder* responder =
        [[CdoResponder alloc] init:@selector(onSetAudioProperty:):self];

    int pos = (int) index;
    
    if (pos == 0)
    {
        [_api
         setProperty:[NSString stringWithFormat:@"%@%@", prefix, enable]
         :@"0"
         :responder
         ];
    }
    else
    {
        [_api
         setProperty:[NSString stringWithFormat:@"%@%@", prefix, enable]
         :@"1"
         :responder
         ];

        [_api
         setProperty:[NSString stringWithFormat:@"%@%@", prefix, mode]
         :[NSString stringWithFormat:@"%d", pos - 1]
         :responder
         ];
    }    
}

// responses

- (void) onInit:(CdoError*) err
{
    if ([CdoAPI onMainThreadHelper_1:@selector(onInit:):self:err])
        return;

    NSLog(@"onInit %d", (int)_state);
        
    if (err->err_code)
    {
        [labelStatus
         setText:@"Error - failed to initialize the SDK: kill the application"];
        labelStatus.textColor = [UIColor redColor];
    }
    else
    {
        if (_state == INIT) // initPlatform succeeded
        {
	    // set service listeners

            _state = INIT_SERVICE_LISTENER;
            
            CdoResponder* responder =
                [[CdoResponder alloc] init:@selector(onInit:):self];
                
            [_api addServiceListener:self:responder];

            return;
        }

	if (_state == INIT_SERVICE_LISTENER) // addServiceListener succeeded
	{
	    // set application id

	    _state = INIT_APPLICATION_ID;

	    CdoResponder* responder =
	      [[CdoResponder alloc] init:@selector(onInit:):self];

	    [_api setApplicationId:CDO_SAMPLES_APP_ID:responder];	    

	    return;
	}

	// setApplicationId succeeded

        _state = DISCONNECTED;

        [labelStatus setText:@"Ready"];
        labelStatus.textColor = [UIColor yellowColor];

        [self nsSheetClickedAtIndex:6];  // set default noise suppression mode
        [self agcSheetClickedAtIndex:4]; // set default gain control mode

	// from here on the application is ready 
    }
}

- (void) onConnect:(CdoError*) err
{
    if ([CdoAPI onMainThreadHelper_1:@selector(onConnect:):self:err])
        return;

    NSLog(@"onConnect");

    buttonConnectDisconnect.enabled = YES;
    
    if (err->err_code) // error
    {
        textFieldURL.enabled = YES;

        [labelStatus setText:[NSString stringWithFormat:@"ERROR %d: %@",
                              err->err_code, err->err_message]];
        labelStatus.textColor = [UIColor redColor];
        
        [buttonConnectDisconnect
         setTitle:@"Connect" forState:UIControlStateNormal];

        return;
    }

    // connect succeeded

    _state = CONNECTED;

    // prevent app from becoming idle
    [[UIApplication sharedApplication] setIdleTimerDisabled:YES];
    
    [labelStatus setText: @"In Call"];
    labelStatus.textColor = [UIColor greenColor];
        
    [buttonConnectDisconnect
     setTitle:@"Disconnect" forState:UIControlStateNormal];    
}

- (void) onDisconnect:(CdoError*) err
{
    if ([CdoAPI onMainThreadHelper_1:@selector(onDisconnect:):self:err])
        return;

    NSLog(@"onDisconnect");

    buttonConnectDisconnect.enabled = YES;

    textFieldURL.enabled = YES;
    
    _state = DISCONNECTED;

    // app can be become idle again
    [[UIApplication sharedApplication] setIdleTimerDisabled:NO];
    
    if (err->err_code) // error
    {
        [labelStatus setText:[NSString stringWithFormat:@"ERROR %d: %@",
                              err->err_code, err->err_message]];        
        labelStatus.textColor = [UIColor redColor];
    }
    else // succeeded
    {
        [labelStatus setText:@"Ready"];
        labelStatus.textColor = [UIColor yellowColor];
    }
    
    [buttonConnectDisconnect
     setTitle:@"Connect" forState:UIControlStateNormal];
}

- (void) onSetAudioProperty:(CdoError*) err
{
    if ([CdoAPI onMainThreadHelper_1:@selector(onSetAudioProperty:):self:err])
        return;

    NSLog(@"onSetAudioProperty");

    if (err->err_code)
        NSLog(@"ERROR %d: %@", err->err_code, err->err_message);
}

- (void) onSpeakerResponse:(CdoError*) err
{
    if ([CdoAPI onMainThreadHelper_1:@selector(onSpeakerResponse:):self:err])
        return;
    
    NSLog(@"onSpeakerResponse");

    if (err->err_code == 0)
        _speakerState = ! _speakerState;
    else
        NSLog(@"ERROR %d: %@", err->err_code, err->err_message);
}

// service listeners

- (void) connectionLost:(CdoConnectionLostEvent*) event
{
    if ([CdoAPI onMainThreadHelper_1:@selector(connectionLost:):self:event])
        return;

    _state = DISCONNECTED;

    [[UIApplication sharedApplication] setIdleTimerDisabled:NO];
    
    [labelStatus setText:[NSString stringWithFormat:@"ERROR %d: %@",
                          event->errCode, event->errMessage]];
    labelStatus.textColor = [UIColor redColor];   

    [buttonConnectDisconnect
     setTitle:@"Connect" forState:UIControlStateNormal];
}

- (void) userEvent:(CdoUserStateChangedEvent*) event
{
    if ([CdoAPI onMainThreadHelper_1:@selector(userEvent:):self:event])
        return;        

    if (event->isConnected)
    {
        NSString* stats = [NSString stringWithFormat:
                           @"User %lld Stats", event->userId];

        [_downlinkStats setObject:stats forKey:[NSNumber numberWithLongLong
                                                   :event->userId]];

        [_downlinkStatsRow addObject:[NSNumber numberWithLongLong
                                      :event->userId]];
    }
    else
    {
        [_downlinkStats removeObjectForKey:[NSNumber numberWithLongLong
                                            :event->userId]];
        [_downlinkStatsRow removeObject:[NSNumber numberWithLongLong
                                         :event->userId]];
    }
    
    [tableViewDownlinkStats reloadData];
}

- (void) mediaStream:(CdoUserStateChangedEvent*) event
{
    if ([CdoAPI onMainThreadHelper_1:@selector(mediaStream:):self:event])
        return;

    // TODO
}

- (void) mediaStats:(CdoMediaStatsEvent*) event
{
    if ([CdoAPI onMainThreadHelper_1:@selector(mediaStats:):self:event])
        return;

    if (! [event->mediaType isEqualToString:@"audio"])
        return;

    if (event->remoteUserId < 0) // uplink stats
    {
        NSString* stats = [NSString stringWithFormat:
            @"kbps = %0.1f RTT = %0.1f #Loss = %d %%Loss = %0.1f",
            8.0f * event->stats->bitRate / 1000.0f,
            event->stats->rtt,
            event->stats->totalLoss,
            event->stats->loss];
    
        [labelUplinkStats setText:stats];
    }
    else // downlink stats
    {
        NSString* stats = [_downlinkStats objectForKey:
                           [NSNumber numberWithLongLong:event->remoteUserId]];
        if (stats == nil)
            return;

        stats = [NSString stringWithFormat:
                 @"User %lld: kbps %0.1f #Loss = %d %%Loss = %0.1f",
                 event->remoteUserId, 
                 8.0f * event->stats->bitRate / 1000.0f,
                 event->stats->totalLoss,
                 event->stats->loss];

        [_downlinkStats setObject:stats forKey:[NSNumber numberWithLongLong
                                                :event->remoteUserId]];
        
        [tableViewDownlinkStats reloadData];
    }
}

- (void) message:(CdoMessageEvent*) event
{
    if ([CdoAPI onMainThreadHelper_1:@selector(message:):self:event])
        return;

    // TODO    
}

- (void) mediaConnTypeChanged:(CdoMediaConnTypeChangedEvent*) event
{
    if ([CdoAPI onMainThreadHelper_1:@selector(mediaConnTypeChanged:)
         :self:event])
        return;
    
    if (! [event->mediaType isEqualToString:@"audio"])
        return;

    NSLog(@"Connection type: %@", event->connectionType);
}

- (void) echo:(CdoEchoEvent*) event
{
    if ([CdoAPI onMainThreadHelper_1:@selector(echo:):self:event])
        return;

    // TODO
}

// actions sheets

- (void) actionSheet:(UIActionSheet*) actionSheet 
clickedButtonAtIndex: (NSInteger) buttonIndex
{
    if (buttonIndex < 0)
        return;
    
    switch (actionSheet.tag)
    {
        case SHEET_AEC: 
            [self aecSheetClickedAtIndex:buttonIndex];
            break;
        case SHEET_NS:
            [self nsSheetClickedAtIndex:buttonIndex];
            break;
        case SHEET_AGC:
            [self agcSheetClickedAtIndex:buttonIndex];
            break;
    }
}

- (void) aecSheetClickedAtIndex:(NSInteger) index
{
    [self setAudioProperty:index:@"enableAEC":@"modeAECM"];
    [buttonAec setTitle:[_aecModes objectAtIndex:index]
     forState:UIControlStateNormal];
}

- (void) nsSheetClickedAtIndex:(NSInteger) index
{
    [self setAudioProperty:index:@"enableNS":@"modeNS"];
    [buttonNs setTitle:[_nsModes objectAtIndex:index]
     forState:UIControlStateNormal];
}

- (void) agcSheetClickedAtIndex:(NSInteger) index
{
    [self setAudioProperty:index:@"enableAGC":@"modeAGC"];
    [buttonAgc setTitle:[_agcModes objectAtIndex:index]
     forState:UIControlStateNormal];
}

//

+ (char*) createTempFilename:(NSString*) template
{
    NSString* tempFileTemplate =
        [NSTemporaryDirectory() stringByAppendingPathComponent:template];
    const char* tempFileTemplateCString =
        [tempFileTemplate fileSystemRepresentation];
    char* tempFileNameCString =
        (char*) malloc(strlen(tempFileTemplateCString) + 1);
    strcpy(tempFileNameCString, tempFileTemplateCString);
    return tempFileNameCString;
}

+ (void) writeLog:(NSFileHandle*) fh
{
    NSMutableDictionary* levelString = [NSMutableDictionary dictionary];
    [levelString setObject:@"EMERG" forKey:@"0"];
    [levelString setObject:@"ALERT" forKey:@"1"];
    [levelString setObject:@"CRIT" forKey:@"2"];
    [levelString setObject:@"ERROR" forKey:@"3"];
    [levelString setObject:@"WARN" forKey:@"4"];
#ifdef NDEBUG
    [levelString setObject:@"NOTICE" forKey:@"5"]; 
#else
    [levelString setObject:@"DEBUG" forKey:@"5"];
#endif
    
    //[levelString setObject:@"INFO" forKey:@"6"];
    //[levelString setObject:@"DEBUG" forKey:@"7"]; 

    NSDate* startDate = [NSDate dateWithTimeIntervalSinceNow:-3600];
    NSString* logSince = [NSString stringWithFormat:@"%.0f",
                          [startDate timeIntervalSince1970]];
    
    aslmsg q = asl_new(ASL_TYPE_QUERY);
    asl_set_query(q, ASL_KEY_TIME, [logSince UTF8String],
                  ASL_QUERY_OP_GREATER_EQUAL);
    asl_set_query(q, ASL_KEY_SENDER, LOG_KEY_SENDER, ASL_QUERY_OP_EQUAL);
    asl_set_query(q, ASL_KEY_LEVEL, "7",
                  ASL_QUERY_OP_LESS_EQUAL | ASL_QUERY_OP_NUMERIC);

    aslresponse r = asl_search(NULL, q);

    aslmsg m;
    while ((m = aslresponse_next(r)))
    {
        NSMutableDictionary* tmpDict = [NSMutableDictionary dictionary];

        char* key;
        for (int i = 0; (key = asl_key(m, i)); i++)
	{
            NSString* keyString = [NSString stringWithUTF8String:(char*)key];
 
            const char* val = asl_get(m, key);
            NSString* valString = [NSString stringWithUTF8String:val];

            [tmpDict setObject:valString forKey:keyString];
	}

        int time;
        [[NSScanner scannerWithString:[tmpDict objectForKey:@"Time"]]
         scanInteger:&time];
        NSDate* date = [NSDate dateWithTimeIntervalSince1970:time];

        NSDateFormatter* formatter = [[NSDateFormatter alloc] init];
        [formatter setDateFormat:@"dd-MM-yyyy HH:mm:ss"];
        NSString* dateString = [formatter stringFromDate:date];
        [formatter release];
        
        NSString* tmpEntry = [NSString stringWithFormat:@"%@ <%@> %@\n",
                              dateString,
                              [levelString objectForKey:
                               [tmpDict objectForKey:@"Level"]],
                              [tmpDict objectForKey:@"Message"]];

        [fh writeData:[tmpEntry dataUsingEncoding:NSUTF8StringEncoding]];
    }

    aslresponse_free(r);

    [fh synchronizeFile];
}

// email

- (void) prepareEmail:(NSString*) filename
{
    MFMailComposeViewController* controller =
        [[[MFMailComposeViewController alloc] init] autorelease];
    controller.mailComposeDelegate = self;
    
    [controller setSubject:LOG_EMAIL_SUBJECT];
    [controller setToRecipients:
     [NSArray arrayWithObjects:LOG_RECEIVER_EMAIL,nil]];
    [controller setMessageBody:@"" isHTML:NO];

    NSData* data = [NSData dataWithContentsOfFile:filename];

    [controller addAttachmentData:data mimeType:@"text/plain"
     fileName:LOG_FILE_EMAIL];
    
    [self presentModalViewController:controller animated:YES];
}

- (void) mailComposeController:(MFMailComposeViewController*) controller 
	   didFinishWithResult:(MFMailComposeResult) result 
			 error:(NSError*) error
{
    [self dismissModalViewControllerAnimated:YES];
}

// UI downlink stats

- (NSInteger) numberOfSectionsInTableView:(UITableView*)tableView
{
    return 1;
}

- (NSInteger) tableView:
(UITableView*)tableView numberOfRowsInSection:(NSInteger)section
{       
    return [_downlinkStats count];
}

- (UITableViewCell *)tableView:
(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath
{
    UITableViewCell* cell =
        [tableViewDownlinkStats dequeueReusableCellWithIdentifier:@"0"];

    if (cell == nil)
    {
        cell = [[[UITableViewCell alloc]
                 initWithStyle:
                 UITableViewCellStyleDefault reuseIdentifier:@"0"] autorelease];
    }

    NSNumber* userId =
        [_downlinkStatsRow objectAtIndex: indexPath.row];

    float fontSize = 17.0f;
    if ([[UIDevice currentDevice] userInterfaceIdiom]
        == UIUserInterfaceIdiomPhone)
    {
        fontSize = 12.0f;
    }

    cell.textLabel.text = [_downlinkStats objectForKey:userId];
    cell.textLabel.textAlignment = UITextAlignmentCenter;
    cell.textLabel.textColor = [UIColor whiteColor];
    cell.textLabel.font = [[UIFont class] systemFontOfSize:fontSize];
    
    return cell;
}

// reachability

- (void) onReachabilityChanged:(NSNotification*) note
{
    Reachability* info = [note object];
    NetworkStatus status = [info currentReachabilityStatus];

    if (status == _networkStatus)
        return;

    [_alert dismissWithClickedButtonIndex:0 animated:YES];
    
    NSString* message = [NSString
                         stringWithFormat:@"Connection changed to %@",
                         [Reachability stringNetworkStatus:status]];

    _alert =
        [[UIAlertView alloc] initWithTitle: @"Connection"
         message: message
         delegate: self
         cancelButtonTitle: @"OK"
         otherButtonTitles: nil];
    [_alert show];
    [_alert release];
    
    _networkStatus = status;

    // TODO
}

@end
