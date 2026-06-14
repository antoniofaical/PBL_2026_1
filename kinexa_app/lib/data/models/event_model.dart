import '../../core/constants/enums.dart';

class EventModel {
  EventModel({
    this.id,
    this.runId,
    required this.timestampMs,
    this.description,
  });

  final int? id;
  final String? runId;
  final int timestampMs;
  final String? description;

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'run_id': runId,
        'timestamp_ms': timestampMs,
        'description': description,
      };

  Map<String, dynamic> toUploadJson() => {
        'timestamp_ms': timestampMs,
        if (description != null && description!.isNotEmpty) 'description': description,
      };

  factory EventModel.fromMap(Map<String, dynamic> map) => EventModel(
        id: map['id'] as int?,
        runId: map['run_id'] as String?,
        timestampMs: map['timestamp_ms'] as int,
        description: map['description'] as String?,
      );

  factory EventModel.fromApiJson(Map<String, dynamic> json) => EventModel(
        id: json['id'] as int?,
        timestampMs: json['timestamp_ms'] as int,
        description: json['description'] as String?,
      );

  EventModel copyWith({
    int? id,
    String? runId,
    int? timestampMs,
    String? description,
  }) =>
      EventModel(
        id: id ?? this.id,
        runId: runId ?? this.runId,
        timestampMs: timestampMs ?? this.timestampMs,
        description: description ?? this.description,
      );
}
