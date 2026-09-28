import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// A very small Markdown renderer, covering exactly the subset used by the
/// legal documents in `assets/legal/`.
///
/// Supported: `#`/`##`/`###` headings, `-` bullets, `---` rules, `**bold**`,
/// `*italic*`, and blank-line-separated paragraphs. Nothing else — no links,
/// tables, images, or code blocks, because none appear in the source files.
///
/// Why not a package
/// -----------------
/// Pulling a Markdown dependency to render four bundled documents would add a
/// transitive tree, a version to keep current, and a rendering style to fight
/// with, in exchange for features these documents do not use. The parser below
/// is small enough to read in one sitting and styles straight from the design
/// tokens, so the notices look like the rest of the app rather than like a
/// web view dropped into it.
///
/// If a future document needs links or tables, replace this rather than
/// growing it — the point of it is that it stays small.
class MarkdownLite extends StatelessWidget {
  const MarkdownLite(this.source, {super.key});

  final String source;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _parse(source),
    );
  }

  static List<Widget> _parse(String source) {
    final widgets = <Widget>[];
    final paragraph = <String>[];

    void flushParagraph() {
      if (paragraph.isEmpty) return;
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: ZirenTokens.space12),
          child: RichText(
            text: TextSpan(
              style: TextStyle(
                fontSize: 14.5,
                height: 1.6,
                color: ZirenTokens.textSecondary,
              ),
              children: _inline(paragraph.join(' ')),
            ),
          ),
        ),
      );
      paragraph.clear();
    }

    for (final raw in source.split('\n')) {
      final line = raw.trimRight();
      final trimmed = line.trim();

      if (trimmed.isEmpty) {
        flushParagraph();
        continue;
      }

      if (trimmed == '---') {
        flushParagraph();
        widgets.add(
          Padding(
            padding: EdgeInsets.symmetric(vertical: ZirenTokens.space20),
            child: Divider(height: 1, color: ZirenTokens.surfaceBorder),
          ),
        );
        continue;
      }

      if (trimmed.startsWith('### ')) {
        flushParagraph();
        widgets.add(_heading(trimmed.substring(4), 15, ZirenTokens.space16));
        continue;
      }
      if (trimmed.startsWith('## ')) {
        flushParagraph();
        widgets.add(_heading(trimmed.substring(3), 17, ZirenTokens.space24));
        continue;
      }
      if (trimmed.startsWith('# ')) {
        flushParagraph();
        widgets.add(_heading(trimmed.substring(2), 22, ZirenTokens.space8));
        continue;
      }

      if (trimmed.startsWith('- ')) {
        flushParagraph();
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(
              bottom: ZirenTokens.space8,
              left: ZirenTokens.space4,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 7, right: 10),
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: const BoxDecoration(
                      color: ZirenTokens.brandOrange,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: TextStyle(
                        fontSize: 14.5,
                        height: 1.55,
                        color: ZirenTokens.textSecondary,
                      ),
                      children: _inline(trimmed.substring(2)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
        continue;
      }

      paragraph.add(trimmed);
    }

    flushParagraph();
    return widgets;
  }

  static Widget _heading(String text, double size, double topGap) {
    return Padding(
      padding: EdgeInsets.only(top: topGap, bottom: ZirenTokens.space8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: size,
          fontWeight: FontWeight.w700,
          height: 1.3,
          letterSpacing: -0.2,
          color: ZirenTokens.textPrimary,
        ),
      ),
    );
  }

  /// Splits `**bold**` and `*italic*` runs out of a line.
  ///
  /// Bold is matched first so that the `*` pair inside `**` is never mistaken
  /// for an italic delimiter.
  static List<TextSpan> _inline(String text) {
    final spans = <TextSpan>[];
    final pattern = RegExp(r'\*\*(.+?)\*\*|\*(.+?)\*');
    var index = 0;

    for (final m in pattern.allMatches(text)) {
      if (m.start > index) {
        spans.add(TextSpan(text: text.substring(index, m.start)));
      }
      if (m.group(1) != null) {
        spans.add(
          TextSpan(
            text: m.group(1),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: ZirenTokens.textPrimary,
            ),
          ),
        );
      } else {
        spans.add(
          TextSpan(
            text: m.group(2),
            style: const TextStyle(fontStyle: FontStyle.italic),
          ),
        );
      }
      index = m.end;
    }

    if (index < text.length) {
      spans.add(TextSpan(text: text.substring(index)));
    }
    return spans;
  }
}
