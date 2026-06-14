import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/constants/api_constants.dart';
import '../models/run_model.dart';
import 'api_service.dart';

class HttpApiService implements ApiService {
  HttpApiService({Dio? dio}) : _dio = dio ?? _createDio() {
    if (kDebugMode) {
      debugPrint('[Kinexa API] baseUrl: ${ApiConstants.baseUrl}');
    }
  }

  final Dio _dio;

  static Dio _createDio() {
    return Dio(
      BaseOptions(
        baseUrl: ApiConstants.baseUrl,
        connectTimeout: ApiConstants.connectTimeout,
        receiveTimeout: ApiConstants.receiveTimeout,
        sendTimeout: ApiConstants.sendTimeout,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );
  }

  @override
  Future<bool> healthCheck() async {
    if (kDebugMode) {
      debugPrint('[Kinexa API] GET ${ApiConstants.health} — início');
    }
    try {
      final res = await _dio.get(ApiConstants.health);
      if (kDebugMode) {
        debugPrint(
          '[Kinexa API] GET ${ApiConstants.health} — fim '
          '(statusCode=${res.statusCode})',
        );
      }
      if (res.statusCode != 200) return false;

      if (res.data is Map) {
        final status = (res.data as Map)['status'];
        if (status != null && status != 'ok' && kDebugMode) {
          debugPrint(
            '[Kinexa API] health: HTTP 200 com body status=$status '
            '(aceito como online)',
          );
        }
      }
      return true;
    } on DioException catch (e) {
      _logDioError('GET ${ApiConstants.health}', e);
      return false;
    }
  }

  @override
  Future<List<RunModel>> fetchRuns() async {
    final res = await _dio.get(ApiConstants.runs);
    final list = res.data as List<dynamic>;
    return list
        .map((e) => RunModel.fromApiJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<RunModel> fetchRunDetail(String runId) async {
    final res = await _dio.get(ApiConstants.run(runId));
    return RunModel.fromApiJson(res.data as Map<String, dynamic>);
  }

  @override
  Future<String> fetchRunCsv(String runId) async {
    final res = await _dio.get(
      ApiConstants.runCsv(runId),
      options: Options(responseType: ResponseType.plain),
    );
    if (kDebugMode) {
      final csv = res.data as String? ?? '';
      debugPrint(
        '[Kinexa API] GET ${ApiConstants.runCsv(runId)} — '
        'csvLength=${csv.length}',
      );
    }
    return res.data as String;
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
