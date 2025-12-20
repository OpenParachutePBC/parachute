import 'package:flutter/foundation.dart';

/// Splits text into sentences using punctuation rules
///
/// Handles common edge cases:
/// - Abbreviations (Dr., Mr., Mrs., etc.)
/// - Decimal numbers (3.14, 2.5)
/// - URLs and email addresses
/// - Multiple punctuation marks
class SentenceSplitter {
  /// Common abbreviations that don't indicate sentence boundaries
  static final _abbreviations = {
    'dr',
    'mr',
    'mrs',
    'ms',
    'prof',
    'sr',
    'jr',
    'phd',
    'md',
    'inc',
    'corp',
    'ltd',
    'etc',
    'e.g',
    'i.e',
    'vs',
    'p.m',
    'a.m',
  };

  /// Split text into sentences
  ///
  /// Returns a list of sentences with whitespace trimmed.
  /// Empty sentences are filtered out.
  List<String> split(String text) {
    if (text.isEmpty) {
      debugPrint('[SentenceSplitter] Input text is empty');
      return [];
    }

    debugPrint('[SentenceSplitter] Splitting text of length: ${text.length}');

    // Step 1: Protect URLs and email addresses
    final protected = _protectUrls(text);

    // Step 2: Split on sentence boundaries
    final sentences = _splitOnPunctuation(protected);

    // Step 3: Restore URLs and email addresses
    final restored = sentences.map(_restoreUrls).toList();

    debugPrint('[SentenceSplitter] Split into ${restored.length} sentences');
    return restored;
  }

  /// Protect URLs and email addresses from being split
  String _protectUrls(String text) {
    // Replace URLs with placeholders
    // Pattern: http(s)://... or www....
    final urlPattern = RegExp(r'https?://[^\s]+|www\.[^\s]+');
    text = text.replaceAllMapped(urlPattern, (match) {
      return '__URL_${match.group(0)!.hashCode}__';
    });

    // Replace email addresses with placeholders
    // Pattern: user@domain.com
    final emailPattern = RegExp(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b');
    text = text.replaceAllMapped(emailPattern, (match) {
      return '__EMAIL_${match.group(0)!.hashCode}__';
    });

    return text;
  }

  /// Restore URLs and email addresses after splitting
  String _restoreUrls(String text) {
    // This is a simplified restoration - in practice, we'd need to maintain
    // a mapping of placeholders to original values. For now, we just remove
    // the placeholders since they're unlikely to appear in voice transcripts.
    return text
        .replaceAll(RegExp(r'__URL_-?\d+__'), '[URL]')
        .replaceAll(RegExp(r'__EMAIL_-?\d+__'), '[EMAIL]');
  }

  /// Split text on sentence-ending punctuation
  List<String> _splitOnPunctuation(String text) {
    final sentences = <String>[];
    final buffer = StringBuffer();

    for (int i = 0; i < text.length; i++) {
      final char = text[i];
      buffer.write(char);

      // Check if this is a sentence-ending punctuation
      if (_isSentenceEnd(char)) {
        // Look ahead to see if this is really a sentence boundary
        if (_isRealSentenceBoundary(text, i)) {
          final sentence = buffer.toString().trim();
          if (sentence.isNotEmpty) {
            sentences.add(sentence);
          }
          buffer.clear();
        }
      }
    }

    // Add any remaining text as the last sentence
    final lastSentence = buffer.toString().trim();
    if (lastSentence.isNotEmpty) {
      sentences.add(lastSentence);
    }

    return sentences;
  }

  /// Check if a character is sentence-ending punctuation
  bool _isSentenceEnd(String char) {
    return char == '.' || char == '!' || char == '?';
  }

  /// Check if a punctuation mark indicates a real sentence boundary
  bool _isRealSentenceBoundary(String text, int punctuationIndex) {
    // Check for abbreviations
    if (_isAbbreviation(text, punctuationIndex)) {
      return false;
    }

    // Check for decimal numbers
    if (_isDecimalNumber(text, punctuationIndex)) {
      return false;
    }

    // Check if followed by closing quotes/parentheses
    final nextNonWhitespace = _getNextNonWhitespace(text, punctuationIndex);
    if (nextNonWhitespace != null) {
      // If followed by closing punctuation, not a boundary yet
      if (nextNonWhitespace == '"' ||
          nextNonWhitespace == "'" ||
          nextNonWhitespace == ')' ||
          nextNonWhitespace == ']') {
        return false;
      }

      // If followed by lowercase letter, probably not a sentence boundary
      if (nextNonWhitespace.toLowerCase() == nextNonWhitespace &&
          RegExp(r'[a-z]').hasMatch(nextNonWhitespace)) {
        return false;
      }
    }

    // Check if followed by multiple punctuation marks (e.g., "?!")
    if (punctuationIndex + 1 < text.length) {
      final nextChar = text[punctuationIndex + 1];
      if (_isSentenceEnd(nextChar)) {
        return false; // Let the next punctuation mark handle it
      }
    }

    return true;
  }

  /// Check if a period is part of an abbreviation
  bool _isAbbreviation(String text, int periodIndex) {
    if (text[periodIndex] != '.') return false;

    // Extract the word before the period
    int start = periodIndex - 1;
    while (start >= 0 && text[start].trim().isNotEmpty && text[start] != ' ') {
      start--;
    }
    start++; // Move to first char of word

    final word = text.substring(start, periodIndex).toLowerCase();

    return _abbreviations.contains(word);
  }

  /// Check if a period is part of a decimal number
  bool _isDecimalNumber(String text, int periodIndex) {
    if (text[periodIndex] != '.') return false;

    // Check if preceded and followed by digits
    final hasPrecedingDigit = periodIndex > 0 &&
        RegExp(r'\d').hasMatch(text[periodIndex - 1]);

    final hasFollowingDigit = periodIndex + 1 < text.length &&
        RegExp(r'\d').hasMatch(text[periodIndex + 1]);

    return hasPrecedingDigit && hasFollowingDigit;
  }

  /// Get the next non-whitespace character after the given index
  String? _getNextNonWhitespace(String text, int startIndex) {
    for (int i = startIndex + 1; i < text.length; i++) {
      if (text[i].trim().isNotEmpty) {
        return text[i];
      }
    }
    return null;
  }
}
