/**
 * Vault Search Service
 *
 * Provides search functionality over the indexed vault content.
 * Reads the SQLite database created by the Flutter app at .parachute/search.db
 *
 * Supports:
 * - Keyword search across all indexed content
 * - Filtering by content type (recording, journal, chat)
 * - Returns source paths and context for results
 */

import Database from 'better-sqlite3';
import path from 'path';
import fs from 'fs';

/**
 * Content types that can be searched
 */
export const ContentType = {
  RECORDING: 'recording',
  JOURNAL: 'journal',
  CHAT: 'chat',
};

/**
 * Vault Search Service
 */
export class VaultSearchService {
  constructor(vaultPath) {
    this.vaultPath = vaultPath;
    this.dbPath = path.join(vaultPath, '.parachute', 'search.db');
    this.db = null;
  }

  /**
   * Check if the search database exists
   */
  isAvailable() {
    return fs.existsSync(this.dbPath);
  }

  /**
   * Initialize the database connection
   */
  initialize() {
    if (this.db) return;

    if (!this.isAvailable()) {
      throw new Error(`Search database not found at ${this.dbPath}. The Flutter app needs to build the index first.`);
    }

    try {
      this.db = new Database(this.dbPath, { readonly: true });
      console.log('[VaultSearch] Connected to search database');
    } catch (e) {
      console.error('[VaultSearch] Failed to open database:', e.message);
      throw e;
    }
  }

  /**
   * Close the database connection
   */
  close() {
    if (this.db) {
      this.db.close();
      this.db = null;
    }
  }

  /**
   * Search for content matching a query
   *
   * Uses simple keyword matching on chunk_text.
   * For semantic search, the Flutter app should be used (it has embeddings).
   *
   * @param {string} query - Search query
   * @param {object} options - Search options
   * @param {number} options.limit - Max results (default: 20)
   * @param {string} options.contentType - Filter by content type
   * @returns {Array} Search results
   */
  search(query, options = {}) {
    if (!this.db) {
      this.initialize();
    }

    const { limit = 20, contentType = null } = options;

    // Build query with optional content type filter
    let sql = `
      SELECT
        c.id,
        c.recording_id as contentId,
        c.content_type as contentType,
        c.field,
        c.chunk_index as chunkIndex,
        c.chunk_text as text,
        m.source_path as sourcePath
      FROM chunks c
      LEFT JOIN index_manifest m ON c.recording_id = m.recording_id
      WHERE c.chunk_text LIKE ?
    `;

    const params = [`%${query}%`];

    if (contentType) {
      sql += ' AND c.content_type = ?';
      params.push(contentType);
    }

    sql += ' ORDER BY c.created_at DESC LIMIT ?';
    params.push(limit);

    try {
      const rows = this.db.prepare(sql).all(...params);

      return rows.map(row => ({
        id: row.id,
        contentId: row.contentId,
        contentType: row.contentType || 'recording',
        field: row.field,
        chunkIndex: row.chunkIndex,
        text: row.text,
        sourcePath: row.sourcePath,
        // Add snippet with highlighted match
        snippet: this.createSnippet(row.text, query),
      }));
    } catch (e) {
      console.error('[VaultSearch] Search error:', e.message);
      return [];
    }
  }

  /**
   * Create a snippet with the query highlighted
   */
  createSnippet(text, query, maxLength = 200) {
    const lowerText = text.toLowerCase();
    const lowerQuery = query.toLowerCase();
    const index = lowerText.indexOf(lowerQuery);

    if (index === -1) {
      // Query not found, return start of text
      return text.length > maxLength
        ? text.substring(0, maxLength) + '...'
        : text;
    }

    // Extract context around the match
    const start = Math.max(0, index - 50);
    const end = Math.min(text.length, index + query.length + 150);

    let snippet = text.substring(start, end);

    if (start > 0) snippet = '...' + snippet;
    if (end < text.length) snippet = snippet + '...';

    return snippet;
  }

  /**
   * Get statistics about indexed content
   */
  getStats() {
    if (!this.db) {
      this.initialize();
    }

    try {
      const stats = {
        totalChunks: 0,
        byContentType: {},
        totalContent: 0,
      };

      // Count total chunks
      const totalRow = this.db.prepare('SELECT COUNT(*) as count FROM chunks').get();
      stats.totalChunks = totalRow.count;

      // Count by content type
      const typeRows = this.db.prepare(`
        SELECT content_type, COUNT(*) as count
        FROM chunks
        GROUP BY content_type
      `).all();

      for (const row of typeRows) {
        stats.byContentType[row.content_type || 'recording'] = row.count;
      }

      // Count unique content items
      const contentRow = this.db.prepare('SELECT COUNT(DISTINCT recording_id) as count FROM chunks').get();
      stats.totalContent = contentRow.count;

      return stats;
    } catch (e) {
      console.error('[VaultSearch] Stats error:', e.message);
      return null;
    }
  }

  /**
   * List all indexed content items
   */
  listIndexedContent(options = {}) {
    if (!this.db) {
      this.initialize();
    }

    const { contentType = null, limit = 100 } = options;

    let sql = `
      SELECT
        recording_id as contentId,
        content_type as contentType,
        content_hash as hash,
        indexed_at as indexedAt,
        chunk_count as chunkCount,
        source_path as sourcePath
      FROM index_manifest
    `;

    const params = [];

    if (contentType) {
      sql += ' WHERE content_type = ?';
      params.push(contentType);
    }

    sql += ' ORDER BY indexed_at DESC LIMIT ?';
    params.push(limit);

    try {
      return this.db.prepare(sql).all(...params);
    } catch (e) {
      console.error('[VaultSearch] List error:', e.message);
      return [];
    }
  }

  /**
   * Get content for a specific item
   */
  getContent(contentId) {
    if (!this.db) {
      this.initialize();
    }

    try {
      const chunks = this.db.prepare(`
        SELECT
          field,
          chunk_index as chunkIndex,
          chunk_text as text
        FROM chunks
        WHERE recording_id = ?
        ORDER BY field, chunk_index
      `).all(contentId);

      const manifest = this.db.prepare(`
        SELECT
          content_type as contentType,
          source_path as sourcePath,
          indexed_at as indexedAt
        FROM index_manifest
        WHERE recording_id = ?
      `).get(contentId);

      if (!manifest && chunks.length === 0) {
        return null;
      }

      return {
        contentId,
        contentType: manifest?.contentType || 'recording',
        sourcePath: manifest?.sourcePath,
        indexedAt: manifest?.indexedAt,
        chunks,
        // Combine chunks into full text by field
        fields: this.groupChunksByField(chunks),
      };
    } catch (e) {
      console.error('[VaultSearch] Get content error:', e.message);
      return null;
    }
  }

  /**
   * Group chunks by field and combine text
   */
  groupChunksByField(chunks) {
    const fields = {};

    for (const chunk of chunks) {
      if (!fields[chunk.field]) {
        fields[chunk.field] = [];
      }
      fields[chunk.field].push(chunk);
    }

    // Sort chunks within each field and combine text
    const result = {};
    for (const [field, fieldChunks] of Object.entries(fields)) {
      fieldChunks.sort((a, b) => a.chunkIndex - b.chunkIndex);
      result[field] = fieldChunks.map(c => c.text).join(' ');
    }

    return result;
  }
}

// Singleton instance
let instance = null;

export function getVaultSearchService(vaultPath) {
  if (!instance || instance.vaultPath !== vaultPath) {
    if (instance) {
      instance.close();
    }
    instance = new VaultSearchService(vaultPath);
  }
  return instance;
}

export default VaultSearchService;
