#import "PipPlugin.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>

@interface NSObject (FlutterWebRTCBridge)
+ (id)sharedSingleton;
- (id)streamForId:(NSString *)streamId peerConnectionId:(NSString *)peerConnectionId;
@end

@interface PipSampleBufferView : UIView
@property(nonatomic, readonly) AVSampleBufferDisplayLayer *sampleBufferLayer;
@end

@implementation PipSampleBufferView
+ (Class)layerClass {
  return [AVSampleBufferDisplayLayer class];
}
- (AVSampleBufferDisplayLayer *)sampleBufferLayer {
  return (AVSampleBufferDisplayLayer *)self.layer;
}
@end

@interface PipSampleBufferRenderer : NSObject <RTCVideoRenderer>
@property(nonatomic, weak) AVSampleBufferDisplayLayer *displayLayer;
@end

@implementation PipSampleBufferRenderer
- (instancetype)initWithDisplayLayer:(AVSampleBufferDisplayLayer *)layer {
  self = [super init];
  if (self) {
    _displayLayer = layer;
  }
  return self;
}
- (void)setSize:(CGSize)size {}
- (void)renderFrame:(nullable RTCVideoFrame *)frame {
  if (!frame) return;

  CVPixelBufferRef pixelBuffer = NULL;
  if ([frame.buffer isKindOfClass:NSClassFromString(@"RTCCVPixelBuffer")]) {
    pixelBuffer = ((RTCCVPixelBuffer *)frame.buffer).pixelBuffer;
  }
  if (!pixelBuffer) return;

  CMVideoFormatDescriptionRef formatDesc = NULL;
  OSStatus status = CMVideoFormatDescriptionCreateForImageBuffer(
      kCFAllocatorDefault, pixelBuffer, &formatDesc);
  if (status != noErr || !formatDesc) return;

  CMSampleTimingInfo timing;
  timing.duration = kCMTimeInvalid;
  timing.presentationTimeStamp =
      CMTimeMakeWithSeconds(CACurrentMediaTime(), 1000000);
  timing.decodeTimeStamp = kCMTimeInvalid;

  CMSampleBufferRef sampleBuffer = NULL;
  status = CMSampleBufferCreateForImageBuffer(
      kCFAllocatorDefault, pixelBuffer, true, NULL, NULL,
      formatDesc, &timing, &sampleBuffer);
  CFRelease(formatDesc);
  if (status != noErr || !sampleBuffer) return;

  AVSampleBufferDisplayLayer *layer = self.displayLayer;
  if (!layer) {
    CFRelease(sampleBuffer);
    return;
  }

  CFRetain(sampleBuffer);
  dispatch_async(dispatch_get_main_queue(), ^{
    if (layer.status == AVQueuedSampleBufferRenderingStatusFailed) {
      [layer flush];
    }
    [layer enqueueSampleBuffer:sampleBuffer];
    CFRelease(sampleBuffer);
  });
}
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

    if (self.attachedVideoTrack && self.pipVideoRenderer) {
      [self.attachedVideoTrack removeRenderer:self.pipVideoRenderer];
    }
    self.nativePipVideoView = nil;
    self.attachedVideoTrack = nil;
    self.pipVideoRenderer = nil;

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

    PipSampleBufferView *videoView =
        [[PipSampleBufferView alloc] initWithFrame:CGRectMake(0, 0, 270, 480)];
    videoView.backgroundColor = [UIColor blackColor];
    videoView.sampleBufferLayer.videoGravity =
        AVLayerVideoGravityResizeAspect;

    PipSampleBufferRenderer *renderer =
        [[PipSampleBufferRenderer alloc]
            initWithDisplayLayer:videoView.sampleBufferLayer];
    [videoTrack addRenderer:renderer];

    RTCCameraVideoCapturer *capturer = [webrtcPlugin valueForKey:@"videoCapturer"];
    if (capturer && capturer.captureSession) {
      if (@available(iOS 18.0, *)) {
        if (capturer.captureSession.isMultitaskingCameraAccessSupported) {
          capturer.captureSession.multitaskingCameraAccessEnabled = YES;
        }
      }
    }

    self.nativePipVideoView = videoView;
    self.attachedVideoTrack = videoTrack;
    self.pipVideoRenderer = renderer;

    uint64_t pointer = (uint64_t)videoView;
    NSLog(@"[PipBridge] Created native video view: %llu", pointer);
    result(@(pointer));

  } else if ([@"disposePipVideoView" isEqualToString:call.method]) {
    if (self.attachedVideoTrack && self.pipVideoRenderer) {
      [self.attachedVideoTrack removeRenderer:self.pipVideoRenderer];
    }
    [self.nativePipVideoView removeFromSuperview];
    self.pipVideoRenderer = nil;
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
