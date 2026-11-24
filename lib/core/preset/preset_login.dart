import 'package:conduit_core/auth/auth_state_manager.dart';
import 'package:conduit_core/models/server_config.dart';
import 'package:conduit_core/providers/app_providers.dart';
import 'package:conduit_core/services/api_service.dart';
import 'package:flutter/foundation.dart' show mapEquals, visibleForTesting;
import 'package:riverpod/misc.dart' show ProviderListenable;
import 'package:conduit_core/preset/preset_build.dart';

export 'package:conduit_core/preset/preset_build.dart';


/// Reads a provider without listening: `Ref.read`, `WidgetRef.read` and
/// `ProviderContainer.read` all fit.
typedef PresetProviderRead = T Function<T>(ProviderListenable<T> provider);

/// Makes [config] the active server, signed out, and waits for its client.
Future<void> saveServerConfigForSignIn(
  PresetProviderRead read,
  ServerConfig config, {
  bool Function()? canCommit,
}) async {
  await read(authStateManagerProvider.notifier)
      .selectUnauthenticatedServerConfig(config, canCommit: canCommit);

  final selectedServer = await read(activeServerProvider.future);
  if (!authenticationServerMatchesSelection(selectedServer, config)) {
    throw StateError('The selected server changed before sign-in was ready.');
  }
  await waitForApiServiceSelection(read, config);
}

Future<void> waitForApiServiceSelection(
  PresetProviderRead read,
  ServerConfig selectedServer,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (DateTime.now().isBefore(deadline)) {
    final api = read(apiServiceProvider);
    if (authenticationApiMatchesSelection(api, selectedServer)) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw StateError('The selected server connection was not ready in time.');
}

@visibleForTesting
String normalizeAuthenticationServerUrl(String value) {
  final trimmed = value.trim();
  final parsed = Uri.tryParse(trimmed);
  if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) {
    return trimmed;
  }

  var path = parsed.path;
  while (path.length > 1 && path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  if (path == '/') path = '';
  return parsed
      .replace(
        scheme: parsed.scheme.toLowerCase(),
        host: parsed.host.toLowerCase(),
        path: path,
      )
      .toString();
}

@visibleForTesting
bool authenticationServerMatchesSelection(
  ServerConfig? actual,
  ServerConfig expected,
) {
  return actual != null &&
      actual.id == expected.id &&
      actual.apiKey == null &&
      normalizeAuthenticationServerUrl(actual.url) ==
          normalizeAuthenticationServerUrl(expected.url) &&
      mapEquals(actual.customHeaders, expected.customHeaders) &&
      actual.allowSelfSignedCertificates ==
          expected.allowSelfSignedCertificates &&
      actual.mtlsCertificateChainPem == expected.mtlsCertificateChainPem &&
      actual.mtlsPrivateKeyPem == expected.mtlsPrivateKeyPem &&
      actual.mtlsPrivateKeyPassword == expected.mtlsPrivateKeyPassword;
}

/// Whether the selected server's newly-created API client is safe for sign-in.
///
/// Selection deliberately strips legacy [ServerConfig.apiKey] values, and the
/// replacement client must not inherit a bearer from the prior session.
@visibleForTesting
bool authenticationApiMatchesSelection(
  ApiService? actual,
  ServerConfig expected,
) {
  return actual != null &&
      actual.authToken == null &&
      authenticationServerMatchesSelection(actual.serverConfig, expected);
}
