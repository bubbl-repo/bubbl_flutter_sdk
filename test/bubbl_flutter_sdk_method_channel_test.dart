import 'package:bubbl_flutter_sdk/bubbl_flutter_sdk_method_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final MethodChannelBubblFlutterSdk platform = MethodChannelBubblFlutterSdk();
  const MethodChannel channel = MethodChannel('tech.bubbl.sdk/methods');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          switch (methodCall.method) {
            case 'sayHello':
              return 'hello from native';
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('sayHello', () async {
    expect(await platform.sayHello(), 'hello from native');
  });
}
