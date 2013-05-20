/*
 * Copyright (C) LiveFoundry Inc 2012
 *
 * All rights reserved. Any use, copying, modification, distribution and selling
 * of this software and it's documentation for any purposes without authors' written
 * permission is hereby prohibited.
 */

#import "CdoViewController.h"
#import "Reachability.h"

#include <asl.h>
#include <time.h>

//

NSString* LOG_RECEIVER_EMAIL = @"dev@addlive.com";
NSString* LOG_EMAIL_SUBJECT = @"AddLiveSDK iOS - Logs";
NSString* LOG_FILE_TEMPLATE = @"log.XXXXXX";
NSString* LOG_FILE_EMAIL = @"log.txt";
char* LOG_KEY_SENDER = "AddLive_SDK";

int AL_SAMPLE_APP_ID = 1;
NSString* AL_SAMPLE_KEY = @"CloudeoTestAccountSecret";

//

#define AUTO_ROTATE 0

//

@interface User : NSObject
@property (nonatomic,copy) NSString* statsAudio;
@property (nonatomic,copy) NSString* statsVideo;
@property (nonatomic,copy) NSString* videoSinkId;
@property (nonatomic,copy) NSString* screenSinkId;
- (id) init;
@end

@implementation User
- (id) init
{
    self = [super init];
    if (self)
    {
        self.statsAudio = @"";
	self.statsVideo = @"";
	self.videoSinkId = @"";
	self.screenSinkId = @"";
    }
    return self;
}
@end

//

@interface CdoViewController ()

{
    enum State
    {
        INIT,
        DISCONNECTED,
        CONNECTED,
        ONHOLD,
        LOST_CONNECTION,
    };

    enum Sheet
    {
        SHEET_NS,
	SHEET_CAMERA,
    };
    
    ALService*              _service;
    enum State              _state;
    BOOL                    _isBackgroundMode;
    NSString*               _uplinkStatsAudio;
    NSString*               _uplinkStatsVideo;
    NSMutableDictionary*    _users;
    NSMutableArray*         _downlinkStatsRow;
    Reachability*           _reachability;
    NetworkStatus           _networkStatus;
    UIAlertView*            _alert;
    NSMutableDictionary*    _videoSinkToVideoView;
    NSString*               _version;
    NSArray*                _cameraDevices;
    long long               _userId;
    int                     _connectAttempts;
}

// responses
- (void) onInitPlatform:(ALError*) err;
- (void) onInitAddServiceListener:(ALError*) err;
- (void) onInitGetVideoCaptureDeviceNames:(ALError*) err 
				  devices:(NSArray*) devices;
- (void) onConnect:(ALError*) err;
- (void) onDisconnect:(ALError*) err;
- (void) onReconnect:(ALError*) err;
- (void) onHold:(ALError*) err;
- (void) onSetNSMode:(ALError*) err;
- (void) onSpeakerResponse:(ALError*) err;
- (void) onSetVideoCaptureDevice:(ALError*) err;
- (void) onStartLocalVideo:(ALError*) err
	       videoSinkId:(NSString*) videoSinkId;
- (void) onStopLocalVideo:(ALError*) err;
- (void) onPublish:(ALError*) err;
- (void) onUnpublish:(ALError*) err;
- (void) onGetVersion:(ALError*) err 
	      version:(NSString*) version;
- (void) onNetworkTest:(ALError*) err 
	       quality:(NSNumber*) quality;
- (void) onSetAllowedSenders:(ALError*) err;
- (void) onStartMeasuringStats:(ALError*) err;

// private
- (void) showError:(NSString*) errorMsg;
- (void) showBusy:(NSString*) busyMsg;
- (void) showReady;
- (void) showInCall;
- (void) connect;
- (void) disconnect;
- (void) reconnect;
- (void) hold;
- (void) showEmailView:(NSString*) filenameAttachment;
- (void) audioStats:(ALMediaStatsEvent*) event;
- (void) videoStats:(ALMediaStatsEvent*) event;
- (void) lockUI;
- (void) unlockUI:(BOOL) enableURL;
- (NSString*) scopeId;
- (BOOL) isURL;
- (void) reloadDownlinkStats;
- (void) cleanUpAfterDisconnect;
- (void) selectVideo:(User*) user;
- (void) putCallOnHold;
- (void) startNetworkTest;
+ (char*) createTempFilename:(NSString*) template;
+ (void) writeLog:(NSFileHandle*) fh;

// action sheets
- (void) nsSheetClickedAtIndex:(NSInteger) index;
- (void) cameraSheetClickedAtIndex:(NSInteger) index;

// reachability
- (void) onReachabilityChanged:(NSNotification*) note;

@end

@implementation CdoViewController

@synthesize scrollView;
@synthesize contentView;
@synthesize buttonConnectDisconnect;
@synthesize switchSpeaker;
@synthesize switchPublishVideo;
@synthesize switchPublishAudio;
@synthesize labelStatus;
@synthesize textFieldURL;
@synthesize labelUplinkStats;
@synthesize buttonNs;
@synthesize buttonCamera;
@synthesize tableViewDownlinkStats;
@synthesize viewVideo0;
@synthesize viewVideo1;

- (id) init
{
    self = [super init];
    if (self)
    {
      _service = nil;	
      _state = INIT;
      _isBackgroundMode = NO;
      _uplinkStatsAudio = nil;
      _uplinkStatsVideo = nil;
      _downlinkStatsRow = nil;
      _users = nil;
      _reachability = nil;
      _networkStatus = NotReachable;
      _alert = nil;
      _videoSinkToVideoView = nil;
      _version = nil;
      _cameraDevices = nil;
      _userId = 0;
      _connectAttempts = 0;
    }
    return self;
}

- (void) dealloc
{
    [_cameraDevices release];
    _cameraDevices = nil;

    [_version release];
    _version = nil;

    [_videoSinkToVideoView release];
    _videoSinkToVideoView = nil;

    [_reachability release];
    _reachability = nil;

    [_downlinkStatsRow release];
    _downlinkStatsRow = nil;

    [_uplinkStatsAudio release];
    _uplinkStatsAudio = nil;

    [_uplinkStatsVideo release];
    _uplinkStatsVideo = nil;
    
    [_users release];
    _users = nil;

    [_alert release];
    _alert = nil;

    [super dealloc];
}

- (void) viewDidLoad
{
    [super viewDidLoad];

    [self lockUI];

    // set user id
    srand(time(0));
    _userId = 1 + (rand() % 1000);

    // setup scroll view
    [self.scrollView addSubview:self.contentView];
    self.scrollView.contentSize = self.contentView.bounds.size;
    self.switchSpeaker.on = NO;

    _videoSinkToVideoView = [[NSMutableDictionary alloc] init];

    // connection type notification. onReachabilityChanged is called
    _reachability = [[Reachability reachabilityForInternetConnection] retain];  
    _networkStatus = [_reachability currentReachabilityStatus];

    [[NSNotificationCenter defaultCenter] addObserver:self 
     selector:@selector(onReachabilityChanged:)
     name:kReachabilityChangedNotification object:nil];

    [_reachability startNotifier];

    //
    _state = INIT;
    _isBackgroundMode = NO;
    _connectAttempts = 0;
    
    _downlinkStatsRow = [[NSMutableArray alloc] init];
    _users = [[NSMutableDictionary alloc] init];

    [self showBusy:@"Initializing ..."];

    // initialize AddLive API. API calls back to onInitPlatform
    _service = [[ALService alloc] 
		 initWithAppId:[NSNumber numberWithInt:AL_SAMPLE_APP_ID]
			appKey:AL_SAMPLE_KEY
		];

    ALInitOptions* options = [[[ALInitOptions alloc] init] autorelease];

    ALResponder* responder =
      [[[ALResponder alloc] 
	 initWithSelector:@selector(onInitPlatform:) withObject:self] 
	autorelease];
    [_service initPlatform:options
		 responder:responder];

    NSLog(@"viewDidLoad");
}

- (void) viewDidUnload
{
    [super viewDidUnload];

    // release the API
    [_service releasePlatform];
    [_service release];
    _service = nil;
    
    NSLog(@"viewDidUnload");
}

- (BOOL) shouldAutorotateToInterfaceOrientation
:(UIInterfaceOrientation)interfaceOrientation
{
#if AUTO_ROTATE
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
#else
    return NO;
#endif    
}

- (BOOL) shouldAutorotate
{
#if AUTO_ROTATE
    return YES;
#else
    return NO;
#endif
}

// called when connect/disconnect was pressed
- (IBAction) onConnectDisconnect
{
    if (_state == INIT)
    {
       return;	
    }

    if (_state == DISCONNECTED || _state == ONHOLD)
    {
        [self connect];
    }
    else
    {
        [self disconnect];
    }
}

// called when publish video state changed
- (IBAction) onPublishVideo
{
    if (_state != CONNECTED)
    {
        return;
    }

    if (self.switchPublishVideo.isOn)
    {
        [self showBusy:@"Publishing video ..."];

        ALResponder* responder =
	  [[[ALResponder alloc] 
	     initWithSelector:@selector(onPublish:)
		   withObject:self] autorelease];

	[_service publish:[self scopeId] 
		     what:@"video"
		  options:nil
		responder:responder];
    }
    else
    {
        [self showBusy:@"Unpublishing video ..."];

        ALResponder* responder =
	  [[[ALResponder alloc] 
	     initWithSelector:@selector(onUnpublish:)
		   withObject:self] 
	    autorelease];

        [_service unpublish:[self scopeId]
		       what:@"video"
		  responder:responder];
    }
}

// called when publish audio state changed
- (IBAction) onPublishAudio
{
    if (_state != CONNECTED)
    {
        return;
    }

    if (self.switchPublishAudio.isOn)
    {
        [self showBusy:@"Publishing audio ..."];

        ALResponder* responder =
	  [[[ALResponder alloc] 
	     initWithSelector:@selector(onPublish:)
		   withObject:self] autorelease];

	[_service publish:[self scopeId]
		     what:@"audio"
		  options:nil
		responder:responder];
    }
    else
    {
        [self showBusy:@"Unpublishing audio ..."];

        ALResponder* responder =
	  [[[ALResponder alloc] 
	     initWithSelector:@selector(onUnpublish:)
		   withObject:self] 
	    autorelease];

        [_service unpublish:[self scopeId]
		       what:@"audio"
		  responder:responder];
    }
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

    [self showEmailView:filename];

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
    ALResponder* responder =
      [[[ALResponder alloc] 
	 initWithSelector:@selector(onSpeakerResponse:)
	       withObject:self] 
	autorelease];

    [_service enableSpeaker:self.switchSpeaker.isOn
		  responder:responder];
}

// called when NS button pressed
- (IBAction) onNS
{
    UIActionSheet* popupQuery = [[UIActionSheet alloc] 
                                 initWithTitle:@"NS" 
                                 delegate:self
                                 cancelButtonTitle:nil
                                 destructiveButtonTitle:nil
                                 otherButtonTitles:nil];

    NSArray* nsModes = [ALService getNSModes];

    for (int i=0; i<[nsModes count]; i++)
    {
        [popupQuery addButtonWithTitle:[nsModes objectAtIndex:i]];
    }

    popupQuery.actionSheetStyle = UIActionSheetStyleBlackTranslucent;
    popupQuery.tag = SHEET_NS;
    
    [popupQuery showInView:self.view];
    [popupQuery release];
}

// called when Camera button pressed
- (IBAction) onCamera
{
    UIActionSheet* popupQuery = [[UIActionSheet alloc] 
				  initWithTitle:@"Video Devices" 
				       delegate:self 
				  cancelButtonTitle:nil
				  destructiveButtonTitle:nil
				  otherButtonTitles:nil];

    for (ALDevice* d in _cameraDevices)
    {
      [popupQuery addButtonWithTitle:d.label];
    }
    
    popupQuery.actionSheetStyle = UIActionSheetStyleBlackTranslucent;
    popupQuery.tag = SHEET_CAMERA;
    
    [popupQuery showInView:self.view];
    [popupQuery release];
}

// called when swipe left on viewVideo1: changes remote video feed
- (IBAction) onSwipeLeft
{
    NSIndexPath* ipath = [tableViewDownlinkStats indexPathForSelectedRow];

    for (int i = 0; i < [_downlinkStatsRow count]; ++i)
    {
        NSUInteger prev = (ipath.row + [_downlinkStatsRow count] - i) %
	  [_downlinkStatsRow count];

	if (prev == ipath.row)
	  continue;

	NSNumber* uId = [_downlinkStatsRow objectAtIndex:prev];
	User* user = [_users objectForKey:uId];
      
	if (user)
	{
	    [self selectVideo:user];
	    return;
	}
    }
}

// called when swipe right on viewVideo1: changes remote video feed
- (IBAction) onSwipeRight
{
    NSIndexPath* ipath = [tableViewDownlinkStats indexPathForSelectedRow];

    for (int i = 0; i < [_downlinkStatsRow count]; ++i)
    {
        NSUInteger next = (ipath.row + i) % [_downlinkStatsRow count];

	if (next == ipath.row)
	  continue;

	NSNumber* uId = [_downlinkStatsRow objectAtIndex:next];
	User* user = [_users objectForKey:uId];
      
	if (user)
	{
	    [self selectVideo:user];
	    return;
	}
    }
}

- (void) becomeActive
{
    [self.viewVideo0 resume];
    [self.viewVideo1 resume];
}

- (void) resignActive
{
    [self.viewVideo0 pause];
    [self.viewVideo1 pause];    
}

// called from application delegate when app goes into foreground
- (void) enterForeground
{
    if (_state == ONHOLD) // resume call if previously on hold
    {
        NSLog(@"Resuming call");

        [self connect];

	// show a local notification
	[[UIApplication sharedApplication] cancelAllLocalNotifications];

	UILocalNotification* localNotification = 
	  [[[UILocalNotification alloc] init] autorelease];

	localNotification.alertBody = @"Resuming AddLive conference.";
	localNotification.applicationIconBadgeNumber = 0;
	localNotification.soundName = UILocalNotificationDefaultSoundName;
	localNotification.fireDate = nil;

	[[UIApplication sharedApplication] 
	    scheduleLocalNotification:localNotification];
    }

    // publish video
    [self onPublishVideo];

    // start local video preview
    ALResponder* responder =
      [[[ALResponder alloc] 
	     initWithSelector:@selector(onStartLocalVideo:videoSinkId:)
		   withObject:self]
	autorelease];
    [_service startLocalVideo:responder];

    _isBackgroundMode = NO;
}

// called from application delegate when app went into background
- (void) enterBackground
{
    _isBackgroundMode = YES;

    // unpublish video
    if (self.switchPublishVideo.isOn)
    {
        self.switchPublishVideo.on = NO;
        [self onPublishVideo];
	self.switchPublishVideo.on = YES;
    }

    // stop local video preview
    ALResponder* responder =
      [[[ALResponder alloc] 
	     initWithSelector:@selector(onStopLocalVideo:)
		   withObject:self]
	autorelease];
    [_service stopLocalVideo:responder];
}

// responses

- (void) onInitPlatform:(ALError*) err
{
    NSLog(@"onInitPlatform");

    if (err)
    {
        [self showError:
	  [NSString stringWithFormat:@"Failed to initialize the SDK. <%@>", 
		    err]];
	[self unlockUI:YES];
    }
    else
    {
        // setup video views
        self.viewVideo0.service = _service; // local video
	self.viewVideo0.mirror  = YES;
	self.viewVideo1.service = _service; // remote video
	self.viewVideo1.mirror  = NO;

	// set service listeners
	ALResponder* respAddServiceListener =
	  [[[ALResponder alloc] 
		   initWithSelector:@selector(onInitAddServiceListener:)
			 withObject:self] 
	    autorelease];
                
	[_service addServiceListener:self
			   responder:respAddServiceListener];

	// get version string
	ALResponder* respGetVersion =
	  [[[ALResponder alloc]
		 initWithSelector:@selector(onGetVersion:version:)
		       withObject:self]
	    autorelease];
	[_service getVersion:respGetVersion];
    }
}

- (void) onInitAddServiceListener:(ALError*) err
{
    NSLog(@"onInitAddServiceListener");

    if (err)
    {
        [self showError:
	  [NSString stringWithFormat:@"Failed to initialize the SDK. <%@>", 
		    err]];
	[self unlockUI:YES];
    }
    else
    {
	// get video devices
        ALResponder* responder =
	  [[[ALResponder alloc] 
	     initWithSelector:
	       @selector(onInitGetVideoCaptureDeviceNames:devices:)
		   withObject:self] 
	    autorelease];
	[_service getVideoCaptureDeviceNames:responder];
    }
}

- (void) onInitGetVideoCaptureDeviceNames:(ALError*) err 
				  devices:(NSArray*) devices
{
    NSLog(@"onInitGetVideoCaptureDeviceNames");

    if (err)
    {
        [self showError:
	  [NSString stringWithFormat:@"Failed to initialize the SDK. <%@>", 
		    err]];
	[self unlockUI:YES];
    }
    else
    {
        [_cameraDevices release];
	_cameraDevices = [devices copy];

	// from here on the application is ready
        _state = DISCONNECTED;

	[self cameraSheetClickedAtIndex:0]; // set default camera (front)
	[self nsSheetClickedAtIndex:6]; // set default noise suppression mode

	// start local video preview      
	ALResponder* responder =
	  [[[ALResponder alloc] 
	     initWithSelector:@selector(onStartLocalVideo:videoSinkId:)
		   withObject:self]
	    autorelease];
	[_service startLocalVideo:responder];

	[self showReady];
    	[self unlockUI:YES];
    }
}

- (void) onConnect:(ALError*) err
{
    NSLog(@"onConnect");

    if (err) // error
    {
        _state = DISCONNECTED;

	if ((err.err_code == kCommInvalidHost) && (_connectAttempts < 3))
	{
	    // retry to connect - connection might not be ready

	    [NSTimer scheduledTimerWithTimeInterval:2.0
					     target:self
					   selector:@selector(connect)
					   userInfo:nil
					    repeats:NO];
	}
	else
	{
	    if (err.err_code == kCommClientVersionNotSupported)
	    {
	        [_alert dismissWithClickedButtonIndex:0 animated:YES];
    
		NSString* message = 
		  [NSString stringWithFormat:
			      @"Version %@ is not supported. Please upgrade.",
			    _version];

		[_alert release];
		_alert =
		  [[UIAlertView alloc] initWithTitle: @"Unsupported version."
					     message: message
					    delegate: self
				   cancelButtonTitle: @"OK"
				   otherButtonTitles: nil];
		[_alert show];
	    }

	    [self showError:[NSString stringWithFormat:@"ERROR %@", err]];

	    [self unlockUI:YES];

	    [buttonConnectDisconnect
	      setTitle:@"Connect" forState:UIControlStateNormal];

	    _connectAttempts = 0;
	}
    }
    else // connect succeeded
    {
        NSLog(@"Success");

	_state = CONNECTED;
	_connectAttempts = 0;

        [self unlockUI:NO];       
	[self showInCall];
        
	// prevent app from becoming idle
	[[UIApplication sharedApplication] setIdleTimerDisabled:YES];

	[buttonConnectDisconnect
	  setTitle:@"Disconnect" forState:UIControlStateNormal];

	// start measuring stats
	ALResponder* responder =
	  [[[ALResponder alloc] 
	     initWithSelector:@selector(onStartMeasuringStats:) 
		   withObject:self] autorelease];
	[_service startMeasuringStats:[self scopeId]
			     interval:[NSNumber numberWithInt:2]
			    responder:responder];
    }
}

- (void) onDisconnect:(ALError*) err
{
    NSLog(@"onDisconnect");

    [self unlockUI:YES];
    
    _state = DISCONNECTED;

    // app can be become idle again
    [[UIApplication sharedApplication] setIdleTimerDisabled:NO];
    
    if (err) // error
    {
        [self showError:[NSString stringWithFormat:@"ERROR %@", err]];
    }
    else // succeeded
    {
        NSLog(@"Success");

        [self showReady];
    }

    [self cleanUpAfterDisconnect];
}

- (void) onReconnect:(ALError*) err
{
    NSLog(@"onReconnect");

    if (err && err.err_code != kLogicInvalidScope) // error
    {
        [self unlockUI:YES];

        [self showError:[NSString stringWithFormat:@"ERROR %@", err]];
    }
    else // succeeded
    {
        [self connect];
    }

    [self cleanUpAfterDisconnect];
}

- (void) onHold:(ALError*) err
{
    NSLog(@"onHold");

    [self unlockUI:NO];
    
    _state = ONHOLD;

    // app can be become idle again
    [[UIApplication sharedApplication] setIdleTimerDisabled:NO];
    
    if (err) // error
    {
        [self showError:[NSString stringWithFormat:@"ERROR %@", err]];
    }
    else // succeeded
    {
        NSLog(@"Success");

        [self showBusy:@"Holding call ..."];
    }

    [self cleanUpAfterDisconnect];   
}

- (void) onSetNSMode:(ALError*) err
{
    NSLog(@"onSetNSMode");

    if (err)
    {
        NSLog(@"ERROR %@", err);
    }
    else
    {
        NSLog(@"Success");
    }
}

- (void) onSpeakerResponse:(ALError*) err
{
    NSLog(@"onSpeakerResponse");

    if (err)
    {
        NSLog(@"ERROR %@", err);

        self.switchSpeaker.on = ! self.switchSpeaker.isOn;
    }
    else
    {
        NSLog(@"Success");
    }
}

- (void) onSetVideoCaptureDevice:(ALError*) err
{
    NSLog(@"onSetVideoCaptureDevice");

    if (err)
    {
        NSLog(@"ERROR %@", err);
    }
    else
    {
        NSLog(@"Success");
    }    
}

- (void) onStartLocalVideo:(ALError*) err
	       videoSinkId:(NSString*) videoSinkId
{
    NSLog(@"onStartLocalVideo");

    if (err)
    {
        NSLog(@"ERROR %@", err);
    }
    else
    {
        NSLog(@"capturing into video sink %@", videoSinkId);

	[_videoSinkToVideoView setObject:self.viewVideo0 forKey:videoSinkId];
	[self.viewVideo0 addRenderer:videoSinkId];
    }
}

- (void) onStopLocalVideo:(ALError*) err
{
    NSLog(@"onStopLocalVideo");

    if (err)
    {
        NSLog(@"ERROR %@", err);
    }
    else
    {
        NSLog(@"Success");

	[_videoSinkToVideoView removeObjectForKey:self.viewVideo0.videoSinkId];
	[self.viewVideo0 removeRenderer];
    }
}

- (void) onPublish:(ALError*) err
{
    NSLog(@"onPublish");

    [self unlockUI:NO];

    if (err)
    {
        NSLog(@"ERROR %@", err);
    }
    else
    {
        NSLog(@"Success");

	[self showInCall];
    }
}

- (void) onUnpublish:(ALError*) err
{
    NSLog(@"onUnpublish");

    [self unlockUI:NO];

    if (err)
    {
        NSLog(@"ERROR %@", err);
    }
    else
    {
        NSLog(@"Success");

	if (! self.switchPublishAudio.isOn)
	{
	    [_uplinkStatsAudio release];
	    _uplinkStatsAudio = nil;
	}

	if (! self.switchPublishVideo.isOn)
	{
	    [_uplinkStatsVideo release];
	    _uplinkStatsVideo = nil;
	}

	[self showInCall];
    }
}

- (void) onGetVersion:(ALError*) err 
	      version:(NSString*) version
{
    NSLog(@"onGetVersion");

    if (err)
    {
        NSLog(@"ERROR %@", err);
    }
    else
    {
        NSLog(@"Success");
	
	[_version release];
	_version = [version copy];
    }
}

- (void) onNetworkTest:(ALError*) err 
	       quality:(NSNumber*) quality
{
    NSLog(@"onNetworkTest");

    if (err)
    {
        NSLog(@"ERROR %@", err);
    }
    else
    {
        NSLog(@"Success: %@", quality);
    }    
}

- (void) onSetAllowedSenders:(ALError*) err
{
    NSLog(@"onSetAllowedSenders");

    if (err)
    {
        NSLog(@"ERROR %@", err);
    }
    else
    {
        NSLog(@"Success");
    }
}

- (void) onStartMeasuringStats:(ALError*) err
{
    NSLog(@"onStartMeasuringStats");

    if (err)
    {
        NSLog(@"ERROR %@", err);
    }
    else
    {
        NSLog(@"Success");
    }
}

// methods from ALServiceListener protocol

- (void) videoFrameSizeChanged:(ALVideoFrameSizeChangedEvent*) event
{
    NSLog(@"videoFrameSizeChanged: %@ -> (%d x %d)", event.sinkId, 
	  event.width, event.height);

    id obj = [_videoSinkToVideoView objectForKey:event.sinkId];
    if (obj)
        [obj resolutionChanged:event.width
			height:event.height];
}

- (void) connectionLost:(ALConnectionLostEvent*) event
{
    NSLog(@"connectionLost");

    [labelStatus setText:[NSString stringWithFormat:@"ERROR %d: %@",
				   event.errCode, event.errMessage]];
    labelStatus.textColor = [UIColor redColor];   

    if (event.errCode != kCommRemoteEndDied)
    {
        _state = DISCONNECTED;

	[[UIApplication sharedApplication] setIdleTimerDisabled:NO];
    
	[buttonConnectDisconnect
	  setTitle:@"Connect" forState:UIControlStateNormal];

	[self cleanUpAfterDisconnect];

	[self unlockUI:YES];
    }
    else
      _state = LOST_CONNECTION;
}

- (void) userEvent:(ALUserStateChangedEvent*) event
{
    NSLog(@"userEvent: %@", event);

    if (event.isConnected)
    {
        [_users setObject:[[[User alloc] init] autorelease]
		   forKey:[NSNumber numberWithLongLong:
				      event.userId]];

        [_downlinkStatsRow addObject:[NSNumber numberWithLongLong
					 :event.userId]];

	[self reloadDownlinkStats];

	if (event.screenPublished)
	{
	    User* user = [_users objectForKey:
				   [NSNumber numberWithLongLong:
					       event.userId]];
	    
	    user.screenSinkId = event.screenSinkId;

	    [self selectVideo:user];
	}

	if (event.videoPublished)
	{
	    User* user = [_users objectForKey:
				   [NSNumber numberWithLongLong:
					       event.userId]];
	    
	    user.videoSinkId = event.videoSinkId;

	    NSArray* keys = 
	      [_videoSinkToVideoView allKeysForObject:self.viewVideo1];

	    if (! [keys count])
	    {
	        [self selectVideo:user];
	    }
	}
    }
    else
    {
        [_downlinkStatsRow removeObject:[NSNumber numberWithLongLong:
						    event.userId]];

	[self reloadDownlinkStats];

	User* user = 
	  [[_users objectForKey:
		     [NSNumber numberWithLongLong:
				 event.userId]] retain];

	[_users removeObjectForKey:[NSNumber numberWithLongLong:
					       event.userId]];

        if ([self.viewVideo1.videoSinkId isEqual:user.videoSinkId] ||
	    [self.viewVideo1.videoSinkId isEqual:user.screenSinkId])
	{
	    [self selectVideo:nil];
	}

	[user release];
    }   
}

- (void) mediaStream:(ALUserStateChangedEvent*) event
{
    NSLog(@"mediaStream: %@", event);

    if ([event.mediaType caseInsensitiveCompare:@"screen"] == NSOrderedSame)
    {
        [self updateScreenStream:event];
    }
    else if ([event.mediaType caseInsensitiveCompare:@"video"] == NSOrderedSame)
    {
        [self updateVideoStream:event];
    }
    else if ([event.mediaType caseInsensitiveCompare:@"audio"] == NSOrderedSame)
    {
        [self updateAudioStream:event];
    }
}

- (void) mediaStats:(ALMediaStatsEvent*) event
{
    //NSLog(@"mediaStats");

    if ([event.mediaType caseInsensitiveCompare:@"audio"] == NSOrderedSame)
    {
        [self audioStats:event];
    }
    else if ([event.mediaType caseInsensitiveCompare:@"video"] == NSOrderedSame)
    {
        [self videoStats:event];
    }
}

- (void) message:(ALMessageEvent*) event
{
    NSLog(@"message from %lld", event.srcUserId);
}

- (void) mediaConnTypeChanged:(ALMediaConnTypeChangedEvent*) event
{
    NSLog(@"[%@] connection type: %@", event.mediaType, event.connectionType);
}

- (void) mediaIssue:(ALMediaIssueEvent*) event
{
    NSLog(@"[%@] media issue: %@ : %@", event.mediaType, event.issueType,
	  event.msg);
}

- (void) mediaInterrupt:(ALMediaInterruptEvent*) event
{
    NSLog(@"mediaInterrupt");

    if ([event.mediaType caseInsensitiveCompare:@"audio"] != NSOrderedSame)
        return;

    NSLog(@"[%@] interrupt: %@", event.mediaType, 
	  event.interrupt ? @"BEGIN" : @"END");

    if (event.interrupt)
    {
        [self putCallOnHold];
    }
    else if (! _isBackgroundMode)
    {
        [UIApplication sharedApplication].applicationIconBadgeNumber = 0;

        [self connect];
    }
}

// private

- (void) showError:(NSString*) errorMsg
{
    labelStatus.textColor = [UIColor redColor];
    [labelStatus setText:errorMsg];
}

- (void) showBusy:(NSString*) busyMsg
{
    labelStatus.textColor = [UIColor cyanColor];
    [labelStatus setText:busyMsg];
}

- (void) showReady
{
    labelStatus.textColor = [UIColor yellowColor];
    [labelStatus setText:[NSString stringWithFormat:@"v%@: Ready", _version]];
}

- (void) showInCall
{
  labelStatus.textColor = [UIColor greenColor];
  [labelStatus setText: @"In Call"];
}

// connect to a conference
- (void) connect
{
    // disable user input
    [self lockUI];

    if (_state == ONHOLD)
    {
        [self showBusy:@"Resuming call ..."];
    }
    else if (_state == DISCONNECTED)
    {
        [self showBusy:@"Connecting ..."];
    }
    else if (_state == LOST_CONNECTION)
    {
        [self showBusy:@"Reconnecting ..."];
    }

    // prepare connection descriptor
    ALConnectionDescriptor* desc = 
      [[[ALConnectionDescriptor alloc] init] autorelease];

    desc.scopeId = [self scopeId];

    if ([self isURL])
        desc.url = [textFieldURL text];
    
    desc.autopublishAudio = self.switchPublishAudio.isOn;
    desc.autopublishVideo = self.switchPublishVideo.isOn;

    // prepare video stream
    desc.videoStream.maxWidth = 480;
    desc.videoStream.maxHeight = 640;
    desc.videoStream.maxBitRate = 1024;
    desc.videoStream.maxFps = 15;

    // prepare authentication (userId, expires, salt)
    desc.authDetails.userId = _userId;
    desc.authDetails.expires = time(0) + 5 * 60;
    desc.authDetails.salt = @"Some random string salt";    
#if 0
    desc.authDetails.signature = 
      [ALAuthDetails signDetails:[NSNumber numberWithInt:AL_SAMPLE_APP_ID]
			 scopeId:desc.scopeId
			  userId:_userId
			    salt:desc.authDetails.salt
			 expires:desc.authDetails.expires
		       secretKey:AL_SAMPLE_KEY];
#endif
    //
    _connectAttempts++;

    // call connect
    ALResponder* responder =
        [[[ALResponder alloc] 
	   initWithSelector:@selector(onConnect:)
		 withObject:self] 
	  autorelease];

    [_service connect:desc 
	    responder:responder]; // response to onConnect
}

// disconnect from the conference call
- (void) disconnect
{
    // disable user input
    [self lockUI];

    [self showBusy:@"Disconnecting ..."];

    // call disconnect
    ALResponder* responder =
      [[[ALResponder alloc] 
	 initWithSelector:@selector(onDisconnect:)
	       withObject:self] autorelease];
    [_service disconnect:[self scopeId]
	       responder:responder]; // response to onDisconnect
}

// disconnect and reconnect
- (void) reconnect
{
    if (_isBackgroundMode)
    {
        [self putCallOnHold];

        return;
    }

    if (_state != CONNECTED && _state != LOST_CONNECTION)
    {
        return;
    }

    // disable user input
    [self lockUI];

    [self showBusy:@"Reconnecting ..."];    

    // call disconnect
    ALResponder* responder =
      [[[ALResponder alloc] 
	 initWithSelector:@selector(onReconnect:)
	       withObject:self] autorelease];
    [_service disconnect:[self scopeId]
	       responder:responder]; // response to onReconnect
}

// holds the conference call (i.e. disconnect)
- (void) hold
{
    // disable user input
    [self lockUI];

    [self showBusy:@"Holding ..."];

    // call disconnect
    ALResponder* responder =
      [[[ALResponder alloc] 
	 initWithSelector:@selector(onHold:)
	       withObject:self] autorelease];    
    [_service disconnect:[self scopeId]
	       responder:responder]; // response to onHold
}

- (void) showEmailView:(NSString*) filenameAttachment;
{
    if (! [MFMailComposeViewController canSendMail])
    {
        [_alert dismissWithClickedButtonIndex:0 animated:YES];
    
	NSString* message = @"Logs failed! Check if your email account works.";

	[_alert release];
	_alert =
	  [[UIAlertView alloc] initWithTitle: @"Error"
				     message: message
				    delegate: self
			   cancelButtonTitle: @"OK"
			   otherButtonTitles: nil];
	[_alert show];

	return;
    }

    MFMailComposeViewController* controller =
      [[[MFMailComposeViewController alloc] init] autorelease];
    controller.mailComposeDelegate = self;
    
    [controller setSubject:LOG_EMAIL_SUBJECT];
    [controller setToRecipients:
     [NSArray arrayWithObjects:LOG_RECEIVER_EMAIL,nil]];
    [controller setMessageBody:@"" isHTML:NO];

    NSData* data = [NSData dataWithContentsOfFile:filenameAttachment];

    [controller addAttachmentData:data mimeType:@"text/plain"
     fileName:LOG_FILE_EMAIL];

    [self presentModalViewController:controller animated:YES];
}

- (void) audioStats:(ALMediaStatsEvent*) event
{
    if (event.remoteUserId < 0) // uplink stats
    {
        NSString* stats = [NSString stringWithFormat:
            @"[A] kbps = %0.1f RTT = %0.1f #Loss = %d %%Loss = %0.1f",
            8.0f * event.stats.bitRate / 1000.0f,
            event.stats.rtt,
            event.stats.totalLoss,
            event.stats.loss];
    
	[_uplinkStatsAudio release];
	_uplinkStatsAudio = [stats copy];

        [labelUplinkStats setText
	    :[NSString stringWithFormat:@"%@ %@", 
	        (_uplinkStatsAudio == nil) ? @"[No Audio]" : _uplinkStatsAudio,
		(_uplinkStatsVideo == nil) ? @"[No Video]" : _uplinkStatsVideo]
	 ];
    }
    else // downlink stats
    {
        User* user = [_users objectForKey:
			       [NSNumber numberWithLongLong:
					   event.remoteUserId]];

        NSString* stats = [NSString stringWithFormat:
            @"[A] kbps %0.1f #Loss = %d %%Loss = %0.1f",
            8.0f * event.stats.bitRate / 1000.0f,
            event.stats.totalLoss,
            event.stats.loss];

	user.statsAudio = stats;

	[self reloadDownlinkStats];
    }
}

- (void) videoStats:(ALMediaStatsEvent*) event
{
    if (event.remoteUserId < 0) // uplink stats
    {
        NSString* stats = [NSString stringWithFormat:
            @"[V] %%CPU = %0.1f kbps = %0.1f #Loss = %d %%Loss = %0.1f "
	     "QDL = %0.1f",
	    event.stats.totalCpu,
            8.0f * event.stats.bitRate / 1000.0f,
            event.stats.totalLoss,
	    event.stats.loss,
	    event.stats.queueDelay]; 

	[_uplinkStatsVideo release];
	_uplinkStatsVideo = [stats copy];

        [labelUplinkStats setText
	    :[NSString stringWithFormat:@"%@ %@", 
	        (_uplinkStatsAudio == nil) ? @"[No Audio]" : _uplinkStatsAudio,
		(_uplinkStatsVideo == nil) ? @"[No Video]" : _uplinkStatsVideo]
	 ];
    }
    else // downlink stats
    {
        User* user = [_users objectForKey:
			       [NSNumber numberWithLongLong:
					   event.remoteUserId]];

        NSString* stats = [NSString stringWithFormat:
	    @"[V] %%CPU = %0.1f kbps = %0.1f #Loss = %d %%Loss = %0.1f",
	    event.stats.totalCpu,
            8.0f * event.stats.bitRate / 1000.0f,
            event.stats.totalLoss,
            event.stats.loss];

	user.statsVideo = stats;
        
	[self reloadDownlinkStats];
    }
}

- (void) lockUI
{
    buttonConnectDisconnect.enabled = NO;
    switchSpeaker.enabled = NO;
    switchPublishVideo.enabled = NO;
    switchPublishAudio.enabled = NO;
    buttonNs.enabled = NO;
    buttonCamera.enabled = NO;
    textFieldURL.enabled = NO;
}

- (void) unlockUI:(BOOL) enableURL
{
    buttonConnectDisconnect.enabled = YES;
    switchSpeaker.enabled = YES;
    switchPublishVideo.enabled = YES;
    switchPublishAudio.enabled = YES;
    buttonNs.enabled = YES;
    buttonCamera.enabled = YES;
    textFieldURL.enabled = enableURL;
}

- (NSString*) scopeId
{
    NSArray* url = [[textFieldURL text] componentsSeparatedByString: @"/"];

    if ([url count] == 1)
      return [url objectAtIndex:0];

    if ([url count] == 2)
      return [url objectAtIndex:1];    

    return nil;
}

- (BOOL) isURL
{
    NSArray* url = [[textFieldURL text] componentsSeparatedByString: @"/"];

    if ([url count] == 2)
    {
        NSArray* host = 
	  [[url objectAtIndex:0] componentsSeparatedByString: @":"];

	if ([host count] == 2) // TODO: check if it's valid
	    return YES;
    }

    return NO;
}

- (void) reloadDownlinkStats
{
    NSIndexPath* ipath = [tableViewDownlinkStats indexPathForSelectedRow];

    [tableViewDownlinkStats reloadData];

    if (ipath)
    {
      [tableViewDownlinkStats 
	  selectRowAtIndexPath:ipath
		      animated:NO 
		scrollPosition:UITableViewScrollPositionNone];
    }
}

- (void) cleanUpAfterDisconnect
{
    [buttonConnectDisconnect
     setTitle:@"Connect" forState:UIControlStateNormal];

    if (self.viewVideo1.videoSinkId)
    {
        [_videoSinkToVideoView removeObjectForKey:self.viewVideo1.videoSinkId];
    }
    [self.viewVideo1 removeRenderer];

    [labelUplinkStats setText:@"Uplink Stats"];

    [_downlinkStatsRow removeAllObjects];
    [_users removeAllObjects];

    [tableViewDownlinkStats reloadData];
}

- (void) selectVideo:(User*) user
{
    NSUInteger index = 0;

    if (user)
    {
        NSNumber* userId = 
	  [[_users allKeysForObject:user] objectAtIndex:0];
	
	index = [_downlinkStatsRow indexOfObject:userId];
    }
    else
    {
        NSNumber* userId = nil;

	NSArray* userIds = [_users allKeys];
        for (NSNumber* uId in userIds)
	{
	    User* u = [_users objectForKey:uId];

	    if (([u.screenSinkId length] > 0) || ([u.videoSinkId length] > 0))
	    {
	        userId = uId;
	        break;
	    }
	}

        if (userId == nil)
	{
	    [_videoSinkToVideoView removeObjectForKey:
				     self.viewVideo1.videoSinkId];
	    [self.viewVideo1 removeRenderer];

	    return;
	}

	index = [_downlinkStatsRow indexOfObject:userId];
    }
    
    NSIndexPath* indexPath = [NSIndexPath indexPathForRow:index 
						inSection:0];
    [tableViewDownlinkStats
		  selectRowAtIndexPath:indexPath
			      animated:NO
			scrollPosition:UITableViewScrollPositionNone];
    [self tableView:tableViewDownlinkStats
	  didSelectRowAtIndexPath:indexPath];
}

- (void) updateScreenStream:(ALUserStateChangedEvent*) event
{
    User* user = [_users objectForKey:
			   [NSNumber numberWithLongLong:
				       event.userId]];

    if (event.screenPublished)
    {
	user.screenSinkId = event.screenSinkId;

	[self selectVideo:user];
    }
    else
    {
        user.statsVideo = @"";

	NSString* screenSinkId = [user.screenSinkId copy];
	user.screenSinkId = @"";

	[self reloadDownlinkStats];

        if ([self.viewVideo1.videoSinkId isEqual:screenSinkId])
	{
	    [self selectVideo:nil];
	}

	[screenSinkId release];
    }    
}

- (void) updateAudioStream:(ALUserStateChangedEvent*) event
{
    if (! event.audioPublished)
    {
        User* user = [_users objectForKey:
			       [NSNumber numberWithLongLong:
					   event.userId]];
	user.statsAudio = @"";

	[self reloadDownlinkStats];
    }
}

- (void) updateVideoStream:(ALUserStateChangedEvent*) event
{
    User* user = [_users objectForKey:
			   [NSNumber numberWithLongLong:
				       event.userId]];

    if (event.videoPublished)
    {
	user.videoSinkId = event.videoSinkId;

        NSArray* keys = 
	  [_videoSinkToVideoView allKeysForObject:self.viewVideo1];

	if (! [keys count])
	{
	    [self selectVideo:user];
	}
    }
    else
    {
        user.statsVideo = @"";

	NSString* videoSinkId = [user.videoSinkId copy];
	user.videoSinkId = @"";

	[self reloadDownlinkStats];

        if ([self.viewVideo1.videoSinkId isEqual:videoSinkId])
	{
	    [self selectVideo:nil];
	}

	[videoSinkId release];
    }
}

- (void) putCallOnHold
{
    [self hold];

    [[UIApplication sharedApplication] cancelAllLocalNotifications];

    UILocalNotification* localNotification = 
      [[[UILocalNotification alloc] init] autorelease];

    localNotification.alertBody = 
      @"Your AddLive conference has been put on hold.";
    localNotification.applicationIconBadgeNumber = 1;
    localNotification.soundName = UILocalNotificationDefaultSoundName;
    localNotification.fireDate = nil;

    [[UIApplication sharedApplication] 
	  scheduleLocalNotification:localNotification];
}

- (void) startNetworkTest
{
  ALResponder* respNetworkTest =
    [[[ALResponder alloc]
		 initWithSelector:@selector(onNetworkTest:quality:)
		       withObject:self]
      autorelease];

  ALAuthDetails* authDetails = [[ALAuthDetails alloc] init];
  authDetails.userId = _userId;
  authDetails.expires = time(0) + 5 * 60;
  authDetails.salt = @"Some random string salt";

#if 0
  authDetails.signature = 
    [ALAuthDetails signDetails:[NSNumber numberWithInt:AL_SAMPLE_APP_ID]
		       scopeId:@""
			userId:_userId
			  salt:authDetails.salt
		       expires:authDetails.expires
		     secretKey:AL_SAMPLE_KEY];
#endif

  [_service networkTest:[NSNumber numberWithInt:1024]
	    authDetails:authDetails
	      responder:respNetworkTest];
}

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

        const char* key;
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

// actions sheets

- (void) actionSheet:(UIActionSheet*) actionSheet 
clickedButtonAtIndex: (NSInteger) buttonIndex
{
    if (buttonIndex < 0)
        return;
    
    switch (actionSheet.tag)
    {
        case SHEET_NS:
            [self nsSheetClickedAtIndex:buttonIndex];
            break;
        case SHEET_CAMERA:
	    [self cameraSheetClickedAtIndex:buttonIndex];
	    break;
    }
}

- (void) nsSheetClickedAtIndex:(NSInteger) index
{
    ALResponder* responder =
      [[[ALResponder alloc] 
	 initWithSelector:@selector(onSetNSMode:)
	       withObject:self] 
	autorelease];

    [_service setNSMode:index
	      responder:responder];

    NSArray* nsModes = [ALService getNSModes];
    [buttonNs setTitle:[nsModes objectAtIndex:index]
     forState:UIControlStateNormal];
}

- (void) cameraSheetClickedAtIndex:(NSInteger) index
{
    // set video capture device
    ALResponder* responder =
      [[[ALResponder alloc] 
	     initWithSelector:@selector(onSetVideoCaptureDevice:)
		   withObject:self]
	autorelease];

    ALDevice* dev = [_cameraDevices objectAtIndex:index];

    [_service setVideoCaptureDevice:dev.id
			  responder:responder];

    [buttonCamera setTitle:dev.label forState:UIControlStateNormal];

    self.viewVideo0.mirror = (index == 0); // assumes index 0 is always front
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

- (NSInteger) tableView:(UITableView*) tableView 
  numberOfRowsInSection:(NSInteger)section
{       
    return [_downlinkStatsRow count];
}

- (UITableViewCell*) tableView:(UITableView*) tableView 
	 cellForRowAtIndexPath:(NSIndexPath*) indexPath
{
    UITableViewCell* cell =
        [tableViewDownlinkStats dequeueReusableCellWithIdentifier:@"0"];

    if (cell == nil)
    {
        cell = [[[UITableViewCell alloc]
		  initWithStyle:
		    UITableViewCellStyleDefault reuseIdentifier:@"0"] 
		 autorelease];
    }

    NSNumber* userId =
        [_downlinkStatsRow objectAtIndex: indexPath.row];

    float fontSize = 14.0f;
    if ([[UIDevice currentDevice] userInterfaceIdiom]
        == UIUserInterfaceIdiomPhone)
    {
        fontSize = 10.0f;
    }

    User* user = [_users objectForKey:userId];

    cell.textLabel.text = 
      [NSString stringWithFormat:@"User %@: %@ %@", 
		userId, 
		(![user.statsAudio length]) ? @"[No Audio]" : user.statsAudio,
		(![user.statsVideo length]) ? @"[No Video]" : user.statsVideo];
    cell.textLabel.textAlignment = UITextAlignmentCenter;
    cell.textLabel.textColor = [UIColor whiteColor];
    cell.textLabel.font = [[UIFont class] systemFontOfSize:fontSize];
    cell.textLabel.lineBreakMode = NSLineBreakByWordWrapping;
    cell.textLabel.numberOfLines = 2;

    return cell;
}

- (NSIndexPath*) tableView:(UITableView*) tableView
willSelectRowAtIndexPath:(NSIndexPath*) indexPath
{
    NSNumber* uId = [_downlinkStatsRow objectAtIndex:indexPath.row];
    if (! uId)
      return nil;

    User* user = [_users objectForKey:uId];
    if (! user)
      return nil;

    return indexPath;
}

- (void) tableView:(UITableView*) tableView
didSelectRowAtIndexPath:(NSIndexPath*) indexPath
{
    NSNumber* uId = [_downlinkStatsRow objectAtIndex:indexPath.row];
    User* user = [_users objectForKey:uId];

    // switch to new video feed
    if (self.viewVideo1.videoSinkId)
    {
        [_videoSinkToVideoView removeObjectForKey:self.viewVideo1.videoSinkId];
    }

    NSString* sinkId = user.videoSinkId;

    if ([user.screenSinkId length]) // always prefer screen
      sinkId = user.screenSinkId;

    [_videoSinkToVideoView setObject:self.viewVideo1
			      forKey:sinkId];
    [self.viewVideo1 addRenderer:sinkId];
	    
    // update allowed senders
    NSArray* uIds = [NSArray arrayWithObject:uId];

    ALResponder* responder =
      [[[ALResponder alloc]
		   initWithSelector:@selector(onSetAllowedSenders:)
			 withObject:self]
	autorelease];
    
    [_service setAllowedSenders:[self scopeId] 
			userIds:uIds
		      responder:responder];
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

    [_alert release];
    _alert =
        [[UIAlertView alloc] initWithTitle: @"Connection"
         message: message
         delegate: self
         cancelButtonTitle: @"OK"
         otherButtonTitles: nil];
    [_alert show];
    
    _networkStatus = status;

    if (_networkStatus != NotReachable)
        [self reconnect];
}

@end
