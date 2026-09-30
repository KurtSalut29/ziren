import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/app_tokens.dart';
import '../../../shared/widgets/markdown_lite.dart';
import '../domain/legal_documents.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// Full-screen reader for one legal document.
///
/// Pops `true` when the reader has scrolled to the end and pressed the accept
/// button, `null` if they backed out.
///
/// The accept button stays disabled until the document has actually been
/// scrolled to the bottom. That is not a dark pattern in reverse — it is the
/// difference between a consent record that means something and a checkbox
/// someone tapped past. It costs a hurried user a flick of the thumb.
///
/// Laid out as a document, not a wall of text: a header card (what it is, its
/// version, how long it takes to read), then each numbered section in its own
/// card with its number in a badge, and the draft note at the end set apart.
/// A bar under the app bar and a percentage at the bottom show how far the
/// reader has got — the same "scroll to the end" requirement, made visible.
class LegalReaderScreen extends StatefulWidget {
  const LegalReaderScreen({
    super.key,
    required this.doc,
    required this.languageCode,
    required this.title,
  });

  final LegalDoc doc;
  final String languageCode;
  final String title;

  @override
  State<LegalReaderScreen> createState() => _LegalReaderScreenState();
}

class _LegalReaderScreenState extends State<LegalReaderScreen> {
  final _scrollController = ScrollController();
  late Future<String> _textFuture;
  bool _reachedEnd = false;

  /// 0..1, how far down the document the reader is. A notifier, so scrolling
  /// repaints only the bar and the percentage, not the whole document.
  final _progress = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    _textFuture = LegalDocuments.load(widget.doc, widget.languageCode);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _progress.dispose();
    super.dispose();
  }

  void _onScroll() {
    final pos = _scrollController.position;
    if (pos.maxScrollExtent > 0) {
      _progress.value = (pos.pixels / pos.maxScrollExtent).clamp(0.0, 1.0);
    }
    if (_reachedEnd) return;
    // 24px of slack. Demanding the exact pixel makes the button feel broken
    // on devices where the final scroll lands a hair short.
    if (pos.pixels >= pos.maxScrollExtent - 24) {
      _progress.value = 1;
      setState(() => _reachedEnd = true);
    }
  }

  /// A document shorter than the viewport can never fire a scroll event, so
  /// there would be nothing the reader could do to enable the button. Checked
  /// after the first layout.
  void _enableIfNotScrollable() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _reachedEnd) return;
      if (!_scrollController.hasClients) return;
      if (_scrollController.position.maxScrollExtent <= 0) {
        _progress.value = 1;
        setState(() => _reachedEnd = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: ZirenTokens.surfaceBase,
      appBar: AppBar(
        backgroundColor: ZirenTokens.surfaceCard,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          widget.title,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: ZirenTokens.textPrimary,
          ),
        ),
        leading: IconButton(
          tooltip: t.legalClose,
          icon: Icon(LucideIcons.x, color: ZirenTokens.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: ValueListenableBuilder<double>(
            valueListenable: _progress,
            builder:
                (_, value, __) => LinearProgressIndicator(
                  key: const Key('legal-progress'),
                  value: value,
                  minHeight: 3,
                  backgroundColor: ZirenTokens.surfaceBorder,
                  valueColor: AlwaysStoppedAnimation(
                    value >= 1
                        ? ZirenTokens.systemSuccess
                        : ZirenTokens.brandOrange,
                  ),
                ),
          ),
        ),
      ),
      body: FutureBuilder<String>(
        future: _textFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || snapshot.data == null) {
            // Bundled assets do not usually fail to load, but a blank sheet
            // where a privacy notice should be must never be silent.
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(ZirenTokens.space32),
                child: Text(
                  t.legalLoadError,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: ZirenTokens.textSecondary),
                ),
              ),
            );
          }

          _enableIfNotScrollable();
          final doc = LegalDocumentView.parse(snapshot.data!);

          return Column(
            children: [
              Expanded(
                child: Scrollbar(
                  controller: _scrollController,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(
                      ZirenTokens.space16,
                      ZirenTokens.space16,
                      ZirenTokens.space16,
                      ZirenTokens.space32,
                    ),
                    child: _Document(
                      doc: doc,
                      icon:
                          widget.doc == LegalDoc.privacy
                              ? LucideIcons.shield_check
                              : LucideIcons.file_text,
                    ),
                  ),
                ),
              ),
              _BottomBar(
                enabled: _reachedEnd,
                progress: _progress,
                confirmLabel: t.legalReadConfirm,
                onAccept: () => Navigator.of(context).pop(true),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A legal document split into the parts the reader lays out separately.
///
/// Every document in `assets/legal/` has the same shape: `# Title`, a bold
/// version line, a few intro paragraphs, `## N. Section` blocks, then `---`
/// and an italic draft note. Anything that does not fit that shape still
/// renders — as intro text — rather than disappearing.
@visibleForTesting
class LegalDocumentView {
  LegalDocumentView({
    required this.title,
    required this.version,
    required this.intro,
    required this.sections,
    required this.footer,
    required this.words,
  });

  final String? title;
  final String? version;
  final String intro;
  final List<({String? number, String heading, String body})> sections;
  final String footer;
  final int words;

  int get minutes => (words / 200).ceil().clamp(1, 99);

  static LegalDocumentView parse(String source) {
    String? title;
    String? version;
    final intro = StringBuffer();
    final footer = StringBuffer();
    final sections = <({String? number, String heading, String body})>[];
    String? heading;
    final body = StringBuffer();
    var inFooter = false;

    void closeSection() {
      if (heading == null) return;
      final m = RegExp(r'^(\d+)\.\s+(.*)$').firstMatch(heading!);
      sections.add((
        number: m?.group(1),
        heading: m?.group(2) ?? heading!,
        body: body.toString().trim(),
      ));
      heading = null;
      body.clear();
    }

    for (final raw in source.split('\n')) {
      final line = raw.trimRight();
      final trimmed = line.trim();
      if (inFooter) {
        footer.writeln(line);
        continue;
      }
      if (trimmed == '---') {
        closeSection();
        inFooter = true;
        continue;
      }
      if (title == null && trimmed.startsWith('# ')) {
        title = trimmed.substring(2);
        continue;
      }
      if (trimmed.startsWith('## ')) {
        closeSection();
        heading = trimmed.substring(3);
        continue;
      }
      if (heading != null) {
        body.writeln(line);
        continue;
      }
      // The version line: the first bold-only paragraph before any section.
      if (version == null &&
          trimmed.startsWith('**') &&
          trimmed.endsWith('**') &&
          trimmed.length > 4) {
        version = trimmed.substring(2, trimmed.length - 2);
        continue;
      }
      intro.writeln(line);
    }
    closeSection();

    return LegalDocumentView(
      title: title,
      version: version,
      intro: intro.toString().trim(),
      sections: sections,
      footer: footer.toString().trim().replaceAll(RegExp(r'^\*|\*$'), ''),
      words: RegExp(r'\S+').allMatches(source).length,
    );
  }
}

class _Document extends StatelessWidget {
  const _Document({required this.doc, required this.icon});

  final LegalDocumentView doc;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Header ─────────────────────────────────────────────
        Container(
          decoration: BoxDecoration(
            color: ZirenTokens.surfaceCard,
            borderRadius: BorderRadius.circular(ZirenTokens.radius20),
            border: Border.all(color: ZirenTokens.surfaceBorder),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: ZirenTokens.brandOrange.withValues(
                  alpha: ZirenTokens.isDark ? 0.14 : 0.07,
                ),
                padding: const EdgeInsets.all(ZirenTokens.space16),
                child: Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: ZirenTokens.brandOrange.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        icon,
                        size: 24,
                        color: ZirenTokens.brandOrange,
                      ),
                    ),
                    const SizedBox(width: ZirenTokens.space12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (doc.title != null)
                            Text(
                              doc.title!,
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                                height: 1.2,
                                color: ZirenTokens.textPrimary,
                              ),
                            ),
                          const SizedBox(height: 4),
                          Text(
                            t.legalMeta(
                              '${doc.sections.length}',
                              '${doc.minutes}',
                            ),
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: ZirenTokens.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  ZirenTokens.space16,
                  ZirenTokens.space12,
                  ZirenTokens.space16,
                  ZirenTokens.space4,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (doc.version != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: ZirenTokens.surfaceRaised,
                          borderRadius: BorderRadius.circular(
                            ZirenTokens.radius32,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              LucideIcons.calendar,
                              size: 12,
                              color: ZirenTokens.textSecondary,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                doc.version!,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: ZirenTokens.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: ZirenTokens.space12),
                    ],
                    if (doc.intro.isNotEmpty) MarkdownLite(doc.intro),
                  ],
                ),
              ),
            ],
          ),
        ),

        // ── Sections ───────────────────────────────────────────
        for (final s in doc.sections) ...[
          const SizedBox(height: ZirenTokens.space12),
          Container(
            padding: const EdgeInsets.fromLTRB(
              ZirenTokens.space16,
              ZirenTokens.space16,
              ZirenTokens.space16,
              ZirenTokens.space4,
            ),
            decoration: BoxDecoration(
              color: ZirenTokens.surfaceCard,
              borderRadius: BorderRadius.circular(ZirenTokens.radius20),
              border: Border.all(color: ZirenTokens.surfaceBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (s.number != null) ...[
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: ZirenTokens.brandOrange,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          s.number!,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: ZirenTokens.space10),
                    ],
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          s.heading,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            height: 1.3,
                            color: ZirenTokens.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: ZirenTokens.space12),
                MarkdownLite(s.body),
              ],
            ),
          ),
        ],

        // ── Draft note ─────────────────────────────────────────
        if (doc.footer.isNotEmpty) ...[
          const SizedBox(height: ZirenTokens.space16),
          Container(
            padding: const EdgeInsets.all(ZirenTokens.space12),
            decoration: BoxDecoration(
              color: ZirenTokens.systemWarningBg,
              borderRadius: BorderRadius.circular(ZirenTokens.radius16),
              border: Border.all(
                color: ZirenTokens.systemWarning.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  LucideIcons.info,
                  size: 16,
                  color: ZirenTokens.systemWarning,
                ),
                const SizedBox(width: ZirenTokens.space8),
                Expanded(
                  child: Text(
                    doc.footer.replaceAll('\n', ' '),
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.45,
                      fontStyle: FontStyle.italic,
                      color: ZirenTokens.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.enabled,
    required this.progress,
    required this.confirmLabel,
    required this.onAccept,
  });

  final bool enabled;
  final ValueNotifier<double> progress;
  final String confirmLabel;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Container(
      decoration: BoxDecoration(
        color: ZirenTokens.surfaceCard,
        border: Border(top: BorderSide(color: ZirenTokens.surfaceBorder)),
        boxShadow: ZirenTokens.shadowSm,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            ZirenTokens.space16,
            ZirenTokens.space12,
            ZirenTokens.space16,
            ZirenTokens.space16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<double>(
                valueListenable: progress,
                builder: (_, value, __) {
                  final done = enabled;
                  final color =
                      done ? ZirenTokens.systemSuccess : ZirenTokens.textMuted;
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        done
                            ? LucideIcons.circle_check
                            : LucideIcons.arrow_down,
                        size: 15,
                        color: color,
                      ),
                      const SizedBox(width: ZirenTokens.space8),
                      Flexible(
                        child: Text(
                          done
                              ? t.legalReachedEnd
                              : '${t.legalScrollHint} · '
                                  '${t.legalProgress('${(value * 100).round()}')}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: color,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: ZirenTokens.space12),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  key: const Key('legal-accept'),
                  onPressed: enabled ? onAccept : null,
                  icon: const Icon(LucideIcons.check, size: 18),
                  label: Text(
                    confirmLabel,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ZirenTokens.brandOrange,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: ZirenTokens.surfaceRaised,
                    disabledForegroundColor: ZirenTokens.textMuted,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(ZirenTokens.radius16),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
