import 'dart:io';

import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/core.dart';
import 'package:fl_clash/providers/state.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:riverpod/riverpod.dart';

class _MockCore extends Mock implements CoreHandlerInterface {}

class _Paths extends PathProviderPlatform {
  final String root;

  _Paths(this.root);

  @override
  Future<String?> getTemporaryPath() async => root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getApplicationCachePath() async => root;
}

class _NoTraffic extends CommonAction {
  @override
  Future<void> updateTraffic() async {}
}

class _RecordingSetup extends SetupAction {
  final List<bool> coreRunning = [];

  @override
  Future<bool> setCoreRunning(bool running) async {
    coreRunning.add(running);
    return true;
  }
}

const _noProfile = SetupState(
  profileId: null,
  profileLastUpdateDate: null,
  overwriteType: OverwriteType.standard,
  rules: [],
  proxyGroups: [],
  addedRules: [],
  script: null,
  overrideDns: false,
  dns: Dns(),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;

  setUpAll(() async {
    registerFallbackValue(const SetupParams(selectedMap: {}, testUrl: ''));
    root = Directory.systemTemp.createTempSync('apply_fail_closed_test');
    PathProviderPlatform.instance = _Paths(root.path);
    await AppLocalizations.load(const Locale('en'));
  });

  tearDownAll(() => root.deleteSync(recursive: true));

  /// The core answers each setupConfig with the next message: '' applied, anything else refused.
  (ProviderContainer, _MockCore) build(List<String> answers) {
    final core = _MockCore();
    when(
      () => core.setupConfig(any()),
    ).thenAnswer((_) async => answers.removeAt(0));
    final container = ProviderContainer(
      overrides: [
        currentProfileProvider.overrideWithValue(null),
        setupStateProvider.overrideWith((_, _) => _noProfile),
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
        setupActionProvider.overrideWith(_RecordingSetup.new),
        commonActionProvider.overrideWith(_NoTraffic.new),
      ],
    );
    globalState.container = container;
    addTearDown(container.dispose);
    return (container, core);
  }

  test(
    'after an apply the core refused, the same config applies again',
    () async {
      final (container, core) = build(['', 'config apply failed', '']);
      final setup = container.read(setupActionProvider.notifier);

      expect(await setup.applyProfile(force: true), isTrue);
      expect(await setup.applyProfile(force: true), isFalse);
      expect(await setup.applyProfile(), isTrue);

      verify(() => core.setupConfig(any())).called(3);
    },
  );

  test(
    'a running app whose apply the core refused stops, never shows connected',
    () async {
      final (container, _) = build(['', 'config apply failed']);
      final setup =
          container.read(setupActionProvider.notifier) as _RecordingSetup;
      await setup.setRunning(true, initialize: true);
      expect(container.read(runTimeProvider), isNotNull);

      expect(await setup.applyProfile(force: true), isFalse);

      expect(setup.coreRunning, [true, false]);
      expect(container.read(runTimeProvider), isNull);
    },
  );
}
