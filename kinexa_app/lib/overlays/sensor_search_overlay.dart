import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../core/widgets/kinexa_button.dart';
import '../core/widgets/kinexa_device_card.dart';
import '../core/widgets/kinexa_overlay_shell.dart';
import '../core/widgets/kinexa_radar.dart';
import '../data/models/device_model.dart';
import '../providers.dart';
import '../services/ble/ble_exception.dart';
import 'debug_bottom_sheet.dart';

// ---------------------------------------------------------------------------
// Search overlay
// ---------------------------------------------------------------------------

enum _SearchPhase { setup, scanning, searchFailed, devicesFound }

Future<DeviceModel?> showSensorSearchOverlay(
  BuildContext context,
  WidgetRef ref, {
  bool showSetup = true,
}) {
  return showKinexaOverlay<DeviceModel>(
    context,
    _SensorSearchDialog(showSetup: showSetup),
  );
}

class _SensorSearchDialog extends ConsumerStatefulWidget {
  const _SensorSearchDialog({required this.showSetup});

  final bool showSetup;

  @override
  ConsumerState<_SensorSearchDialog> createState() => _SensorSearchDialogState();
}

class _SensorSearchDialogState extends ConsumerState<_SensorSearchDialog> {
  late _SearchPhase _phase;
  List<DeviceModel> _devices = [];
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _phase = widget.showSetup ? _SearchPhase.setup : _SearchPhase.scanning;
    if (!widget.showSetup) _scan();
  }

  Future<void> _scan() async {
    setState(() {
      _phase = _SearchPhase.scanning;
      _devices = [];
      _selectedId = null;
    });

    final ble = ref.read(bleServiceProvider);
    var gotResults = false;

    await for (final list in ble.scanDevices()) {
      if (!mounted) return;
      if (list.isNotEmpty) {
        gotResults = true;
        setState(() {
          _devices = list;
          _phase = _SearchPhase.devicesFound;
        });
        break;
      }
    }

    if (!mounted) return;
    if (!gotResults) {
      setState(() => _phase = _SearchPhase.searchFailed);
    }
  }

  void _selectDevice(DeviceModel device) {
    setState(() => _selectedId = device.deviceId);
    Future.delayed(const Duration(milliseconds: 180), () {
      if (mounted) Navigator.pop(context, device);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: switch (_phase) {
        _SearchPhase.setup => _buildSetup(),
        _SearchPhase.scanning => _buildScanning(),
        _SearchPhase.searchFailed => _buildSearchFailed(),
        _SearchPhase.devicesFound => _buildDevicesFound(),
      },
    );
  }

  Widget _buildSetup() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _overlayTitle('CONFIGURAÇÃO DE DISPOSITIVO'),
        const SizedBox(height: 30),
        _overlaySubtitle(
          'Nenhum sensor Kinexa padrão foi configurado neste dispositivo.',
          center: true,
        ),
        const SizedBox(height: 10),
        _overlaySubtitle(
          'Para iniciar uma coleta, conecte um sensor.',
          center: true,
        ),
        const SizedBox(height: 30),
        KinexaButton.primary(
          label: 'PROCURAR SENSORES',
          onPressed: _scan,
        ),
      ],
    );
  }

  Widget _buildScanning() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _overlayTitle('PROCURANDO SENSORES'),
        const SizedBox(height: 30),
        const _RadarGlow(),
        const SizedBox(height: 30),
        _overlaySubtitle('Escaneando dispositivos Kinexa próximos...'),
      ],
    );
  }

  Widget _buildSearchFailed() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _overlayTitle('PROCURANDO SENSORES'),
        const SizedBox(height: 30),
        const _RadarGlow(),
        const SizedBox(height: 30),
        _overlaySubtitle('Escaneando dispositivos Kinexa próximos...'),
        const SizedBox(height: 10),
        _overlaySubtitle('Nenhum dispositivo encontrado', center: true),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Verifique:\n\n'
            '✓ Sensor ligado\n\n'
            '✓ Bluetooth ativo\n\n'
            '✓ Distância inferior a 5 m',
            style: AppTextStyles.mono(size: 12, letterSpacing: 0),
          ),
        ),
        const SizedBox(height: 20),
        _secondaryPillButton('TENTAR NOVAMENTE', onPressed: _scan),
      ],
    );
  }

  Widget _buildDevicesFound() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _overlayTitle('PROCURANDO SENSORES'),
        const SizedBox(height: 25),
        const _RadarGlow(),
        const SizedBox(height: 25),
        _overlaySubtitle('Escaneando dispositivos Kinexa próximos...'),
        const SizedBox(height: 10),
        _overlaySubtitle(
          '${_devices.length} dispositivo${_devices.length == 1 ? '' : 's'} encontrado${_devices.length == 1 ? '' : 's'}',
          center: true,
        ),
        const SizedBox(height: 10),
        _overlaySubtitle('Escolha o dispositivo a ser conectado', center: true),
        const SizedBox(height: 10),
        ..._devices.map(
          (d) => Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: KinexaDeviceCard(
              device: d,
              selected: _selectedId == d.deviceId,
              onTap: () => _selectDevice(d),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Validation overlay
// ---------------------------------------------------------------------------

enum _ValidationPhase {
  preparing,
  connecting,
  preparationFailed,
  connectionFailed,
  success,
}

enum _StepStatus { pending, inProgress, done, failed }

class _ValidationStep {
  const _ValidationStep(this.label, this.status);
  final String label;
  final _StepStatus status;
}

Future<DeviceModel?> showDeviceValidationOverlay(
  BuildContext context,
  WidgetRef ref,
  DeviceModel device,
) {
  return showKinexaOverlay<DeviceModel>(
    context,
    _DeviceValidationDialog(device: device),
  );
}

class _DeviceValidationDialog extends ConsumerStatefulWidget {
  const _DeviceValidationDialog({required this.device});
  final DeviceModel device;

  @override
  ConsumerState<_DeviceValidationDialog> createState() =>
      _DeviceValidationDialogState();
}

class _DeviceValidationDialogState extends ConsumerState<_DeviceValidationDialog> {
  _ValidationPhase _phase = _ValidationPhase.preparing;
  int _completedSteps = 0;
  int? _failedStepIndex;
  bool? _setAsDefault;
  bool _showDefaultPrompt = true;
  DeviceModel? _validatedDevice;

  static const _stepLabels = [
    'Conexão estabelecida',
    'Serviços BLE encontrados',
    'Firmware compatível',
    'Sensor operacional',
  ];

  @override
  void initState() {
    super.initState();
    _validate();
  }

  List<_ValidationStep> get _steps {
    return List.generate(_stepLabels.length, (i) {
      if (_failedStepIndex != null) {
        if (i < _failedStepIndex!) {
          return _ValidationStep(_stepLabels[i], _StepStatus.done);
        }
        if (i == _failedStepIndex) {
          return _ValidationStep(_stepLabels[i], _StepStatus.failed);
        }
        return _ValidationStep(_stepLabels[i], _StepStatus.pending);
      }
      if (i < _completedSteps) {
        return _ValidationStep(_stepLabels[i], _StepStatus.done);
      }
      if (i == _completedSteps &&
          (_phase == _ValidationPhase.preparing ||
              _phase == _ValidationPhase.connecting)) {
        return _ValidationStep(_stepLabels[i], _StepStatus.inProgress);
      }
      return _ValidationStep(_stepLabels[i], _StepStatus.pending);
    });
  }

  Future<void> _validate() async {
    setState(() {
      _phase = _ValidationPhase.preparing;
      _completedSteps = 0;
      _failedStepIndex = null;
      _validatedDevice = null;
    });

    try {
      final ble = ref.read(bleServiceProvider);
      final reusedSession =
          ble.connectedDevice?.deviceId == widget.device.deviceId;

      if (!reusedSession) {
        await Future.delayed(const Duration(milliseconds: 600));
        if (!mounted) return;

        setState(() => _phase = _ValidationPhase.connecting);
        if (widget.device.mac != null) {
          ble.registerBleConnectionId(widget.device.deviceId, widget.device.mac!);
        }
        final connected = await ble.connect(widget.device.deviceId);
        if (!mounted) return;

        setState(() => _completedSteps = 1);
        await Future.delayed(const Duration(milliseconds: 400));
        await _runValidateSteps(ble, connected);
        return;
      }

      setState(() {
        _phase = _ValidationPhase.connecting;
        _completedSteps = 1;
      });
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;

      await _runValidateSteps(ble, ble.connectedDevice!);
    } on BleException catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _ValidationPhase.connectionFailed;
        _failedStepIndex = _completedSteps.clamp(0, _stepLabels.length - 1);
      });
      ref.read(debugLogProvider).add('BLE validate error: ${e.message}');
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (_completedSteps == 0) {
          _phase = _ValidationPhase.preparationFailed;
          _failedStepIndex = null;
        } else {
          _phase = _ValidationPhase.connectionFailed;
          _failedStepIndex = _completedSteps;
        }
      });
    }
  }

  Future<void> _runValidateSteps(dynamic ble, DeviceModel device) async {
    for (var i = 1; i < 4; i++) {
      if (!mounted) return;
      setState(() => _completedSteps = i + 1);
      await Future.delayed(const Duration(milliseconds: 400));
    }

    final validated = await ble.validate(device);
    if (!mounted) return;

    final askDefault =
        await ref.read(deviceRepositoryProvider).shouldAskDefaultDevice();
    if (!mounted) return;

    setState(() {
      _phase = _ValidationPhase.success;
      _validatedDevice = validated;
      _showDefaultPrompt = askDefault;
      if (_showDefaultPrompt) _setAsDefault ??= true;
    });
  }

  Future<void> _continue() async {
    final device = _validatedDevice;
    if (device == null) return;

    final repo = ref.read(deviceRepositoryProvider);
    if (_showDefaultPrompt && (_setAsDefault ?? true)) {
      await repo.setDefaultDevice(device);
      await repo.markDefaultPromptDismissed();
    }

    if (mounted) Navigator.pop(context, device);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: switch (_phase) {
        _ValidationPhase.preparing => _buildProgress(
            subtitle: 'Preparando conexão com o dispositivo...',
          ),
        _ValidationPhase.connecting => _buildProgress(
            subtitle: 'Conectando ao Dispositivo...',
          ),
        _ValidationPhase.preparationFailed => _buildFailure(
            subtitle: 'Erro na preparação',
            allPending: true,
          ),
        _ValidationPhase.connectionFailed => _buildFailure(
            subtitle: 'Erro na conexão',
          ),
        _ValidationPhase.success => _buildSuccess(),
      },
    );
  }

  Widget _buildProgress({required String subtitle}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _overlayTitle('VALIDANDO DISPOSITIVO'),
        const SizedBox(height: 25),
        _overlaySubtitle(subtitle),
        const SizedBox(height: 25),
        const _ProgressRing(),
        const SizedBox(height: 25),
        KinexaDeviceCard(device: widget.device),
        const SizedBox(height: 25),
        _ValidationStepsList(steps: _steps),
        const SizedBox(height: 25),
        _secondaryPillButton('AGUARDANDO...', enabled: false),
        const SizedBox(height: 10),
        _debugLink(ref),
      ],
    );
  }

  Widget _buildFailure({
    required String subtitle,
    bool allPending = false,
  }) {
    final steps = allPending
        ? _stepLabels
            .map((l) => _ValidationStep(l, _StepStatus.pending))
            .toList()
        : _steps;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _overlayTitle('VALIDANDO DISPOSITIVO'),
        const SizedBox(height: 30),
        _overlaySubtitle(subtitle),
        const SizedBox(height: 10),
        const _BigStatusIcon(success: false),
        const SizedBox(height: 10),
        KinexaDeviceCard(device: widget.device, error: true),
        const SizedBox(height: 30),
        _ValidationStepsList(steps: steps),
        const SizedBox(height: 30),
        _secondaryPillButton('TENTAR NOVAMENTE', onPressed: _validate),
        const SizedBox(height: 10),
        _debugLink(ref),
      ],
    );
  }

  Widget _buildSuccess() {
    final device = _validatedDevice ?? widget.device;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _overlayTitle('VALIDANDO DISPOSITIVO'),
        const SizedBox(height: 25),
        _overlaySubtitle('Dispositivo Conectado!'),
        const SizedBox(height: 10),
        const _BigStatusIcon(success: true),
        const SizedBox(height: 10),
        KinexaDeviceCard(device: device, success: true),
        const SizedBox(height: 25),
        _ValidationStepsList(
          steps: _stepLabels
              .map((l) => _ValidationStep(l, _StepStatus.done))
              .toList(),
        ),
        const SizedBox(height: 25),
        if (_showDefaultPrompt) ...[
          _DefaultDevicePrompt(
            setAsDefault: _setAsDefault ?? true,
            onChanged: (v) => setState(() => _setAsDefault = v),
          ),
          const SizedBox(height: 25),
        ],
        KinexaButton.primary(label: 'CONTINUAR', onPressed: _continue),
        const SizedBox(height: 10),
        _debugLink(ref),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared overlay widgets
// ---------------------------------------------------------------------------

Widget _overlayTitle(String text) {
  return Text(
    text,
    textAlign: TextAlign.center,
    style: AppTextStyles.title.copyWith(letterSpacing: 0),
  );
}

Widget _overlaySubtitle(String text, {bool center = false}) {
  return Text(
    text,
    textAlign: center ? TextAlign.center : TextAlign.start,
    style: AppTextStyles.mono(size: 12, letterSpacing: 0),
  );
}

Widget _secondaryPillButton(
  String label, {
  VoidCallback? onPressed,
  bool enabled = true,
}) {
  return Material(
    color: AppColors.cardBackground.withValues(alpha: enabled ? 1 : 0.5),
    borderRadius: BorderRadius.circular(97),
    child: InkWell(
      onTap: enabled ? onPressed : null,
      borderRadius: BorderRadius.circular(97),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Center(
          child: Text(
            label,
            style: AppTextStyles.mono(
              size: 14,
              weight: enabled ? FontWeight.w700 : FontWeight.w400,
              letterSpacing: 0,
            ),
          ),
        ),
      ),
    ),
  );
}

Widget _debugLink(WidgetRef ref) {
  return Builder(
    builder: (context) => GestureDetector(
      onTap: () => showDebugBottomSheet(context, ref),
      child: Text(
        'Ver detalhes técnicos',
        style: AppTextStyles.mono(
          size: 14,
          color: const Color(0xFFAAAAAA),
          letterSpacing: 0,
        ),
      ),
    ),
  );
}

class _RadarGlow extends StatelessWidget {
  const _RadarGlow();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: AppColors.redPrimary.withValues(alpha: 0.36),
            blurRadius: 27.75,
          ),
        ],
        shape: BoxShape.circle,
      ),
      child: const KinexaRadar(),
    );
  }
}

class _ProgressRing extends StatefulWidget {
  const _ProgressRing();

  @override
  State<_ProgressRing> createState() => _ProgressRingState();
}

class _ProgressRingState extends State<_ProgressRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 102,
      height: 102,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, child) {
          return CustomPaint(
            painter: _RingPainter(progress: _controller.value),
            child: child,
          );
        },
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 6;
    const stroke = 8.0;

    final track = Paint()
      ..color = AppColors.redDark.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    final arc = Paint()
      ..color = AppColors.redPrimary
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, track);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -1.2 + progress * 6.28,
      2.2,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _BigStatusIcon extends StatelessWidget {
  const _BigStatusIcon({required this.success});

  final bool success;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 102,
      child: Center(
        child: Text(
          success ? '✓' : '✗',
          style: AppTextStyles.mono(
            size: 64,
            color: success ? AppColors.text : AppColors.redPrimary,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class _ValidationStepsList extends StatelessWidget {
  const _ValidationStepsList({required this.steps});

  final List<_ValidationStep> steps;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: steps.map(_buildRow).toList(),
    );
  }

  Widget _buildRow(_ValidationStep step) {
    final prefix = switch (step.status) {
      _StepStatus.done => '✓ ',
      _StepStatus.failed => '✗ ',
      _StepStatus.inProgress => '⟳ ',
      _StepStatus.pending => '☐ ',
    };

    final color = step.status == _StepStatus.failed
        ? AppColors.digitalAccent
        : AppColors.text;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        '$prefix${step.label}',
        style: AppTextStyles.mono(size: 12, color: color, letterSpacing: 0),
      ),
    );
  }
}

class _DefaultDevicePrompt extends StatelessWidget {
  const _DefaultDevicePrompt({
    required this.setAsDefault,
    required this.onChanged,
  });

  final bool setAsDefault;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Text(
            'Registrar dispositivo como padrão?',
            textAlign: TextAlign.center,
            style: AppTextStyles.mono(size: 12, letterSpacing: 0),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => onChanged(true),
            child: Text(
              'SIM',
              style: AppTextStyles.mono(
                size: 12,
                color: setAsDefault
                    ? const Color(0xFF27C840)
                    : AppColors.text,
                letterSpacing: 0,
                weight: setAsDefault ? FontWeight.w700 : FontWeight.w400,
              ).copyWith(
                shadows: setAsDefault
                    ? [
                        const Shadow(
                          color: Color(0xFF27C840),
                          blurRadius: 4,
                        ),
                      ]
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => onChanged(false),
            child: Text(
              'NÃO, perguntar sempre.',
              style: AppTextStyles.mono(
                size: 12,
                color: !setAsDefault
                    ? AppColors.digitalAccent
                    : AppColors.text,
                letterSpacing: 0,
                weight: !setAsDefault ? FontWeight.w700 : FontWeight.w400,
              ).copyWith(
                shadows: !setAsDefault
                    ? [
                        Shadow(
                          color: AppColors.digitalAccent.withValues(alpha: 0.8),
                          blurRadius: 4,
                        ),
                      ]
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
