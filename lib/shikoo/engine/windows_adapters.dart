import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Friendly names of the adapters Windows reports up.
Set<String> upAdapters() => using((arena) {
  final skipAddresses =
      GAA_FLAG_SKIP_UNICAST |
      GAA_FLAG_SKIP_ANYCAST |
      GAA_FLAG_SKIP_MULTICAST |
      GAA_FLAG_SKIP_DNS_SERVER;
  final size = arena<Uint32>()..value = 32 * 1024;
  var list = arena<Uint8>(size.value).cast<IP_ADAPTER_ADDRESSES_LH>();
  var result = GetAdaptersAddresses(0, skipAddresses, list, size);
  if (result == ERROR_BUFFER_OVERFLOW) {
    list = arena<Uint8>(size.value).cast<IP_ADAPTER_ADDRESSES_LH>();
    result = GetAdaptersAddresses(0, skipAddresses, list, size);
  }
  if (result != 0) return const {};
  final up = <String>{};
  for (var at = list; at != nullptr; at = at.ref.Next) {
    final name = at.ref.FriendlyName;
    if (at.ref.OperStatus == IfOperStatusUp && name != nullptr) {
      up.add(name.toDartString());
    }
  }
  return up;
});
