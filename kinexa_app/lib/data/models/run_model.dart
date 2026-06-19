import '../../core/constants/enums.dart';
import 'event_model.dart';
import 'run_calibration_model.dart';

class RunModel {
  RunModel({
    required this.runId,
    required this.deviceId,
    required this.datetime,
    required this.athlete,
    required this.activity,
    required this.environment,
    this.notes,
    this.csvPath,
    this.csvContent,
    this.sampleCount,
    this.createdAt,
    this.syncStatus = SyncStatus.localOnly,
    this.events = const [],
    this.calibration,
  });

  final String runId;
  final String deviceId;
  final String datetime;
  final String athlete;
  final int activity;
  final int environment;
  final String? notes;
  final String? csvPath;
  final String? csvContent;
  final int? sampleCount;
  final String? createdAt;
  final SyncStatus syncStatus;
  final List<EventModel> events;
  final RunCalibrationModel? calibration;

  RunCalibrationModel? get effectiveCalibration =>
      calibration ?? RunCalibrationModel.tryFromCsv(csvContent);

  Map<String, dynamic> toMap() => {
        'run_id': runId,
        'device_id': deviceId,
        'datetime': datetime,
        'athlete': athlete,
        'activity': activity,
        'environment': environment,
        'notes': notes,
        'csv_path': csvPath,
        'csv_content': csvContent,
        'sample_count': sampleCount,
        'created_at': createdAt,
        'sync_status': syncStatus.key,
      };

  Map<String, dynamic> toUploadJson() {
    final calib = effectiveCalibration;
    return {
      'run_id': runId,
      'device_id': deviceId,
      'datetime': datetime,
      'athlete': athlete,
      'activity': activity,
      'environment': environment,
      if (notes != null && notes!.isNotEmpty) 'notes': notes,
      'events': events.map((e) => e.toUploadJson()).toList(),
      'csv': csvContent ?? '',
      if (calib != null) 'calibration': calib.toUploadJson(),
    };
  }

  factory RunModel.fromMap(Map<String, dynamic> map, {List<EventModel>? events}) =>
      RunModel(
        runId: map['run_id'] as String,
        deviceId: map['device_id'] as String,
        datetime: map['datetime'] as String,
        athlete: map['athlete'] as String,
        activity: map['activity'] as int,
        environment: map['environment'] as int,
        notes: map['notes'] as String?,
        csvPath: map['csv_path'] as String?,
        csvContent: map['csv_content'] as String?,
        sampleCount: map['sample_count'] as int?,
        createdAt: map['created_at'] as String?,
        syncStatus: SyncStatus.fromKey(map['sync_status'] as String?),
        events: events ?? const [],
      );

  factory RunModel.fromApiJson(Map<String, dynamic> json, {String? csvContent}) {
    final eventsJson = json['events'] as List<dynamic>? ?? [];
    return RunModel(
      runId: json['run_id'] as String,
      deviceId: json['device_id'] as String,
      datetime: json['datetime'] as String,
      athlete: json['athlete'] as String,
      activity: (json['activity'] as num).toInt(),
      environment: (json['environment'] as num).toInt(),
      notes: json['notes'] as String?,
      csvPath: json['csv_path'] as String?,
      csvContent: csvContent,
      sampleCount: json['sample_count'] == null
          ? null
          : (json['sample_count'] as num).toInt(),
      createdAt: json['created_at']?.toString(),
      syncStatus: SyncStatus.synced,
      calibration: RunCalibrationModel.tryFromApiJson(json),
      events: eventsJson
          .map((e) {
            final map = e is Map<String, dynamic>
                ? e
                : Map<String, dynamic>.from(e as Map);
            return EventModel.fromApiJson(map);
          })
          .toList(),
    );
  }

  RunModel copyWith({
    String? runId,
    String? deviceId,
    String? datetime,
    String? athlete,
    int? activity,
    int? environment,
    String? notes,
    String? csvPath,
    String? csvContent,
    bool clearCsvContent = false,
    int? sampleCount,
    String? createdAt,
    SyncStatus? syncStatus,
    List<EventModel>? events,
    RunCalibrationModel? calibration,
  }) =>
      RunModel(
        runId: runId ?? this.runId,
        deviceId: deviceId ?? this.deviceId,
        datetime: datetime ?? this.datetime,
        athlete: athlete ?? this.athlete,
        activity: activity ?? this.activity,
        environment: environment ?? this.environment,
        notes: notes ?? this.notes,
        csvPath: csvPath ?? this.csvPath,
        csvContent: clearCsvContent ? null : (csvContent ?? this.csvContent),
        sampleCount: sampleCount ?? this.sampleCount,
        createdAt: createdAt ?? this.createdAt,
        syncStatus: syncStatus ?? this.syncStatus,
        events: events ?? this.events,
        calibration: calibration ?? this.calibration,
      );
}
