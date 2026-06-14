class DebugLogService {
  final List<String> _logs = [];

  List<String> get logs => List.unmodifiable(_logs);

  String exportText() => _logs.join('\n');

  void add(String message) {
    final ts = DateTime.now().toIso8601String().substring(11, 19);
    _logs.add('[$ts] $message');
    if (_logs.length > 300) _logs.removeAt(0);
  }

  void clear() => _logs.clear();
}
