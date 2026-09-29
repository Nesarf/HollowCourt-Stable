import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/ui/theme.dart';

/// **One name in three scripts**, and the owner corrected this by hand on 2026-09-22:
/// *"根据语言区不同，空庭使用 Hollow Court 或虚ろな庭"*.
void main() {
  test('the name follows the reader\'s script', () {
    expect(Copy.appName.textFor('zh-Hans'), '空庭');
    expect(Copy.appName.textFor('zh-HK'), '空庭');
    expect(Copy.appName.textFor('zh-TW'), '空庭');
    expect(Copy.appName.textFor('en'), 'Hollow Court');
    expect(Copy.appName.textFor('ja'), '虚ろな庭');
  });

  test('and 空庭 is still the single-language form the platform chrome takes', () {
    expect(Copy.appTitle, '空庭');
    expect(Copy.appJaTitle, '虚ろな庭');
    expect(Copy.appSubtitle, 'Hollow Court');
  });
}
