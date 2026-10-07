import 'package:collection/collection.dart';
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

int _sortKey(int? ms) => ms != null && ms > 0 ? ms : 1 << 30;

/// `sortedBy` is a stable merge sort: ties and the servers without an answer keep panel order.
List<String> sortByPing(List<String> panel, int? Function(String name) ping) =>
    panel.sortedBy((name) => _sortKey(ping(name)));

String? fastest(List<String> panel, int? Function(String name) ping) =>
    minBy(panel.where((name) => (ping(name) ?? 0) > 0), (name) => ping(name)!);

List<String> keepOrder(List<String> order, List<String> panel) => [
  ...order.where(panel.contains),
  ...panel.where((name) => !order.contains(name)),
];
