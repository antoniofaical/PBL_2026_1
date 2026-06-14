import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

class BlePermissions {
  static Future<bool> ensureBlePermissions(void Function(String) log) async {
    if (!Platform.isAndroid) {
      log('[BLE] permissions skipped (not Android)');
      return true;
    }

    log('[BLE] requesting permissions');

    final permissions = <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ];

    final statuses = await permissions.request();
    final denied = statuses.entries
        .where((e) => !e.value.isGranted)
        .map((e) => e.key)
        .toList();

    if (denied.isEmpty) {
      log('[BLE] permissions granted');
      return true;
    }

    log('[BLE] permissions denied: ${denied.join(', ')}');
    return false;
  }
}
