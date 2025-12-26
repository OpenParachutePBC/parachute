import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:app/core/theme/design_tokens.dart';
import 'package:app/core/providers/embedding_provider.dart';
import 'package:app/features/ask/models/ask_result.dart';
import 'package:app/features/ask/providers/ask_providers.dart';
import 'package:app/features/journal/providers/journal_providers.dart';
import 'package:app/core/services/search/models/vector_search_result.dart';

/// Ask content widget - chat-like Q&A interface for journal queries
///
/// Uses local RAG (embedding search + Gemma LLM) to answer questions
/// about the user's journal entries.
class AskContent extends ConsumerStatefulWidget {
  const AskContent({super.key});

  @override
  ConsumerState<AskContent> createState() => _AskContentState();
}

class _AskContentState extends ConsumerState<AskContent> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  bool _isLoading = false;

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _askQuestion() async {
    final question = _inputController.text.trim();
    if (question.isEmpty || _isLoading) return;

    setState(() => _isLoading = true);
    _inputController.clear();

    try {
      await ref.read(currentAskMessagesProvider.notifier).askQuestion(question);

      // Scroll to bottom after new message
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final messages = ref.watch(currentAskMessagesProvider);
    final embeddingStatus = ref.watch(embeddingModelStatusProvider);
    final isDesktop = Platform.isMacOS || Platform.isLinux || Platform.isWindows;

    // Check if embedding model is ready
    if (!embeddingStatus.isReady) {
      return _buildModelNotReadyState(isDark, embeddingStatus);
    }

    // Check Ollama availability on desktop
    if (isDesktop) {
      final ollamaStatus = ref.watch(ollamaAvailableProvider);
      return ollamaStatus.when(
        data: (available) {
          if (!available) {
            return _buildOllamaNotAvailableState(isDark);
          }
          return _buildMainContent(isDark, messages);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _buildOllamaNotAvailableState(isDark),
      );
    }

    return _buildMainContent(isDark, messages);
  }

  Widget _buildMainContent(bool isDark, List<AskMessage> messages) {
    return Column(
      children: [
        // Info banner
        _buildInfoBanner(isDark),

        // Messages list
        Expanded(
          child: messages.isEmpty
              ? _buildEmptyState(isDark)
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(Spacing.md),
                  itemCount: messages.length + (_isLoading ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (_isLoading && index == messages.length) {
                      return _buildLoadingMessage(isDark);
                    }
                    return _buildMessageBubble(messages[index], isDark);
                  },
                ),
        ),

        // Input bar
        _buildInputBar(isDark),
      ],
    );
  }

  Widget _buildOllamaNotAvailableState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.computer,
              size: 64,
              color: BrandColors.warning.withValues(alpha: 0.7),
            ),
            const SizedBox(height: Spacing.lg),
            Text(
              'Ollama Required',
              style: TextStyle(
                fontSize: TypographyTokens.titleMedium,
                fontWeight: FontWeight.bold,
                color: isDark ? BrandColors.nightText : BrandColors.charcoal,
              ),
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              'The Ask feature requires Ollama to generate answers on desktop.\n\n'
              'Install Ollama and pull a model like llama3.2:1b to get started.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: TypographyTokens.bodyMedium,
                color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
              ),
            ),
            const SizedBox(height: Spacing.xl),
            // Install instructions
            Container(
              padding: const EdgeInsets.all(Spacing.md),
              decoration: BoxDecoration(
                color: isDark
                    ? BrandColors.nightSurfaceElevated
                    : BrandColors.stone.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(Radii.md),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '1. Install Ollama:',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: TypographyTokens.bodySmall,
                      color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                    ),
                  ),
                  const SizedBox(height: Spacing.xs),
                  Container(
                    padding: const EdgeInsets.all(Spacing.sm),
                    decoration: BoxDecoration(
                      color: BrandColors.ink,
                      borderRadius: BorderRadius.circular(Radii.sm),
                    ),
                    child: Text(
                      Platform.isMacOS
                          ? 'brew install ollama'
                          : 'curl -fsSL https://ollama.com/install.sh | sh',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: TypographyTokens.labelSmall,
                        color: BrandColors.softWhite,
                      ),
                    ),
                  ),
                  const SizedBox(height: Spacing.md),
                  Text(
                    '2. Pull a model:',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: TypographyTokens.bodySmall,
                      color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                    ),
                  ),
                  const SizedBox(height: Spacing.xs),
                  Container(
                    padding: const EdgeInsets.all(Spacing.sm),
                    decoration: BoxDecoration(
                      color: BrandColors.ink,
                      borderRadius: BorderRadius.circular(Radii.sm),
                    ),
                    child: Text(
                      'ollama pull llama3.2:1b',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: TypographyTokens.labelSmall,
                        color: BrandColors.softWhite,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Spacing.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: () async {
                    final url = Uri.parse('https://ollama.com');
                    if (await canLaunchUrl(url)) {
                      await launchUrl(url, mode: LaunchMode.externalApplication);
                    }
                  },
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Visit ollama.com'),
                ),
                const SizedBox(width: Spacing.md),
                FilledButton.icon(
                  onPressed: () {
                    ref.invalidate(ollamaAvailableProvider);
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Check Again'),
                  style: FilledButton.styleFrom(
                    backgroundColor: BrandColors.forest,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModelNotReadyState(bool isDark, EmbeddingStatusState status) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_awesome,
              size: 64,
              color: isDark
                  ? BrandColors.nightTextSecondary.withValues(alpha: 0.5)
                  : BrandColors.driftwood.withValues(alpha: 0.5),
            ),
            const SizedBox(height: Spacing.lg),
            Text(
              'AI Models Required',
              style: TextStyle(
                fontSize: TypographyTokens.titleMedium,
                fontWeight: FontWeight.bold,
                color: isDark ? BrandColors.nightText : BrandColors.charcoal,
              ),
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              'Download the embedding model to ask questions about your journals.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: TypographyTokens.bodyMedium,
                color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
              ),
            ),
            const SizedBox(height: Spacing.lg),
            if (status.isDownloading) ...[
              SizedBox(
                width: 200,
                child: Column(
                  children: [
                    LinearProgressIndicator(
                      value: status.progress > 0 ? status.progress : null,
                      backgroundColor: isDark
                          ? BrandColors.nightTextSecondary.withValues(alpha: 0.2)
                          : BrandColors.driftwood.withValues(alpha: 0.2),
                      color: BrandColors.forest,
                    ),
                    const SizedBox(height: Spacing.sm),
                    Text(
                      'Downloading... ${(status.progress * 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: TypographyTokens.labelSmall,
                        color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              FilledButton.icon(
                onPressed: () {
                  ref.read(embeddingModelStatusProvider.notifier).download();
                },
                icon: const Icon(Icons.download),
                label: const Text('Download Model (~200 MB)'),
                style: FilledButton.styleFrom(
                  backgroundColor: BrandColors.forest,
                ),
              ),
            ],
            if (status.error != null) ...[
              const SizedBox(height: Spacing.md),
              Container(
                padding: const EdgeInsets.all(Spacing.md),
                decoration: BoxDecoration(
                  color: BrandColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(Radii.sm),
                ),
                child: Text(
                  status.error!,
                  style: TextStyle(
                    color: BrandColors.error,
                    fontSize: TypographyTokens.labelSmall,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoBanner(bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(Spacing.md, Spacing.md, Spacing.md, 0),
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: (isDark ? BrandColors.nightForest : BrandColors.forest)
            .withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(
          color: (isDark ? BrandColors.nightForest : BrandColors.forest)
              .withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 16,
            color: isDark ? BrandColors.nightForest : BrandColors.forest,
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              'Ask questions about your journals. Answers are generated locally using AI.',
              style: TextStyle(
                fontSize: TypographyTokens.labelSmall,
                color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
              ),
            ),
          ),
          // New session button
          IconButton(
            icon: Icon(
              Icons.refresh,
              size: 18,
              color: isDark ? BrandColors.nightForest : BrandColors.forest,
            ),
            tooltip: 'New session',
            onPressed: () {
              ref.read(currentAskMessagesProvider.notifier).clearSession();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 64,
            color: isDark
                ? BrandColors.nightTextSecondary.withValues(alpha: 0.5)
                : BrandColors.driftwood.withValues(alpha: 0.5),
          ),
          const SizedBox(height: Spacing.lg),
          Text(
            'Ask about your journals',
            style: TextStyle(
              fontSize: TypographyTokens.titleSmall,
              fontWeight: FontWeight.w500,
              color: isDark ? BrandColors.nightText : BrandColors.charcoal,
            ),
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            'Try asking something like:',
            style: TextStyle(
              fontSize: TypographyTokens.bodySmall,
              color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
            ),
          ),
          const SizedBox(height: Spacing.md),
          _buildSuggestionChips(isDark),
        ],
      ),
    );
  }

  Widget _buildSuggestionChips(bool isDark) {
    final suggestions = [
      'What did I write about last week?',
      'How have I been feeling lately?',
      'What are my goals?',
    ];

    return Wrap(
      spacing: Spacing.sm,
      runSpacing: Spacing.sm,
      alignment: WrapAlignment.center,
      children: suggestions.map((suggestion) {
        return ActionChip(
          label: Text(
            suggestion,
            style: TextStyle(
              fontSize: TypographyTokens.labelSmall,
              color: isDark ? BrandColors.nightForest : BrandColors.forest,
            ),
          ),
          backgroundColor: (isDark ? BrandColors.nightForest : BrandColors.forest)
              .withValues(alpha: 0.1),
          side: BorderSide(
            color: (isDark ? BrandColors.nightForest : BrandColors.forest)
                .withValues(alpha: 0.3),
          ),
          onPressed: () {
            _inputController.text = suggestion;
            _askQuestion();
          },
        );
      }).toList(),
    );
  }

  Widget _buildMessageBubble(AskMessage message, bool isDark) {
    final isUser = message.isUser;

    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: isDark ? BrandColors.nightForest : BrandColors.forest,
              child: const Icon(
                Icons.auto_awesome,
                size: 16,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: Spacing.sm),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(Spacing.md),
                  decoration: BoxDecoration(
                    color: isUser
                        ? (isDark ? BrandColors.nightTurquoise : BrandColors.turquoise)
                        : (isDark ? BrandColors.nightSurfaceElevated : BrandColors.softWhite),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(Radii.md),
                      topRight: const Radius.circular(Radii.md),
                      bottomLeft: Radius.circular(isUser ? Radii.md : 4),
                      bottomRight: Radius.circular(isUser ? 4 : Radii.md),
                    ),
                  ),
                  child: Text(
                    message.content,
                    style: TextStyle(
                      fontSize: TypographyTokens.bodyMedium,
                      color: isUser
                          ? Colors.white
                          : (isDark ? BrandColors.nightText : BrandColors.charcoal),
                    ),
                  ),
                ),
                // Show sources for assistant messages
                if (!isUser && message.sources != null && message.sources!.isNotEmpty)
                  _buildSourceChips(message.sources!, isDark),
              ],
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: Spacing.sm),
            CircleAvatar(
              radius: 16,
              backgroundColor: isDark ? BrandColors.nightTurquoise : BrandColors.turquoise,
              child: const Icon(
                Icons.person,
                size: 16,
                color: Colors.white,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSourceChips(List<VectorSearchResult> sources, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.sm),
      child: Wrap(
        spacing: Spacing.xs,
        runSpacing: Spacing.xs,
        children: [
          Text(
            'Sources:',
            style: TextStyle(
              fontSize: TypographyTokens.labelSmall,
              color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
            ),
          ),
          ...sources.take(5).map((source) => _buildSourceChip(source, isDark)),
        ],
      ),
    );
  }

  Widget _buildSourceChip(VectorSearchResult source, bool isDark) {
    // Parse date from recordingId (format: journal:YYYY-MM-DD:entryId)
    String label = 'Source';
    DateTime? date;
    String? paraId;

    final parts = source.recordingId.split(':');
    if (parts.length >= 2 && parts[0] == 'journal') {
      try {
        date = DateTime.parse(parts[1]);
        label = '${_monthName(date.month)} ${date.day}';
        if (parts.length >= 3) {
          paraId = parts[2];
        }
      } catch (e) {
        label = parts[1];
      }
    }

    return InkWell(
      onTap: () => _navigateToSource(date, paraId),
      borderRadius: BorderRadius.circular(Radii.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.sm,
          vertical: Spacing.xs,
        ),
        decoration: BoxDecoration(
          color: BrandColors.forest.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(Radii.sm),
          border: Border.all(
            color: BrandColors.forest.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.book,
              size: 12,
              color: BrandColors.forest,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: TypographyTokens.labelSmall,
                color: BrandColors.forest,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToSource(DateTime? date, String? paraId) {
    if (date == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not parse source date'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // Set the selected journal date
    ref.read(selectedJournalDateProvider.notifier).state = date;

    // Show snackbar with navigation hint
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Journal date set to ${_formatDate(date)} - switch to Journal tab',
        ),
        duration: const Duration(seconds: 3),
      ),
    );

    // TODO: When journal screen supports scrollToParaId, pass it
    // Navigator.of(context).push(MaterialPageRoute(
    //   builder: (_) => JournalScreen(scrollToParaId: paraId),
    // ));
  }

  Widget _buildLoadingMessage(bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: isDark ? BrandColors.nightForest : BrandColors.forest,
            child: const Icon(
              Icons.auto_awesome,
              size: 16,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: Spacing.sm),
          Container(
            padding: const EdgeInsets.all(Spacing.md),
            decoration: BoxDecoration(
              color: isDark ? BrandColors.nightSurfaceElevated : BrandColors.softWhite,
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: isDark ? BrandColors.nightForest : BrandColors.forest,
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Text(
                  'Searching journals...',
                  style: TextStyle(
                    fontSize: TypographyTokens.bodySmall,
                    color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: isDark ? BrandColors.nightSurface : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _inputController,
                focusNode: _focusNode,
                enabled: !_isLoading,
                decoration: InputDecoration(
                  hintText: 'Ask about your journals...',
                  hintStyle: TextStyle(
                    color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Radii.lg),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: isDark
                      ? BrandColors.nightSurfaceElevated
                      : BrandColors.stone.withValues(alpha: 0.3),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: Spacing.md,
                    vertical: Spacing.sm,
                  ),
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _askQuestion(),
              ),
            ),
            const SizedBox(width: Spacing.sm),
            IconButton.filled(
              onPressed: _isLoading ? null : _askQuestion,
              icon: _isLoading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send),
              style: IconButton.styleFrom(
                backgroundColor: isDark ? BrandColors.nightForest : BrandColors.forest,
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                    (isDark ? BrandColors.nightForest : BrandColors.forest)
                        .withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _monthName(int month) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return months[month - 1];
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
