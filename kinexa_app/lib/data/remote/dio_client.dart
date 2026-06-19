import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/boot/app_boot.dart';
import '../../core/constants/api_constants.dart';

/// Cliente HTTP compartilhado com cookies persistentes (sessão do backend).
class DioClient {
  DioClient._();

  static Dio? _dio;
  static PersistCookieJar? _cookieJar;

  static Dio get dio {
    final client = _dio;
    if (client == null) {
      throw StateError('DioClient.initialize() must be called before use.');
    }
    return client;
  }

  static Future<void> initialize() async {
    if (_dio != null) return;

    final appDir = await getApplicationDocumentsDirectory();
    _cookieJar = PersistCookieJar(
      storage: FileStorage('${appDir.path}/.cookies/'),
    );

    final client = Dio(
      BaseOptions(
        baseUrl: ApiConstants.baseUrl,
        connectTimeout: ApiConstants.connectTimeout,
        receiveTimeout: ApiConstants.receiveTimeout,
        sendTimeout: ApiConstants.sendTimeout,
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'KinexaApp/0.1',
        },
      ),
    );

    client.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final path = options.uri.path;
          final method = options.method;

          options.headers['X-Kinexa-Boot'] =
              '${bootPhaseLabel(bootPhase.value)}:$bootTraceId';

          if (!bootAllowsRequest(method, path)) {
            if (kDebugMode) {
              debugPrint(
                '[Kinexa API] BLOQUEADO $method $path '
                '(fase=${bootPhaseLabel(bootPhase.value)})',
              );
            }
            return handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.cancel,
                message:
                    'Request bloqueada na fase ${bootPhaseLabel(bootPhase.value)}',
              ),
            );
          }

          handler.next(options);
        },
      ),
    );
    client.interceptors.add(CookieManager(_cookieJar!));
    _dio = client;
  }

  static Future<void> clearCookies() async {
    await _cookieJar?.deleteAll();
  }
}
