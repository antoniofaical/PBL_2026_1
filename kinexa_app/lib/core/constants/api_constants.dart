class ApiConstants {
  static const String defaultLocalBaseUrl = 'http://10.0.2.2:8000';
  static const String productionBaseUrl = 'https://api.antoniofaical.dev.br';

  static const String baseUrl = String.fromEnvironment(
    'KINEXA_API_BASE_URL',
    defaultValue: defaultLocalBaseUrl,
  );

  static const Duration connectTimeout = Duration(seconds: 8);
  static const Duration receiveTimeout = Duration(seconds: 20);
  static const Duration sendTimeout = Duration(seconds: 30);

  static const String health = '/api/health';
  static const String runs = '/api/runs';
  static String run(String id) => '/api/runs/$id';
  static String runCsv(String id) => '/api/runs/$id/csv';
  static const String upload = '/api/runs/upload';
}
