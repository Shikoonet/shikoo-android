import 'dart:async';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:fl_clash/shikoo/engine/account.dart';
import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/settings.dart';
import 'package:fl_clash/shikoo/engine/update.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/clock.dart';
import 'package:fl_clash/shikoo/ui/dialogs.dart';
import 'package:fl_clash/shikoo/ui/focus.dart';
import 'package:fl_clash/shikoo/ui/home.dart';
import 'package:fl_clash/shikoo/ui/icons.dart';
import 'package:fl_clash/shikoo/ui/paste.dart';
import 'package:fl_clash/shikoo/ui/report.dart';
import 'package:fl_clash/shikoo/ui/settings.dart';
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:fl_clash/shikoo/ui/update.dart';
import 'package:fl_clash/shikoo/ui/widgets.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// Home once this device holds a service, else sign-in. A TV without one never sees home: its
/// `tv-home-no-service` gave way to `tv-login`.
final shikooHomeShownProvider = Provider<bool>((ref) {
  final hasService = ref.watch(
    shikooStateProvider.select((s) => s.service != null),
  );
  return ref.watch(shikooLoginProvider) == null &&
      (hasService || ref.watch(shikooAccountProvider).withoutLink.isNotEmpty);
});

class ShikooRoot extends ConsumerWidget {
  const ShikooRoot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(
      shikooUpdateOfferProvider.select((o) => o?.forced ?? false),
    )) {
      return const ForcedUpdatePage();
    }
    if (ref.watch(shikooHomeShownProvider)) return const ShikooHome();
    final login = ref.watch(shikooLoginProvider);
    final account = ref.watch(shikooAccountProvider);
    return LoginPage(
      login:
          login ??
          (account.who == null
              ? null
              : ShikooLogin(LoginPhase.noService, account: account.who)),
    );
  }
}

/// Frames `phone-login*` and `tv-login*`; a null [login] is the first screen.
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key, required this.login});

  final ShikooLogin? login;

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

/// The phases that show a code; the rest show a result.
const _coding = {
  null,
  LoginPhase.starting,
  LoginPhase.startFailed,
  LoginPhase.waiting,
  LoginPhase.expired,
};

class _LoginPageState extends ConsumerState<LoginPage> {
  /// `phone-login-no-telegram`: the same code as a QR and digits, for another device.
  bool _otherDevice = false;

  final _supportNode = FocusNode();
  final _newCodeNode = FocusNode();
  final _retryNode = FocusNode();
  final _warpNode = FocusNode();
  final _resultNode = FocusNode();
  final _chooseNode = FocusNode();
  final _notMineNode = FocusNode();
  final _firstChoiceNode = FocusNode();

  /// Every service starts ticked; these were unticked on the checklist.
  final _unticked = <int>{};

  ShikooSignIn get _signIn => ref.read(shikooSignInProvider);

  bool get _isTV => ref.read(shikooStateProvider).isTV;

  @override
  void initState() {
    super.initState();
    _startOnTv();
    _focusFirst();
  }

  @override
  void didUpdateWidget(LoginPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _startOnTv();
    if (!_coding.contains(widget.login?.phase)) _otherDevice = false;
    if (widget.login?.phase != LoginPhase.choosing) _unticked.clear();
    if (_first(oldWidget.login?.phase) != _first(widget.login?.phase)) {
      _focusFirst();
    }
  }

  @override
  void dispose() {
    _supportNode.dispose();
    _newCodeNode.dispose();
    _retryNode.dispose();
    _warpNode.dispose();
    _resultNode.dispose();
    _chooseNode.dispose();
    _notMineNode.dispose();
    _firstChoiceNode.dispose();
    super.dispose();
  }

  /// Where each frame puts the remote, wherever it was before the screen changed by itself.
  FocusNode _first(LoginPhase? phase) => switch (phase) {
    null || LoginPhase.starting || LoginPhase.waiting => _supportNode,
    LoginPhase.expired => _newCodeNode,
    LoginPhase.startFailed
        when !(widget.login?.clock ?? false) &&
            !ref.read(shikooStateProvider).bridge.on =>
      _warpNode,
    LoginPhase.startFailed => _retryNode,
    LoginPhase.choosing => _chooseNode,
    _ => _resultNode,
  };

  void _toggle(int id) => setState(() {
    if (!_unticked.remove(id)) _unticked.add(id);
  });

  /// Null while nothing is ticked, which greys «ادامه» out.
  VoidCallback? _choose(ShikooLogin login) {
    final ticked = {
      for (final service in login.choices)
        if (!_unticked.contains(service.id)) service.id,
    };
    return ticked.isEmpty ? null : () => unawaited(_signIn.choose(ticked));
  }

  void _focusFirst() {
    if (!_isTV) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _first(widget.login?.phase).requestFocus();
    });
  }

  /// The TV has no first screen to press through: it shows a code at once.
  void _startOnTv() {
    if (widget.login == null && _isTV) {
      scheduleMicrotask(() => unawaited(_signIn.start()));
    }
  }

  void _open(String? link) {
    if (link == null) return;
    unawaited(launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication));
  }

  Future<void> _telegram() async => _open(await _signIn.start());

  /// «امتحان از راه WARP»: the switch on, then the code asked for again.
  Future<void> _tryWarp() async {
    await ref.read(shikooControllerProvider).setBridge(true);
    _isTV ? await _signIn.start() : await _telegram();
  }

  Future<void> _otherAccount() async {
    await _signIn.notMine();
    if (!_isTV) await _telegram();
  }

  void _showOtherDevice() {
    setState(() => _otherDevice = true);
    if (!{
      LoginPhase.starting,
      LoginPhase.waiting,
      LoginPhase.expired,
    }.contains(widget.login?.phase)) {
      unawaited(_signIn.start());
    }
  }

  /// No report where a sign-in code may show: its pictures would carry the code.
  void _support() => unawaited(
    openSupport(
      context,
      isTV: _isTV,
      trigger: _coding.contains(widget.login?.phase) ? null : 'login',
    ),
  );

  void _report() => unawaited(openReport(context, 'login'));

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final isTV = ref.watch(shikooStateProvider.select((s) => s.isTV));
    final login = widget.login;
    final Widget page = isTV
        ? _tv(context, login)
        : PageWidth(
            child: _otherDevice
                ? _phoneOtherDevice(context, login)
                : _phone(context, login),
          );
    // Signing in from settings, with pasted services: Back goes home to them. A checklist is
    // never left that way: Back closes the app, and it is still there on the next open.
    final home =
        login != null &&
        login.phase != LoginPhase.choosing &&
        ref.watch(shikooStateProvider.select((s) => s.service != null));
    return PopScope(
      canPop: !_otherDevice && !home,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _otherDevice ? setState(() => _otherDevice = false) : _signIn.finish();
      },
      child: Scaffold(
        backgroundColor: t.c.bg,
        body: PageFocusScope(
          child: FocusTraversalGroup(
            policy: PageTraversalPolicy(),
            child: page,
          ),
        ),
      ),
    );
  }

  Widget _language() {
    final l = ShikooL10n.of(context);
    final look = ref.watch(shikooLookProvider);
    return Segmented(
      small: true,
      selected: look.language,
      options: {'fa': l.languageFa, 'en': l.languageEn},
      onSelect: (language) => unawaited(
        ref.read(shikooLookProvider.notifier).setLanguage(language),
      ),
    );
  }

  Widget _paste({required bool enabled, bool dateButton = true}) {
    final l = ShikooL10n.of(context);
    return PasteLink(
      onAdded: (_) => _signIn.finish(),
      report: false,
      dateButton: dateButton,
      builder: (context, busy, paste) => ShikooButton(
        label: busy ? l.pasteChecking : l.pasteLink,
        icon: ShikooIcon.paste,
        busy: busy,
        height: ShikooSizes.touch,
        onPressed: enabled ? paste : null,
      ),
    );
  }

  /// `.login`: language in a corner, the brand or a result in the middle, the actions below.
  Widget _phone(BuildContext context, ShikooLogin? login) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final phase = login?.phase;
    final account = login?.account;
    final clock = login?.clock ?? false;
    final starting = phase == LoginPhase.starting;
    final offerWarp = !ref.watch(
      shikooStateProvider.select((s) => s.bridge.on),
    );
    final viaWarp =
        starting && ref.watch(shikooStateProvider.select((s) => s.bridge.door));
    Widget telegram(String label, VoidCallback onPressed) => ShikooButton(
      label: starting ? l.codeFetching : label,
      icon: ShikooIcon.plane,
      telegram: true,
      busy: starting,
      onPressed: starting ? () {} : onPressed,
    );
    Widget primary(String label, VoidCallback? onPressed, {ShikooIcon? icon}) =>
        ShikooButton(
          label: label,
          icon: icon,
          primary: true,
          height: ShikooSizes.touch,
          onPressed: onPressed,
        );
    Widget outline(String label, VoidCallback onPressed, {ShikooIcon? icon}) =>
        ShikooButton(
          label: label,
          icon: icon,
          height: ShikooSizes.touch,
          onPressed: onPressed,
        );
    void signIn() => unawaited(_telegram());
    final elsewhere = LinkButton(
      label: (shikooDesktop ? l.noTelegramHereDesktop : l.noTelegramHere),
      onPressed: starting ? null : _showOtherDevice,
    );
    ResultBlock chosen({bool start = false}) => ResultBlock(
      icon: ShikooIcon.check,
      tone: ResultTone.positive,
      title: l.approvedTitle,
      body: sayWith(
        (shikooDesktop
            ? l.approvedBodyChooseDesktop
            : l.approvedBodyChooseTouch),
        _account(l, account),
      ),
      start: start,
    );
    List<Widget> choose() => [
      primary(l.continueButton, _choose(login!)),
      outline(l.notMyAccount, () => unawaited(_signIn.notMine())),
    ];
    if (phase == LoginPhase.choosing &&
        identical(t.s, ShikooSizes.desktop) &&
        MediaQuery.sizeOf(context).width >= ShikooSizes.twoColumns) {
      return _split(chosen(start: true), choose(), _checklist(login!));
    }
    final warp = offerWarp && !clock;
    final failedBox = MessageBox(
      icon: ShikooIcon.alert,
      danger: true,
      strong: clock ? l.clockWrongTitle : l.codeFailedTitle,
      rest: clock
          ? l.clockWrongHelp
          : switch ((shikooDesktop, warp)) {
              (true, true) => l.warpLoginFailDesktop,
              (false, true) => l.warpLoginFailTouch,
              (true, false) => l.codeFailedHelpDesktop,
              (false, false) => l.codeFailedHelpTouch,
            },
    );
    // A computer keeps the buttons at the bottom, and WARP's two lines would push them out of a small
    // window: the message takes the brand's place above them, where it is seen without scrolling.
    final failedAbove = shikooDesktop && warp;
    final waitBox = MessageBox(
      icon: ShikooIcon.spin,
      strong: l.warpLoginWaitTitle,
      rest: l.warpLoginWait,
    );
    final (Widget middle, List<Widget> actions) = switch (phase) {
      null || LoginPhase.starting => (
        shikooDesktop && viaWarp ? waitBox : const _BrandBlock(),
        [
          if (viaWarp && !shikooDesktop) waitBox,
          telegram(l.loginTelegram, signIn),
          Text(
            shikooDesktop ? l.loginTelegramNoteDesktop : l.loginTelegramNote,
            textAlign: TextAlign.center,
            style: t.text(t.s.bodySm, color: t.c.textMuted),
          ),
          _paste(enabled: !starting),
          elsewhere,
        ],
      ),
      LoginPhase.startFailed => (
        failedAbove ? failedBox : const _BrandBlock(),
        [
          if (!failedAbove) failedBox,
          if (clock)
            const DateSettingsButton()
          else ...[
            if (warp)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                // A computer's foot is short of room: the line keeps close under its button.
                spacing: shikooDesktop ? Space.s2 : Space.s4,
                children: [
                  outline(l.warpTry, () => unawaited(_tryWarp())),
                  Text(
                    l.warpNote,
                    textAlign: TextAlign.center,
                    style: t.text(t.s.bodySm, color: t.c.textMuted),
                  ),
                ],
              ),
            LinkButton(label: l.reportSendToSupport, onPressed: _report),
          ],
          telegram(l.loginTelegram, signIn),
          _paste(enabled: true, dateButton: !clock),
          elsewhere,
        ],
      ),
      LoginPhase.waiting => (
        const _BrandBlock(),
        [
          MessageBox(
            icon: ShikooIcon.spin,
            strong: l.waitingTitle,
            rest: l.waitingHelp,
          ),
          telegram(l.reopenTelegram, () => _open(login?.botUrl)),
          _paste(enabled: true),
          LinkButton(label: l.approveElsewhere, onPressed: _showOtherDevice),
        ],
      ),
      LoginPhase.expired => (
        const _BrandBlock(),
        [
          MessageBox(
            icon: ShikooIcon.alert,
            strong: l.codeExpiredNote,
            rest: '',
          ),
          telegram(l.loginTelegram, signIn),
          _paste(enabled: true),
          elsewhere,
        ],
      ),
      LoginPhase.rejected => (
        ResultBlock(
          icon: ShikooIcon.x,
          tone: ResultTone.danger,
          title: l.rejectedTitle,
          body: [
            TextSpan(
              text: (shikooDesktop
                  ? l.rejectedBodyDesktop
                  : l.rejectedBodyTouch),
            ),
          ],
        ),
        [telegram(l.loginTelegram, signIn), _paste(enabled: true)],
      ),
      LoginPhase.syncing || LoginPhase.approved => (
        ResultBlock(
          icon: ShikooIcon.check,
          tone: ResultTone.positive,
          title: l.approvedTitle,
          body: sayWith(
            login!.services.length == 1
                ? (shikooDesktop
                      ? l.approvedBodyOneDesktop
                      : l.approvedBodyOneTouch)
                : (shikooDesktop ? l.approvedBodyDesktop : l.approvedBodyTouch),
            _account(l, account),
          ),
          below: _ServicesBelow(login: login),
        ),
        [
          if (phase == LoginPhase.approved)
            primary(l.continueButton, _signIn.finish),
          outline(l.notMyAccount, () => unawaited(_signIn.notMine())),
        ],
      ),
      LoginPhase.choosing => (
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.s4,
          children: [chosen(), _checklist(login!)],
        ),
        choose(),
      ),
      LoginPhase.servicesFailed => (
        ResultBlock(
          icon: ShikooIcon.alert,
          tone: ResultTone.danger,
          title: l.servicesFailedTitle,
          body: clock
              ? [TextSpan(text: clockText(l))]
              : sayWith(
                  (shikooDesktop
                      ? l.servicesFailedBodyDesktop
                      : l.servicesFailedBodyTouch),
                  _account(l, account),
                ),
        ),
        [
          primary(
            l.retry,
            () => unawaited(_signIn.retry()),
            icon: ShikooIcon.refresh,
          ),
          if (clock) const DateSettingsButton(),
          outline(l.support, _support),
          outline(l.notMyAccount, () => unawaited(_signIn.notMine())),
        ],
      ),
      LoginPhase.noService => (
        ResultBlock(
          icon: ShikooIcon.alert,
          tone: ResultTone.muted,
          title: l.noServiceTitle,
          body: sayWith(l.noServiceBodyTouch, _account(l, account)),
        ),
        [
          MessageBox(
            icon: ShikooIcon.plane,
            strong: '',
            rest: shikooDesktop ? l.noServiceHelpDesktop : l.noServiceHelpTouch,
          ),
          telegram(l.otherAccount, () => unawaited(_otherAccount())),
          outline(
            l.logout,
            () => unawaited(_signIn.notMine()),
            icon: ShikooIcon.logout,
          ),
          LinkButton(label: l.askSupportLink, onPressed: _support),
        ],
      ),
    };
    final language = !const {
      LoginPhase.syncing,
      LoginPhase.choosing,
      LoginPhase.approved,
      LoginPhase.servicesFailed,
      LoginPhase.noService,
    }.contains(phase);
    return SafeArea(
      minimum: const EdgeInsets.only(bottom: Space.s8),
      child: FillPage(
        packed: phase == LoginPhase.choosing,
        padding: const EdgeInsets.fromLTRB(Space.s6, Space.s2, Space.s6, 0),
        top: language
            ? Align(
                alignment: AlignmentDirectional.centerEnd,
                child: _language(),
              )
            : const SizedBox.shrink(),
        middle: Center(child: middle),
        bottom: actions,
      ),
    );
  }

  /// `.split` in win-fit.html, a wide computer window's `tv-p3a-login`: the result and its
  /// buttons at the start, the checklist beside them, each column scrolling on its own.
  Widget _split(Widget result, List<Widget> actions, Widget list) {
    final s = ShikooTheme.of(context).s;
    Widget column(Widget child, {double end = 0}) => FocusTraversalGroup(
      child: Center(
        child: EdgeScroll(
          padding: EdgeInsetsDirectional.only(
            top: Space.s6,
            bottom: Space.s6,
            end: end,
          ),
          child: child,
        ),
      ),
    );
    // The list's region runs on into the window's margin, so its bar sits there, not on the rows.
    return Padding(
      padding: EdgeInsetsDirectional.only(start: s.safeX),
      child: Row(
        spacing: Space.s10,
        children: [
          Expanded(
            child: column(
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: Space.s6,
                children: [
                  result,
                  Center(
                    child: SizedBox(
                      width: ShikooSizes.splitButtons,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: Space.s4,
                        children: actions,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            width: s.pane + s.safeX,
            child: column(list, end: s.safeX),
          ),
        ],
      ),
    );
  }

  /// `.alt-login`: the code for a phone with Telegram's camera, or a computer's keyboard.
  Widget _phoneOtherDevice(BuildContext context, ShikooLogin? login) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final s = t.s;
    final lead = t.text(s.body, height: Leading.body);
    final phase = login?.phase;
    final button =
        phase == LoginPhase.startFailed || phase == LoginPhase.expired;
    final before = [
      Text(
        shikooDesktop ? l.otherDeviceScanDesktop : l.otherDeviceScan,
        textAlign: TextAlign.center,
        style: lead,
      ),
      _Qr(login: login),
      if (phase != LoginPhase.startFailed) ...[
        Text(l.otherDeviceComputer, textAlign: TextAlign.center, style: lead),
        _CodeBox(login: login),
      ],
    ];
    final after = [
      if (button)
        ShikooButton(
          label: phase == LoginPhase.expired ? l.newCode : l.retry,
          icon: ShikooIcon.refresh,
          primary: true,
          onPressed: () => unawaited(_signIn.start()),
        ),
      if (phase == LoginPhase.startFailed && login!.clock)
        const DateSettingsButton(),
      Text(
        phase != LoginPhase.startFailed
            ? l.otherDeviceFine
            : (login!.clock
                  ? clockText(l)
                  : (shikooDesktop
                        ? l.codeFailedHelpDesktop
                        : l.codeFailedHelpTouch)),
        textAlign: TextAlign.center,
        style: t.text(s.bodySm, color: t.c.textMuted, height: Leading.body),
      ),
    ];
    Widget column(List<Widget> children) => PaneColumn(
      child: Column(spacing: Space.s4, children: children),
    );
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: s.appbar,
            padding: EdgeInsetsDirectional.only(start: Space.s1, end: s.safeX),
            child: Row(
              spacing: Space.s1,
              children: [
                ShikooIconButton(
                  icon: ShikooIcon.back,
                  label: l.back,
                  flipInLtr: true,
                  onPressed: () => setState(() => _otherDevice = false),
                ),
                Expanded(
                  child: Text(
                    l.otherDeviceTitle,
                    style: t.text(s.title, weight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: button && identical(s, ShikooSizes.desktop)
                ? _StuckButtons(
                    packed: true,
                    trailing: Space.s10 - Space.s6,
                    body: EdgeScroll(
                      divider: true,
                      padding: const EdgeInsets.fromLTRB(
                        Space.s6,
                        Space.s2,
                        Space.s6,
                        Space.s4 - Space.s3,
                      ),
                      child: column(before),
                    ),
                    foot: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Space.s6,
                        Space.s3,
                        Space.s6,
                        Space.s6,
                      ),
                      child: column(after),
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      Space.s6,
                      Space.s2,
                      Space.s6,
                      Space.s10,
                    ),
                    child: column([...before, ...after]),
                  ),
          ),
        ],
      ),
    );
  }

  /// `.tv-top` over `.tv-login` (a code) or `.tv-result`.
  Widget _tv(BuildContext context, ShikooLogin? login) {
    final t = ShikooTheme.of(context);
    final s = t.s;
    final phase = login?.phase;
    final coding = _coding.contains(phase);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: s.safeX, vertical: s.safeY),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: s.appbar + 2 * ShikooSizes.ring,
            padding: const EdgeInsets.symmetric(horizontal: ShikooSizes.ring),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [const Brand(), if (coding) _language()],
            ),
          ),
          Expanded(
            child: coding
                ? _tvCode(context, login)
                : _tvResult(context, login!),
          ),
        ],
      ),
    );
  }

  /// `tv-login`, `tv-login-loading`, `tv-login-code-failed` and `tv-login-expired`.
  Widget _tvCode(BuildContext context, ShikooLogin? login) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final s = t.s;
    final phase = login?.phase;
    final expired = phase == LoginPhase.expired;
    final failed = phase == LoginPhase.startFailed;
    final offerWarp = !ref.watch(
      shikooStateProvider.select((s) => s.bridge.on),
    );
    final viaWarp =
        phase == LoginPhase.starting &&
        ref.watch(shikooStateProvider.select((s) => s.bridge.door));
    final fine = t.text(s.bodySm, color: t.c.textMuted, height: Leading.body);
    Widget newCode(String label, FocusNode node) => ShikooButton(
      label: label,
      icon: ShikooIcon.refresh,
      primary: true,
      focusNode: node,
      onPressed: () => unawaited(_signIn.start()),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.s8),
      child: Row(
        children: [
          Expanded(
            // The padding keeps the focus ring of «کد تازه» in view.
            child: ShrinkToFit(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.s2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: Space.s3,
                  children: [
                    Text(
                      l.loginTelegram,
                      style: t.text(s.headline, weight: FontWeight.w800),
                    ),
                    Text(
                      failed
                          ? (login!.clock
                                ? clockText(l)
                                : (offerWarp
                                      ? '${l.codeFailedTitle} ${l.warpLoginFailTv}'
                                      : l.codeFailedLeadTv))
                          : (expired
                                ? l.codeExpiredLead
                                : (viaWarp
                                      ? '${l.warpLoginWaitTitle} ${l.warpLoginWait}'
                                      : l.tvLoginLead)),
                      style: t.text(s.title),
                    ),
                    if (failed && login!.clock) ...[
                      newCode(l.retry, _retryNode),
                      const DateSettingsButton(),
                    ] else if (failed) ...[
                      Wrap(
                        spacing: Space.s2,
                        runSpacing: Space.s2,
                        children: [
                          newCode(l.retry, _retryNode),
                          ShikooButton(
                            label: l.reportSendToSupport,
                            icon: ShikooIcon.report,
                            onPressed: _report,
                          ),
                        ],
                      ),
                      if (offerWarp) ...[
                        ShikooButton(
                          label: l.warpTry,
                          focusNode: _warpNode,
                          onPressed: () => unawaited(_tryWarp()),
                        ),
                        Text(l.warpNote, style: fine),
                      ],
                    ] else ...[
                      if (!expired) Text(l.tvLoginVpnHint, style: fine),
                      _CodeBox(
                        login: login,
                        label: expired ? l.previousCode : l.tvLoginComputer,
                      ),
                      if (expired)
                        newCode(l.newCode, _newCodeNode)
                      else
                        Text(l.codeLifetime, style: fine),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: Space.s16),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: Space.s3,
            children: [
              _Qr(login: login, large: true),
              if (!expired)
                ShikooButton(
                  label: l.support,
                  icon: ShikooIcon.qr,
                  focusNode: _supportNode,
                  onPressed: _support,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _checklist(ShikooLogin login) => _Checklist(
    choices: login.choices,
    unticked: _unticked,
    onToggle: _toggle,
    firstNode: _firstChoiceNode,
  );

  /// [key] takes the remote to [to], where the frame says, not to the nearest box; the buttons
  /// may wrap under large text.
  Widget _redirect(
    LogicalKeyboardKey key,
    FocusNode Function() to,
    Widget child,
  ) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onKeyEvent: (_, event) {
      if (event is KeyUpEvent || event.logicalKey != key) {
        return KeyEventResult.ignored;
      }
      jumpFocus(context, to());
      return KeyEventResult.handled;
    },
    child: child,
  );

  /// `tv-p3a-login`: the result and its buttons at the start, the checklist beside them.
  Widget _tvChoose(BuildContext context, ShikooLogin login) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final go = _choose(login);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final toStart = rtl
        ? LogicalKeyboardKey.arrowRight
        : LogicalKeyboardKey.arrowLeft;
    final toEnd = rtl
        ? LogicalKeyboardKey.arrowLeft
        : LogicalKeyboardKey.arrowRight;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: ShikooSizes.ring),
      child: Row(
        spacing: Space.s10,
        children: [
          Expanded(
            child: ShrinkToFit(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.s2),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: Space.s4,
                  children: [
                    ResultBlock(
                      icon: ShikooIcon.check,
                      tone: ResultTone.positive,
                      title: l.approvedTitle,
                      body: sayWith(
                        l.approvedBodyChooseTv,
                        _account(l, login.account),
                      ),
                      start: true,
                    ),
                    _redirect(
                      toEnd,
                      () => _chooseNode.hasPrimaryFocus
                          ? _notMineNode
                          : _firstChoiceNode,
                      Wrap(
                        spacing: Space.s2,
                        runSpacing: Space.s2,
                        children: [
                          ShikooButton(
                            label: l.continueButton,
                            primary: true,
                            focusNode: _chooseNode,
                            onPressed: go,
                          ),
                          ShikooButton(
                            label: l.notMyAccount,
                            focusNode: _notMineNode,
                            onPressed: () => unawaited(_signIn.notMine()),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(
            width: t.s.pane,
            child: _redirect(
              toStart,
              () => go == null ? _notMineNode : _chooseNode,
              _checklist(login),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tvResult(BuildContext context, ShikooLogin login) {
    if (login.phase == LoginPhase.choosing) return _tvChoose(context, login);
    final l = ShikooL10n.of(context);
    final account = _account(l, login.account);
    Widget Function(FocusNode?) button(
      String label,
      VoidCallback onPressed, {
      ShikooIcon? icon,
      bool primary = false,
    }) =>
        (node) => ShikooButton(
          label: label,
          icon: icon,
          primary: primary,
          focusNode: node,
          onPressed: onPressed,
        );
    final notMine = button(l.notMyAccount, () => unawaited(_signIn.notMine()));
    final support = button(l.support, _support, icon: ShikooIcon.qr);
    final (result, actions) = switch (login.phase) {
      LoginPhase.rejected => (
        ResultBlock(
          icon: ShikooIcon.x,
          tone: ResultTone.danger,
          title: l.rejectedTitle,
          body: [TextSpan(text: l.rejectedBodyTv)],
        ),
        [
          button(
            l.newCode,
            () => unawaited(_signIn.start()),
            icon: ShikooIcon.refresh,
            primary: true,
          ),
        ],
      ),
      LoginPhase.syncing || LoginPhase.approved => (
        ResultBlock(
          icon: ShikooIcon.check,
          tone: ResultTone.positive,
          title: l.approvedTitle,
          body: sayWith(
            login.services.length == 1 ? l.approvedBodyOneTv : l.approvedBodyTv,
            account,
          ),
          below: _ServicesBelow(login: login),
        ),
        [
          if (login.phase == LoginPhase.approved)
            button(l.continueButton, _signIn.finish, primary: true),
          notMine,
        ],
      ),
      LoginPhase.servicesFailed => (
        ResultBlock(
          icon: ShikooIcon.alert,
          tone: ResultTone.danger,
          title: l.servicesFailedTitle,
          body: login.clock
              ? [TextSpan(text: clockText(l))]
              : sayWith(l.servicesFailedBodyTv, account),
        ),
        [
          button(
            l.retry,
            () => unawaited(_signIn.retry()),
            icon: ShikooIcon.refresh,
            primary: true,
          ),
          if (login.clock)
            (FocusNode? node) => DateSettingsButton(focusNode: node),
          support,
          notMine,
        ],
      ),
      _ => (
        ResultBlock(
          icon: ShikooIcon.alert,
          tone: ResultTone.muted,
          title: l.noServiceTitle,
          body: sayWith(l.noServiceBodyTv, account),
          more: l.noServiceHelpTv,
        ),
        [
          button(
            l.otherAccount,
            () => unawaited(_otherAccount()),
            icon: ShikooIcon.refresh,
            primary: true,
          ),
          support,
        ],
      ),
    };
    return Center(
      child: ShrinkToFit(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.s2,
            Space.s2,
            Space.s2,
            Space.s2 + Space.s2,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: Space.s6,
            children: [
              result,
              Row(
                mainAxisSize: MainAxisSize.min,
                spacing: Space.s2,
                children: [
                  for (final (i, action) in actions.indexed)
                    action(i == 0 ? _resultNode : null),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The display name in bold beside the `@username`, as the bot's account is shown: a display
/// name is not unique. The username keeps left-to-right inside Persian.
List<InlineSpan> _account(ShikooL10n l, TelegramAccount? who) {
  const bold = TextStyle(fontWeight: FontWeight.w700);
  final name = who?.name?.trim() ?? '';
  final handle = who?.username;
  final username = handle == null || handle.isEmpty
      ? null
      : '\u2066@$handle\u2069';
  if (name.isEmpty) return [TextSpan(text: username ?? '', style: bold)];
  if (username == null) return [TextSpan(text: name, style: bold)];
  return sayWith((part) => l.accountWithUsername(part, username), [
    TextSpan(text: name, style: bold),
  ]);
}

/// Fills the screen and scrolls only when large text does not fit; on a computer only what is above
/// the buttons scrolls, they keep to the bottom.
class FillPage extends StatelessWidget {
  const FillPage({
    super.key,
    required this.padding,
    required this.top,
    required this.middle,
    required this.bottom,
    this.packed = false,
  });

  final EdgeInsets padding;
  final Widget top;
  final Widget middle;
  final List<Widget> bottom;

  /// `.login.is-choosing`: from the top, the buttons right under the list.
  final bool packed;

  @override
  Widget build(BuildContext context) {
    final actions = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.s4,
      children: bottom,
    );
    if (identical(ShikooTheme.of(context).s, ShikooSizes.desktop)) {
      // A window far taller than a phone would split them into two islands: they stay one group.
      return _StuckButtons(
        packed: packed,
        give: (bottom.length - 1) * (Space.s4 - Space.s2) + Space.s3,
        trailing: packed ? padding.bottom : Space.s4 + padding.bottom,
        body: EdgeScroll(
          divider: true,
          padding: EdgeInsets.fromLTRB(
            padding.left,
            padding.top,
            padding.right,
            (packed ? Space.s4 : Space.s6) - Space.s3,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              top,
              Padding(
                padding: const EdgeInsets.only(top: Space.s4),
                child: PaneColumn(child: middle),
              ),
            ],
          ),
        ),
        foot: Padding(
          padding: EdgeInsets.fromLTRB(padding.left, 0, padding.right, 0),
          child: PaneColumn(
            child: _Gaps(lead: Space.s3, children: bottom),
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        padding: padding,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: box.maxHeight - padding.vertical,
          ),
          // spaceBetween, not IntrinsicHeight and Expanded: ServiceName lays out by its width.
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: packed
                ? MainAxisAlignment.start
                : MainAxisAlignment.spaceBetween,
            children: [
              top,
              PaneColumn(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.s4),
                  child: middle,
                ),
              ),
              PaneColumn(child: actions),
            ],
          ),
        ),
      ),
    );
  }
}

/// `.stuck` in win-fit.html, a computer only: [body] and [foot] as one group while they fit,
/// centred unless [packed], with [trailing] under it; once they do not, [foot] keeps to the
/// bottom and [body] scrolls above it; with less room than a touch target the page scrolls as one.
class _StuckButtons extends StatelessWidget {
  const _StuckButtons({
    required this.body,
    required this.foot,
    required this.trailing,
    this.packed = false,
    this.give = 0,
  });

  final Widget body;
  final Widget foot;
  final double trailing;
  final bool packed;

  final double give;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => EdgeScroll(
      padding: EdgeInsets.zero,
      child: _Stuck(
        look: (
          page: box.maxHeight,
          least: MediaQuery.textScalerOf(context).scale(ShikooSizes.touch),
          trailing: trailing,
          packed: packed,
          give: give,
        ),
        children: [body, foot],
      ),
    ),
  );
}

typedef _Look = ({
  double page,
  double least,
  double trailing,
  bool packed,
  double give,
});

class _Stuck extends MultiChildRenderObjectWidget {
  const _Stuck({required this.look, required super.children});

  final _Look look;

  @override
  _RenderStuck createRenderObject(BuildContext context) => _RenderStuck(look);

  @override
  void updateRenderObject(BuildContext context, _RenderStuck renderObject) =>
      renderObject.look = look;
}

class _RenderStuck extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, MultiChildLayoutParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, MultiChildLayoutParentData> {
  _RenderStuck(this._look);

  _Look _look;

  set look(_Look look) {
    if (look == _look) return;
    _look = look;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! MultiChildLayoutParentData) {
      child.parentData = MultiChildLayoutParentData();
    }
  }

  @override
  void performLayout() {
    final body = firstChild!;
    final foot = childAfter(body)!;
    final width = constraints.maxWidth;
    foot.layout(BoxConstraints.tightFor(width: width), parentUsesSize: true);
    final (:page, :least, :trailing, :packed, :give) = _look;
    body.layout(BoxConstraints.tightFor(width: width), parentUsesSize: true);
    final short = body.size.height + foot.size.height - page;
    if (short > 0 && give > 0) {
      foot.layout(
        BoxConstraints.tightFor(width: width).copyWith(
          maxHeight: math.max(
            foot.size.height - short,
            foot.size.height - give,
          ),
        ),
        parentUsesSize: true,
      );
    }
    final room = page - foot.size.height;
    // Loose first: the body's own height while it fits, and the same scroll extent it ends with.
    body.layout(
      BoxConstraints(
        minWidth: width,
        maxWidth: width,
        maxHeight: room < least ? double.infinity : room,
      ),
      parentUsesSize: true,
    );
    final free = room - body.size.height - trailing;
    final pinned = room >= least || free >= 0;
    if (pinned && free > 0 && !packed) {
      body.layout(
        BoxConstraints.tightFor(
          width: width,
          height: body.size.height + free / 2,
        ),
        parentUsesSize: true,
      );
    }
    final under = pinned && free < 0 ? room : body.size.height;
    (foot.parentData! as MultiChildLayoutParentData).offset = Offset(0, under);
    size = constraints.constrain(
      Size(width, pinned ? page : under + foot.size.height + trailing),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

/// [FillPage]'s buttons on a computer, [Space.s4] apart; short of room under [_RenderStuck], the gaps
/// give way evenly down to [Space.s2], then the [lead] above them, before the page above them scrolls.
class _Gaps extends MultiChildRenderObjectWidget {
  const _Gaps({required this.lead, required super.children});

  final double lead;

  @override
  _RenderGaps createRenderObject(BuildContext context) => _RenderGaps(lead);

  @override
  void updateRenderObject(BuildContext context, _RenderGaps renderObject) =>
      renderObject.lead = lead;
}

class _RenderGaps extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, MultiChildLayoutParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, MultiChildLayoutParentData> {
  _RenderGaps(this._lead);

  double _lead;

  set lead(double lead) {
    if (lead == _lead) return;
    _lead = lead;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! MultiChildLayoutParentData) {
      child.parentData = MultiChildLayoutParentData();
    }
  }

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    final children = getChildrenAsList();
    for (final child in children) {
      child.layout(BoxConstraints.tightFor(width: width), parentUsesSize: true);
    }
    final gaps = children.length - 1;
    final over = math.max(
      0.0,
      children.map((child) => child.size.height).sum +
          _lead +
          gaps * Space.s4 -
          constraints.maxHeight,
    );
    final closed = math.min(over, gaps * (Space.s4 - Space.s2));
    final each = gaps == 0 ? 0.0 : Space.s4 - closed / gaps;
    var y = math.max(0.0, _lead - (over - closed));
    for (final child in children) {
      (child.parentData! as MultiChildLayoutParentData).offset = Offset(0, y);
      y += child.size.height + each;
    }
    size = constraints.constrain(Size(width, y - each));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

/// `.login-brand`: the large mark, the name and who the app is for.
class _BrandBlock extends StatelessWidget {
  const _BrandBlock();

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const BrandMark(size: ShikooSizes.markLg),
        const SizedBox(height: Space.s3 + Space.s2),
        Text(l.appName, style: t.text(t.s.headline, weight: FontWeight.w800)),
        const SizedBox(height: Space.s3),
        Text(
          l.loginTagline,
          textAlign: TextAlign.center,
          style: t.text(t.s.bodySm, color: t.c.textMuted),
        ),
      ],
    );
  }
}

enum ResultTone { positive, danger, muted }

/// `.hero-icon` over the result's title, its sentence and, after it, [below].
class ResultBlock extends StatelessWidget {
  const ResultBlock({
    super.key,
    required this.icon,
    required this.tone,
    required this.title,
    required this.body,
    this.more,
    this.below,
    this.spin = false,
    this.start = false,
  });

  final ShikooIcon icon;
  final bool spin;
  final ResultTone tone;
  final String title;
  final List<InlineSpan> body;
  final String? more;
  final Widget? below;

  /// `.login-copy`: lined up at the start, beside a list, not centred.
  final bool start;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final c = t.c;
    final s = t.s;
    final tv = identical(s, ShikooSizes.tv);
    final (fill, ink) = switch (tone) {
      ResultTone.positive => (c.positiveSoft, c.positive),
      ResultTone.danger => (c.dangerSoft, c.danger),
      ResultTone.muted => (c.surfaceSunken, c.textMuted),
    };
    final paragraph = t.text(
      tv ? s.title : s.bodySm,
      color: c.textMuted,
      height: Leading.body,
    );
    final more = this.more;
    final below = this.below;
    final align = start ? TextAlign.start : TextAlign.center;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: tv ? s.dialog : double.infinity),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: start
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        spacing: Space.s3,
        children: [
          Container(
            width: s.heroIcon,
            height: s.heroIcon,
            decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: spin
                ? Spinner(size: s.heroIcon / 2, color: ink)
                : SvgIcon(
                    icon,
                    size: s.heroIcon / 2,
                    stroke: ShikooSizes.iconStrokeStrong,
                    color: ink,
                  ),
          ),
          Padding(
            padding: EdgeInsets.only(top: tv ? 0 : Space.s2),
            child: Text(
              title,
              textAlign: align,
              style: t.text(s.headline, weight: FontWeight.w800),
            ),
          ),
          if (body.isNotEmpty)
            Text.rich(
              TextSpan(children: body),
              textAlign: align,
              style: paragraph,
            ),
          if (more != null) Text(more, textAlign: align, style: paragraph),
          ?below,
        ],
      ),
    );
  }
}

/// `.result-list` once the account's services are on this device; until then `.progress`.
class _ServicesBelow extends StatelessWidget {
  const _ServicesBelow({required this.login});

  final ShikooLogin login;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    if (login.phase == LoginPhase.syncing) {
      return Column(
        spacing: Space.s2,
        children: [
          SizedBox(
            width: ShikooSizes.qrSm * 0.8,
            child: LinearProgressIndicator(
              value: MediaQuery.disableAnimationsOf(context) ? 0.4 : null,
              minHeight: t.s.bar,
              color: t.c.primary,
              backgroundColor: t.c.surfaceSunken,
              borderRadius: BorderRadius.circular(t.s.bar),
            ),
          ),
          Text(
            l.servicesComing,
            style: t.text(t.s.bodySm, color: t.c.textMuted),
          ),
        ],
      );
    }
    final services = login.services;
    // tv-login-approved-many: four lines at most, so the page fits the screen of a box.
    final more = identical(t.s, ShikooSizes.tv) && services.length > 4
        ? services.length - 3
        : 0;
    final style = t.text(
      t.s.title,
      weight: FontWeight.w700,
      height: Leading.snug,
    );
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.s8,
        vertical: Space.s2,
      ),
      decoration: ShapeDecoration(
        color: t.c.surface,
        shadows: t.c.cardShadow,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: Space.s1,
        children: [
          for (final title in more > 0 ? services.take(3) : services)
            ServiceName(
              title,
              style: style,
              textAlign: TextAlign.center,
              twoLines: true,
            ),
          if (more > 0)
            Text(
              l.approvedMoreServices(more),
              textAlign: TextAlign.center,
              style: style.copyWith(
                color: t.c.textMuted,
                fontWeight: FontWeight.w400,
              ),
            ),
        ],
      ),
    );
  }
}

/// `.choose`: the question, a ticked row for each of the account's services, finished ones too,
/// and under them why «ادامه» is grey. On a TV more than five scroll under the remote.
class _Checklist extends StatelessWidget {
  const _Checklist({
    required this.choices,
    required this.unticked,
    required this.onToggle,
    required this.firstNode,
  });

  final List<LinkedService> choices;
  final Set<int> unticked;
  final ValueChanged<int> onToggle;
  final FocusNode firstNode;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final s = t.s;
    final tv = identical(s, ShikooSizes.tv);
    final inset = EdgeInsets.symmetric(horizontal: tv ? ShikooSizes.ring : 0);
    final card = DecoratedBox(
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
          for (final (i, service) in choices.indexed) ...[
            if (i > 0) Container(height: 1, color: t.c.border),
            _ChoiceRow(
              service: service,
              ticked: !unticked.contains(service.id),
              focusNode: i == 0 ? firstNode : null,
              onPressed: () => onToggle(service.id),
            ),
          ],
        ],
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.s2,
      children: [
        Padding(
          padding: inset,
          child: Text(
            tv
                ? l.chooseServicesTv
                : (shikooDesktop
                      ? l.chooseServicesDesktop
                      : l.chooseServicesTouch),
            style: t.text(
              tv ? s.title : s.body,
              weight: FontWeight.w700,
              height: Leading.tight,
            ),
          ),
        ),
        if (tv)
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(ShikooSizes.ring),
              child: card,
            ),
          )
        else
          card,
        if (choices.every((service) => unticked.contains(service.id)))
          Padding(
            padding: inset,
            child: Text(
              l.chooseAtLeastOne,
              style: t.text(
                s.bodySm,
                color: t.c.textMuted,
                height: Leading.tight,
              ),
            ),
          ),
      ],
    );
  }
}

/// `.choose .row`: the tick, then the service's name and, for one that ended, home's chip.
class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.service,
    required this.ticked,
    required this.onPressed,
    this.focusNode,
  });

  final LinkedService service;
  final bool ticked;
  final VoidCallback onPressed;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final c = t.c;
    final s = t.s;
    final shape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(Radii.md),
    );
    return MergeSemantics(
      child: Semantics(
        checked: ticked,
        child: Pressable(
          focusNode: focusNode,
          shape: shape,
          onPressed: onPressed,
          builder: (context, focused) => Container(
            constraints: BoxConstraints(minHeight: s.row),
            padding: const EdgeInsets.symmetric(
              horizontal: Space.s4,
              vertical: Space.s2,
            ),
            decoration: ShapeDecoration(
              color: focused ? c.focusBg : null,
              shadows: focused ? c.raisedShadow : null,
              shape: shape,
            ),
            child: Row(
              spacing: Space.s3,
              children: [
                Container(
                  width: ShikooSizes.checkbox,
                  height: ShikooSizes.checkbox,
                  alignment: Alignment.center,
                  decoration: ShapeDecoration(
                    color: ticked ? c.primary : null,
                    shape: RoundedSuperellipseBorder(
                      borderRadius: BorderRadius.circular(Radii.checkbox),
                      side: ticked
                          ? BorderSide.none
                          : BorderSide(
                              color: c.outline,
                              width: ShikooSizes.borderRadio,
                            ),
                    ),
                  ),
                  child: ticked
                      ? SvgIcon(
                          ShikooIcon.check,
                          size: ShikooSizes.checkbox - Space.s1,
                          stroke: ShikooSizes.iconStrokeStrong,
                          color: c.onPrimary,
                        )
                      : null,
                ),
                Expanded(
                  child: Wrap(
                    spacing: Space.s2,
                    runSpacing: Space.s1,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ServiceName(
                        service.title,
                        style: t.text(
                          s.body,
                          weight: FontWeight.w700,
                          height: Leading.snug,
                        ),
                        twoLines: true,
                      ),
                      if (service.finished) StatusChip.linked(service),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The QR of the bot link; an empty tile while the code comes or when it did not, faded once
/// it expired.
class _Qr extends StatelessWidget {
  const _Qr({required this.login, this.large = false});

  final ShikooLogin? login;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final phase = login?.phase;
    final link = login?.botUrl;
    Widget over(Widget icon, String text, Color color) => Column(
      mainAxisSize: MainAxisSize.min,
      spacing: Space.s2,
      children: [
        icon,
        Text(
          text,
          textAlign: TextAlign.center,
          style: t.text(t.s.title, weight: FontWeight.w700, color: color),
        ),
      ],
    );
    final size = t.s.heroIcon / 2;
    return QrTile(
      data: link,
      large: large,
      over: switch (phase) {
        LoginPhase.expired => over(
          SvgIcon(ShikooIcon.refresh, size: size, color: ShikooColors.onQrBg),
          l.codeExpiredOverlay,
          ShikooColors.onQrBg,
        ),
        LoginPhase.startFailed => over(
          SvgIcon(ShikooIcon.alert, size: size, color: t.c.text),
          l.codeFailedOverlay,
          t.c.text,
        ),
        _ when link == null => over(
          Spinner(size: size, color: t.c.text),
          l.codeFetching,
          t.c.text,
        ),
        _ => null,
      },
    );
  }
}

/// The six digits in the UI's numerals, two groups of three, read from three metres.
String _digits(BuildContext context, String code) {
  final local = [
    for (final digit in code.split('')) localNumber(context, int.parse(digit)),
  ].join();
  return local.length == 6
      ? '${local.substring(0, 3)} ${local.substring(3)}'
      : local;
}

/// `.code-box`: the code, the bot to send it to and a warning not to pass it on.
class _CodeBox extends StatelessWidget {
  const _CodeBox({required this.login, this.label});

  final ShikooLogin? login;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final s = t.s;
    final code = login?.code;
    final expired = login?.phase == LoginPhase.expired;
    final bot =
        Uri.tryParse(login?.botUrl ?? '')?.pathSegments.firstOrNull ??
        ShikooLinks.bot;
    final label = this.label;
    final digits = t
        .text(
          s.code,
          weight: FontWeight.w800,
          color: expired ? t.c.textMuted : t.c.text,
        )
        .copyWith(
          wordSpacing: s.code * ShikooSizes.codeWordSpacing,
          decoration: expired ? TextDecoration.lineThrough : null,
          decorationColor: t.c.textMuted,
        );
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.s6,
        vertical: Space.s4,
      ),
      decoration: ShapeDecoration(
        color: t.c.surface,
        shadows: t.c.cardShadow,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: Space.s2,
        children: [
          if (label != null)
            Text(
              label,
              textAlign: TextAlign.center,
              style: t.text(s.body, color: t.c.textMuted),
            ),
          if (code == null)
            ExcludeSemantics(
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  color: t.c.surfaceSunken,
                  shape: RoundedSuperellipseBorder(
                    borderRadius: BorderRadius.circular(Radii.sm),
                  ),
                ),
                child: Text(
                  _digits(context, '000000'),
                  textDirection: TextDirection.ltr,
                  style: digits.copyWith(color: Colors.transparent),
                ),
              ),
            )
          else
            Text(
              _digits(context, code),
              textDirection: TextDirection.ltr,
              style: digits,
            ),
          if (!expired) ...[
            Row(
              mainAxisSize: MainAxisSize.min,
              spacing: Space.s2,
              children: [
                SvgIcon(
                  ShikooIcon.plane,
                  size: s.icon,
                  color: ShikooColors.telegram,
                ),
                Text(
                  '@$bot',
                  textDirection: TextDirection.ltr,
                  style: t.text(s.body, weight: FontWeight.w700),
                ),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              spacing: Space.s2,
              children: [
                SvgIcon(ShikooIcon.alert, size: s.iconSm, color: t.c.warning),
                Flexible(
                  child: Text(
                    l.codeOnlyYou,
                    style: t.text(s.bodySm, color: t.c.textMuted),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
