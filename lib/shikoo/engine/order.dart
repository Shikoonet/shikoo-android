import 'package:fl_clash/providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const shikooOrderKey = 'shikoo.order';

List<int> inOrder(List<int> saved, List<int> ids) => [
  ...saved.where(ids.contains),
  ...ids.where((id) => !saved.contains(id)),
];

/// The cards' order on this device only, from Settings › «ترتیب سرویس‌ها».
class SavedOrder extends Notifier<List<int>> {
  @override
  List<int> build() => const [];

  Future<void> load() async {
    final stored = (await SharedPreferences.getInstance()).getStringList(
      shikooOrderKey,
    );
    state = [for (final id in stored ?? const <String>[]) ?int.tryParse(id)];
  }

  Future<void> save(List<int> ids) async {
    state = ids;
    await (await SharedPreferences.getInstance()).setStringList(
      shikooOrderKey,
      [for (final id in ids) '$id'],
    );
  }

  Future<void> forget(int id) async {
    if (state.contains(id)) await save([...state]..remove(id));
  }
}

final savedOrderProvider = NotifierProvider<SavedOrder, List<int>>(
  SavedOrder.new,
);

/// Every service's id in card order; the one in use keeps its place in it.
final serviceOrderProvider = Provider<List<int>>(
  (ref) => inOrder(ref.watch(savedOrderProvider), [
    for (final profile in ref.watch(profilesProvider)) profile.id,
  ]),
);
