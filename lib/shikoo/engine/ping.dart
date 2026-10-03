import 'package:fl_clash/common/task_pool.dart';

/// One at a time let a dead server hold the rest for 8 s; FlClash's 16 gave false timeouts.
const pingConcurrency = 4;
const pingEvery = Duration(minutes: 2);
const refreshEvery = Duration(minutes: 10);

bool isDue(DateTime? last, DateTime now, Duration every) =>
    last == null || now.difference(last) >= every;

/// A server is tested again only after every first test, and reported -1 after both failed.
Future<void> pingServers(
  List<String> names,
  Future<int?> Function(String name) probe,
  void Function(String name, int ms) onResult, {
  int concurrency = pingConcurrency,
}) async {
  final pool = TaskPool(concurrency);
  Future<List<String>> pass(List<String> batch, {required bool last}) async {
    final failed = <String>[];
    await Future.wait([
      for (final name in batch)
        pool.run(() async {
          final ms = await probe(name);
          if (ms != null && ms > 0) {
            onResult(name, ms);
          } else if (last) {
            onResult(name, -1);
          } else {
            failed.add(name);
          }
        }),
    ]);
    return failed;
  }

  await pass(await pass(names, last: false), last: true);
}

List<String> sortByPing(List<String> panel, int? Function(String name) ping) {
  int key(String name) {
    final ms = ping(name);
    return ms != null && ms > 0 ? ms : 1 << 30;
  }

  final indexed = [for (var i = 0; i < panel.length; i++) (i, panel[i])];
  indexed.sort((a, b) {
    final byPing = key(a.$2).compareTo(key(b.$2));
    return byPing != 0 ? byPing : a.$1.compareTo(b.$1);
  });
  return [for (final (_, name) in indexed) name];
}

String? fastest(List<String> panel, int? Function(String name) ping) {
  final sorted = sortByPing(panel, ping);
  if (sorted.isEmpty) return null;
  final ms = ping(sorted.first);
  return ms != null && ms > 0 ? sorted.first : null;
}

List<String> keepOrder(List<String> order, List<String> panel) {
  final present = panel.toSet();
  final kept = [
    for (final name in order)
      if (present.contains(name)) name,
  ];
  final known = kept.toSet();
  return [
    ...kept,
    for (final name in panel)
      if (!known.contains(name)) name,
  ];
}
