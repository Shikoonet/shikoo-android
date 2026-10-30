import 'dart:async';
import 'dart:io';

import 'package:fl_clash/common/boot_guard.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/system_dns.dart';
import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:fl_clash/providers/actions/system_exit.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/shikoo/engine/cores.dart'
    show markCores, shikooCoreSpecsProvider, shikooTunnelProvider;
import 'package:fl_clash/shikoo/engine/direct_dns.dart'
    show shikooDirectAuth, withDirectInbound;
import 'package:fl_clash/shikoo/engine/owner.dart'
    show shikooOwnerHeldOffProvider;
import 'package:fl_clash/shikoo/engine/settings.dart' show shikooCoresProvider;
import 'package:fl_clash/shikoo/engine/warp.dart'
    show markWarp, shikooWarpRouteProvider, warpOnlyProfile;
import 'package:fl_clash/state.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' show basename;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:url_launcher/url_launcher.dart';

part 'actions/common.dart';
part 'actions/setup.dart';
part 'actions/backup.dart';
part 'actions/core.dart';
part 'actions/system.dart';
part 'actions/store.dart';
part 'actions/theme.dart';
part 'actions/proxies.dart';
part 'actions/profiles.dart';
part 'actions/geo_resource.dart';
part 'actions/updating.dart';
part 'generated/action.g.dart';
