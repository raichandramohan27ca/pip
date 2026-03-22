import 'package:flutter_test/flutter_test.dart';
import 'package:pip_webrtc/pip.dart';
import 'package:pip_webrtc/pip_platform_interface.dart';
import 'package:pip_webrtc/pip_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockPipPlatform
    with MockPlatformInterfaceMixin
    implements PipPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final PipPlatform initialPlatform = PipPlatform.instance;

  test('$MethodChannelPip is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelPip>());
  });

  test('getPlatformVersion', () async {
    Pip pipPlugin = Pip();
    MockPipPlatform fakePlatform = MockPipPlatform();
    PipPlatform.instance = fakePlatform;

    expect(await pipPlugin.getPlatformVersion(), '42');
  });
}
