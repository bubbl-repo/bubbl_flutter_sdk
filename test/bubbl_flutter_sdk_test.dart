import 'package:bubbl_flutter_sdk/bubbl_flutter_sdk.dart';
import 'package:bubbl_flutter_sdk/bubbl_flutter_sdk_method_channel.dart';
import 'package:bubbl_flutter_sdk/bubbl_flutter_sdk_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class FakeBubblFlutterSdkPlatform extends BubblFlutterSdkPlatform
    with MockPlatformInterfaceMixin {
  @override
  Future<String> sayHello() async => 'hello';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final BubblFlutterSdkPlatform initialPlatform =
      BubblFlutterSdkPlatform.instance;

  test('$MethodChannelBubblFlutterSdk is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelBubblFlutterSdk>());
  });

  test('sayHello delegates to platform implementation', () async {
    final FakeBubblFlutterSdkPlatform fakePlatform =
        FakeBubblFlutterSdkPlatform();
    BubblFlutterSdkPlatform.instance = fakePlatform;

    expect(await BubblFlutterSdk.instance.sayHello(), 'hello');
  });
}
