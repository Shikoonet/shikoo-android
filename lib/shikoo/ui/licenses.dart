part of 'settings.dart';

/// The cores' packages as LicenseRegistry names them: the Go modules (tools/shikoo-go-licenses.py) and the native
/// library. A core this build lacks registers nothing, so it gets no row.
const _corePackages = [
  'github.com/metacubex/mihomo',
  'github.com/xtls/xray-core',
  'github.com/sagernet/sing-box',
  'golang.zx2c4.com/wireguard',
  'OpenVPN 3',
];

String _coreTitle(ShikooL10n l, String package) => switch (package) {
  'github.com/metacubex/mihomo' => l.coreMihomo,
  'github.com/xtls/xray-core' => l.coreXray,
  'github.com/sagernet/sing-box' => l.coreSingBox,
  'golang.zx2c4.com/wireguard' => l.protocolWireguard,
  _ => package,
};

/// Every package Flutter, the Dart packages and the cores registered, with its licence texts.
Future<Map<String, List<LicenseEntry>>> _licensesByPackage() async {
  final byPackage = <String, List<LicenseEntry>>{};
  await for (final entry in LicenseRegistry.licenses) {
    for (final package in entry.packages) {
      (byPackage[package] ??= []).add(entry);
    }
  }
  return byPackage;
}

/// Shape «ب» of design/mockups/licenses-options.html: the cores first, then every other package A to Z.
class ShikooLicenses extends ConsumerStatefulWidget {
  const ShikooLicenses({super.key});

  @override
  ConsumerState<ShikooLicenses> createState() => _ShikooLicensesState();
}

class _ShikooLicensesState extends ConsumerState<ShikooLicenses> {
  final _byPackage = _licensesByPackage();

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final isTV = ref.watch(shikooStateProvider.select((state) => state.isTV));
    return SubPage(
      title: l.licensesTitle,
      isTV: isTV,
      scrolls: !isTV,
      child: FutureBuilder(
        future: _byPackage,
        builder: (context, snapshot) {
          final byPackage = snapshot.data;
          if (byPackage == null) return const SizedBox.shrink();
          var first = isTV;
          Widget row(String package, String title, {bool core = false}) {
            final entries = byPackage[package]!;
            final count = l.licenseCount(entries.length);
            final autofocus = first;
            first = false;
            return _Row(
              title: title,
              subtitle: core && package != title
                  ? '${bidiName(package)} · $count'
                  : count,
              forward: true,
              autofocus: autofocus,
              onPressed: () => unawaited(
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        ShikooLicenseText(title: title, entries: entries),
                    settings: const RouteSettings(name: 'license'),
                  ),
                ),
              ),
            );
          }

          final cores = [
            for (final package in _corePackages)
              if (byPackage.containsKey(package))
                row(package, _coreTitle(l, package), core: true),
          ];
          final others =
              byPackage.keys.where((p) => !_corePackages.contains(p)).toList()
                ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
          // shortcut: every row is built at once (some 460 on Android); a lazy list if a box stutters here.
          final column = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.s6,
            children: [
              if (cores.isNotEmpty)
                _Group(
                  title: l.coresGroup,
                  child: _Card(rows: cores),
                ),
              _Group(
                title: l.licensesOthers,
                child: _Card(
                  rows: [for (final p in others) row(p, bidiName(p))],
                ),
              ),
            ],
          );
          return isTV
              ? Center(
                  child: SizedBox(
                    width: t.s.pane + 2 * Space.s8,
                    child: TvScrollColumn(
                      child: Center(
                        child: SizedBox(width: t.s.pane, child: column),
                      ),
                    ),
                  ),
                )
              : column;
        },
      ),
    );
  }
}

/// One package's licence texts, English and left to right in a card. On the TV the card is one item under the remote,
/// whose Up and Down scroll it a part of a screen at a time.
class ShikooLicenseText extends ConsumerWidget {
  const ShikooLicenseText({
    super.key,
    required this.title,
    required this.entries,
  });

  final String title;
  final List<LicenseEntry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final isTV = ref.watch(shikooStateProvider.select((state) => state.isTV));
    final style = t.text(isTV ? t.s.body : t.s.bodySm, height: Leading.body);
    final text = Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.s2,
        children: [
          for (final (i, entry) in entries.indexed) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.s3),
                child: Container(height: 1, color: t.c.border),
              ),
            for (final paragraph in entry.paragraphs)
              paragraph.indent == LicenseParagraph.centeredIndent
                  ? Text(
                      paragraph.text,
                      textAlign: TextAlign.center,
                      style: style,
                    )
                  : Padding(
                      padding: EdgeInsets.only(
                        left: Space.s4 * paragraph.indent,
                      ),
                      child: Text(paragraph.text, style: style),
                    ),
          ],
        ],
      ),
    );
    if (!isTV) {
      return SubPage(
        title: title,
        isTV: false,
        child: _Card(
          rows: [Padding(padding: const EdgeInsets.all(Space.s4), child: text)],
        ),
      );
    }
    return SubPage(
      title: title,
      isTV: true,
      scrolls: false,
      hint: l.licenseScrollTv,
      child: Center(
        child: SizedBox(
          width: t.s.pane * 1.5,
          height: double.infinity,
          child: Padding(
            padding: const EdgeInsets.only(bottom: ShikooSizes.ring),
            child: _TvLicenseText(child: text),
          ),
        ),
      ),
    );
  }
}

class _TvLicenseText extends StatefulWidget {
  const _TvLicenseText({required this.child});

  final Widget child;

  @override
  State<_TvLicenseText> createState() => _TvLicenseTextState();
}

class _TvLicenseTextState extends State<_TvLicenseText> {
  final _scroll = ScrollController();
  bool _scrolled = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final scrolled = _scroll.offset > 0;
      if (scrolled != _scrolled) setState(() => _scrolled = scrolled);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  KeyEventResult _key(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final step = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowDown => 1,
      LogicalKeyboardKey.arrowUp => -1,
      _ => 0,
    };
    if (step == 0 || !_scroll.hasClients) return KeyEventResult.ignored;
    final position = _scroll.position;
    final to = clampDouble(
      position.pixels + step * position.viewportDimension * 3 / 4,
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(to);
    } else {
      unawaited(
        _scroll.animateTo(
          to,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        ),
      );
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _key,
      child: Pressable(
        autofocus: true,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
        onPressed: () {},
        builder: (context, _) => _Card(
          rows: [
            Expanded(
              child: RawScrollbar(
                controller: _scroll,
                thumbVisibility: true,
                thickness: ShikooSizes.scrollThumb,
                radius: const Radius.circular(ShikooSizes.scrollThumb),
                thumbColor: t.c.outline,
                child: ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (rect) => LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      _scrolled ? Colors.transparent : Colors.black,
                      Colors.black,
                    ],
                    stops: [0, ShikooSizes.fade / rect.height],
                  ).createShader(rect),
                  child: SingleChildScrollView(
                    controller: _scroll,
                    padding: const EdgeInsets.all(Space.s4),
                    child: widget.child,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
