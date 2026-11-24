import 'package:conduit/core/preset/preset_login.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a build without preset defines is not a preset build', () {
    expect(isPresetBuild, isFalse);
    expect(presetServerUrl, isEmpty);
    expect(presetEmail, isEmpty);
  });
}
