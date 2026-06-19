import 'package:flutter/foundation.dart';

/// Fases do boot — controla quais endpoints o app pode chamar.
enum BootPhase {
  /// Splash: somente `GET /api/health`.
  splash,

  /// Tela de login: somente `POST /api/auth/login`.
  auth,

  /// Sync pós-login.
  syncing,

  /// App liberado (home, settings, etc.).
  ready,

  /// Boot offline na splash — nenhuma request remota.
  offline,
}

/// Fase atual do boot (resetada a cada abertura do app na splash).
final bootPhase = ValueNotifier<BootPhase>(BootPhase.splash);

/// Correlaciona requests no log do servidor (header `X-Kinexa-Boot`).
String bootTraceId = 'boot-0';

void resetBoot({required String traceId}) {
  bootTraceId = traceId;
  bootPhase.value = BootPhase.splash;
}

String _normalizePath(String path) {
  if (path.length > 1 && path.endsWith('/')) {
    return path.substring(0, path.length - 1);
  }
  return path;
}

/// App nunca baixa CSV nem detalhe de coleta remota — só `GET /api/runs`.
bool _isRunsPayloadGet(String method, String path) {
  if (method != 'GET') return false;
  if (path == '/api/runs') return false;
  return path.startsWith('/api/runs/');
}

bool bootAllowsRequest(String method, String path) {
  final normalized = _normalizePath(path);
  final upper = method.toUpperCase();

  if (_isRunsPayloadGet(upper, normalized)) {
    return false;
  }

  switch (bootPhase.value) {
    case BootPhase.splash:
      return upper == 'GET' && normalized == '/api/health';
    case BootPhase.auth:
      return upper == 'POST' && normalized == '/api/auth/login';
    case BootPhase.offline:
      return false;
    case BootPhase.syncing:
    case BootPhase.ready:
      return true;
  }
}

String bootPhaseLabel(BootPhase phase) => switch (phase) {
      BootPhase.splash => 'splash',
      BootPhase.auth => 'auth',
      BootPhase.syncing => 'syncing',
      BootPhase.ready => 'ready',
      BootPhase.offline => 'offline',
    };
