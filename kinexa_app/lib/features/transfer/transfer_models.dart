enum TransferPhase {
  receivingBle,
  verifying,
  savingLocal,
  syncingServer,
  updatingDb,
  finishing,
}

enum TransferOutcome {
  inProgress,
  successSynced,
  successPending,
  syncFailed,
  bleFailed,
  localSaveFailed,
}

enum TransferChecklistId {
  collectionEnded,
  receivingData,
  verifying,
  savingLocal,
  uploadingServer,
  updatingDb,
}

enum TransferChecklistState {
  pending,
  active,
  done,
  failed,
}

class TransferChecklistItem {
  const TransferChecklistItem({
    required this.id,
    required this.label,
    required this.state,
  });

  final TransferChecklistId id;
  final String label;
  final TransferChecklistState state;
}

enum TransferFlowLayout {
  deviceToPhone,
  phoneToServer,
  deviceToPhoneComplete,
  deviceToServerComplete,
}

enum TransferProgressTone {
  active,
  success,
  warning,
  error,
}
