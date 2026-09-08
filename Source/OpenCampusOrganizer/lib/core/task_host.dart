/// ツールはOSのサービスやウィンドウに直接依存しない。
abstract interface class TaskHost {
  Future<void> start(String id, String title);
  void update(String id, String message, int done, int? total);
  Future<void> finish(
    String id,
    String message, {
    required bool closeEligible,
    bool failed = false,
  });
}

class NoopTaskHost implements TaskHost {
  const NoopTaskHost();
  @override
  Future<void> start(String id, String title) async {}
  @override
  void update(String id, String message, int done, int? total) {}
  @override
  Future<void> finish(
    String id,
    String message, {
    required bool closeEligible,
    bool failed = false,
  }) async {}
}
