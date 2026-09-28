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
    super.dispose();
  }

  void _onScroll() {
    if (_reachedEnd) return;
    final pos = _scrollController.position;
    // 24px of slack. Demanding the exact pixel makes the button feel broken
    // on devices where the final scroll lands a hair short.
    if (pos.pixels >= pos.maxScrollExtent - 24) {
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
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: ZirenTokens.surfaceBorder),
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

          return Column(
            children: [
              Expanded(
                child: Scrollbar(
                  controller: _scrollController,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(
                      ZirenTokens.space20,
                      ZirenTokens.space20,
                      ZirenTokens.space20,
                      ZirenTokens.space32,
                    ),
                    child: MarkdownLite(snapshot.data!),
                  ),
                ),
              ),
              _BottomBar(
                enabled: _reachedEnd,
                scrollHint: t.legalScrollHint,
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

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.enabled,
    required this.scrollHint,
    required this.confirmLabel,
    required this.onAccept,
  });

  final bool enabled;
  final String scrollHint;
  final String confirmLabel;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ZirenTokens.surfaceCard,
        border: Border(top: BorderSide(color: ZirenTokens.surfaceBorder)),
        boxShadow: ZirenTokens.shadowSm,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(ZirenTokens.space16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!enabled) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      LucideIcons.arrow_down,
                      size: 15,
                      color: ZirenTokens.textMuted,
                    ),
                    const SizedBox(width: ZirenTokens.space8),
                    Flexible(child: Text(
                      scrollHint,
                      style: TextStyle(
                        fontSize: 13,
                        color: ZirenTokens.textMuted,
                      ),
                    )),
                  ],
                ),
                const SizedBox(height: ZirenTokens.space12),
              ],
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: enabled ? onAccept : null,
                  child: Text(confirmLabel),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
