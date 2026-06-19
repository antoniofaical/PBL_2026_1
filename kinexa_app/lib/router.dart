import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import 'core/boot/app_boot.dart';
import 'features/about/about_screen.dart';
import 'features/auth/auth_screen.dart';
import 'features/calibration/calibration_screen.dart';
import 'features/collection/collection_screen.dart';
import 'features/home/home_screen.dart';
import 'features/metadata/metadata_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/splash/splash_screen.dart';
import 'features/sync/sync_screen.dart';
import 'features/transfer/transfer_screen.dart';

/// Só true após login explícito nesta sessão do app.
final authGate = ValueNotifier<bool>(false);

final appRouter = GoRouter(
  initialLocation: '/splash',
  redirect: (context, state) {
    final loc = state.matchedLocation;
    final offlineBoot = state.uri.queryParameters['start'] == 'failed';

    if (loc == '/sync' &&
        !offlineBoot &&
        bootPhase.value != BootPhase.syncing) {
      return '/auth';
    }
    return null;
  },
  routes: [
    GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
    GoRoute(path: '/auth', builder: (_, __) => const AuthScreen()),
    GoRoute(
      path: '/sync',
      builder: (_, state) => SyncScreen(
        startFailed: state.uri.queryParameters['start'] == 'failed',
      ),
    ),
    GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
    GoRoute(path: '/calibration', builder: (_, __) => const CalibrationScreen()),
    GoRoute(path: '/metadata', builder: (_, __) => const MetadataScreen()),
    GoRoute(path: '/collection', builder: (_, __) => const CollectionScreen()),
    GoRoute(path: '/transfer', builder: (_, __) => const TransferScreen()),
    GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
    GoRoute(path: '/about', builder: (_, __) => const AboutScreen()),
  ],
);
