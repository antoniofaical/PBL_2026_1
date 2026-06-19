class AuthSession {
  const AuthSession({
    required this.userId,
    required this.username,
  });

  final int userId;
  final String username;
}

class AuthException implements Exception {
  AuthException(this.message, {this.code});

  final String message;
  final String? code;

  factory AuthException.invalidCredentials() =>
      AuthException('Usuário ou senha incorretos.', code: 'invalid_credentials');

  factory AuthException.sessionExpired() =>
      AuthException('Sessão expirada. Entre novamente.', code: 'session_expired');

  @override
  String toString() => message;
}
