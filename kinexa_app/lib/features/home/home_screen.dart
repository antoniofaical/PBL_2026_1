import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/constants/enums.dart';
import '../../debug/demo_runs_seed.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_gradients.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/kinexa_dashed_border.dart';
import '../../core/widgets/kinexa_card.dart';
import '../../core/widgets/kinexa_logo.dart';
import '../../core/widgets/kinexa_scaffold.dart';
import '../../core/widgets/status_badge.dart';
import '../../data/models/device_model.dart';
import '../../data/models/run_model.dart';
import '../../overlays/sensor_search_overlay.dart';
import '../../providers.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  List<RunModel> _runs = [];
  int _athletes = 0;
  String? _lastSync;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    _tryAutoSync();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final repo = ref.read(runRepositoryProvider);
    final sync = ref.read(syncRepositoryProvider);
    if (ref.read(offlineModeProvider)) {
      await seedDemoRunsIfEmpty(repo, ref.read(settingsDaoProvider));
    }
    _runs = await repo.getLocalRuns();
    _athletes = await repo.countAthletes();
    _lastSync = await sync.lastSync();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _refresh() async {
    if (!ref.read(offlineModeProvider)) {
      final sync = ref.read(syncRepositoryProvider);
      final result = await sync.syncAll();
      ref.read(serverOnlineProvider.notifier).state = result.online;
    }
    await _load();
  }

  Future<void> _tryAutoSync() async {
    if (ref.read(offlineModeProvider)) return;
    final sync = ref.read(syncRepositoryProvider);
    if (await sync.isServerOnline()) {
      ref.read(serverOnlineProvider.notifier).state = true;
      await sync.syncPendingUploads();
      await _load();
    }
  }

  Future<void> _startNewCollection() async {
    ref.read(sensorFlowModeProvider.notifier).state =
        SensorFlowMode.newCollection;
    ref.read(collectionSessionProvider.notifier).reset();
    final deviceRepo = ref.read(deviceRepositoryProvider);
    DeviceModel? device = await deviceRepo.getDefaultDevice();

    if (device == null) {
      device = await showSensorSearchOverlay(context, ref);
      if (device == null || !mounted) return;
    }

    if (!mounted) return;
    final validated = await showDeviceValidationOverlay(context, ref, device);
    if (validated == null || !mounted) return;

    ref.read(collectionSessionProvider.notifier).setDevice(validated);
    if (!mounted) return;
    if (validated.state == DeviceState.ready) {
      ref.read(collectionSessionProvider.notifier).markCalibrated();
      context.push('/metadata');
    } else {
      context.push('/calibration');
    }
  }

  int get _pendingCount =>
      _runs.where((r) => r.syncStatus != SyncStatus.synced).length;

  @override
  Widget build(BuildContext context) {
    ref.listen(homeRefreshProvider, (_, __) => _load());
    final online = ref.watch(serverOnlineProvider);
    final offlineMode = ref.watch(offlineModeProvider);
    final isOnline = online && !offlineMode;

    return KinexaScaffold(
      body: Column(
        children: [
          _HomeHeader(
            isOnline: isOnline,
            pendingCount: _pendingCount,
            onSettings: () => context.push('/settings'),
          ),
          Expanded(
            child: Stack(
              children: [
                RefreshIndicator(
                  color: AppColors.redPrimary,
                  onRefresh: _refresh,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.screenHorizontal,
                          AppSpacing.homeSection,
                          AppSpacing.screenHorizontal,
                          220,
                        ),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                          ),
                          child: Column(
                            children: _bodyChildren(),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _HomeFooter(onPressed: _startNewCollection),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _bodyChildren() {
    return [
      _sectionTitle('INFORMAÇÕES DA BASE DE DADOS'),
      const SizedBox(height: 10),
      _statsRow(),
      const SizedBox(height: AppSpacing.homeSection),
      _sectionTitle('RESUMO DAS ÚLTIMAS COLETAS'),
      const SizedBox(height: 5),
      if (_loading)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (_runs.isEmpty)
        _emptyState()
      else
        ..._runs.take(8).map(_runTile),
    ];
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          text,
          style: AppTextStyles.mono(
            size: 14,
            weight: FontWeight.w700,
            letterSpacing: 0,
          ),
          textAlign: TextAlign.center,
        ),
      );

  static const _statsCardHeight = 132.0;

  Widget _statsRow() {
    final syncParts = _formatLastSync(_lastSync);

    return Row(
      children: [
        Expanded(
          child: _statCard(
            value: '$_athletes',
            label: 'ATLETAS',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _statCard(
            value: '${_runs.length}',
            label: 'COLETAS',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _statCard(
            value: syncParts.time,
            label: 'ÚLTIMA SYNC',
            topLabel: syncParts.dayLabel,
          ),
        ),
      ],
    );
  }

  Widget _statCard({
    required String value,
    required String label,
    String? topLabel,
  }) {
    return SizedBox(
      height: _statsCardHeight,
      child: KinexaCard(
        padding: 8,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (topLabel != null) ...[
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  topLabel,
                  style: AppTextStyles.mono(
                    size: 10,
                    weight: FontWeight.w700,
                    color: AppColors.textMuted,
                    letterSpacing: 0,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 4),
            ],
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: AppTextStyles.digital(
                  size: 32,
                  color: AppColors.digitalAccent,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: AppTextStyles.mono(size: 12, letterSpacing: 0),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    return KinexaDashedBorder(
      color: AppColors.patternCircle,
      strokeWidth: 2,
      radius: AppRadii.card,
      child: Container(
        width: double.infinity,
        height: 400,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.athleteCardHorizontal,
          vertical: AppSpacing.athleteCardVertical,
        ),
        decoration: BoxDecoration(
          color: AppColors.cardBackground.withValues(alpha: 0.36),
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
        alignment: Alignment.center,
        child: Text(
          'Nada para ver por aqui...',
          style: AppTextStyles.mono(
            size: 12,
            color: AppColors.textMuted,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }

  Widget _runTile(RunModel run) {
    final activity = Activity.fromValue(run.activity);
    final environment = Environment.fromValue(run.environment);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.homeCardVertical),
      child: KinexaRunCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              run.athlete,
              style: AppTextStyles.mono(
                size: 21,
                weight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  _activityIcon(activity),
                  size: 20,
                  color: AppColors.text,
                ),
                const SizedBox(width: 10),
                Text(
                  '${activity.label} - ${environment.label}',
                  style: AppTextStyles.mono(size: 12, letterSpacing: 0),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _formatRunDate(run.datetime),
                    style: AppTextStyles.mono(
                      size: 12,
                      color: AppColors.text,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                StatusBadge(status: run.syncStatus),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _activityIcon(Activity activity) {
    return switch (activity) {
      Activity.marcha => Symbols.directions_walk,
      Activity.corrida => Symbols.directions_run,
      Activity.saltoVertical => Symbols.shoe_cleats,
      Activity.saltoDistancia => Symbols.shoe_cleats,
    };
  }

  String _formatRunDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final date = DateTime(dt.year, dt.month, dt.day);
      final time = DateFormat('HH:mm').format(dt);

      if (date == today) return 'Hoje, $time';
      if (date == today.subtract(const Duration(days: 1))) {
        return 'Ontem, $time';
      }
      return DateFormat('dd/MM/yyyy').format(dt);
    } catch (_) {
      return iso;
    }
  }
}

class _SyncParts {
  const _SyncParts({required this.dayLabel, required this.time});

  final String dayLabel;
  final String time;
}

_SyncParts _formatLastSync(String? iso) {
  if (iso == null) {
    return const _SyncParts(dayLabel: 'n/a', time: '--:--');
  }
  try {
    final dt = DateTime.parse(iso);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(dt.year, dt.month, dt.day);
    final time = DateFormat('HH:mm').format(dt);

    if (date == today) {
      return _SyncParts(dayLabel: 'HOJE', time: time);
    }
    if (date == today.subtract(const Duration(days: 1))) {
      return _SyncParts(dayLabel: 'ONTEM', time: time);
    }
    return _SyncParts(
      dayLabel: DateFormat('dd/MM').format(dt),
      time: time,
    );
  } catch (_) {
    return _SyncParts(dayLabel: 'n/a', time: '--:--');
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.isOnline,
    required this.pendingCount,
    required this.onSettings,
  });

  final bool isOnline;
  final int pendingCount;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.baseBackground,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenHorizontal,
          vertical: 16,
        ),
        child: Row(
          children: [
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
                child: _OnlineStatus(
                  isOnline: isOnline,
                  pendingCount: pendingCount,
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: Icon(
                Symbols.settings,
                color: AppColors.textMuted,
                size: 20,
              ),
              onPressed: onSettings,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnlineStatus extends StatelessWidget {
  const _OnlineStatus({
    required this.isOnline,
    required this.pendingCount,
  });

  final bool isOnline;
  final int pendingCount;

  @override
  Widget build(BuildContext context) {
    final dotColor = isOnline ? AppColors.success : AppColors.textMuted;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
                boxShadow: isOnline
                    ? [
                        BoxShadow(
                          color: dotColor.withValues(alpha: 0.6),
                          blurRadius: 6,
                        ),
                      ]
                    : null,
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
        if (!isOnline && pendingCount > 0)
          Text(
            '$pendingCount pendente${pendingCount == 1 ? '' : 's'}',
            style: AppTextStyles.mono(
              size: 9,
              color: AppColors.warning,
              letterSpacing: 0,
            ),
          ),
      ],
    );
  }
}

class _HomeFooter extends StatelessWidget {
  const _HomeFooter({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 88, 10, 30),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0x00121212),
            Color(0x33121212),
            Color(0x99121212),
            AppColors.baseBackground,
          ],
          stops: [0.0, 0.3, 0.72, 1.0],
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Material(
              color: Colors.transparent,
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(AppRadii.squareButton),
              ),
              child: InkWell(
                onTap: onPressed,
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(AppRadii.squareButton),
                ),
                child: Ink(
                  decoration: const BoxDecoration(
                    gradient: AppGradients.primaryButton,
                    borderRadius: BorderRadius.horizontal(
                      left: Radius.circular(AppRadii.squareButton),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    'NOVA COLETA',
                    style: AppTextStyles.mono(
                      size: 20,
                      weight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 3,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
          Material(
            color: Colors.transparent,
            borderRadius: const BorderRadius.horizontal(
              right: Radius.circular(AppRadii.squareButton),
            ),
            child: InkWell(
              onTap: onPressed,
              borderRadius: const BorderRadius.horizontal(
                right: Radius.circular(AppRadii.squareButton),
              ),
              child: Ink(
                width: 127,
                height: 50,
                decoration: const BoxDecoration(
                  gradient: AppGradients.primaryButton,
                  borderRadius: BorderRadius.horizontal(
                    right: Radius.circular(AppRadii.squareButton),
                  ),
                ),
                child: const Icon(
                  Symbols.keyboard_double_arrow_right,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
