import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/constants/api_constants.dart';
import '../models/run_model.dart';
import 'api_service.dart';

class HttpApiService implements ApiService {
  HttpApiService({required Dio dio}) : _dio = dio {
    if (kDebugMode) {
      debugPrint('[Kinexa API] baseUrl: ${ApiConstants.baseUrl}');
    }
  }

  final Dio _dio;

  List<dynamic>? _jsonList(dynamic data) {
    if (data is List) return data;
    if (data is String && data.isNotEmpty) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is List) return decoded;
      } catch (_) {}
    }
    return null;
  }

  Map<String, dynamic>? _jsonMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String && data.isNotEmpty) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return null;
  }

  @override
  /// Servidor saudável = HTTP 200 e corpo `{"status":"ok"}`.
  Future<bool> healthCheck() async {
    if (kDebugMode) {
      debugPrint('[Kinexa API] GET ${ApiConstants.health} — início');
    }
    try {
      final res = await _dio.get<dynamic>(
        ApiConstants.health,
        options: Options(responseType: ResponseType.json),
      );
      if (kDebugMode) {
        debugPrint(
          '[Kinexa API] GET ${ApiConstants.health} — fim '
          '(statusCode=${res.statusCode}, dataType=${res.data.runtimeType})',
        );
      }
      if (res.statusCode != 200) {
        if (kDebugMode) {
          debugPrint(
            '[Kinexa API] health rejeitado: status ${res.statusCode} '
            '(esperado 200 com status=ok)',
          );
        }
        return false;
      }

      final body = _jsonMap(res.data);
      if (body?['status'] == 'ok') return true;

      if (kDebugMode) {
        debugPrint('[Kinexa API] health rejeitado: body inválido ${res.data}');
      }
      return false;
    } on DioException catch (e) {
      _logDioError('GET ${ApiConstants.health}', e);
      return false;
    }
  }

  @override
  Future<List<RunModel>> fetchRuns({int? limit, int skip = 0}) async {
    final query = <String, dynamic>{};
    if (limit != null) query['limit'] = limit;
    if (skip > 0) query['skip'] = skip;
    final res = await _dio.get<dynamic>(
      ApiConstants.runs,
      queryParameters: query.isEmpty ? null : query,
      options: Options(responseType: ResponseType.json),
    );
    final list = _jsonList(res.data);
    if (list == null) {
      throw DioException(
        requestOptions: res.requestOptions,
        response: res,
        type: DioExceptionType.badResponse,
        message: 'Lista de runs inválida: ${res.data.runtimeType}',
      );
    }
    final runs = <RunModel>[];
    for (final item in list) {
      final map = item is Map<String, dynamic>
          ? item
          : item is Map
              ? Map<String, dynamic>.from(item)
              : null;
      if (map == null) continue;
      try {
        runs.add(RunModel.fromApiJson(map));
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[Kinexa API] run ignorada (parse): $e — $map');
        }
      }
    }
    return runs;
  }

  @override
  Future<Map<String, dynamic>> uploadRun(RunModel run) async {
    if (kDebugMode) {
      debugPrint(
        '[Kinexa API] POST ${ApiConstants.upload} — início '
        '(run_id=${run.runId}, sampleCount=${run.sampleCount})',
      );
    }
    try {
      final res = await _dio.post(
        ApiConstants.upload,
        data: run.toUploadJson(),
        options: Options(
          headers: {'Content-Type': 'application/json'},
        ),
      );
      if (kDebugMode) {
        debugPrint(
          '[Kinexa API] POST ${ApiConstants.upload} — fim '
          '(run_id=${run.runId}, statusCode=${res.statusCode})',
        );
      }
      if (res.statusCode == 200 || res.statusCode == 201) {
        return Map<String, dynamic>.from(res.data as Map);
      }
      throw DioException(
        requestOptions: res.requestOptions,
        response: res,
        type: DioExceptionType.badResponse,
        message: 'Upload retornou status ${res.statusCode}',
      );
    } on DioException catch (e) {
      _logDioError('POST ${ApiConstants.upload} (run_id=${run.runId})', e);
      rethrow;
    }
  }

  @override
  Future<void> deleteRun(String runId) async {
    await _dio.delete(ApiConstants.run(runId));
  }

  void _logDioError(String label, DioException e) {
    if (!kDebugMode) return;
    debugPrint(
      '[Kinexa API] $label — DioException '
      'type=${e.type} message=${e.message} statusCode=${e.response?.statusCode}',
    );
  }
}
