import 'dart:io';
import 'package:flutter/services.dart';

/// Bridge between pip_webrtc and flutter_webrtc on iOS.
///
/// Creates a native RTCMTLVideoView attached to a remote WebRTC video track,
/// returning its memory pointer for use as [PipOptions.contentView].
class PipWebRTCBridge {
  static const _channel = MethodChannel('pip_webrtc_bridge');

  /// Creates a native video view rendering the remote WebRTC stream.
  ///
  /// [remoteStreamId] is the stream ID from flutter_webrtc's
  /// MediaStream.id (e.g. from onAddRemoteStream).
  ///
  /// Returns the native UIView pointer as an int (for use as
  /// [PipOptions.contentView]), or 0 if creation failed.
  /// Only works on iOS; returns 0 on other platforms.
  static Future<int> createPipVideoView(String remoteStreamId) async {
    if (!Platform.isIOS) return 0;
    final result = await _channel.invokeMethod<int>(
      'createPipVideoView',
      {'remoteStreamId': remoteStreamId},
    );
    return result ?? 0;
  }

  /// Disposes the native video view and detaches from the video track.
  /// Safe to call even if no view was created.
  static Future<void> disposePipVideoView() async {
    if (!Platform.isIOS) return;
    await _channel.invokeMethod<void>('disposePipVideoView');
  }
}
