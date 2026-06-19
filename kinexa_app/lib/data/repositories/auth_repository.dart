import 'package:dio/dio.dart';

import '../../core/constants/api_constants.dart';
import '../../core/constants/app_constants.dart';
import '../local/settings_dao.dart';
import '../models/auth_session.dart';
import '../remote/dio_client.dart';

class AuthRepository {
  AuthRepository(this._settings, this._dio);

  final SettingsDao _settings;
  final Dio _dio;

  Future<AuthSession?> restoreSession() async {
    try {
      final session = await _fetchMe();
      await _settings.set(AppConstants.authUsernameKey, session.username);
      return session;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        await _clearLocalSession();
        return null;
      }
      rethrow;
    }
  }

  Future<AuthSession> login({
    required String username,
    required String password,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        ApiConstants.authLogin,
        data: {
          'username': username.trim(),
          'password': password,
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
        ),
      );
      final data = res.data ?? {};
      final session = AuthSession(
        userId: data['user_id'] as int,
        username: data['username'] as String,
      );
      await _settings.set(AppConstants.authUsernameKey, session.username);
      return session;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw AuthException.invalidCredentials();
      }
      if (e.response?.statusCode == 400) {
        final detail = e.response?.data;
        if (detail is Map && detail['detail'] is String) {
          throw AuthException(detail['detail'] as String, code: 'bad_request');
        }
      }
      rethrow;
    }
  }

  Future<void> logout() async {
    try {
      await _dio.post(ApiConstants.authLogout);
    } catch (_) {
      // Limpa local mesmo se o servidor estiver offline.
    }
    await _clearLocalSession();
  }

  Future<String?> cachedUsername() => _settings.get(AppConstants.authUsernameKey);

  Future<AuthSession> _fetchMe() async {
    final res = await _dio.get<Map<String, dynamic>>(ApiConstants.authMe);
    final data = res.data ?? {};
    return AuthSession(
      userId: data['user_id'] as int,
      username: data['username'] as String,
    );
  }

  Future<void> _clearLocalSession() async {
    await DioClient.clearCookies();
    await _settings.delete(AppConstants.authUsernameKey);
  }
}
