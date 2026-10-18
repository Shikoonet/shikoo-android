import 'dart:ffi';

import 'package:ffi/ffi.dart';

typedef _GetAdaptersC =
    Uint32 Function(
      Uint32 family,
      Uint32 flags,
      Pointer<Void> reserved,
      Pointer<Uint8> addresses,
      Pointer<Uint32> size,
    );
typedef _GetAdapters =
    int Function(int, int, Pointer<Void>, Pointer<Uint8>, Pointer<Uint32>);

const _skipAddressLists = 0x0f;
const _bufferOverflow = 111;
const _operStatusUp = 1;

/// Friendly names of the adapters Windows reports up. Offsets are `IP_ADAPTER_ADDRESSES_LH` on 64-bit
/// Windows: `Next` at 8, `FriendlyName` at 72, `OperStatus` at 104.
Set<String> upAdapters() => using((arena) {
  final get = DynamicLibrary.open(
    'iphlpapi.dll',
  ).lookupFunction<_GetAdaptersC, _GetAdapters>('GetAdaptersAddresses');
  final size = arena<Uint32>()..value = 32 * 1024;
  var buffer = arena<Uint8>(size.value);
  var result = get(0, _skipAddressLists, nullptr, buffer, size);
  if (result == _bufferOverflow) {
    buffer = arena<Uint8>(size.value);
    result = get(0, _skipAddressLists, nullptr, buffer, size);
  }
  if (result != 0) return const {};
  final up = <String>{};
  for (var at = buffer.address; at != 0;) {
    final name = Pointer<Pointer<Utf16>>.fromAddress(at + 72).value;
    if (Pointer<Uint32>.fromAddress(at + 104).value == _operStatusUp &&
        name != nullptr) {
      up.add(name.toDartString());
    }
    at = Pointer<IntPtr>.fromAddress(at + 8).value;
  }
  return up;
});
