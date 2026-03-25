#import <Flutter/Flutter.h>
#import <WebRTC/WebRTC.h>
#import "PipController.h"

@interface PipPlugin : NSObject <FlutterPlugin, PipStateChangedDelegate>

@property(nonatomic, strong) UIView *nativePipVideoView;
@property(nonatomic, strong) RTCVideoTrack *attachedVideoTrack;
@property(nonatomic, strong) id pipVideoRenderer;
@property(nonatomic, strong) AVCaptureVideoPreviewLayer *localPreviewLayer;

@end
