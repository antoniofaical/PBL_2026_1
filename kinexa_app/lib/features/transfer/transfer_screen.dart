import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/enums.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/kinexa_button.dart';
import '../../core/widgets/kinexa_logo.dart';
import '../../core/widgets/kinexa_scaffold.dart';
import '../../core/widgets/kinexa_scroll_reveal.dart';
import '../../data/models/device_model.dart';
import '../../data/models/run_model.dart';
import '../../overlays/debug_bottom_sheet.dart';
import '../../providers.dart';
import '../../services/ble/ble_constants.dart';
import '../../services/ble/ble_exception.dart';
import '../../services/ble/ble_run_payload.dart';
import 'transfer_models.dart';
import 'widgets/transfer_ui.dart';

class TransferScreen extends ConsumerStatefulWidget {
  const TransferScreen({super.key});

  @override
  ConsumerState<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends ConsumerState<TransferScreen> {
  static var _globalTransferRunning = false;

  TransferPhase _phase = TransferPhase.receivingBle;
  TransferOutcome _outcome = TransferOutcome.inProgress;
  bool _serverOnline = false;
  bool _includeServerSteps = false;

  int _percent = 0;
  int _samplesDone = 0;
  int _samplesTotal = 0;
  int _packetsDone = 0;
  int _packetsTotal = 0;

  MockDownloadResult? _download;
  RunModel? _savedRun;
  String? _errorMessage;

  Timer? _progressTimer;
  var _bleStopAlreadySent = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runTransfer());
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    super.dispose();
  }

  Future<void> _runTransfer({
    bool retryUploadOnly = false,
    bool retryBleOnly = false,
  }) async {
    if (_globalTransferRunning) return;
    _globalTransferRunning = true;

    try {
      await _runTransferInternal(
        retryUploadOnly: retryUploadOnly,
        retryBleOnly: retryBleOnly,
      );
    } finally {
      _globalTransferRunning = false;
    }
  }

  Future<void> _runTransferInternal({
    bool retryUploadOnly = false,
    bool retryBleOnly = false,
  }) async {
    final session = ref.read(collectionSessionProvider);
    final ble = ref.read(bleServiceProvider);
    final runRepo = ref.read(runRepositoryProvider);
    final syncRepo = ref.read(syncRepositoryProvider);

    if (!retryUploadOnly && !retryBleOnly) {
      _download = null;
      _savedRun = null;
      _bleStopAlreadySent = false;
    }

    setState(() {
      _outcome = TransferOutcome.inProgress;
      _errorMessage = null;
      _percent = retryUploadOnly ? 100 : 0;
      _samplesDone = retryUploadOnly ? _samplesTotal : 0;
      _packetsDone = retryUploadOnly ? _packetsTotal : 0;
    });

    try {
      if (!retryUploadOnly) {
        _serverOnline = !ref.read(offlineModeProvider) &&
            await syncRepo.isServerOnline();
        ref.read(serverOnlineProvider.notifier).state = _serverOnline;
        _includeServerSteps = _serverOnline;

        await _receiveBle(ble, retryOnly: retryBleOnly);
        await _verifyDownload();
        _savedRun = await _saveLocal(session, runRepo);
      } else if (_savedRun == null) {
        throw StateError('Nenhuma coleta salva para reenviar');
      }

      var run = _savedRun!;

      if (_serverOnline) {
        final uploadOk = await _syncToServer(runRepo, run);
        run = (await runRepo.getRun(run.runId)) ?? run;
        if (!uploadOk) {
          await _completeWithSyncFailure(run);
          return;
        }
      }

      await _finish(
        run: run,
        uploadOk: _serverOnline,
        uploadAttempted: _serverOnline,
      );
    } on _TransferFailure catch (failure) {
      setState(() {
        _outcome = failure.outcome;
        _errorMessage = _formatTransferError(failure);
      });
    } catch (e) {
      setState(() {
        _outcome = TransferOutcome.bleFailed;
        _phase = TransferPhase.receivingBle;
        _errorMessage = e.toString();
      });
    }
  }

  String _formatTransferError(_TransferFailure failure) {
    final cause = failure.cause;
    if (cause is BleException) {
      return '${failure.message}\n${cause.message}';
    }
    if (cause != null) {
      return '${failure.message}\n$cause';
    }
    return failure.message;
  }

  Future<void> _receiveBle(dynamic ble, {bool retryOnly = false}) async {
    setState(() {
      _phase = TransferPhase.receivingBle;
      if (!retryOnly) {
        _samplesTotal = 0;
        _packetsTotal = 0;
      }
      _samplesDone = 0;
      _packetsDone = 0;
      _percent = 0;
    });

    _progressTimer?.cancel();

    try {
      final onProgress = ({
        required int bytesReceived,
        int? bytesTotal,
        required int packetCount,
      }) {
        if (!mounted) return;
        final total = bytesTotal ?? 0;
        final packetsTotal = total > 0
            ? (total / KinexaBleConfig.xferChunkSize).ceil()
            : _packetsTotal;
        final payloadBytes = bytesReceived > KinexaRunPayloadParser.calibSize
            ? bytesReceived - KinexaRunPayloadParser.calibSize
            : 0;
        final samplesTotal = total > 0
            ? (total - KinexaRunPayloadParser.calibSize) ~/
                KinexaRunPayloadParser.sampleSize
            : _samplesTotal;
        final samplesDone = payloadBytes ~/ KinexaRunPayloadParser.sampleSize;
        final percent = total > 0
            ? ((bytesReceived * 100) / total).round().clamp(0, 99)
            : _percent;

        setState(() {
          if (packetsTotal > 0) _packetsTotal = packetsTotal;
          _packetsDone = packetCount;
          if (samplesTotal > 0) _samplesTotal = samplesTotal;
          _samplesDone = samplesDone;
          _percent = percent;
        });
      };

      if (retryOnly) {
        _download = await ble.retryDownload(onProgress: onProgress);
      } else {
        _download = await ble.stopAndDownload(onProgress: onProgress);
        _bleStopAlreadySent = true;
      }
    } catch (e) {
      throw _TransferFailure(
        outcome: TransferOutcome.bleFailed,
        message: 'Falha ao receber dados do sensor via Bluetooth.',
        cause: e,
      );
    } finally {
      _progressTimer?.cancel();
    }

    final download = _download!;
    setState(() {
      _samplesTotal = download.sampleCount;
      _packetsTotal = download.packetCount;
      _samplesDone = download.sampleCount;
      _packetsDone = download.packetCount;
      _percent = 100;
    });
  }

  Future<void> _verifyDownload() async {
    setState(() => _phase = TransferPhase.verifying);
    await Future.delayed(const Duration(milliseconds: 450));

    final download = _download;
    if (download == null ||
        download.csvContent.trim().isEmpty ||
        download.sampleCount <= 0) {
      throw _TransferFailure(
        outcome: TransferOutcome.bleFailed,
        message: 'Os dados recebidos estão vazios ou corrompidos.',
      );
    }
  }

  Future<RunModel> _saveLocal(CollectionSession session, dynamic runRepo) async {
    setState(() => _phase = TransferPhase.savingLocal);

    final download = _download!;
    final runId = 'run_${const Uuid().v4().split('-').first}';
    final now = DateTime.now().toIso8601String();
    final run = RunModel(
      runId: runId,
      deviceId: session.device?.deviceId ?? 'UNKNOWN',
      datetime: now,
      athlete: session.athlete,
      activity: session.activity,
      environment: session.environment,
      notes: session.notes.isEmpty ? null : session.notes,
      csvContent: download.csvContent,
      sampleCount: download.sampleCount,
      createdAt: now,
      syncStatus: SyncStatus.localOnly,
      events: session.events.map((e) => e.copyWith(runId: runId)).toList(),
      calibration: download.calibration,
    );

    try {
      await runRepo.saveLocal(run);
      return run;
    } catch (e) {
      throw _TransferFailure(
        outcome: TransferOutcome.localSaveFailed,
        message: 'Não foi possível salvar a coleta no armazenamento local.',
        cause: e,
      );
    }
  }

  Future<bool> _syncToServer(dynamic runRepo, RunModel run) async {
    setState(() => _phase = TransferPhase.syncingServer);
    await Future.delayed(const Duration(milliseconds: 350));

    final uploadOk = await runRepo.uploadRun(run);

    setState(() => _phase = TransferPhase.updatingDb);
    await Future.delayed(const Duration(milliseconds: 300));

    return uploadOk;
  }

  Future<void> _completeWithSyncFailure(RunModel run) async {
    setState(() {
      _phase = TransferPhase.finishing;
      _outcome = TransferOutcome.syncFailed;
      _errorMessage =
          'A coleta foi salva no celular, mas o envio ao servidor falhou.';
      _percent = 100;
      _samplesDone = _samplesTotal;
      _packetsDone = _packetsTotal;
    });

    ref.read(transferResultProvider.notifier).state = TransferResult(
      run: run,
      uploadSuccess: false,
    );
    bumpHomeRefresh(ref);
  }

  Future<void> _finish({
    required RunModel run,
    required bool uploadOk,
    required bool uploadAttempted,
  }) async {
    setState(() {
      _phase = TransferPhase.finishing;
      _outcome = uploadOk
          ? TransferOutcome.successSynced
          : uploadAttempted
              ? TransferOutcome.syncFailed
              : TransferOutcome.successPending;
      _percent = 100;
      _samplesDone = _samplesTotal;
      _packetsDone = _packetsTotal;
    });

    ref.read(transferResultProvider.notifier).state = TransferResult(
      run: run,
      uploadSuccess: uploadOk,
    );
    bumpHomeRefresh(ref);

    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;

    ref.read(collectionSessionProvider.notifier).reset();
    context.go('/home');
  }

  bool get _isInProgress => _outcome == TransferOutcome.inProgress;

  bool get _isError =>
      _outcome == TransferOutcome.bleFailed ||
      _outcome == TransferOutcome.localSaveFailed;

  String get _title => switch (_outcome) {
        TransferOutcome.inProgress => switch (_phase) {
            TransferPhase.syncingServer || TransferPhase.updatingDb =>
              'SINCRONIZANDO DADOS',
            _ => 'RECEBENDO DADOS',
          },
        TransferOutcome.successSynced => 'DADOS SALVOS COM SUCESSO',
        TransferOutcome.successPending => 'DADOS SALVOS (SYNC PENDENTE)',
        TransferOutcome.syncFailed => 'DADOS SALVOS (SYNC PENDENTE)',
        TransferOutcome.bleFailed => 'FALHA AO RECEBER DADOS',
        TransferOutcome.localSaveFailed => 'FALHA AO SALVAR NO CELULAR',
      };

  TransferProgressTone get _tone {
    if (_isInProgress) return TransferProgressTone.active;
    return switch (_outcome) {
      TransferOutcome.successSynced => TransferProgressTone.success,
      TransferOutcome.successPending => TransferProgressTone.warning,
      TransferOutcome.syncFailed => TransferProgressTone.warning,
      TransferOutcome.bleFailed || TransferOutcome.localSaveFailed =>
        TransferProgressTone.error,
      TransferOutcome.inProgress => TransferProgressTone.active,
    };
  }

  TransferFlowLayout get _flowLayout {
    if (_isError && _outcome == TransferOutcome.bleFailed) {
      return TransferFlowLayout.deviceToPhone;
    }
    if (_isInProgress &&
        (_phase == TransferPhase.syncingServer ||
            _phase == TransferPhase.updatingDb)) {
      return TransferFlowLayout.phoneToServer;
    }
    if (_outcome == TransferOutcome.successSynced) {
      return TransferFlowLayout.deviceToServerComplete;
    }
    if (_outcome == TransferOutcome.successPending ||
        _outcome == TransferOutcome.syncFailed ||
        _outcome == TransferOutcome.localSaveFailed) {
      return TransferFlowLayout.deviceToPhoneComplete;
    }
    return TransferFlowLayout.deviceToPhone;
  }

  TransferFlowMidIcon get _midIcon {
    if (_isError) return TransferFlowMidIcon.error;
    if (_flowLayout == TransferFlowLayout.deviceToPhoneComplete ||
        _flowLayout == TransferFlowLayout.deviceToServerComplete) {
      return TransferFlowMidIcon.check;
    }
    return TransferFlowMidIcon.bluetooth;
  }

  List<TransferChecklistItem> get _checklist {
    TransferChecklistState stateFor(TransferChecklistId id) {
      if (_outcome == TransferOutcome.bleFailed) {
        return switch (id) {
          TransferChecklistId.collectionEnded => TransferChecklistState.done,
          TransferChecklistId.receivingData => TransferChecklistState.failed,
          _ => TransferChecklistState.pending,
        };
      }

      if (_outcome == TransferOutcome.localSaveFailed) {
        return switch (id) {
          TransferChecklistId.collectionEnded ||
          TransferChecklistId.receivingData ||
          TransferChecklistId.verifying =>
            TransferChecklistState.done,
          TransferChecklistId.savingLocal => TransferChecklistState.failed,
          _ => TransferChecklistState.pending,
        };
      }

      if (_outcome == TransferOutcome.syncFailed) {
        return switch (id) {
          TransferChecklistId.collectionEnded ||
          TransferChecklistId.receivingData ||
          TransferChecklistId.verifying ||
          TransferChecklistId.savingLocal =>
            TransferChecklistState.done,
          TransferChecklistId.uploadingServer ||
          TransferChecklistId.updatingDb =>
            TransferChecklistState.failed,
        };
      }

      if (!_isInProgress) {
        return TransferChecklistState.done;
      }

      int order(TransferChecklistId id) => switch (id) {
            TransferChecklistId.collectionEnded => 0,
            TransferChecklistId.receivingData => 1,
            TransferChecklistId.verifying => 2,
            TransferChecklistId.savingLocal => 3,
            TransferChecklistId.uploadingServer => 4,
            TransferChecklistId.updatingDb => 5,
          };

      final current = switch (_phase) {
        TransferPhase.receivingBle => TransferChecklistId.receivingData,
        TransferPhase.verifying => TransferChecklistId.verifying,
        TransferPhase.savingLocal => TransferChecklistId.savingLocal,
        TransferPhase.syncingServer => TransferChecklistId.uploadingServer,
        TransferPhase.updatingDb => TransferChecklistId.updatingDb,
        TransferPhase.finishing => TransferChecklistId.updatingDb,
      };

      final currentOrder = order(current);
      final itemOrder = order(id);

      if (id == TransferChecklistId.collectionEnded) {
        return TransferChecklistState.done;
      }
      if (itemOrder < currentOrder) return TransferChecklistState.done;
      if (itemOrder == currentOrder) return TransferChecklistState.active;
      return TransferChecklistState.pending;
    }

    final items = <TransferChecklistItem>[
      TransferChecklistItem(
        id: TransferChecklistId.collectionEnded,
        label: 'Coleta encerrada',
        state: stateFor(TransferChecklistId.collectionEnded),
      ),
      TransferChecklistItem(
        id: TransferChecklistId.receivingData,
        label: 'Recebendo dados',
        state: stateFor(TransferChecklistId.receivingData),
      ),
      TransferChecklistItem(
        id: TransferChecklistId.verifying,
        label: 'Verificando integridade',
        state: stateFor(TransferChecklistId.verifying),
      ),
      TransferChecklistItem(
        id: TransferChecklistId.savingLocal,
        label: 'Salvando no celular',
        state: stateFor(TransferChecklistId.savingLocal),
      ),
    ];

    if (_includeServerSteps) {
      items.addAll([
        TransferChecklistItem(
          id: TransferChecklistId.uploadingServer,
          label: 'Enviando para servidor',
          state: stateFor(TransferChecklistId.uploadingServer),
        ),
        TransferChecklistItem(
          id: TransferChecklistId.updatingDb,
          label: 'Atualizando banco local',
          state: stateFor(TransferChecklistId.updatingDb),
        ),
      ]);
    }

    return items;
  }

  List<Widget> _buildFooterActions() {
    if (_isError) {
      return [
        if (_errorMessage != null) TransferErrorBanner(message: _errorMessage!),
        const SizedBox(height: 10),
        KinexaButton.primary(
          label: 'Tentar novamente',
          onPressed: _isInProgress
              ? null
              : () => _runTransfer(
                    retryUploadOnly: false,
                    retryBleOnly:
                        _outcome == TransferOutcome.bleFailed && _bleStopAlreadySent,
                  ),
        ),
        const SizedBox(height: 10),
        KinexaButton.secondary(
          label: 'Voltar ao início',
          onPressed: _goHome,
        ),
      ];
    }

    if (_outcome == TransferOutcome.syncFailed) {
      return [
        TransferFinishPill(tone: _tone),
        const SizedBox(height: 10),
        if (_errorMessage != null) TransferErrorBanner(message: _errorMessage!),
        const SizedBox(height: 10),
        KinexaButton.primary(
          label: 'Tentar sincronizar',
          onPressed: () => _runTransfer(retryUploadOnly: true),
        ),
        const SizedBox(height: 10),
        KinexaButton.secondary(
          label: 'Voltar ao início',
          onPressed: _goHome,
        ),
      ];
    }

    if (_outcome == TransferOutcome.successPending) {
      return [
        TransferFinishPill(tone: _tone),
        const SizedBox(height: 10),
        KinexaButton.secondary(
          label: 'Voltar ao início',
          onPressed: _goHome,
        ),
      ];
    }

    if (_outcome == TransferOutcome.successSynced &&
        _phase == TransferPhase.finishing) {
      return [TransferFinishPill(tone: _tone)];
    }

    if (_isInProgress) {
      return [const TransferWarningBanner()];
    }

    return const [];
  }

  void _goHome() {
    ref.read(collectionSessionProvider.notifier).reset();
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(collectionSessionProvider);
    final online = ref.watch(serverOnlineProvider);
    final offlineMode = ref.watch(offlineModeProvider);
    final isOnline = online && !offlineMode;
    final deviceId = session.device?.deviceId ?? 'KINEXA_01';

    return KinexaScaffold(
      backgroundColor: AppColors.popupBackground,
      body: Column(
        children: [
          _TransferHeader(isOnline: isOnline),
          Expanded(
            child: KinexaScrollReveal(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TransferScreenTitle(title: _title),
                  const SizedBox(height: 16),
                  TransferFlowDiagram(
                    layout: _flowLayout,
                    leftLabel: deviceId,
                    midIcon: _midIcon,
                    tone: _tone,
                  ),
                  const SizedBox(height: 16),
                  TransferProgressPanel(
                    percent: _percent,
                    samplesDone: _samplesDone,
                    samplesTotal: _samplesTotal,
                    packetsDone: _packetsDone,
                    packetsTotal: _packetsTotal,
                    tone: _tone,
                  ),
                  const SizedBox(height: 16),
                  TransferChecklist(items: _checklist),
                  const SizedBox(height: 12),
                  ..._buildFooterActions(),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => showDebugBottomSheet(context, ref),
                    child: Text(
                      'Ver detalhes técnicos',
                      style: AppTextStyles.mono(
                        size: 14,
                        color: const Color(0xFFAAAAAA),
                        letterSpacing: 0,
                      ),
                      textAlign: TextAlign.center,
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

class _TransferHeader extends StatelessWidget {
  const _TransferHeader({required this.isOnline});

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
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isOnline ? AppColors.success : AppColors.textMuted,
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
          ],
        ),
      ),
    );
  }
}

class _TransferFailure implements Exception {
  _TransferFailure({
    required this.outcome,
    required this.message,
    this.cause,
  });

  final TransferOutcome outcome;
  final String message;
  final Object? cause;
}
