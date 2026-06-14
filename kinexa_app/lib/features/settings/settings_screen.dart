import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/constants/api_constants.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/asset_paths.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/kinexa_logo.dart';
import '../../core/widgets/kinexa_scaffold.dart';
import '../../data/models/device_model.dart';
import '../../data/repositories/sync_repository.dart';
import '../../overlays/sensor_search_overlay.dart';
import '../../providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String? _defaultDeviceId;
  String? _firmware;
  String? _lastSync;
  int _pending = 0;
  bool _online = false;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final deviceRepo = ref.read(deviceRepositoryProvider);
    final device = await deviceRepo.getDefaultDevice();
    final sync = ref.read(syncRepositoryProvider);
    final pending = await ref.read(runRepositoryProvider).getPendingRuns();
    final bleDevice = ref.read(bleServiceProvider).connectedDevice;

    _lastSync = await sync.lastSync();
    _online = !ref.read(offlineModeProvider) && await sync.isServerOnline();
    ref.read(serverOnlineProvider.notifier).state = _online;

    if (!mounted) return;
    setState(() {
      _defaultDeviceId = device?.deviceId;
      _firmware = bleDevice?.firmwareVersion ?? AppConstants.firmwareCompat;
      _pending = pending.length;
    });
  }

  Future<void> _syncNow() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      final sync = ref.read(syncRepositoryProvider);
      final result = await sync.syncAll();

      if (result.success) {
        ref.read(offlineModeProvider.notifier).state = false;
      } else if (!result.skipped && mounted) {
        _showSyncFailedSnackBar(result);
      }

      await _load();
      bumpHomeRefresh(ref);
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  void _showSyncFailedSnackBar(SyncAllResult result) {
    final message = !result.online
        ? 'Servidor indisponível. Verifique a conexão ou o endereço em Servidor.'
        : result.error != null
            ? 'Falha na sincronização: ${result.error}'
            : 'Falha na sincronização. Tente novamente.';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: AppTextStyles.mono(size: 12, letterSpacing: 0),
        ),
        backgroundColor: AppColors.redDark,
      ),
    );
  }

  Future<void> _clearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.popupBackground,
        title: Text(
          'Limpar cache local?',
          style: AppTextStyles.mono(
            size: 16,
            weight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
        content: Text(
          'Remove todas as coletas salvas neste celular. '
          'Os dados no servidor não serão apagados.',
          style: AppTextStyles.mono(
            size: 12,
            color: AppColors.textMuted,
            letterSpacing: 0,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancelar',
              style: AppTextStyles.mono(size: 12, letterSpacing: 0),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Limpar',
              style: AppTextStyles.mono(
                size: 12,
                weight: FontWeight.w700,
                color: AppColors.redPrimary,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    await ref.read(syncRepositoryProvider).clearLocalCache();
    await _load();
    bumpHomeRefresh(ref);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Cache local limpo.',
          style: AppTextStyles.mono(size: 12, letterSpacing: 0),
        ),
        backgroundColor: AppColors.cardBackground,
      ),
    );
  }

  Future<void> _calibrateSensor() async {
    ref.read(sensorFlowModeProvider.notifier).state =
        SensorFlowMode.calibrateSensor;
    ref.read(collectionSessionProvider.notifier).reset();

    DeviceModel? device =
        await ref.read(deviceRepositoryProvider).getDefaultDevice();
    if (!mounted) return;
    device ??= await showSensorSearchOverlay(context, ref);
    if (device == null || !mounted) return;

    final validated = await showDeviceValidationOverlay(context, ref, device);
    if (validated == null || !mounted) return;

    ref.read(collectionSessionProvider.notifier).setDevice(validated);
    await context.push('/calibration');
    if (mounted) await _load();
  }

  Future<void> _changeSensor() async {
    ref.read(sensorFlowModeProvider.notifier).state =
        SensorFlowMode.changeSensor;
    ref.read(collectionSessionProvider.notifier).reset();
    await ref.read(bleServiceProvider).disconnect();
    await ref.read(deviceRepositoryProvider).clearDefaultDevice();

    if (!mounted) return;
    final device = await showSensorSearchOverlay(context, ref);
    if (device == null || !mounted) return;

    final validated = await showDeviceValidationOverlay(context, ref, device);
    if (validated == null || !mounted) return;

    ref.read(collectionSessionProvider.notifier).setDevice(validated);
    await context.push('/calibration');
    if (mounted) await _load();
  }

  Future<void> _testSensor() async {
    ref.read(sensorFlowModeProvider.notifier).state = SensorFlowMode.testSensor;
    ref.read(collectionSessionProvider.notifier).reset();

    DeviceModel? device =
        await ref.read(deviceRepositoryProvider).getDefaultDevice();
    if (!mounted) return;
    device ??= await showSensorSearchOverlay(context, ref);
    if (device == null || !mounted) return;

    final validated = await showDeviceValidationOverlay(context, ref, device);
    if (!mounted) return;

    if (validated == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Teste do sensor falhou.',
            style: AppTextStyles.mono(size: 12, letterSpacing: 0),
          ),
          backgroundColor: AppColors.redDark,
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Sensor ${validated.deviceId} validado com sucesso.',
          style: AppTextStyles.mono(size: 12, letterSpacing: 0),
        ),
        backgroundColor: AppColors.cardBackground,
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(homeRefreshProvider, (_, __) => _load());
    final offlineMode = ref.watch(offlineModeProvider);
    final isOnline = _online && !offlineMode;

    return KinexaScaffold(
      backgroundColor: AppColors.popupBackground,
      body: Column(
        children: [
          _SettingsHeader(
            isOnline: isOnline,
            onBack: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/home');
              }
            },
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  'CONFIGURAÇÕES',
                  style: AppTextStyles.mono(
                    size: 32,
                    weight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 15),
                _SettingsSection(
                  icon: _DeviceSectionIcon(),
                  title: 'DISPOSITIVO',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _InfoField(
                        label: 'Sensor Padrão',
                        value: _defaultDeviceId ?? '—',
                      ),
                      const SizedBox(height: 10),
                      _InfoField(
                        label: 'Firmware',
                        value: 'v$_firmware',
                      ),
                      const SizedBox(height: 20),
                      _OutlineActionButton(
                        label: 'CALIBRAR SENSOR',
                        onPressed: _calibrateSensor,
                      ),
                      const SizedBox(height: 10),
                      _OutlineActionButton(
                        label: 'ALTERAR SENSOR',
                        onPressed: _changeSensor,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 15),
                _SettingsSection(
                  icon: const Icon(
                    Symbols.cloud,
                    size: 16,
                    color: Colors.white,
                  ),
                  title: 'SINCRONIZAÇÃO',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _InfoField(
                        label: 'Status',
                        value: isOnline ? 'Online' : 'Offline',
                      ),
                      const SizedBox(height: 10),
                      _InfoField(
                        label: 'Coletas Pendentes',
                        value: '$_pending',
                      ),
                      const SizedBox(height: 10),
                      _InfoField(
                        label: 'Última sincronização',
                        value: _formatSync(_lastSync),
                      ),
                      const SizedBox(height: 10),
                      _InfoField(
                        label: 'Servidor',
                        value: ApiConstants.baseUrl,
                      ),
                      const SizedBox(height: 20),
                      _FilledActionButton(
                        label: _syncing ? 'SINCRONIZANDO...' : 'SINCRONIZAR AGORA',
                        icon: Symbols.sync,
                        onPressed: _syncing ? null : _syncNow,
                      ),
                      const SizedBox(height: 10),
                      _OutlineActionButton(
                        label: 'LIMPAR CACHE',
                        icon: Symbols.delete_sweep,
                        onPressed: _syncing ? null : _clearCache,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 15),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _SettingsSection(
                        icon: const Icon(
                          Symbols.bug_report,
                          size: 16,
                          color: Colors.white,
                        ),
                        title: 'DIAGNÓSTICO',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Verifique o status do sensor e da conexão Bluetooth',
                              style: AppTextStyles.mono(
                                size: 12,
                                color: const Color(0xFFAAAAAA),
                                letterSpacing: 0,
                              ),
                            ),
                            const SizedBox(height: 20),
                            _OutlineActionButton(
                              label: 'TESTAR SENSOR',
                              icon: Symbols.monitor_heart,
                              onPressed: _testSensor,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _SettingsSection(
                        icon: const Icon(
                          Symbols.info,
                          size: 20,
                          color: Colors.white,
                        ),
                        title: 'SOBRE',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Informações do aplicativo e do projeto Kinexa',
                              style: AppTextStyles.mono(
                                size: 12,
                                color: const Color(0xFFAAAAAA),
                                letterSpacing: 0,
                              ),
                            ),
                            const SizedBox(height: 20),
                            _OutlineActionButton(
                              label: 'VER INFOS',
                              icon: Symbols.article,
                              onPressed: () => context.push('/about'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 30),
                const _SettingsPoweredBy(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatSync(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    try {
      final dt = DateTime.parse(iso);
      final now = DateTime.now();
      final isToday =
          dt.year == now.year && dt.month == now.month && dt.day == now.day;
      final time = DateFormat('HH:mm').format(dt);
      return isToday ? 'Hoje, $time' : DateFormat('dd/MM/yyyy HH:mm').format(dt);
    } catch (_) {
      return iso;
    }
  }
}

class _SettingsHeader extends StatelessWidget {
  const _SettingsHeader({
    required this.isOnline,
    required this.onBack,
  });

  final bool isOnline;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.baseBackground,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: const Icon(
                Symbols.arrow_back_ios_new,
                size: 18,
                color: Colors.white,
              ),
              onPressed: onBack,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: const KinexaLogo(
                    size: 36,
                    variant: KinexaLogoVariant.darkInv,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color:
                            isOnline ? AppColors.success : AppColors.textMuted,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      isOnline ? 'Online' : 'Offline',
                      style: AppTextStyles.mono(
                        size: 10,
                        weight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.icon,
    required this.title,
    required this.child,
  });

  final Widget icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppColors.cardBackground),
              ),
            ),
            child: Row(
              children: [
                SizedBox(width: 22, child: icon),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: AppTextStyles.mono(size: 16, letterSpacing: 0),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _DeviceSectionIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      AssetPaths.icons.device,
      width: 15,
      height: 25,
      colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
    );
  }
}

class _InfoField extends StatelessWidget {
  const _InfoField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTextStyles.mono(
              size: 12,
              color: const Color(0xFFAAAAAA),
              letterSpacing: 0,
            ),
          ),
          Text(
            value,
            style: AppTextStyles.mono(size: 15, letterSpacing: 0),
            softWrap: true,
          ),
        ],
      ),
    );
  }
}

class _OutlineActionButton extends StatelessWidget {
  const _OutlineActionButton({
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.redPrimary),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 7),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 14, color: AppColors.redPrimary),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    label,
                    style: AppTextStyles.mono(
                      size: 12,
                      weight: FontWeight.w700,
                      color: AppColors.redPrimary,
                      letterSpacing: 0,
                    ),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FilledActionButton extends StatelessWidget {
  const _FilledActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.redPrimary,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 7),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: Colors.white),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  style: AppTextStyles.mono(
                    size: 12,
                    weight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsPoweredBy extends StatelessWidget {
  const _SettingsPoweredBy();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'Powered by:',
          style: AppTextStyles.mono(
            size: 10,
            weight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              AssetPaths.logos.sesiPng,
              height: 15,
              width: 46,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 100),
            Image.asset(
              AssetPaths.logos.einsteinPng,
              height: 40,
              width: 50,
              fit: BoxFit.contain,
            ),
          ],
        ),
      ],
    );
  }
}
