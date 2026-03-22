#import "PipPlugin.h"

@interface NSObject (FlutterWebRTCBridge)
+ (id)sharedSingleton;
- (id)streamForId:(NSString *)streamId peerConnectionId:(NSString *)peerConnectionId;
@end

@interface PipPlugin ()

@property(nonatomic) FlutterMethodChannel *channel;
@property(nonatomic) FlutterMethodChannel *bridgeChannel;

@property(nonatomic, strong) PipController *pipController;

@end

@implementation PipPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  FlutterMethodChannel *channel =
      [FlutterMethodChannel methodChannelWithName:@"pip"
                                  binaryMessenger:[registrar messenger]];
  PipPlugin *instance = [[PipPlugin alloc] init];

  instance.channel = channel;
  instance.pipController =
      [[PipController alloc] initWith:(id<PipStateChangedDelegate>)instance];

  [registrar addMethodCallDelegate:instance channel:channel];

  FlutterMethodChannel *bridgeChannel =
      [FlutterMethodChannel methodChannelWithName:@"pip_webrtc_bridge"
                                  binaryMessenger:[registrar messenger]];
  instance.bridgeChannel = bridgeChannel;
  [registrar addMethodCallDelegate:instance channel:bridgeChannel];
}

- (void)handleMethodCall:(FlutterMethodCall *)call
                  result:(FlutterResult)result {
  if ([@"isSupported" isEqualToString:call.method]) {
    result([NSNumber numberWithBool:[self.pipController isSupported]]);
  } else if ([@"isAutoEnterSupported" isEqualToString:call.method]) {
    result([NSNumber numberWithBool:[self.pipController isAutoEnterSupported]]);
  } else if ([@"isActived" isEqualToString:call.method]) {
    result([NSNumber numberWithBool:[self.pipController isActived]]);
  } else if ([@"setup" isEqualToString:call.method]) {
    @autoreleasepool {
      // new options
      PipOptions *options = [[PipOptions alloc] init];

      // source content view
      if ([call.arguments objectForKey:@"sourceContentView"] &&
          [[call.arguments objectForKey:@"sourceContentView"]
              isKindOfClass:[NSNumber class]]) {
        options.sourceContentView = (__bridge UIView *)[[call.arguments
            objectForKey:@"sourceContentView"] pointerValue];
      }

      // content view
      if ([call.arguments objectForKey:@"contentView"] &&
          [[call.arguments objectForKey:@"contentView"]
              isKindOfClass:[NSNumber class]]) {
        options.contentView = (__bridge UIView *)[[call.arguments
            objectForKey:@"contentView"] pointerValue];
      }

      // auto enter
      if ([call.arguments objectForKey:@"autoEnterEnabled"]) {
        options.autoEnterEnabled =
            [[call.arguments objectForKey:@"autoEnterEnabled"] boolValue];
      }

      // preferred content size
      if ([call.arguments objectForKey:@"preferredContentWidth"] &&
          [call.arguments objectForKey:@"preferredContentHeight"]) {
        options.preferredContentSize = CGSizeMake(
            [[call.arguments objectForKey:@"preferredContentWidth"] floatValue],
            [[call.arguments objectForKey:@"preferredContentHeight"]
                floatValue]);
      }

      // control style
      if ([call.arguments objectForKey:@"controlStyle"]) {
        options.controlStyle =
            [[call.arguments objectForKey:@"controlStyle"] intValue];
      } else {
        // default to show all system controls
        options.controlStyle = 0;
      }

      result([NSNumber numberWithBool:[self.pipController setup:options]]);
    }
  } else if ([@"getPipView" isEqualToString:call.method]) {
    result([NSNumber
        numberWithUnsignedLongLong:(uint64_t)[self.pipController getPipView]]);
  } else if ([@"start" isEqualToString:call.method]) {
    result([NSNumber numberWithBool:[self.pipController start]]);
  } else if ([@"stop" isEqualToString:call.method]) {
    [self.pipController stop];
    result(nil);
  } else if ([@"dispose" isEqualToString:call.method]) {
    [self.pipController dispose];
    result(nil);
  } else if ([@"createPipVideoView" isEqualToString:call.method]) {
    NSString *remoteStreamId = [call.arguments objectForKey:@"remoteStreamId"];
    if (remoteStreamId == nil) {
      result(@(0));
      return;
    }

    if (self.attachedVideoTrack && self.nativePipVideoView) {
      [self.attachedVideoTrack removeRenderer:self.nativePipVideoView];
    }
    self.nativePipVideoView = nil;
    self.attachedVideoTrack = nil;

    Class webrtcClass = NSClassFromString(@"FlutterWebRTCPlugin");
    if (!webrtcClass || ![webrtcClass respondsToSelector:@selector(sharedSingleton)]) {
      NSLog(@"[PipBridge] FlutterWebRTCPlugin not available");
      result(@(0));
      return;
    }

    id webrtcPlugin = [webrtcClass performSelector:@selector(sharedSingleton)];
    RTCVideoTrack *videoTrack = nil;

    NSDictionary *peerConnections = [webrtcPlugin valueForKey:@"peerConnections"];
    if (peerConnections) {
      for (NSString *pcId in peerConnections) {
        RTCMediaStream *stream = [webrtcPlugin streamForId:remoteStreamId
                                          peerConnectionId:pcId];
        if (stream && stream.videoTracks.count > 0) {
          videoTrack = stream.videoTracks.firstObject;
          break;
        }
      }
    }

    if (!videoTrack) {
      RTCMediaStream *stream = [webrtcPlugin streamForId:remoteStreamId
                                        peerConnectionId:nil];
      if (stream) {
        videoTrack = stream.videoTracks.firstObject;
      }
    }

    if (!videoTrack) {
      NSLog(@"[PipBridge] No video track found for stream: %@", remoteStreamId);
      result(@(0));
      return;
    }

    RTCMTLVideoView *videoView = [[RTCMTLVideoView alloc] init];
    videoView.frame = CGRectMake(0, 0, 270, 480);
    [videoView setVideoContentMode:UIViewContentModeScaleAspectFill];
    [videoTrack addRenderer:videoView];

    // Add to root view hierarchy so Metal rendering is active immediately.
    // Without this, the view never renders live frames (only a frozen buffer).
    // PipController's insertContentViewIfNeeded will move it to the PiP window
    // when PiP starts, and restoreContentViewIfNeeded will return it here after.
    UIWindow *window = [UIApplication sharedApplication].keyWindow;
    if (window && window.rootViewController) {
      [window.rootViewController.view insertSubview:videoView atIndex:0];
    }

    self.nativePipVideoView = videoView;
    self.attachedVideoTrack = videoTrack;

    uint64_t pointer = (uint64_t)videoView;
    NSLog(@"[PipBridge] Created native video view: %llu", pointer);
    result(@(pointer));

  } else if ([@"disposePipVideoView" isEqualToString:call.method]) {
    if (self.attachedVideoTrack && self.nativePipVideoView) {
      [self.attachedVideoTrack removeRenderer:self.nativePipVideoView];
    }
    [self.nativePipVideoView removeFromSuperview];
    self.nativePipVideoView = nil;
    self.attachedVideoTrack = nil;
    NSLog(@"[PipBridge] Disposed native video view");
    result(nil);

  } else {
    result(FlutterMethodNotImplemented);
  }
}

- (void)pipStateChanged:(PipState)state error:(NSString *)error {
  NSDictionary *arguments = [[NSDictionary alloc]
      initWithObjectsAndKeys:[NSNumber numberWithLong:(long)state], @"state",
                             error, @"error", nil];
  [self.channel invokeMethod:@"stateChanged" arguments:arguments];
}

@end
