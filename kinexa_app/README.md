# Kinexa App (Flutter)

App móvel Kinexa — controle de sensor (BLE mock), coleta, sync com backend.

## Rodar (desenvolvimento local)

Com backend local na máquina e app no Android Emulator:

```bash
cd kinexa_app
flutter pub get
flutter run
```

Por padrão o app usa:

```text
http://10.0.2.2:8000
```

(`10.0.2.2` é o host da máquina de desenvolvimento visto pelo emulador Android.)

## Rodar apontando para API online (MVP / apresentação)

Com Cloudflare Tunnel ativo em `https://api.antoniofaical.dev.br`:

```bash
flutter run --dart-define=KINEXA_API_BASE_URL=https://api.antoniofaical.dev.br
```

## Gerar APK de apresentação

```bash
flutter build apk --dart-define=KINEXA_API_BASE_URL=https://api.antoniofaical.dev.br
```

O APK gerará em `build/app/outputs/flutter-apk/app-release.apk`.

## Base URL da API

A URL é configurada via `--dart-define` em `lib/core/constants/api_constants.dart`:

```dart
static const String baseUrl = String.fromEnvironment(
  'KINEXA_API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8000',
);
```

Valores suportados:

| Ambiente | URL |
|---|---|
| Local (emulador Android) | `http://10.0.2.2:8000` |
| Produção / MVP | `https://api.antoniofaical.dev.br` |

A URL atual aparece em **Configurações → Sincronização → Servidor**.

## BLE — mock vs real

Por padrão o app usa `MockBleService` (emulador/desktop).

### Mock (padrão)

```bash
flutter run
```

### BLE real (celular Android físico — fase 1: scan/connect/validate)

```bash
flutter run --dart-define=KINEXA_USE_REAL_BLE=true
```

Com API online:

```bash
flutter run \
  --dart-define=KINEXA_USE_REAL_BLE=true \
  --dart-define=KINEXA_API_BASE_URL=https://api.antoniofaical.dev.br
```

### APK apresentação (BLE real + API online)

```bash
flutter build apk --release \
  --dart-define=KINEXA_USE_REAL_BLE=true \
  --dart-define=KINEXA_API_BASE_URL=https://api.antoniofaical.dev.br
```

**Fase atual:** scan, connect, validate e getStatus reais. Calibrate / START / STOP / download ainda lançam erro controlado — próxima fase.

Logs BLE aparecem em **Ver detalhes técnicos** (DebugLogService).

## Testar com backend

1. Suba PostgreSQL + backend (`kinexa-backend`)
2. Rode o app com a `baseUrl` correta
3. SyncScreen faz health check em `GET /api/health`, baixa runs e envia pendentes
4. Nova Coleta usa BLE (mock ou real) e faz `POST /api/runs/upload` quando online

## Modo offline

- Splash → Sync; se falhar, o usuário pode **Tentar novamente** ou **Entrar no modo offline**
- O modo offline vale apenas para a sessão atual (não persiste entre reinicializações)
- Coletas em offline são salvas localmente e não fazem upload automático na finalização
- **Sincronizar agora** nas Configurações ainda funciona quando o servidor voltar
