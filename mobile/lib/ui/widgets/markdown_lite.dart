import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'common.dart';

/// Zero-dependency clinical Markdown renderer for streaming assistant replies.
/// Supports headings (`#`, `##`, `###`), bullet lists (`- `, `* `), numbered lists (`1. `),
/// inline bold spans (`**bold**`), and interactive citation pills (`[1]`, `[2]`).
class MarkdownLite extends StatelessWidget {
  const MarkdownLite(this.text, {super.key, this.onCitationTap});

  final String text;
  final ValueChanged<int>? onCitationTap;

  static final _numberedRe = RegExp(r'^(\d+)\.\s+(.*)$');
  static final _inlineRe = RegExp(r'\*\*(.+?)\*\*|\[(\d+)\]');

  @override
  Widget build(BuildContext context) {
    final lines = text.split('\n');
    final children = <Widget>[];

    const bodyStyle = TextStyle(
      color: Palette.text,
      fontSize: 14.5,
      height: 1.5,
    );

    for (var i = 0; i < lines.length; i++) {
      final raw = lines[i];
      final trimmed = raw.trim();

      if (trimmed.isEmpty) {
        if (children.isNotEmpty) {
          children.add(const SizedBox(height: 6));
        }
        continue;
      }

      if (trimmed.startsWith('### ')) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: _buildRichText(
              trimmed.substring(4),
              const TextStyle(color: Palette.text, fontSize: 15, fontWeight: FontWeight.w700, height: 1.35),
            ),
          ),
        );
        continue;
      }

      if (trimmed.startsWith('## ')) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 4),
            child: _buildRichText(
              trimmed.substring(3),
              const TextStyle(color: Palette.text, fontSize: 16.5, fontWeight: FontWeight.w800, height: 1.35),
            ),
          ),
        );
        continue;
      }

      if (trimmed.startsWith('# ')) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 6),
            child: _buildRichText(
              trimmed.substring(2),
              const TextStyle(color: Palette.text, fontSize: 18, fontWeight: FontWeight.w800, height: 1.3),
            ),
          ),
        );
        continue;
      }

      if (trimmed.startsWith('- ') || trimmed.startsWith('* ') || trimmed.startsWith('• ')) {
        final itemText = trimmed.substring(2).trimLeft();
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2.5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 7.5, right: 10),
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: const BoxDecoration(color: Palette.red, shape: BoxShape.circle),
                  ),
                ),
                Expanded(child: _buildRichText(itemText, bodyStyle)),
              ],
            ),
          ),
        );
        continue;
      }

      final numMatch = _numberedRe.firstMatch(trimmed);
      if (numMatch != null) {
        final numStr = numMatch.group(1)!;
        final itemText = numMatch.group(2)!;
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2.5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 24,
                  child: Text(
                    '$numStr.',
                    style: const TextStyle(
                      color: Palette.red,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      height: 1.5,
                      fontFeatures: kTabular,
                    ),
                  ),
                ),
                Expanded(child: _buildRichText(itemText, bodyStyle)),
              ],
            ),
          ),
        );
        continue;
      }

      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 1.5),
          child: _buildRichText(trimmed, bodyStyle),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  Widget _buildRichText(String content, TextStyle baseStyle) {
    final spans = <InlineSpan>[];
    var lastEnd = 0;

    for (final m in _inlineRe.allMatches(content)) {
      if (m.start > lastEnd) {
        spans.add(TextSpan(text: content.substring(lastEnd, m.start)));
      }
      final boldText = m.group(1);
      final citationStr = m.group(2);
      if (boldText != null) {
        spans.add(
          TextSpan(
            text: boldText,
            style: baseStyle.copyWith(fontWeight: FontWeight.w700, color: Palette.text),
          ),
        );
      } else if (citationStr != null) {
        final n = int.tryParse(citationStr) ?? 0;
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: GestureDetector(
                onTap: onCitationTap == null ? null : () => onCitationTap!(n),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: Palette.redLight,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '[$n]',
                    style: const TextStyle(
                      color: Palette.red,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      fontFeatures: kTabular,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }
      lastEnd = m.end;
    }

    if (lastEnd < content.length) {
      spans.add(TextSpan(text: content.substring(lastEnd)));
    }

    return Text.rich(TextSpan(style: baseStyle, children: spans));
  }
}
