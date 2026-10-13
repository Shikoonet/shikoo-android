import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:fl_clash/shikoo/ui/widgets.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _title = 17.0;
const _smallest = _title * ShikooSizes.nameShrinkMin;

/// The test font draws every letter, space and «·» one em wide, and the isolates none.
Future<(Text, RenderParagraph)> _name(
  WidgetTester tester,
  String name, {
  double width = 200,
  bool twoLines = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: shikooThemeData(Brightness.light, tv: false),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Align(
          alignment: Alignment.topRight,
          child: SizedBox(
            width: width,
            child: ServiceName(name, twoLines: twoLines),
          ),
        ),
      ),
    ),
  );
  final text = find.descendant(
    of: find.byType(ServiceName),
    matching: find.byType(Text),
  );
  return (
    tester.widget<Text>(text),
    tester.renderObject<RenderParagraph>(
      find.descendant(of: text, matching: find.byType(RichText)),
    ),
  );
}

int _lines(RenderParagraph paragraph) => paragraph
    .getBoxesForSelection(
      TextSelection(
        baseOffset: 0,
        extentOffset: paragraph.text.toPlainText().length,
      ),
    )
    .map((box) => box.top.round())
    .toSet()
    .length;

void main() {
  testWidgets('a name that fits stays on one line at the full size', (
    tester,
  ) async {
    final (text, paragraph) = await _name(tester, 'ab · cd');
    expect(text.style!.fontSize, _title);
    expect(text.data, bidiName('ab · cd'));
    expect(_lines(paragraph), 1);
  });

  testWidgets('the tier goes under the username before the font shrinks', (
    tester,
  ) async {
    final (text, paragraph) = await _name(tester, 'abcdefghij · klmnop');
    expect(text.style!.fontSize, _title);
    expect(text.data, isNot(contains('…')));
    expect(text.data!.split('\n').last, startsWith('·'));
    expect(_lines(paragraph), 2);
  });

  testWidgets('two lines too narrow: the font steps down, nothing is cut', (
    tester,
  ) async {
    final (text, paragraph) = await _name(tester, 'abcdefghijkl · klmnop');
    expect(text.style!.fontSize, lessThan(_title));
    expect(text.style!.fontSize, greaterThan(_smallest));
    expect(text.data, isNot(contains('…')));
    expect(text.data, contains('abcdefghijkl'));
    expect(_lines(paragraph), 2);
    expect(paragraph.size.width, lessThanOrEqualTo(200));
  });

  testWidgets('at the smallest size the username is cut in the middle, its '
      'last five kept, and the tier stays whole', (tester) async {
    final (text, paragraph) = await _name(tester, 'aaaaaaaaaaaaaaa12345 · xy');
    expect(text.style!.fontSize, _smallest);
    expect(text.data, contains('a…12345'));
    expect(text.data!.split('\n').last, isNot(contains('…')));
    expect(text.data, contains('xy'));
    expect(_lines(paragraph), 2);
    expect(paragraph.size.width, lessThanOrEqualTo(200));
  });

  testWidgets('last of all the tier ends in «…», never below the smallest '
      'size, never past two lines', (tester) async {
    for (final user in ['abcdefghij', 'aaaaaaaaaaaaaaa12345']) {
      final (text, paragraph) = await _name(
        tester,
        '$user · klmnopqrstuvwxyzABCDE',
      );
      expect(text.style!.fontSize, _smallest, reason: user);
      final [first, second] = text.data!.split('\n');
      expect(first, user.length > 10 ? contains('…12345') : contains(user));
      expect(second, contains('klmnopqrstuv…'), reason: user);
      expect(_lines(paragraph), 2, reason: user);
      expect(paragraph.size.width, lessThanOrEqualTo(200), reason: user);
    }
  });

  testWidgets('without twoLines a name keeps its size and only the cut', (
    tester,
  ) async {
    final (text, _) = await _name(
      tester,
      'aaaaaaaaaaaaaaa12345 · xy',
      twoLines: false,
    );
    expect(text.style!.fontSize, _title);
    expect(text.data, bidiName('aaaaa…12345 · xy'));
  });
}
