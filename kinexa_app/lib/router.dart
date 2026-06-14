import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'features/about/about_screen.dart';
import 'features/calibration/calibration_screen.dart';
import 'features/collection/collection_screen.dart';
import 'features/home/home_screen.dart';
import 'features/metadata/metadata_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/splash/splash_screen.dart';
import 'features/sync/sync_screen.dart';
import 'features/transfer/transfer_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/splash',
  routes: [
    GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
    GoRoute(path: '/sync', builder: (_, __) => const SyncScreen()),
    GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
    GoRoute(path: '/calibration', builder: (_, __) => const CalibrationScreen()),
    GoRoute(path: '/metadata', builder: (_, __) => const MetadataScreen()),
    GoRoute(path: '/collection', builder: (_, __) => const CollectionScreen()),
    GoRoute(path: '/transfer', builder: (_, __) => const TransferScreen()),
    GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
    GoRoute(path: '/about', builder: (_, __) => const AboutScreen()),
  ],
);
