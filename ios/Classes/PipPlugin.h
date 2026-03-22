#import "PipController.h"
#import <Flutter/Flutter.h>
#import <WebRTC/WebRTC.h>

@interface PipPlugin : NSObject <FlutterPlugin, PipStateChangedDelegate>

@property(nonatomic, strong) RTCMTLVideoView *nativePipVideoView;
@property(nonatomic, weak) RTCVideoTrack *attachedVideoTrack;

@end
