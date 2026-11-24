import 'package:conduit/core/preset/preset_login.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';

T _unexpectedRead<T>(ProviderListenable<T> provider) {
  throw StateError('Preset read a provider despite empty defines: $provider');
}

void main() {
  test('a build without preset defines is not a preset build', () {
    expect(isPresetBuild, isFalse);
  });

  test('preset login is a no-op without preset defines', () async {
    await runPresetLogin(_unexpectedRead);
  });
}
