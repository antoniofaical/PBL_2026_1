enum Activity {
  marcha(1, 'Marcha'),
  corrida(2, 'Corrida'),
  saltoVertical(3, 'Salto Vertical'),
  saltoDistancia(4, 'Salto em Distância');

  const Activity(this.value, this.label);
  final int value;
  final String label;

  static Activity fromValue(int v) =>
      Activity.values.firstWhere((e) => e.value == v, orElse: () => Activity.corrida);
}

enum Environment {
  esteira(1, 'Esteira'),
  pistaExterna(2, 'Pista Externa');

  const Environment(this.value, this.label);
  final int value;
  final String label;

  static Environment fromValue(int v) =>
      Environment.values.firstWhere((e) => e.value == v, orElse: () => Environment.esteira);
}

enum SyncStatus {
  localOnly('localOnly', 'PENDENTE'),
  syncing('syncing', 'SINCRONIZANDO'),
  synced('synced', 'SINCRONIZADO'),
  syncFailed('syncFailed', 'FALHA');

  const SyncStatus(this.key, this.label);
  final String key;
  final String label;

  static SyncStatus fromKey(String? key) => SyncStatus.values.firstWhere(
        (e) => e.key == key,
        orElse: () => SyncStatus.localOnly,
      );
}

enum DeviceState {
  disconnected,
  scanning,
  connecting,
  needsCalibration,
  calibrating,
  ready,
  recording,
  transferring,
  error,
}

enum TransferStep {
  receivingBle,
  verifying,
  savingLocal,
  uploadingServer,
  updatingDb,
  done,
}
