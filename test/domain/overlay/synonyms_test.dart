import 'package:hollow_court/domain/overlay/synonyms.dart';
import 'package:test/test.dart';

/// Equivalent names, tested against the examples that motivated the feature.
///
/// The owner's list, verbatim: *"利口酒和力娇/力娇酒指的是同一个东西，安高天娜和安哥斯图拉也是如此，马天尼和马提尼同理，
/// 类似的还有菲士与菲兹、金酒与琴酒、蓝柑与蓝橙"*. Each of those pairs is a test below, because each is a
/// case somebody actually met in a bar.
void main() {
  test('**the six examples from the owner are all one thing**', () {
    const block = '''
# 同一件东西的不同叫法
利口酒 = 力娇, 力娇酒
安高天娜 = 安哥斯图拉
马天尼 = 马提尼
菲士 = 菲兹
金酒 = 琴酒
蓝柑 = 蓝橙
''';
    final parsed = parseSynonymBlock(block);
    expect(parsed.ok, isTrue, reason: parsed.problems.map((p) => p.reason).join('; '));
    expect(parsed.groups, hasLength(6));

    for (final pair in const [
      ('力娇', '利口酒'),
      ('力娇酒', '利口酒'),
      ('安哥斯图拉', '安高天娜'),
      ('马提尼', '马天尼'),
      ('菲兹', '菲士'),
      ('琴酒', '金酒'),
      ('蓝橙', '蓝柑'),
    ]) {
      expect(canonicalNameOf(pair.$1, parsed.groups), pair.$2, reason: pair.$1);
      expect(canonicalNameOf(pair.$2, parsed.groups), pair.$2, reason: 'the canonical name is itself');
    }
    expect(canonicalNameOf('金酒', parsed.groups), '金酒');
    expect(canonicalNameOf('没定义过的东西', parsed.groups), isNull);
  });

  test('a group names every equivalent, from either end', () {
    final parsed = parseSynonymBlock('金酒 = 琴酒, 杜松子酒');
    expect(synonymsOf('金酒', parsed.groups), ['琴酒', '杜松子酒']);
    expect(synonymsOf('琴酒', parsed.groups), ['金酒', '杜松子酒']);
  });

  test('separators a person actually types are accepted', () {
    // `＝` and `：` come out of a Chinese keyboard's full-width mode, and `，`/`、` are how somebody writing
    // Chinese lists things. Refusing any of them would make the feature unusable on the machine it is for.
    final parsed = parseSynonymBlock('金酒＝琴酒，杜松子酒\n朗姆酒：白朗姆、金朗姆');
    expect(parsed.problems, isEmpty);
    expect(parsed.groups.first.also, ['琴酒', '杜松子酒']);
    expect(parsed.groups.last.canonical, '朗姆酒');
    expect(parsed.groups.last.also, ['白朗姆', '金朗姆']);
  });

  test('blank lines and comments are ignored, so a block can carry its own notes', () {
    final parsed = parseSynonymBlock('\n# a note\n\n金酒 = 琴酒\n\n');
    expect(parsed.groups, hasLength(1));
    expect(parsed.problems, isEmpty);
  });

  test('a name on its own is a group of one, not an error', () {
    final parsed = parseSynonymBlock('金酒');
    expect(parsed.ok, isTrue);
    expect(parsed.groups.single.canonical, '金酒');
    expect(parsed.groups.single.also, isEmpty);
    expect(canonicalNameOf('金酒', parsed.groups), '金酒');
  });

  test('**a line that cannot be read is reported with its number, not dropped**', () {
    // The failure mode this prevents: the reader pastes twenty names, sees success, and the one that mattered
    // is silently missing -- surfacing weeks later as a drink that cannot be made.
    final parsed = parseSynonymBlock('金酒 = 琴酒\n = 没有名字\n伏特加 = 俄得克');
    expect(parsed.groups, hasLength(2));
    expect(parsed.problems, hasLength(1));
    expect(parsed.problems.single.line, 2, reason: 'numbered the way the reader sees it');
    expect(parsed.problems.single.reason, contains('no name before'));
  });

  test('matching ignores case and spacing, and nothing else', () {
    // `Blue Curaçao` and `blue curaçao` are one thing. A *fuzzy* match would answer confidently about a name
    // nobody defined, which is the failure this file exists to prevent.
    final parsed = parseSynonymBlock('Blue Curaçao = 蓝柑');
    expect(canonicalNameOf('blue curaçao', parsed.groups), 'Blue Curaçao');
    expect(canonicalNameOf('BLUE  CURAÇAO', parsed.groups), 'Blue Curaçao');
    expect(canonicalNameOf('blue curacoa', parsed.groups), isNull, reason: 'a typo is not a synonym');
  });

  test('a name repeated inside its own group is not listed twice or as a synonym of itself', () {
    final parsed = parseSynonymBlock('金酒 = 琴酒, 金酒, 琴酒');
    expect(parsed.groups.single.also, ['琴酒']);
    expect(synonymsOf('金酒', parsed.groups), ['琴酒']);
  });

  test('**what the editor shows is what the editor accepts**', () {
    // Round-tripping matters: the reader opens the screen, sees last time's work, edits it and saves. A
    // display format that the parser did not accept would make every visit a small translation.
    final original = parseSynonymBlock('金酒 = 琴酒, 杜松子酒\n安高天娜 = 安哥斯图拉');
    final again = parseSynonymBlock(renderSynonymBlock(original.groups));
    expect(again.ok, isTrue);
    expect(again.groups.map((g) => g.toString()), original.groups.map((g) => g.toString()));
  });

  test('the first name is the canonical one, and that is the reader\'s choice', () {
    // A format with no first name (`金酒 琴酒 杜松子酒`) would leave the application choosing, and it would
    // choose the seed's English.
    final parsed = parseSynonymBlock('琴酒 = 金酒');
    expect(parsed.groups.single.canonical, '琴酒');
    expect(canonicalNameOf('金酒', parsed.groups), '琴酒');
  });
}
