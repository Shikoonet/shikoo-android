import 'dart:async';
import 'dart:math' as math;

import 'package:fl_clash/shikoo/engine/account.dart';
import 'package:fl_clash/shikoo/engine/clock.dart';
import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/cores.dart';
import 'package:fl_clash/shikoo/engine/diag.dart';
import 'package:fl_clash/shikoo/engine/settings.dart';
import 'package:fl_clash/shikoo/engine/update.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/clock.dart';
import 'package:fl_clash/shikoo/ui/cores.dart';
import 'package:fl_clash/shikoo/ui/dialogs.dart';
import 'package:fl_clash/shikoo/ui/focus.dart';
import 'package:fl_clash/shikoo/ui/icons.dart';
import 'package:fl_clash/shikoo/ui/internet_check.dart';
import 'package:fl_clash/shikoo/ui/logs.dart';
import 'package:fl_clash/shikoo/ui/order.dart';
import 'package:fl_clash/shikoo/ui/paste.dart';
import 'package:fl_clash/shikoo/ui/report.dart';
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:fl_clash/shikoo/ui/update.dart';
import 'package:fl_clash/shikoo/ui/widgets.dart';
import 'package:flutter/foundation.dart'
    show LicenseEntry, LicenseParagraph, LicenseRegistry, clampDouble;
import 'package:flutter/services.dart'
    show KeyDownEvent, KeyEvent, KeyRepeatEvent, LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

part 'licenses.dart';

void openSettings(BuildContext context) => unawaited(
  Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => const ShikooSettings(),
      settings: const RouteSettings(name: 'settings'),
    ),
  ),
);

/// Frames `tv-settings-pre-login` and `phone-settings-pasted`: on the TV two columns.
class ShikooSettings extends ConsumerWidget {
  const ShikooSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = ShikooL10n.of(context);
    final look = ref.watch(shikooLookProvider);
    final setLook = ref.read(shikooLookProvider.notifier);
    final state = ref.watch(shikooStateProvider);
    final isTV = state.isTV;
    final account = ref.watch(shikooAccountProvider);
    final who = account.who;
    final pasted = [
      for (final service in [?state.service, ...state.others])
        if (service.pasted && account.serviceOf(service.id) == null) service,
    ];
    final username = who?.username;
    final shown = who?.name ?? '@${username ?? ''}';
    final order =
        [?state.service, ...state.others].where((s) => !s.finished).length < 2
        ? null
        : _Group(
            title: l.servicesGroup,
            child: _Card(
              rows: [
                _Row(
                  icon: ShikooIcon.handle,
                  title: l.orderServices,
                  subtitle: isTV
                      ? l.orderServicesHelpTv
                      : (shikooDesktop
                            ? l.orderServicesHelpDesktop
                            : l.orderServicesHelpTouch),
                  forward: true,
                  onPressed: () => unawaited(
                    Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const ServiceOrder(),
                        settings: const RouteSettings(name: 'order'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
    // tv-p5-settings puts «سرویس‌ها» last in its column, phone-p5-settings under the language.
    final here = account.services.length;
    final servicesNote = who == null || account.total < 2
        ? null
        : isTV
        ? l.changeServicesTv
        : here < account.total
        ? (shikooDesktop ? l.servicesHereDesktop : l.servicesHereTouch)(
            here,
            account.total,
          )
        : (shikooDesktop ? l.servicesAllHereDesktop : l.servicesAllHereTouch);
    final groups = [
      _Group(
        title: l.appearance,
        child: Segmented(
          autofocus: true,
          selected: look.theme,
          options: {
            ThemeMode.light: l.themeLight,
            ThemeMode.dark: l.themeDark,
            ThemeMode.system: l.themeAuto,
          },
          onSelect: (theme) => unawaited(setLook.setTheme(theme)),
        ),
      ),
      _Group(
        title: l.language,
        child: Segmented(
          selected: look.language,
          options: {'fa': l.languageFa, 'en': l.languageEn},
          onSelect: (language) => unawaited(setLook.setLanguage(language)),
        ),
      ),
      _Group(
        title: l.connectionGroup,
        child: _Card(
          rows: [
            SwitchRow(
              label: l.iranDirect,
              help: l.iranDirectHelp,
              on: state.iranDirect,
              inCard: true,
              onChanged: (on) => unawaited(
                ref.read(shikooControllerProvider).setIranDirect(on),
              ),
            ),
            SwitchRow(
              label: l.warpSwitch,
              help: l.warpSwitchHelp,
              on: state.bridge.on,
              inCard: true,
              onChanged: (on) =>
                  unawaited(ref.read(shikooControllerProvider).setBridge(on)),
            ),
          ],
        ),
      ),
      if (state.cores.isNotEmpty)
        _Group(
          title: l.coresGroup,
          note: l.coresNote,
          child: _Card(
            rows: [
              for (final row in state.cores)
                _CoreRow(key: ValueKey(row.protocol), row: row),
            ],
          ),
        ),
      if (shikooDesktop)
        _Group(
          title: l.windowsGroup,
          child: _Card(
            rows: [
              SwitchRow(
                label: l.autoStart,
                help: l.autoStartHelp,
                on: ref.watch(shikooAutoStartProvider),
                onChanged: (on) => setAutoStart(ref, on),
                inCard: true,
              ),
              SwitchRow(
                label: l.updateNotice,
                help: l.updateNoticeHelp,
                on: ref.watch(shikooUpdateNoticeProvider),
                onChanged: (on) => unawaited(
                  ref.read(shikooUpdateNoticeProvider.notifier).set(on),
                ),
                inCard: true,
              ),
            ],
          ),
        ),
      if (!isTV) ?order,
      PasteLink(
        onAdded: (_) => Navigator.popUntil(context, (route) => route.isFirst),
        builder: (context, busy, paste) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.s6,
          children: [
            if (pasted.isNotEmpty && !isTV)
              _Group(
                title: l.pastedServicesTitle,
                child: _Card(
                  rows: [
                    for (final service in pasted)
                      _PastedRow(
                        service: service,
                        // The link being checked may be this service's new one.
                        onRemove: busy
                            ? null
                            : () => unawaited(
                                _remove(context, ref, service, state),
                              ),
                      ),
                  ],
                ),
              ),
            _Group(
              title: l.account,
              note: servicesNote,
              child: _Card(
                rows: [
                  if (who != null)
                    _Row(
                      icon: ShikooIcon.plane,
                      title: l.signedInWith(shown),
                      rich: sayWith(l.signedInWith, [
                        TextSpan(
                          text: shown,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ]),
                      subtitle: username == null
                          ? l.telegramAccount
                          : l.telegramAccountUsername('\u2066@$username\u2069'),
                    )
                  else if (!isTV)
                    _Row(
                      icon: ShikooIcon.plane,
                      title: l.signInRow,
                      subtitle: l.signInRowHelp,
                      onPressed: () => unawaited(_signIn(context, ref, isTV)),
                    ),
                  if (!isTV && who == null)
                    _Row(
                      icon: ShikooIcon.paste,
                      busy: busy,
                      title: l.pasteAnother,
                      subtitle: busy ? l.pasteChecking : l.pasteAnotherHelp,
                      onPressed: paste,
                    ),
                  _Row(
                    key: const ValueKey('logout'),
                    icon: ShikooIcon.logout,
                    danger: true,
                    title: l.logout,
                    subtitle: switch ((who != null, isTV)) {
                      (true, true) => l.logoutHelpSignedInTv,
                      (true, false) => l.logoutHelpSignedInTouch,
                      (false, true) => l.logoutHelpTv,
                      (false, false) =>
                        (shikooDesktop
                            ? l.logoutHelpDesktop
                            : l.logoutHelpTouch),
                    },
                    onPressed: () =>
                        unawaited(_logOut(context, ref, isTV, who != null)),
                  ),
                ],
              ),
            ),
            _Group(
              title: l.support,
              child: _Card(
                rows: [
                  _Row(
                    icon: ShikooIcon.report,
                    title: l.diagTitle,
                    subtitle: l.diagRowHelp,
                    forward: true,
                    onPressed: () => unawaited(_diagnose(context)),
                  ),
                  if (!isTV)
                    _Row(
                      icon: ShikooIcon.lines,
                      title: l.logsTitle,
                      subtitle: l.logsRowHelp(ShikooDiag.keep.inDays),
                      keys: shikooDesktop ? logsKeys : const [],
                      forward: true,
                      onPressed: () => openLogs(context),
                    ),
                ],
              ),
            ),
            if (isTV) ?order,
          ],
        ),
      ),
      _AppGroup(isTV: isTV),
    ];
    final coreSwitch = state.coreSwitch;
    return SubPage(
      title: l.settings,
      isTV: isTV,
      // The TV has no bar: a core switch's news holds the hint's place, moving nothing.
      hint: isTV && coreSwitch != null
          ? coreNews(l, coreSwitch).join(' ')
          : null,
      hintAlert: isTV && coreSwitch?.stage == ShikooSwitchStage.failed,
      child: _columns(groups, isTV: isTV),
    );
  }

  /// The pictures are of Settings, where the customer came from: the fault was seen elsewhere.
  static Future<void> _diagnose(BuildContext context) async {
    final shots = await takeShots(context);
    if (!context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ShikooDiagnose(shots: shots),
        settings: const RouteSettings(name: 'diagnose'),
      ),
    );
  }

  /// The last service gone, home shows the no-service card; else Settings stay.
  static Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    ShikooService service,
    ShikooState state,
  ) async {
    final removed = await confirmRemove(
      context,
      controller: ref.read(shikooControllerProvider),
      service: service,
      connected:
          service.id == state.service?.id &&
          {
            ShikooConnection.on,
            ShikooConnection.connecting,
          }.contains(state.connection),
    );
    if (removed &&
        context.mounted &&
        ref.read(shikooStateProvider).service == null) {
      Navigator.popUntil(context, (route) => route.isFirst);
    }
  }

  /// Home comes back to sign-in; the phone goes on to Telegram.
  static Future<void> _signIn(
    BuildContext context,
    WidgetRef ref,
    bool isTV,
  ) async {
    final signIn = ref.read(shikooSignInProvider);
    Navigator.popUntil(context, (route) => route.isFirst);
    final link = await signIn.start();
    if (link == null || isTV) return;
    await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
  }

  /// Signed in, the device leaves the account too; with pasted links only, they are removed.
  static Future<void> _logOut(
    BuildContext context,
    WidgetRef ref,
    bool isTV,
    bool signedIn,
  ) async {
    final sure = await showShikooDialog<bool>(
      context,
      children: (context) {
        final t = ShikooTheme.of(context);
        final l = ShikooL10n.of(context);
        return [
          Text(
            signedIn
                ? l.logoutSignedInTitle
                : (isTV
                      ? l.logoutTitleTv
                      : (shikooDesktop
                            ? l.logoutTitleDesktop
                            : l.logoutTitleTouch)),
            style: t.text(t.s.title, weight: FontWeight.w700),
          ),
          Text(
            switch ((signedIn, isTV)) {
              (true, true) => l.logoutSignedInBodyTv,
              (true, false) => l.logoutSignedInBodyTouch,
              (false, true) => l.logoutBodyTv,
              (false, false) =>
                (shikooDesktop ? l.logoutBodyDesktop : l.logoutBodyTouch),
            },
            style: t.text(
              t.s.dialogText,
              color: t.c.textMuted,
              height: Leading.body,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: Space.s2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              spacing: Space.s2,
              children: [
                ShikooButton(
                  label: l.cancelButton,
                  autofocus: true,
                  onPressed: () => Navigator.pop(context, false),
                ),
                ShikooButton(
                  label: signedIn ? l.logout : l.removeButton,
                  danger: true,
                  onPressed: () => Navigator.pop(context, true),
                ),
              ],
            ),
          ),
        ];
      },
    );
    if (sure != true || !context.mounted) return;
    await ref.read(shikooSignInProvider).signOut();
    if (context.mounted) Navigator.popUntil(context, (route) => route.isFirst);
  }
}

enum _Check { idle, checking, latest, failed, clock }

/// Settings › App: version, a check past six hours, About; a known update is Home's card (phone-cards-settings-app).
class _AppGroup extends ConsumerStatefulWidget {
  const _AppGroup({required this.isTV});

  final bool isTV;

  @override
  ConsumerState<_AppGroup> createState() => _AppGroupState();
}

class _AppGroupState extends ConsumerState<_AppGroup> {
  final _card = GlobalKey();
  final _cardButton = FocusNode();
  var _check = _Check.idle;

  @override
  void dispose() {
    _cardButton.dispose();
    super.dispose();
  }

  Future<void> _checkNow() async {
    if (_check == _Check.checking) return;
    setState(() => _check = _Check.checking);
    final error = await ref.read(shikooUpdateProvider).checkNow();
    if (!mounted) return;
    setState(
      () => _check = switch (error) {
        null => _Check.latest,
        UpdateError.clock => _Check.clock,
        _ => _Check.failed,
      },
    );
    if (ref.read(shikooUpdateOfferProvider) == null) return;
    // The answer to the press shows: on the TV the remote goes from the row that left to the
    // card's button (tv-settings-app-found); on a phone the card scrolls into view once. A
    // computer's click took the focus to the row, which would fall back to the top of the page.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.isTV || shikooDesktop) {
        jumpFocus(context, _cardButton);
      } else if (_card.currentContext case final card?) {
        revealWithRing(card);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = ShikooL10n.of(context);
    final update = ref.watch(shikooUpdateOfferProvider);
    return _Group(
      title: l.appSection,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.s3,
        children: [
          _Card(
            rows: [
              _Row(
                title: l.version,
                value: _version(context, ref.watch(shikooVersionProvider)),
              ),
              if (update == null)
                _Row(
                  icon: ShikooIcon.refresh,
                  busy: _check == _Check.checking,
                  title: l.settingsCheckUpdate,
                  subtitle: switch (_check) {
                    _Check.idle => null,
                    _Check.checking => l.settingsChecking,
                    _Check.latest => l.settingsUpToDate,
                    _Check.failed => l.settingsCheckFailed,
                    _Check.clock => clockText(l),
                  },
                  alert: _check == _Check.failed || _check == _Check.clock,
                  onPressed: () => unawaited(_checkNow()),
                ),
              if (update == null && _check == _Check.clock)
                _Row(
                  icon: ShikooIcon.gear,
                  title: l.dateSettings,
                  onPressed: () => unawaited(openDateSettings()),
                ),
              _Row(
                key: const ValueKey('about'),
                title: l.about,
                subtitle: l.aboutSummary,
                forward: true,
                onPressed: () => unawaited(
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const ShikooAbout(),
                      settings: const RouteSettings(name: 'about'),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (update != null)
            UpdateCard(
              key: _card,
              offer: update,
              isTV: widget.isTV,
              focusNode: _cardButton,
            ),
        ],
      ),
    );
  }
}

/// Frame `tv-about`: the licence, the credits and where the source comes from.
class ShikooAbout extends ConsumerWidget {
  const ShikooAbout({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final body = t.text(t.s.body, height: Leading.body);
    final isTV = ref.watch(shikooStateProvider.select((state) => state.isTV));
    return SubPage(
      title: l.about,
      isTV: isTV,
      child: Center(
        child: SizedBox(
          width: isTV ? t.s.pane : double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.s3,
            children: [
              _Card(
                rows: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Space.s6,
                      vertical: Space.s4,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: Space.s3,
                      children: [
                        Text(
                          '${l.appName} ${_version(context, ref.watch(shikooVersionProvider))}',
                          style: t.text(t.s.title, weight: FontWeight.w700),
                        ),
                        Text(l.aboutFree, style: body),
                        Text(l.aboutBasedOn, style: body),
                        Text(l.aboutWarp, style: body),
                        Text(l.aboutSource, style: body),
                        Text(
                          l.aboutLicense,
                          style: body.copyWith(color: t.c.textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              _Card(
                rows: [
                  _Row(
                    title: l.aboutLicenses,
                    subtitle: l.aboutLicensesHelp,
                    forward: true,
                    autofocus: isTV,
                    onPressed: () => unawaited(
                      Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const ShikooLicenses(),
                          settings: const RouteSettings(name: 'licenses'),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _version(BuildContext context, String version) => version
    .split('.')
    .map((part) {
      final number = int.tryParse(part);
      return number == null ? part : localNumber(context, number);
    })
    .join('.');

/// `.tv-top` with `.tv-title` and `.tv-hint` over the page; on the phone `.appbar.sub`. A
/// [child] that does not [scrolls] lays out its own room, the phone's bottom inset included.
class SubPage extends StatelessWidget {
  const SubPage({
    super.key,
    required this.title,
    required this.isTV,
    required this.child,
    this.scrolls = true,
    this.wide = false,
    this.barGap = true,
    this.hint,
    this.hintAlert = false,
  });

  final String title;
  final bool isTV;
  final Widget child;
  final bool scrolls;

  /// A [child] that does not [scrolls] takes the page's width on a computer, not the pane's.
  final bool wide;

  /// False for a page whose own head sits right under the bar, as `.logs-head`.
  final bool barGap;
  final String? hint;

  final bool hintAlert;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final s = t.s;
    final l = ShikooL10n.of(context);
    final heading = Text(
      title,
      style: t.text(s.title, weight: FontWeight.w700),
    );
    return PageWidth(
      child: Scaffold(
        backgroundColor: t.c.bg,
        body: SafeArea(
          bottom: isTV,
          child: PageFocusScope(
            child: FocusTraversalGroup(
              policy: PageTraversalPolicy(),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isTV ? s.safeX : 0,
                  vertical: s.safeY,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      height: s.appbar + (isTV ? 2 * ShikooSizes.ring : 0),
                      padding: isTV
                          ? const EdgeInsets.symmetric(
                              horizontal: ShikooSizes.ring,
                            )
                          : EdgeInsetsDirectional.only(
                              start: Space.s1,
                              end: s.safeX,
                            ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        spacing: Space.s1,
                        children: isTV
                            ? [
                                heading,
                                Flexible(
                                  child: Text(
                                    hint ?? l.backHintTv,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: t.text(
                                      s.bodySm,
                                      color: hintAlert
                                          ? t.c.danger
                                          : t.c.textMuted,
                                    ),
                                  ),
                                ),
                              ]
                            : [
                                ShikooIconButton(
                                  icon: ShikooIcon.back,
                                  label: l.back,
                                  flipInLtr: true,
                                  onPressed: () =>
                                      unawaited(Navigator.maybePop(context)),
                                ),
                                Expanded(child: heading),
                              ],
                      ),
                    ),
                    SizedBox(height: isTV ? Space.s3 : (barGap ? Space.s2 : 0)),
                    Expanded(
                      child: !scrolls
                          ? (wide
                                ? child
                                : PaneColumn(padding: s.safeX, child: child))
                          : isTV
                          ? TvScrollColumn(child: child)
                          : SingleChildScrollView(
                              padding: EdgeInsets.fromLTRB(
                                s.safeX,
                                0,
                                s.safeX,
                                Space.s6 + MediaQuery.paddingOf(context).bottom,
                              ),
                              child: PaneColumn(child: child),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Widget _columns(List<Widget> groups, {required bool isTV}) => isTV
    ? Padding(
        padding: const EdgeInsets.symmetric(horizontal: ShikooSizes.ring),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Space.s10,
          children: [
            for (final first in [0, 1])
              Expanded(
                child: _Column(
                  children: [
                    for (var i = first; i < groups.length; i += 2) groups[i],
                  ],
                ),
              ),
          ],
        ),
      )
    : _Column(children: groups);

/// Frames `phone-diagnose`, `tv-diagnose`: the internet check, run on open, over the report,
/// the remote on its button. A check that missed the door hides it, as a report cannot arrive.
class ShikooDiagnose extends ConsumerStatefulWidget {
  const ShikooDiagnose({super.key, required this.shots});

  final ReportShots shots;

  @override
  ConsumerState<ShikooDiagnose> createState() => _ShikooDiagnoseState();
}

class _ShikooDiagnoseState extends ConsumerState<ShikooDiagnose> {
  final _again = FocusNode();
  final _send = FocusNode();
  ProbeChecks? _checks;
  var _checking = true;

  @override
  void initState() {
    super.initState();
    unawaited(_check());
  }

  @override
  void dispose() {
    _again.dispose();
    _send.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final checks = await ref.read(shikooProbeProvider.notifier).probe();
    if (!mounted) return;
    final onSend = _send.hasPrimaryFocus;
    setState(() {
      _checks = checks;
      _checking = false;
    });
    if (!onSend) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_send.hasPrimaryFocus) _again.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final state = ref.watch(shikooStateProvider);
    final isTV = state.isTV;
    final reading = readProbes(_checks, state.servers);
    final towardCheck = Directionality.of(context) == TextDirection.rtl
        ? TraversalDirection.right
        : TraversalDirection.left;
    final internet = _Group(
      title: l.diagInternetGroup,
      child: InternetCheckCard(
        check: _checking ? const AsyncLoading() : AsyncData(_checks!),
        state: state,
        controller: ref.watch(shikooControllerProvider),
        onAgain: () {
          setState(() => _checking = true);
          unawaited(_check());
        },
        firstFocus: _again,
      ),
    );
    final report = _Group(
      title: l.diagReportGroup,
      child: Container(
        padding: const EdgeInsets.all(Space.s4),
        decoration: ShapeDecoration(
          color: t.c.surface,
          shadows: t.c.cardShadow,
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(Radii.lg),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.s3,
          children: [
            Text(
              l.diagReportHelp,
              style: t.text(
                t.s.bodySm,
                color: t.c.textMuted,
                height: Leading.body,
              ),
            ),
            if (reading == ProbeReading.offline ||
                reading == ProbeReading.noDoor)
              Text(
                l.diagReportLater,
                style: t.text(
                  t.s.bodySm,
                  weight: FontWeight.w700,
                  height: Leading.body,
                ),
              )
            else
              Actions(
                actions: {
                  DirectionalFocusIntent:
                      CallbackAction<DirectionalFocusIntent>(
                        onInvoke: (intent) {
                          if (intent.direction != towardCheck) {
                            return Actions.maybeInvoke(context, intent);
                          }
                          _again.requestFocus();
                          return null;
                        },
                      ),
                },
                child: ShikooButton(
                  label: l.reportSendToSupport,
                  icon: ShikooIcon.report,
                  primary: true,
                  autofocus: isTV && _checks == null,
                  focusNode: _send,
                  onPressed: () =>
                      unawaited(openReport(context, 'diagnose', widget.shots)),
                ),
              ),
          ],
        ),
      ),
    );
    return SubPage(
      title: l.diagTitle,
      isTV: isTV,
      child: _columns([internet, report], isTV: isTV),
    );
  }
}

/// The frame's remote order: up and down stay in a column, left and right cross to the other.
class _Column extends StatelessWidget {
  const _Column({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => FocusScope(
    child: FocusTraversalGroup(
      policy: _ColumnPolicy(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.s6,
        children: children,
      ),
    ),
  );
}

class _ColumnPolicy extends ReadingOrderTraversalPolicy {
  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    final scope = currentNode.nearestScope!;
    scope.directionalTraversalEdgeBehavior = TraversalEdgeBehavior.stop;
    final moved = super.inDirection(currentNode, direction);
    if (moved ||
        direction == TraversalDirection.up ||
        direction == TraversalDirection.down) {
      return moved;
    }
    if (_level(currentNode, direction) case final target?) {
      invalidateScopeData(scope);
      jumpFocus(target.context!, target);
      return true;
    }
    scope.directionalTraversalEdgeBehavior = TraversalEdgeBehavior.parentScope;
    return super.inDirection(currentNode, direction);
  }
}

/// Across the columns, the item level with [from], else the nearest up or down; Flutter picked the other column's top.
FocusNode? _level(FocusNode from, TraversalDirection direction) {
  final at = from.rect;
  final beside = [
    for (final node
        in from.nearestScope?.enclosingScope?.traversalDescendants ??
            <FocusNode>[])
      if (node is! FocusScopeNode &&
          (direction == TraversalDirection.left
              ? node.rect.right <= at.left
              : node.rect.left >= at.right))
        node,
  ];
  double apart(Rect r) =>
      math.max(0, math.max(at.top - r.bottom, r.top - at.bottom));
  double off(Rect r) => (r.center.dy - at.center.dy).abs();
  int closer(FocusNode a, FocusNode b) {
    final byGap = apart(a.rect).compareTo(apart(b.rect));
    return byGap != 0 ? byGap : off(a.rect).compareTo(off(b.rect));
  }

  return beside.isEmpty
      ? null
      : beside.reduce((a, b) => closer(a, b) <= 0 ? a : b);
}

/// `.group-title` over its control, and a `.group-note` under it.
class _Group extends StatelessWidget {
  const _Group({required this.title, required this.child, this.note});

  final String title;
  final Widget child;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.s2, 0, Space.s2, Space.s2),
          child: Text(
            title,
            style: t.text(
              t.s.bodySm,
              weight: FontWeight.w700,
              color: t.c.textMuted,
              height: Leading.body,
            ),
          ),
        ),
        child,
        if (note case final note?)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.s2, Space.s2, Space.s2, 0),
            child: Text(
              note,
              style: t.text(
                t.s.bodySm,
                color: t.c.textMuted,
                height: Leading.tight,
              ),
            ),
          ),
      ],
    );
  }
}

/// `.segmented`: one choice of a few, the chosen one raised.
class Segmented<T> extends StatefulWidget {
  const Segmented({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelect,
    this.autofocus = false,
    this.small = false,
    this.counts = const {},
    this.wraps = false,
  });

  final Map<T, String> options;
  final T selected;

  /// `.cnt`: a red number after an option's label, none at zero.
  final Map<T, int> counts;

  /// Two rows when one would cut a label, as the Logs page's four tabs in large text.
  final bool wraps;

  /// Null greys every option out, as the mode switch while connecting.
  final ValueChanged<T>? onSelect;

  /// Lands the remote on the chosen option.
  final bool autofocus;

  /// `.segmented.sm`: the sign-in screens' language switch in a corner.
  final bool small;

  @override
  State<Segmented<T>> createState() => _SegmentedState<T>();
}

class _SegmentedState<T> extends State<Segmented<T>> {
  final _nodes = <T, FocusNode>{};

  @override
  void dispose() {
    for (final node in _nodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final Segmented(
      :options,
      :selected,
      :onSelect,
      :autofocus,
      :small,
      :counts,
      :wraps,
    ) = widget;
    final shape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(Radii.sm),
    );
    TextStyle labelStyle(bool chosen) => t.text(
      small ? t.s.bodySm : t.s.body,
      weight: chosen ? FontWeight.w700 : FontWeight.w500,
      color: onSelect == null
          ? (chosen ? t.c.textMuted : t.c.iconDisabled)
          : (chosen ? t.c.text : t.c.textMuted),
    );
    final countStyle = t.text(
      t.s.caption,
      weight: FontWeight.w700,
      color: t.c.onDanger,
      height: 1,
    );
    Widget option(T value, String label) {
      final count = counts[value] ?? 0;
      return Flexible(
        flex: small ? 0 : 1,
        fit: FlexFit.tight,
        child: Pressable(
          focusNode: _nodes.putIfAbsent(value, FocusNode.new),
          autofocus: autofocus && value == selected,
          shape: shape,
          onPressed: onSelect == null ? null : () => onSelect(value),
          builder: (context, focused) {
            final chosen = value == selected;
            final text = Text(label, maxLines: 1, style: labelStyle(chosen));
            return Semantics(
              selected: chosen,
              button: true,
              enabled: onSelect != null,
              child: Container(
                height: small ? null : t.s.button,
                padding: small
                    ? const EdgeInsets.symmetric(
                        horizontal: Space.s4,
                        vertical: Space.s1,
                      )
                    : null,
                alignment: Alignment.center,
                decoration: ShapeDecoration(
                  color: focused ? t.c.focusBg : (chosen ? t.c.surface : null),
                  shadows: focused
                      ? t.c.raisedShadow
                      : (chosen ? t.c.cardShadow : null),
                  shape: shape,
                ),
                child: count == 0
                    ? text
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: Space.s1,
                        children: [
                          Flexible(child: text),
                          Container(
                            constraints: const BoxConstraints(
                              minWidth: ShikooSizes.count,
                              minHeight: ShikooSizes.count,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: Space.s1,
                            ),
                            decoration: ShapeDecoration(
                              color: t.c.danger,
                              shape: const StadiumBorder(),
                            ),
                            child: Center(
                              widthFactor: 1,
                              heightFactor: 1,
                              child: Text(
                                localNumber(context, count),
                                style: countStyle,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            );
          },
        ),
      );
    }

    Widget row(Iterable<MapEntry<T, String>> entries) => Row(
      mainAxisSize: small ? MainAxisSize.min : MainAxisSize.max,
      spacing: Space.s1,
      children: [for (final e in entries) option(e.key, e.value)],
    );
    final entries = options.entries.toList();
    // The remote or Tab coming from another row lands on the chosen option, not the nearest one;
    // a click lands where it clicked.
    final segmented = Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (inside) {
        final keys =
            FocusManager.instance.highlightMode ==
            FocusHighlightMode.traditional;
        if (inside && keys) _nodes[selected]?.requestFocus();
      },
      child: Container(
        padding: const EdgeInsets.all(Space.s1),
        decoration: ShapeDecoration(
          color: t.c.surfaceSunken,
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(Radii.md),
          ),
        ),
        child: !wraps
            ? row(entries)
            : LayoutBuilder(
                builder: (context, box) {
                  final room =
                      (box.maxWidth - Space.s1 * (entries.length - 1)) /
                      entries.length;
                  final fits = entries.every((e) {
                    final count = counts[e.key] ?? 0;
                    final badge = count == 0
                        ? 0.0
                        : Space.s1 +
                              (textWidth(
                                        context,
                                        localNumber(context, count),
                                        countStyle,
                                      ) +
                                      2 * Space.s1)
                                  .clamp(ShikooSizes.count, double.infinity);
                    return textWidth(context, e.value, labelStyle(true)) +
                            badge <=
                        room;
                  });
                  if (fits) return row(entries);
                  final half = (entries.length + 1) ~/ 2;
                  return Column(
                    spacing: Space.s1,
                    children: [
                      row(entries.take(half)),
                      row(entries.skip(half)),
                    ],
                  );
                },
              ),
      ),
    );
    return onSelect == null
        ? IgnorePointer(child: ExcludeFocus(child: segmented))
        : segmented;
  }
}

/// `.card` holding `.row`s, a hairline between each two. Rows are matched by place, so one that
/// keeps the remote while a row above it comes or goes needs a key.
class _Card extends StatelessWidget {
  const _Card({required this.rows});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: t.c.surface,
        shadows: t.c.cardShadow,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, row) in rows.indexed) ...[
            if (i > 0) Container(height: 1, color: t.c.border),
            row,
          ],
        ],
      ),
    );
  }
}

/// phone-settings-pasted: the name over the card's chip text, and «حذف»; the row itself does
/// nothing, so a scroll never opens the dialog.
class _PastedRow extends StatelessWidget {
  const _PastedRow({required this.service, required this.onRemove});

  final ShikooService service;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final onRemove = this.onRemove;
    final remove = Container(
      constraints: const BoxConstraints(
        minWidth: ShikooSizes.touch,
        minHeight: ShikooSizes.touch,
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: Space.s2),
      child: Text(
        l.removeService,
        style: t.text(
          t.s.body,
          weight: FontWeight.w700,
          color: onRemove == null ? t.c.textMuted : t.c.danger,
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        start: Space.s4,
        end: Space.s2,
        top: Space.s2,
        bottom: Space.s2,
      ),
      child: Row(
        spacing: Space.s3,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(serviceTitle(context, service), style: t.text(t.s.body)),
                Text(
                  statusLabel(l, service.statusAt(shikooNow())),
                  style: t.text(t.s.bodySm, color: t.c.textMuted),
                ),
              ],
            ),
          ),
          Semantics(
            button: true,
            enabled: onRemove != null,
            label: l.removeServiceLabel(serviceTitle(context, service)),
            excludeSemantics: true,
            child: onRemove == null
                ? remove
                : Pressable(
                    shape: RoundedSuperellipseBorder(
                      borderRadius: BorderRadius.circular(Radii.sm),
                    ),
                    onPressed: onRemove,
                    builder: (context, _) => remove,
                  ),
          ),
        ],
      ),
    );
  }
}

/// `.row`: an icon, a title over a line of help, then a value or a forward chevron.
class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.title,
    this.rich,
    this.subtitle,
    this.value,
    this.icon,
    this.forward = false,
    this.down = false,
    this.danger = false,
    this.alert = false,
    this.busy = false,
    this.keys = const [],
    this.autofocus = false,
    this.onPressed,
  });

  final String title;
  final bool autofocus;

  /// `.value + .icon`: a small ⌄ after the value, for a row that opens a list of choices.
  final bool down;

  /// The subtitle in red, as `.row small.danger`.
  final bool alert;

  /// `.keys`: a shortcut that opens the same page, before the chevron.
  final List<String> keys;

  /// The title with bold parts.
  final List<InlineSpan>? rich;
  final String? subtitle;
  final String? value;
  final ShikooIcon? icon;
  final bool forward;
  final bool danger;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final s = t.s;
    final shape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(Radii.md),
    );
    final ink = danger ? t.c.danger : t.c.text;
    // The icons are drawn for Persian; English mirrors them, as `.flip-ltr`.
    final ltr = Directionality.of(context) == TextDirection.ltr;
    final icon = this.icon;
    final subtitle = this.subtitle;
    final value = this.value;
    final texts = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (rich case final rich?)
          Text.rich(
            TextSpan(children: rich),
            style: t.text(s.body, color: ink),
          )
        else
          Text(title, style: t.text(s.body, color: ink)),
        if (subtitle != null)
          Text(
            subtitle,
            style: t.text(s.bodySm, color: alert ? t.c.danger : t.c.textMuted),
          ),
      ],
    );
    Widget row(bool focused) => Container(
      constraints: BoxConstraints(minHeight: s.row),
      padding: const EdgeInsets.symmetric(
        horizontal: Space.s4,
        vertical: Space.s3,
      ),
      decoration: ShapeDecoration(
        color: focused ? t.c.focusBg : null,
        shadows: focused ? t.c.raisedShadow : null,
        shape: shape,
      ),
      child: Row(
        spacing: Space.s3,
        children: [
          if (busy)
            Spinner(size: s.icon, color: t.c.textMuted)
          else if (icon != null)
            Transform.flip(
              flipX: ltr,
              child: SvgIcon(
                icon,
                size: s.icon,
                color: danger ? ink : t.c.textMuted,
              ),
            ),
          Expanded(
            child: value == null
                ? texts
                // `.row:has(> .value)` wraps: a value that does not fit goes under its label.
                : Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: Space.s3,
                    runSpacing: Space.s1,
                    children: [
                      texts,
                      // Never wraps or clips: at 320 with font 1.45 the core shrinks a little.
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          value,
                          style: t.text(
                            s.body,
                            color: t.c.textMuted,
                            height: Leading.body,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
          if (keys.isNotEmpty)
            Directionality(
              textDirection: TextDirection.ltr,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: Space.s1,
                children: [for (final key in keys) _Key(key)],
              ),
            ),
          if (down)
            SvgIcon(
              ShikooIcon.chevronDown,
              size: s.iconSm,
              color: t.c.textMuted,
            ),
          if (forward)
            Transform.flip(
              flipX: ltr,
              child: SvgIcon(
                ShikooIcon.chevronFwd,
                size: s.icon,
                color: t.c.textMuted,
              ),
            ),
        ],
      ),
    );
    final onPressed = this.onPressed;
    if (onPressed == null) return row(false);
    return Pressable(
      shape: shape,
      autofocus: autofocus,
      onPressed: onPressed,
      builder: (context, focused) => row(focused),
    );
  }
}

/// Option «الف»: a kind of server and its core; its list opens from here, under it on a computer.
/// A protocol with one core is a plain row like the version's, which the remote passes over.
class _CoreRow extends ConsumerWidget {
  const _CoreRow({super.key, required this.row});

  final ShikooCoreRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = ShikooL10n.of(context);
    final locked = shikooOnlyCores.containsKey(row.protocol);
    return _Row(
      title: protocolLabel(l, row.protocol),
      value: coreLabel(l, row.chosen),
      down: !locked,
      onPressed: locked ? null : () => unawaited(pickCore(context, ref, row)),
    );
  }
}

/// `.kbd`: a key cap whose lower edge is darker, as the mockup's inset shadow.
class _Key extends StatelessWidget {
  const _Key(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final shape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(Radii.sm),
    );
    const edge = 2.0;
    return Container(
      padding: const EdgeInsets.only(bottom: edge),
      decoration: ShapeDecoration(color: t.c.border, shape: shape),
      child: Container(
        constraints: const BoxConstraints(
          minWidth: ShikooSizes.key,
          minHeight: ShikooSizes.key - edge,
        ),
        padding: const EdgeInsets.symmetric(horizontal: Space.s2),
        alignment: Alignment.center,
        decoration: ShapeDecoration(color: t.c.surfaceSunken, shape: shape),
        child: Text(
          label,
          style: t.text(
            t.s.caption,
            weight: FontWeight.w700,
            color: t.c.textMuted,
            height: 1,
          ),
        ),
      ),
    );
  }
}
