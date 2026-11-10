import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rekreta_app/theme/oled_theme.dart';

void main() {
  test('OledTheme uses pure black background and color-coded grade badges', () {
    final theme = OledTheme.buildTheme();
    expect(theme.scaffoldBackgroundColor, Colors.black);
    expect(OledTheme.gradeColor(5), const Color(0xFF2E7D32));
    expect(OledTheme.gradeColor(4), const Color(0xFF1565C0));
    expect(OledTheme.gradeColor(3), const Color(0xFFF9A825));
    expect(OledTheme.gradeColor(2), const Color(0xFFEF6C00));
    expect(OledTheme.gradeColor(1), const Color(0xFFC62828));
  });
}
