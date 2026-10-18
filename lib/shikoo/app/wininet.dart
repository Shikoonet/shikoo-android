import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// The LAN setting in Windows' Internet Options: `PROXY_TYPE_*` [flags] (`ProxyEnable` and
/// "Automatically detect settings" among them), `ProxyServer`, `ProxyOverride` and `AutoConfigURL`.
typedef WinProxy = ({int flags, String? server, String? bypass, String? pac});

const proxyTypeDirect = 1;
const proxyTypeProxy = 2;

final class _Value extends Union {
  @Uint32()
  external int dword;

  external Pointer<Utf16> text;
}

final class _Option extends Struct {
  @Uint32()
  external int option;

  external _Value value;
}

final class _OptionList extends Struct {
  @Uint32()
  external int size;

  external Pointer<Utf16> connection;

  @Uint32()
  external int count;

  @Uint32()
  external int error;

  external Pointer<_Option> options;
}

typedef _QueryC =
    Int32 Function(Pointer<Void>, Uint32, Pointer<Void>, Pointer<Uint32>);
typedef _Query =
    int Function(Pointer<Void>, int, Pointer<Void>, Pointer<Uint32>);
typedef _SetC = Int32 Function(Pointer<Void>, Uint32, Pointer<Void>, Uint32);
typedef _Set = int Function(Pointer<Void>, int, Pointer<Void>, int);

const _perConnectionOption = 75;
const _settingsChanged = 39;
const _refresh = 37;

/// `INTERNET_PER_CONN_*`; the flags are read as the settings page shows them (`FLAGS_UI`), since
/// WinINet drops auto-detect from `FLAGS` after a detection that found nothing.
const _readOptions = [10, 2, 3, 4];
const _writeOptions = [1, 2, 3, 4];

Pointer<_OptionList> _list(Arena arena, List<int> ids) {
  final options = arena<_Option>(ids.length);
  for (final (i, id) in ids.indexed) {
    options[i].option = id;
  }
  return arena<_OptionList>()
    ..ref.size = sizeOf<_OptionList>()
    ..ref.connection = nullptr
    ..ref.count = ids.length
    ..ref.options = options;
}

/// Null when WinINet would not say.
WinProxy? readWinProxy() => using((arena) {
  final query = DynamicLibrary.open(
    'wininet.dll',
  ).lookupFunction<_QueryC, _Query>('InternetQueryOptionW');
  final free = DynamicLibrary.open('kernel32.dll')
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>),
        Pointer<Void> Function(Pointer<Void>)
      >('GlobalFree');
  final list = _list(arena, _readOptions);
  final size = arena<Uint32>()..value = sizeOf<_OptionList>();
  if (query(nullptr, _perConnectionOption, list.cast(), size) == 0) {
    return null;
  }
  final options = list.ref.options;
  String? text(int i) {
    final value = options[i].value.text;
    if (value == nullptr) return null;
    final string = value.toDartString();
    free(value.cast());
    return string;
  }

  return (
    flags: options[0].value.dword,
    server: text(1),
    bypass: text(2),
    pac: text(3),
  );
});

bool writeWinProxy(WinProxy setting) => using((arena) {
  final set = DynamicLibrary.open(
    'wininet.dll',
  ).lookupFunction<_SetC, _Set>('InternetSetOptionW');
  final list = _list(arena, _writeOptions);
  final options = list.ref.options;
  options[0].value.dword = setting.flags;
  for (final (i, text) in [
    setting.server,
    setting.bypass,
    setting.pac,
  ].indexed) {
    options[i + 1].value.text =
        text?.toNativeUtf16(allocator: arena) ?? nullptr;
  }
  final written =
      set(nullptr, _perConnectionOption, list.cast(), sizeOf<_OptionList>()) !=
      0;
  final changed = set(nullptr, _settingsChanged, nullptr, 0) != 0;
  return written && changed && set(nullptr, _refresh, nullptr, 0) != 0;
});

bool proxyIsOurs(WinProxy setting, int port) =>
    setting.flags & proxyTypeProxy != 0 && setting.server == '127.0.0.1:$port';
