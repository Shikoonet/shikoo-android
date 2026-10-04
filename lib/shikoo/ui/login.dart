import 'dart:async';

import 'package:collection/collection.dart';
import 'package:fl_clash/shikoo/engine/account.dart';
import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/settings.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/dialogs.dart';
import 'package:fl_clash/shikoo/ui/focus.dart';
import 'package:fl_clash/shikoo/ui/home.dart';
import 'package:fl_clash/shikoo/ui/icons.dart';
import 'package:fl_clash/shikoo/ui/paste.dart';
import 'package:fl_clash/shikoo/ui/settings.dart';
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:fl_clash/shikoo/ui/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// Home once this device holds a service, else sign-in. A TV without one never sees home: its
/// `tv-home-no-service` gave way to `tv-login`.
class ShikooRoot extends ConsumerWidget {
  const ShikooRoot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final login = ref.watch(shikooLoginProvider);
    final account = ref.watch(shikooAccountProvider);
    final hasService = ref.watch(
      shikooStateProvider.select((s) => s.service != null),
    );
    if (login == null && (hasService || account.withoutLink.isNotEmpty)) {
      return const ShikooHome();
    }
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
  final _resultNode = FocusNode();

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
    if (_first(oldWidget.login?.phase) != _first(widget.login?.phase)) {
      _focusFirst();
    }
  }

  @override
  void dispose() {
    _supportNode.dispose();
    _newCodeNode.dispose();
    _retryNode.dispose();
    _resultNode.dispose();
    super.dispose();
  }

  /// Where each frame puts the remote, wherever it was before the screen changed by itself.
  FocusNode _first(LoginPhase? phase) => switch (phase) {
    null || LoginPhase.starting || LoginPhase.waiting => _supportNode,
    LoginPhase.expired => _newCodeNode,
    LoginPhase.startFailed => _retryNode,
    _ => _resultNode,
  };

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

  void _support() {
    final l = ShikooL10n.of(context);
    openLink(
      context,
      isTV: _isTV,
      link: ShikooLinks.support,
      title: l.supportTitle,
      help: l.supportHelpTv,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final isTV = ref.watch(shikooStateProvider.select((s) => s.isTV));
    final login = widget.login;
    final Widget page = isTV
        ? _tv(context, login)
        : (_otherDevice
              ? _phoneOtherDevice(context, login)
              : _phone(context, login));
    // Signing in from settings, with pasted services: Back goes home to them.
    final home =
        login != null &&
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

  Widget _paste({required bool enabled}) {
    final l = ShikooL10n.of(context);
    return PasteLink(
      onAdded: _signIn.finish,
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
    final starting = phase == LoginPhase.starting;
    Widget telegram(String label, VoidCallback onPressed) => ShikooButton(
      label: starting ? l.codeFetching : label,
      icon: ShikooIcon.plane,
      telegram: true,
      busy: starting,
      onPressed: starting ? () {} : onPressed,
    );
    Widget primary(String label, VoidCallback onPressed, {ShikooIcon? icon}) =>
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
    final elsewhere = _LinkButton(
      label: l.noTelegramHere,
      onPressed: starting ? null : _showOtherDevice,
    );
    final (Widget middle, List<Widget> actions) = switch (phase) {
      null || LoginPhase.starting => (
        const _BrandBlock(),
        [
          telegram(l.loginTelegram, signIn),
          Text(
            l.loginTelegramNote,
            textAlign: TextAlign.center,
            style: t.text(t.s.bodySm, color: t.c.textMuted),
          ),
          _paste(enabled: !starting),
          elsewhere,
        ],
      ),
      LoginPhase.startFailed => (
        const _BrandBlock(),
        [
          MessageBox(
            icon: ShikooIcon.alert,
            danger: true,
            strong: l.codeFailedTitle,
            rest: l.codeFailedHelpTouch,
          ),
          telegram(l.loginTelegram, signIn),
          _paste(enabled: true),
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
          _LinkButton(label: l.approveElsewhere, onPressed: _showOtherDevice),
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
        _Result(
          icon: ShikooIcon.x,
          tone: _Tone.danger,
          title: l.rejectedTitle,
          body: [TextSpan(text: l.rejectedBodyTouch)],
        ),
        [telegram(l.loginTelegram, signIn), _paste(enabled: true)],
      ),
      LoginPhase.syncing || LoginPhase.approved => (
        _Result(
          icon: ShikooIcon.check,
          tone: _Tone.positive,
          title: l.approvedTitle,
          body: sayWith(l.approvedBodyTouch, _account(l, account)),
          below: _ServicesBelow(login: login!),
        ),
        [
          if (phase == LoginPhase.approved)
            primary(l.continueButton, _signIn.finish),
          outline(l.notMyAccount, () => unawaited(_signIn.notMine())),
        ],
      ),
      LoginPhase.servicesFailed => (
        _Result(
          icon: ShikooIcon.alert,
          tone: _Tone.danger,
          title: l.servicesFailedTitle,
          body: sayWith(l.servicesFailedBodyTouch, _account(l, account)),
        ),
        [
          primary(
            l.retry,
            () => unawaited(_signIn.retry()),
            icon: ShikooIcon.refresh,
          ),
          outline(l.support, _support),
          outline(l.notMyAccount, () => unawaited(_signIn.notMine())),
        ],
      ),
      LoginPhase.noService => (
        _Result(
          icon: ShikooIcon.alert,
          tone: _Tone.muted,
          title: l.noServiceTitle,
          body: sayWith(l.noServiceBodyTouch, _account(l, account)),
        ),
        [
          MessageBox(
            icon: ShikooIcon.plane,
            strong: '',
            rest: l.noServiceHelpTouch,
          ),
          telegram(l.otherAccount, () => unawaited(_otherAccount())),
          outline(
            l.logout,
            () => unawaited(_signIn.notMine()),
            icon: ShikooIcon.logout,
          ),
          _LinkButton(label: l.askSupportLink, onPressed: _support),
        ],
      ),
    };
    final language = !const {
      LoginPhase.syncing,
      LoginPhase.approved,
      LoginPhase.servicesFailed,
      LoginPhase.noService,
    }.contains(phase);
    return SafeArea(
      minimum: const EdgeInsets.only(bottom: Space.s8),
      child: _Fill(
        padding: const EdgeInsets.fromLTRB(Space.s6, Space.s2, Space.s6, 0),
        children: [
          if (language)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: _language(),
            ),
          Expanded(child: Center(child: middle)),
          ...actions,
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
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                Space.s6,
                Space.s2,
                Space.s6,
                Space.s10,
              ),
              child: Column(
                spacing: Space.s4,
                children: [
                  Text(
                    l.otherDeviceScan,
                    textAlign: TextAlign.center,
                    style: lead,
                  ),
                  _Qr(login: login),
                  if (phase != LoginPhase.startFailed) ...[
                    Text(
                      l.otherDeviceComputer,
                      textAlign: TextAlign.center,
                      style: lead,
                    ),
                    _CodeBox(login: login),
                  ],
                  if (phase == LoginPhase.startFailed ||
                      phase == LoginPhase.expired)
                    ShikooButton(
                      label: phase == LoginPhase.expired ? l.newCode : l.retry,
                      icon: ShikooIcon.refresh,
                      primary: true,
                      onPressed: () => unawaited(_signIn.start()),
                    ),
                  Text(
                    l.otherDeviceFine,
                    textAlign: TextAlign.center,
                    style: t.text(
                      s.bodySm,
                      color: t.c.textMuted,
                      height: Leading.body,
                    ),
                  ),
                ],
              ),
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
          SizedBox(
            height: s.appbar,
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
            // Scrolls only for large text; the padding keeps the focus ring in view.
            child: SingleChildScrollView(
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
                        ? l.codeFailedLeadTv
                        : (expired ? l.codeExpiredLead : l.tvLoginLead),
                    style: t.text(s.title),
                  ),
                  if (failed)
                    newCode(l.retry, _retryNode)
                  else ...[
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

  Widget _tvResult(BuildContext context, ShikooLogin login) {
    final l = ShikooL10n.of(context);
    final account = _account(l, login.account);
    ShikooButton Function(FocusNode?) button(
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
        _Result(
          icon: ShikooIcon.x,
          tone: _Tone.danger,
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
        _Result(
          icon: ShikooIcon.check,
          tone: _Tone.positive,
          title: l.approvedTitle,
          body: sayWith(l.approvedBodyTv, account),
          below: _ServicesBelow(login: login),
        ),
        [
          if (login.phase == LoginPhase.approved)
            button(l.continueButton, _signIn.finish, primary: true),
          notMine,
        ],
      ),
      LoginPhase.servicesFailed => (
        _Result(
          icon: ShikooIcon.alert,
          tone: _Tone.danger,
          title: l.servicesFailedTitle,
          body: sayWith(l.servicesFailedBodyTv, account),
        ),
        [
          button(
            l.retry,
            () => unawaited(_signIn.retry()),
            icon: ShikooIcon.refresh,
            primary: true,
          ),
          support,
          notMine,
        ],
      ),
      _ => (
        _Result(
          icon: ShikooIcon.alert,
          tone: _Tone.muted,
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
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Space.s2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: Space.s4,
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

/// Fills the screen and scrolls only when large text does not fit.
class _Fill extends StatelessWidget {
  const _Fill({required this.padding, required this.children});

  final EdgeInsets padding;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => SingleChildScrollView(
      padding: padding,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: box.maxHeight - padding.vertical,
        ),
        child: IntrinsicHeight(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.s4,
            children: children,
          ),
        ),
      ),
    ),
  );
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
        Text(l.appTitle, style: t.text(t.s.headline, weight: FontWeight.w800)),
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

enum _Tone { positive, danger, muted }

/// `.hero-icon` over the result's title, its sentence and, after it, [below].
class _Result extends StatelessWidget {
  const _Result({
    required this.icon,
    required this.tone,
    required this.title,
    required this.body,
    this.more,
    this.below,
  });

  final ShikooIcon icon;
  final _Tone tone;
  final String title;
  final List<InlineSpan> body;
  final String? more;
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final c = t.c;
    final s = t.s;
    final tv = identical(s, ShikooSizes.tv);
    final (fill, ink) = switch (tone) {
      _Tone.positive => (c.positiveSoft, c.positive),
      _Tone.danger => (c.dangerSoft, c.danger),
      _Tone.muted => (c.surfaceSunken, c.textMuted),
    };
    final paragraph = t.text(
      tv ? s.title : s.bodySm,
      color: c.textMuted,
      height: Leading.body,
    );
    final more = this.more;
    final below = this.below;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: tv ? s.dialog : double.infinity),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: tv ? Space.s4 : Space.s3,
        children: [
          Container(
            width: s.heroIcon,
            height: s.heroIcon,
            decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: SvgIcon(
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
              textAlign: TextAlign.center,
              style: t.text(s.headline, weight: FontWeight.w800),
            ),
          ),
          Text.rich(
            TextSpan(children: body),
            textAlign: TextAlign.center,
            style: paragraph,
          ),
          if (more != null)
            Text(more, textAlign: TextAlign.center, style: paragraph),
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
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.s8,
        vertical: Space.s3,
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
          for (final title in login.services)
            Text(
              title,
              textAlign: TextAlign.center,
              style: t.text(
                t.s.title,
                weight: FontWeight.w700,
                height: Leading.snug,
              ),
            ),
        ],
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

/// `.btn-link`: an underlined line of text that is a button; greyed out with no [onPressed].
class _LinkButton extends StatelessWidget {
  const _LinkButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final onPressed = this.onPressed;
    Widget text() => Container(
      constraints: const BoxConstraints(minHeight: ShikooSizes.touch),
      padding: const EdgeInsets.symmetric(horizontal: Space.s3),
      alignment: Alignment.center,
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: t
            .text(
              t.s.bodySm,
              weight: FontWeight.w700,
              color: onPressed == null ? t.c.textMuted : t.c.text,
            )
            .copyWith(decoration: TextDecoration.underline),
      ),
    );
    return Center(
      child: onPressed == null
          ? text()
          : Pressable(
              shape: RoundedSuperellipseBorder(
                borderRadius: BorderRadius.circular(Radii.sm),
              ),
              onPressed: onPressed,
              builder: (context, _) => Semantics(button: true, child: text()),
            ),
    );
  }
}
