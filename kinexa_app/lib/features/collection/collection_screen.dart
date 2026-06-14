import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/constants/enums.dart';
import '../../core/theme/app_gradients.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/kinexa_collection_timer.dart';
import '../../core/widgets/kinexa_logo.dart';
import '../../core/widgets/kinexa_scaffold.dart';
import '../../core/widgets/digital_display.dart';
import '../../data/models/event_model.dart';
import '../../overlays/register_event_dialog.dart';
import '../../providers.dart';
import '../../services/ble/ble_exception.dart';

enum _RecordingUiState { starting, recording, failed }

class CollectionScreen extends ConsumerStatefulWidget {
  const CollectionScreen({super.key});

  @override
  ConsumerState<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends ConsumerState<CollectionScreen> {
  Timer? _timer;
  int _elapsedMs = 0;
  bool _started = false;
  bool _eventsExpanded = true;
  _RecordingUiState _recordingState = _RecordingUiState.starting;
  String? _recordingError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _begin());
  }

  Future<void> _begin() async {
    if (_started) return;
    _started = true;

    final session = ref.read(collectionSessionProvider);
    if (!session.isCalibrated) {
      if (!mounted) return;
      setState(() {
        _recordingState = _RecordingUiState.failed;
        _recordingError = 'Sensor não calibrado.';
      });
      await _showRecordingError(
        'O sensor precisa ser calibrado antes da coleta.',
        showCalibrateAction: true,
      );
      return;
    }

    setState(() {
      _recordingState = _RecordingUiState.starting;
      _recordingError = null;
    });

    try {
      // Cronômetro só inicia após REC:STARTED do firmware (dentro de startRecording).
      await ref.read(bleServiceProvider).startRecording();
      if (!mounted) return;

      ref.read(collectionSessionProvider.notifier).startTimer();
      _timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
        final ms = ref.read(collectionSessionProvider.notifier).elapsedMs;
        if (mounted) setState(() => _elapsedMs = ms);
      });
      setState(() => _recordingState = _RecordingUiState.recording);
    } on BleException catch (e) {
      if (!mounted) return;
      setState(() {
        _recordingState = _RecordingUiState.failed;
        _recordingError = e.message;
      });
      await _showRecordingError(e.message, showCalibrateAction: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _recordingState = _RecordingUiState.failed;
        _recordingError = e.toString();
      });
      await _showRecordingError('Falha ao iniciar gravação no sensor.');
    }
  }

  Future<void> _showRecordingError(
    String message, {
    bool showCalibrateAction = false,
  }) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        title: Text(
          'Falha na coleta',
          style: AppTextStyles.mono(size: 16, weight: FontWeight.w700),
        ),
        content: Text(
          message,
          style: AppTextStyles.mono(size: 14, color: AppColors.textMuted),
        ),
        actions: [
          if (showCalibrateAction)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                context.push('/calibration');
              },
              child: Text(
                'CALIBRAR',
                style: AppTextStyles.mono(
                  size: 12,
                  color: AppColors.redPrimary,
                  weight: FontWeight.w700,
                ),
              ),
            ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.pop();
            },
            child: Text(
              'VOLTAR',
              style: AppTextStyles.mono(size: 12, weight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _registerEvent() async {
    final event = await showRegisterEventDialog(context, _elapsedMs);
    if (event != null) {
      ref.read(collectionSessionProvider.notifier).addEvent(event);
      setState(() => _eventsExpanded = true);
    }
  }

  Future<void> _finish() async {
    if (_recordingState != _RecordingUiState.recording) return;
    final session = ref.read(collectionSessionProvider);
    final confirmed = await showFinishCollectionDialog(
      context,
      durationMs: _elapsedMs,
      eventCount: session.events.length,
    );
    if (!confirmed || !mounted) return;
    context.push('/transfer');
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(collectionSessionProvider);
    final online = ref.watch(serverOnlineProvider);
    final offlineMode = ref.watch(offlineModeProvider);
    final isOnline = online && !offlineMode;

    return KinexaScaffold(
      backgroundColor: AppColors.popupBackground,
      body: Column(
        children: [
          _CollectionHeader(isOnline: isOnline),
          Expanded(
            child: ColoredBox(
              color: AppColors.popupBackground,
              child: Column(
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final eventsHeight = _eventsExpanded
                            ? (constraints.maxHeight * 0.28).clamp(72.0, 140.0)
                            : null;

                        return SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(10, 12, 10, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _AthleteSummaryCard(session: session),
                              const SizedBox(height: 8),
                              _SensorStatusCard(
                                deviceId: session.device?.deviceId ?? '—',
                                recordingState: _recordingState,
                                errorMessage: _recordingError,
                              ),
                              const SizedBox(height: 16),
                              KinexaCollectionTimer(elapsedMs: _elapsedMs),
                              const SizedBox(height: 16),
                              _EventsPanel(
                                events: session.events,
                                expanded: _eventsExpanded,
                                maxHeight: eventsHeight,
                                onToggle: () => setState(
                                  () => _eventsExpanded = !_eventsExpanded,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                      child: Column(
                        children: [
                          _CollectionActionButton(
                            label: 'REGISTRAR EVENTO',
                            onPressed: _recordingState == _RecordingUiState.recording
                                ? _registerEvent
                                : null,
                          ),
                          const SizedBox(height: 10),
                          _CollectionActionButton(
                            label: 'FINALIZAR COLETA',
                            primary: true,
                            onPressed: _recordingState == _RecordingUiState.recording
                                ? _finish
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CollectionHeader extends StatelessWidget {
  const _CollectionHeader({required this.isOnline});

  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.baseBackground,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            const KinexaLogo(size: 36, variant: KinexaLogoVariant.darkInv),
            const Spacer(),
            _OnlineStatus(isOnline: isOnline),
          ],
        ),
      ),
    );
  }
}

class _OnlineStatus extends StatelessWidget {
  const _OnlineStatus({required this.isOnline});

  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    final dotColor = isOnline ? AppColors.success : AppColors.textMuted;

    return Row(
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
    );
  }
}

class _AthleteSummaryCard extends StatelessWidget {
  const _AthleteSummaryCard({required this.session});

  final CollectionSession session;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            session.athlete,
            style: AppTextStyles.mono(
              size: 24,
              weight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                Activity.fromValue(session.activity).label,
                style: AppTextStyles.mono(
                  size: 15,
                  color: const Color(0xFFAAAAAA),
                  letterSpacing: 0,
                ),
              ),
              Text(
                '•',
                style: AppTextStyles.mono(
                  size: 15,
                  color: const Color(0xFFAAAAAA),
                  letterSpacing: 0,
                ),
              ),
              Text(
                Environment.fromValue(session.environment).label,
                style: AppTextStyles.mono(
                  size: 15,
                  color: const Color(0xFFAAAAAA),
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SensorStatusCard extends StatelessWidget {
  const _SensorStatusCard({
    required this.deviceId,
    required this.recordingState,
    this.errorMessage,
  });

  final String deviceId;
  final _RecordingUiState recordingState;
  final String? errorMessage;

  String get _statusLabel => switch (recordingState) {
        _RecordingUiState.starting => 'Aguardando confirmação do sensor...',
        _RecordingUiState.recording => '✓ Gravando',
        _RecordingUiState.failed => errorMessage ?? 'Erro na gravação',
      };

  Color get _statusColor => switch (recordingState) {
        _RecordingUiState.starting => AppColors.warning,
        _RecordingUiState.recording => const Color(0xFFAAAAAA),
        _RecordingUiState.failed => AppColors.redPrimary,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.baseBackground.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sensor: $deviceId',
            style: AppTextStyles.mono(
              size: 16,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _statusLabel,
            style: AppTextStyles.mono(
              size: 15,
              color: _statusColor,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _EventsPanel extends StatelessWidget {
  const _EventsPanel({
    required this.events,
    required this.expanded,
    required this.onToggle,
    this.maxHeight,
  });

  final List<EventModel> events;
  final bool expanded;
  final VoidCallback onToggle;
  final double? maxHeight;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.baseBackground,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _EventsPanelHeader(
            count: events.length,
            expanded: expanded,
            onToggle: onToggle,
          ),
          if (expanded)
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: maxHeight ?? 140,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(10),
                child: events.isEmpty
                    ? Text(
                        'Nenhum evento registrado',
                        style: AppTextStyles.mono(
                          size: 15,
                          color: const Color(0xFFAAAAAA),
                          letterSpacing: 0,
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < events.length; i++) ...[
                            if (i > 0) const SizedBox(height: 10),
                            Text(
                              _formatEventLine(events[i]),
                              style: AppTextStyles.mono(
                                size: 15,
                                color: const Color(0xFFAAAAAA),
                                letterSpacing: 0,
                              ),
                            ),
                          ],
                        ],
                      ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatEventLine(EventModel event) {
    final time = formatDurationMs(event.timestampMs);
    final description = event.description;
    if (description == null || description.isEmpty) return time;
    return '$time - $description';
  }
}

class _EventsPanelHeader extends StatelessWidget {
  const _EventsPanelHeader({
    required this.count,
    required this.expanded,
    required this.onToggle,
  });

  final int count;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: expanded
              ? const Border(
                  bottom: BorderSide(color: Color(0x1AAAAAAA)),
                )
              : null,
        ),
        child: Row(
          children: [
            Text(
              'Eventos: $count',
              style: AppTextStyles.mono(
                size: 15,
                color: const Color(0xFFAAAAAA),
                letterSpacing: 0,
              ),
            ),
            const Spacer(),
            Icon(
              expanded ? Symbols.keyboard_arrow_up : Symbols.keyboard_arrow_down,
              color: AppColors.redPrimary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _CollectionActionButton extends StatelessWidget {
  const _CollectionActionButton({
    required this.label,
    required this.onPressed,
    this.primary = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool primary;

  static const _radius = 97.0;
  static const _padding = EdgeInsets.symmetric(vertical: 15);

  @override
  Widget build(BuildContext context) {
    final labelWidget = Padding(
      padding: _padding,
      child: Center(
        child: Text(
          label,
          style: AppTextStyles.mono(
            size: 20,
            weight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
      ),
    );

    if (primary) {
      return Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(_radius),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(_radius),
          child: Ink(
            decoration: BoxDecoration(
              gradient: AppGradients.primaryButton,
              borderRadius: BorderRadius.circular(_radius),
            ),
            child: labelWidget,
          ),
        ),
      );
    }

    return Material(
      color: AppColors.cardBackground.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(_radius),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(_radius),
        child: labelWidget,
      ),
    );
  }
}
