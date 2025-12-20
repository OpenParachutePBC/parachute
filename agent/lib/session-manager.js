/**
 * Session Manager
 *
 * Manages conversation sessions for agents.
 * Sessions are stored as markdown files in the vault for:
 * - Syncing with Obsidian Sync
 * - Human readability
 * - Searchability within Obsidian
 * - Cross-machine session resumption
 *
 * Architecture:
 * - Lazy loading: Only session index loaded at startup (lightweight)
 * - Full sessions loaded on-demand from markdown files
 * - SDK sessions are ephemeral; markdown is source of truth
 * - Context injection when SDK sessions expire
 */

import fs from 'fs/promises';
import fsSync from 'fs';
import path from 'path';
import { randomUUID } from 'crypto';
import { generateSessionTitle } from './title-generator.js';

/**
 * Session resumption info returned to caller for debugging/visibility
 */
export class SessionResumeInfo {
  constructor() {
    this.method = 'new';           // 'sdk_resume' | 'context_injection' | 'new'
    this.sdkSessionValid = false;  // Was SDK session ID available and valid?
    this.sdkResumeAttempted = false;
    this.sdkResumeFailed = false;
    this.contextInjected = false;
    this.messagesInjected = 0;     // How many messages were injected as context
    this.tokensEstimate = 0;       // Rough token estimate for injected context
    this.previousMessageCount = 0; // Total messages in session history
    this.loadedFromDisk = false;   // Was session loaded from markdown file?
    this.cacheHit = false;         // Was session already in memory?
  }

  toJSON() {
    return {
      method: this.method,
      sdkSessionValid: this.sdkSessionValid,
      sdkResumeAttempted: this.sdkResumeAttempted,
      sdkResumeFailed: this.sdkResumeFailed,
      contextInjected: this.contextInjected,
      messagesInjected: this.messagesInjected,
      tokensEstimate: this.tokensEstimate,
      previousMessageCount: this.previousMessageCount,
      loadedFromDisk: this.loadedFromDisk,
      cacheHit: this.cacheHit
    };
  }

  toString() {
    if (this.method === 'sdk_resume') {
      return `[SDK Resume] ${this.previousMessageCount} msgs in history`;
    } else if (this.method === 'context_injection') {
      return `[Context Injection] ${this.messagesInjected}/${this.previousMessageCount} msgs (~${this.tokensEstimate} tokens)`;
    } else {
      return `[New Session]`;
    }
  }
}

export class SessionManager {
  constructor(vaultPath) {
    this.vaultPath = vaultPath;
    this.sessionsPath = path.join(vaultPath, 'agent-sessions');
    // Legacy paths for migration
    this.legacyChatsPath = path.join(vaultPath, 'agent-chats');
    this.legacyLogsPath = path.join(vaultPath, 'agent-logs');

    // Lightweight index: id -> { filePath, agentPath, lastAccessed, archived }
    this.sessionIndex = new Map();

    // Full sessions loaded on-demand (LRU cache behavior)
    this.loadedSessions = new Map();

    // Active SDK session objects
    this.activeSessions = new Map();

    // Cache settings
    this.cacheMaxAge = 30 * 60 * 1000; // 30 minutes
    this.contextTokenBudget = 50000;   // ~50k tokens for context injection
  }

  /**
   * Initialize session manager - builds lightweight index only
   */
  async initialize() {
    // Ensure new directory exists
    await fs.mkdir(this.sessionsPath, { recursive: true });

    // Build lightweight index from files (including legacy paths for migration)
    await this.buildSessionIndex();
    console.log(`[SessionManager] Indexed ${this.sessionIndex.size} sessions (lazy load enabled)`);
  }

  /**
   * Build lightweight session index from markdown files
   * Only extracts frontmatter, not full message content
   * Indexes from new path + legacy paths for migration
   */
  async buildSessionIndex() {
    // Index from new unified path
    try {
      await this.indexSessionsFromDir(this.sessionsPath);
    } catch (e) {
      // Directory may not exist yet
    }

    // Also index from legacy paths for migration
    try {
      await this.indexSessionsFromDir(this.legacyChatsPath);
    } catch (e) {
      // Legacy directory may not exist
    }
    try {
      await this.indexSessionsFromDir(this.legacyLogsPath);
    } catch (e) {
      // Legacy directory may not exist
    }
  }

  /**
   * Recursively index sessions from a directory
   */
  async indexSessionsFromDir(dir) {
    try {
      const entries = await fs.readdir(dir, { withFileTypes: true });

      for (const entry of entries) {
        const fullPath = path.join(dir, entry.name);

        if (entry.isDirectory()) {
          await this.indexSessionsFromDir(fullPath);
        } else if (entry.name.endsWith('.md')) {
          await this.indexSessionFromFile(fullPath);
        }
      }
    } catch (e) {
      // Directory doesn't exist yet
    }
  }

  /**
   * Add a session to the index (lightweight - just frontmatter)
   */
  async indexSessionFromFile(filePath) {
    try {
      const content = await fs.readFile(filePath, 'utf-8');
      const matter = this.parseFrontmatter(content);

      if (!matter.data.session_id) return;

      // Only store lightweight index data
      this.sessionIndex.set(matter.data.session_key, {
        id: matter.data.session_id,
        key: matter.data.session_key,
        filePath,
        agentPath: matter.data.agent,
        agentName: matter.data.agent_name,
        title: matter.data.title || null,
        createdAt: matter.data.created_at,
        lastAccessed: matter.data.last_accessed,
        archived: matter.data.archived === 'true' || matter.data.archived === true,
        sdkSessionId: this.validateSdkSessionId(matter.data.sdk_session_id),
        workingDirectory: matter.data.working_directory || null,
        // Don't load messages - that's the heavy part
        messageCount: (content.match(/### (User|Assistant|System) \|/g) || []).length
      });
    } catch (e) {
      console.error(`[SessionManager] Error indexing ${filePath}:`, e.message);
    }
  }

  /**
   * Load full session from markdown file
   */
  async loadSessionFromFile(filePath) {
    try {
      const content = await fs.readFile(filePath, 'utf-8');
      const session = this.parseSessionMarkdown(content, filePath);

      if (session) {
        this.loadedSessions.set(session.key, session);
        console.log(`[SessionManager] Loaded session from disk: ${session.key} (${session.messages.length} messages)`);
      }

      return session;
    } catch (e) {
      console.error(`[SessionManager] Error loading session from ${filePath}:`, e.message);
      return null;
    }
  }

  /**
   * Load full session from markdown file (synchronous version)
   * Used by getSessionById when session is in index but not loaded
   */
  loadSessionFromFileSync(filePath) {
    try {
      const content = fsSync.readFileSync(filePath, 'utf-8');
      const session = this.parseSessionMarkdown(content, filePath);

      if (session) {
        this.loadedSessions.set(session.key, session);
        console.log(`[SessionManager] Loaded session from disk (sync): ${session.key} (${session.messages.length} messages)`);
      }

      return session;
    } catch (e) {
      console.error(`[SessionManager] Error loading session from ${filePath}:`, e.message);
      return null;
    }
  }

  /**
   * Parse a session from markdown format
   */
  parseSessionMarkdown(content, filePath) {
    const matter = this.parseFrontmatter(content);
    if (!matter.data.session_id) return null;

    const messages = this.parseMessages(matter.body);

    // Validate sdkSessionId when loading from file
    const rawSdkId = matter.data.sdk_session_id;
    const validatedSdkId = this.validateSdkSessionId(rawSdkId);

    return {
      id: matter.data.session_id,
      key: matter.data.session_key,
      agentPath: matter.data.agent,
      title: matter.data.title || null,
      context: matter.data.context || {},
      sdkSessionId: validatedSdkId,
      messages,
      filePath,
      createdAt: matter.data.created_at,
      lastAccessed: matter.data.last_accessed,
      archived: matter.data.archived === 'true' || matter.data.archived === true,
      workingDirectory: matter.data.working_directory || null
    };
  }

  /**
   * Parse frontmatter from markdown
   */
  parseFrontmatter(content) {
    const match = content.match(/^---\n([\s\S]*?)\n---\n([\s\S]*)$/);
    if (!match) {
      return { data: {}, body: content };
    }

    const yamlStr = match[1];
    const body = match[2];

    // Simple YAML parser for our use case
    const data = {};
    for (const line of yamlStr.split('\n')) {
      const colonIdx = line.indexOf(':');
      if (colonIdx > 0) {
        const key = line.slice(0, colonIdx).trim();
        let value = line.slice(colonIdx + 1).trim();

        // Handle quoted strings
        if ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'"))) {
          value = value.slice(1, -1);
        }

        // Handle objects (simple case) - but NOT for sdk_session_id which should stay as string
        if (key !== 'sdk_session_id' && (value === '' || value === '{}')) {
          value = {};
        }
        // Keep empty strings as null for sdk_session_id
        if (key === 'sdk_session_id' && value === '') {
          value = null;
        }

        data[key] = value;
      }
    }

    return { data, body };
  }

  /**
   * Parse messages from markdown body
   */
  parseMessages(body) {
    const messages = [];
    // Match timestamps with or without milliseconds (e.g., 2025-12-07T04:39:47.485Z or 2025-12-07T04:39:47Z)
    const regex = /### (User|Assistant|System) \| (\d{4}-\d{2}-\d{2}T[\d:.]+Z?)\n\n([\s\S]*?)(?=\n### |\n---|\n## |$)/g;

    let match;
    while ((match = regex.exec(body)) !== null) {
      messages.push({
        role: match[1].toLowerCase(),
        timestamp: match[2],
        content: match[3].trim()
      });
    }

    return messages;
  }

  /**
   * Generate session key from agent path and optional context
   */
  getSessionKey(agentPath, context = {}) {
    // Use sessionId if provided (for unique chat sessions from plugin)
    // Fall back to documentPath for doc agents, or 'default'
    const contextKey = context.sessionId || context.documentPath || 'default';
    return `${agentPath}:${contextKey}`;
  }

  /**
   * Get the file path for a session
   */
  getSessionFilePath(agentPath, context = {}) {
    const agentName = agentPath.replace('agents/', '').replace('.md', '');
    const today = new Date().toISOString().split('T')[0];

    if (context.sessionId) {
      // Plugin session with unique ID
      return path.join(this.sessionsPath, agentName, `${today}-${context.sessionId}.md`);
    } else if (context.documentPath) {
      // Doc-specific session
      const docName = context.documentPath.replace(/\//g, '-').replace('.md', '');
      return path.join(this.sessionsPath, agentName, `${today}-${docName}.md`);
    } else {
      // General session (legacy)
      return path.join(this.sessionsPath, agentName, `${today}.md`);
    }
  }

  /**
   * Get or create a session for an agent
   * Returns { session, resumeInfo } for debugging visibility
   */
  async getSession(agentPath, context = {}) {
    const key = this.getSessionKey(agentPath, context);
    const resumeInfo = new SessionResumeInfo();

    console.log(`[SessionManager] getSession called for key: ${key}`);

    // Check if fully loaded in memory
    if (this.loadedSessions.has(key)) {
      const session = this.loadedSessions.get(key);
      session.lastAccessed = new Date().toISOString();
      resumeInfo.cacheHit = true;
      resumeInfo.previousMessageCount = session.messages.length;
      resumeInfo.sdkSessionValid = !!session.sdkSessionId;
      console.log(`[SessionManager] Cache hit: ${session.id} (${session.messages.length} messages)`);
      return { session, resumeInfo };
    }

    // Check if indexed but not loaded
    if (this.sessionIndex.has(key)) {
      const index = this.sessionIndex.get(key);
      resumeInfo.loadedFromDisk = true;

      // Load full session from disk
      const session = await this.loadSessionFromFile(index.filePath);
      if (session) {
        session.lastAccessed = new Date().toISOString();
        resumeInfo.previousMessageCount = session.messages.length;
        resumeInfo.sdkSessionValid = !!session.sdkSessionId;
        await this.saveSession(session);
        console.log(`[SessionManager] Loaded from disk: ${session.id} (${session.messages.length} messages)`);
        return { session, resumeInfo };
      }
    }

    // Create new session
    const filePath = this.getSessionFilePath(agentPath, context);

    // Ensure directory exists
    await fs.mkdir(path.dirname(filePath), { recursive: true });

    const session = {
      id: randomUUID(),
      key,
      agentPath,
      title: null,
      context,
      sdkSessionId: null,
      messages: [],
      filePath,
      createdAt: new Date().toISOString(),
      lastAccessed: new Date().toISOString(),
      archived: false,
      workingDirectory: context.workingDirectory || null
    };

    this.loadedSessions.set(key, session);
    this.sessionIndex.set(key, {
      id: session.id,
      key,
      filePath,
      agentPath,
      title: null,
      createdAt: session.createdAt,
      lastAccessed: session.lastAccessed,
      archived: false,
      sdkSessionId: null,
      messageCount: 0,
      workingDirectory: session.workingDirectory
    });

    await this.saveSession(session);

    resumeInfo.method = 'new';
    console.log(`[SessionManager] Created new session: ${session.id} at ${filePath}`);
    return { session, resumeInfo };
  }

  /**
   * Build context string from message history for injection
   * Returns { contextString, messagesUsed, tokensEstimate }
   */
  buildContextFromHistory(messages) {
    if (!messages || messages.length === 0) {
      return { contextString: '', messagesUsed: 0, tokensEstimate: 0 };
    }

    const contextMessages = [];
    let estimatedTokens = 0;

    // Work backwards from most recent
    for (let i = messages.length - 1; i >= 0; i--) {
      const msg = messages[i];
      // Skip system messages (errors, etc.)
      if (msg.role === 'system') continue;

      const msgTokens = Math.ceil(msg.content.length / 4); // Rough estimate: 4 chars/token

      if (estimatedTokens + msgTokens > this.contextTokenBudget) {
        // Add indicator of omitted messages
        if (i > 0) {
          contextMessages.unshift({
            role: 'system',
            content: `[${i} earlier messages omitted for context limits]`
          });
        }
        break;
      }

      contextMessages.unshift(msg);
      estimatedTokens += msgTokens;
    }

    // Format as conversation history
    const contextString = contextMessages.map(m => {
      const role = m.role.charAt(0).toUpperCase() + m.role.slice(1);
      return `### ${role}\n${m.content}`;
    }).join('\n\n');

    return {
      contextString,
      messagesUsed: contextMessages.filter(m => m.role !== 'system').length,
      tokensEstimate: estimatedTokens
    };
  }

  /**
   * Prepare a prompt with context injection if SDK session is unavailable
   * Returns { prompt, resumeInfo, queryOptions }
   */
  preparePromptWithContext(session, message, resumeInfo) {
    // Check if we have a valid SDK session ID
    const sdkId = session.sdkSessionId;
    const isValidSessionId = this.validateSdkSessionId(sdkId);

    resumeInfo.sdkSessionValid = !!isValidSessionId;
    resumeInfo.previousMessageCount = session.messages.length;

    if (isValidSessionId) {
      // We have a valid SDK session - try to resume
      resumeInfo.method = 'sdk_resume';
      resumeInfo.sdkResumeAttempted = true;
      console.log(`[SessionManager] Preparing SDK resume with session: ${sdkId}`);

      return {
        prompt: message,
        resumeInfo,
        queryOptions: { resume: sdkId }
      };
    }

    // No valid SDK session - inject context from history
    if (session.messages.length > 0) {
      const { contextString, messagesUsed, tokensEstimate } = this.buildContextFromHistory(session.messages);

      if (contextString) {
        resumeInfo.method = 'context_injection';
        resumeInfo.contextInjected = true;
        resumeInfo.messagesInjected = messagesUsed;
        resumeInfo.tokensEstimate = tokensEstimate;

        const prompt = `## Previous Conversation\n\n${contextString}\n\n---\n\n## Current Message\n\n${message}`;

        console.log(`[SessionManager] Context injection: ${messagesUsed} messages (~${tokensEstimate} tokens)`);

        return {
          prompt,
          resumeInfo,
          queryOptions: {} // No resume - new SDK session
        };
      }
    }

    // No history - new session
    resumeInfo.method = 'new';
    console.log(`[SessionManager] New session, no context to inject`);

    return {
      prompt: message,
      resumeInfo,
      queryOptions: {}
    };
  }

  /**
   * Handle SDK resume failure - mark session for context injection on next message
   */
  handleSdkResumeFailed(session, resumeInfo) {
    resumeInfo.sdkResumeFailed = true;
    resumeInfo.method = 'context_injection'; // Will use this on retry
    session.sdkSessionId = null; // Clear invalid SDK session
    console.log(`[SessionManager] SDK resume failed, will use context injection`);
  }

  /**
   * Save session to markdown file
   */
  async saveSession(session) {
    try {
      // Ensure directory exists before writing
      await fs.mkdir(path.dirname(session.filePath), { recursive: true });
      const markdown = this.sessionToMarkdown(session);
      await fs.writeFile(session.filePath, markdown, 'utf-8');

      // Update index
      this.sessionIndex.set(session.key, {
        id: session.id,
        key: session.key,
        filePath: session.filePath,
        agentPath: session.agentPath,
        title: session.title,
        createdAt: session.createdAt,
        lastAccessed: session.lastAccessed,
        archived: session.archived,
        sdkSessionId: session.sdkSessionId,
        messageCount: session.messages.length,
        workingDirectory: session.workingDirectory
      });

      console.log(`[SessionManager] Saved session to ${session.filePath}`);
    } catch (e) {
      console.error(`[SessionManager] Failed to save session to ${session.filePath}:`, e.message);
    }
  }

  /**
   * Validate that a value is a valid SDK session ID
   * Returns the value if valid, or null if invalid
   */
  validateSdkSessionId(value) {
    // Must be a non-empty string that doesn't look like a stringified object
    if (!value || typeof value !== 'string') {
      return null;
    }
    if (value.length === 0) {
      return null;
    }
    if (value === '[object Object]' || value.startsWith('[object')) {
      console.warn(`[SessionManager] Rejecting invalid sdkSessionId: ${value}`);
      return null;
    }
    return value;
  }

  /**
   * Convert session to markdown format
   */
  sessionToMarkdown(session) {
    const agentName = session.agentPath.replace('agents/', '').replace('.md', '');

    // Validate sdkSessionId before saving
    const validatedSdkId = this.validateSdkSessionId(session.sdkSessionId) || '';

    // Serialize context if it has values
    const contextYaml = Object.keys(session.context || {}).length > 0
      ? `context: ${JSON.stringify(session.context)}`
      : '';

    // Title line - only include if we have a title
    const titleYaml = session.title ? `title: "${session.title}"` : '';

    // Working directory line - only include if set
    const workingDirYaml = session.workingDirectory ? `working_directory: "${session.workingDirectory}"` : '';

    // Use title for heading if available, otherwise default
    const heading = session.title || `Chat with ${agentName}`;

    let md = `---
session_id: "${session.id}"
session_key: "${session.key}"
agent: "${session.agentPath}"
agent_name: "${agentName}"
${titleYaml}
type: chat
created_at: "${session.createdAt}"
last_accessed: "${session.lastAccessed}"
sdk_session_id: "${validatedSdkId}"
archived: ${session.archived || false}
${workingDirYaml}
${contextYaml}
---

# ${heading}

`;

    if (session.context?.documentPath) {
      md += `> Context: [[${session.context.documentPath}]]\n\n`;
    }

    md += `## Conversation\n\n`;

    for (const msg of session.messages) {
      const role = msg.role.charAt(0).toUpperCase() + msg.role.slice(1);
      const timestamp = msg.timestamp || new Date().toISOString();
      md += `### ${role} | ${timestamp}\n\n${msg.content}\n\n`;
    }

    return md;
  }

  /**
   * Update session with SDK session ID
   */
  async updateSdkSessionId(sessionKey, sdkSessionId) {
    const session = this.loadedSessions.get(sessionKey);
    if (session) {
      // Validate before storing
      const validated = this.validateSdkSessionId(sdkSessionId);
      session.sdkSessionId = validated;
      await this.saveSession(session);
      console.log(`[SessionManager] Updated SDK session ID: ${validated ? validated.slice(0, 20) + '...' : 'null'}`);
    }
  }

  /**
   * Add a message to session history
   */
  async addMessage(sessionKey, role, content) {
    const session = this.loadedSessions.get(sessionKey);
    if (session) {
      session.messages.push({
        role,
        content,
        timestamp: new Date().toISOString()
      });
      session.lastAccessed = new Date().toISOString();
      await this.saveSession(session);
      console.log(`[SessionManager] Added ${role} message to session ${sessionKey} (now ${session.messages.length} messages)`);
    } else {
      console.error(`[SessionManager] Cannot add message - session not found: ${sessionKey}`);
    }
  }

  /**
   * Generate a title for a session if it doesn't have one
   * Should be called after the first user+assistant exchange
   *
   * @param {string} sessionKey - The session key
   * @param {string} agentName - The agent name for title context
   * @returns {Promise<string|null>} - Generated title or null
   */
  async maybeGenerateTitle(sessionKey, agentName) {
    const session = this.loadedSessions.get(sessionKey);
    if (!session) {
      console.log(`[SessionManager] Cannot generate title - session not found: ${sessionKey}`);
      return null;
    }

    // Already has a title
    if (session.title) {
      console.log(`[SessionManager] Session already has title: "${session.title}"`);
      return session.title;
    }

    // Need at least one user message and one assistant message
    const hasUser = session.messages.some(m => m.role === 'user');
    const hasAssistant = session.messages.some(m => m.role === 'assistant');
    if (!hasUser || !hasAssistant) {
      console.log(`[SessionManager] Not enough messages for title generation (user: ${hasUser}, assistant: ${hasAssistant})`);
      return null;
    }

    // Generate title using Haiku
    try {
      const title = await generateSessionTitle(session.messages, agentName);
      if (title) {
        session.title = title;
        await this.saveSession(session);
        console.log(`[SessionManager] Set session title: "${title}"`);
        return title;
      }
    } catch (error) {
      console.error(`[SessionManager] Error generating title:`, error.message);
    }

    return null;
  }

  /**
   * Get message history for a session
   */
  getMessages(sessionKey) {
    const session = this.loadedSessions.get(sessionKey);
    return session?.messages || [];
  }

  /**
   * Clear a session (archive old, start fresh)
   */
  async clearSession(agentPath, context = {}) {
    const key = this.getSessionKey(agentPath, context);

    if (this.loadedSessions.has(key)) {
      const session = this.loadedSessions.get(key);

      // Close active SDK session if any
      if (this.activeSessions.has(key)) {
        const activeSession = this.activeSessions.get(key);
        try {
          activeSession.close();
        } catch (e) {
          // Ignore close errors
        }
        this.activeSessions.delete(key);
      }

      // Archive old file by renaming with timestamp
      if (session.messages.length > 0) {
        const archivePath = session.filePath.replace('.md', `-${Date.now()}.md`);
        try {
          await fs.rename(session.filePath, archivePath);
        } catch (e) {
          // Ignore if file doesn't exist
        }
      }

      // Reset session
      session.sdkSessionId = null;
      session.messages = [];
      session.lastAccessed = new Date().toISOString();
      session.filePath = this.getSessionFilePath(agentPath, context);

      await this.saveSession(session);
      console.log(`[SessionManager] Cleared session: ${key}`);
    }
  }

  /**
   * Delete a session entirely
   */
  async deleteSession(agentPath, context = {}) {
    const key = this.getSessionKey(agentPath, context);

    if (this.activeSessions.has(key)) {
      const activeSession = this.activeSessions.get(key);
      try {
        activeSession.close();
      } catch (e) {
        // Ignore
      }
      this.activeSessions.delete(key);
    }

    const session = this.loadedSessions.get(key);
    if (session?.filePath) {
      try {
        await fs.unlink(session.filePath);
      } catch (e) {
        // Ignore if file doesn't exist
      }
    }

    this.loadedSessions.delete(key);
    this.sessionIndex.delete(key);
    console.log(`[SessionManager] Deleted session: ${key}`);
  }

  /**
   * List all sessions (from index - lightweight)
   */
  listSessions() {
    return Array.from(this.sessionIndex.values()).map(s => {
      // Extract the context sessionId from the session_key
      // Format: "agentPath:contextSessionId" or "agentPath:default"
      const keyParts = s.key ? s.key.split(':') : [];
      const contextSessionId = keyParts.length > 1 ? keyParts.slice(1).join(':') : null;

      return {
        id: s.id,
        agentPath: s.agentPath,
        agentName: s.agentName || s.agentPath.replace('agents/', '').replace('.md', ''),
        title: s.title || null,
        messageCount: s.messageCount || 0,
        createdAt: s.createdAt,
        lastAccessed: s.lastAccessed,
        filePath: s.filePath.replace(this.vaultPath + '/', ''),
        archived: s.archived || false,
        workingDirectory: s.workingDirectory || null,
        // Include context info for session routing
        context: contextSessionId && contextSessionId !== 'default'
          ? { sessionId: contextSessionId }
          : null
      };
    });
  }

  /**
   * Get session by ID (loads from disk synchronously if needed)
   */
  getSessionById(sessionId) {
    // Check loaded sessions first
    for (const session of this.loadedSessions.values()) {
      if (session.id === sessionId) {
        return session;
      }
    }

    // Check index and load if needed
    for (const index of this.sessionIndex.values()) {
      if (index.id === sessionId) {
        // Load from disk synchronously
        return this.loadSessionFromFileSync(index.filePath);
      }
    }

    return null;
  }

  /**
   * Get session by ID (async - loads from disk if needed)
   */
  async getSessionByIdAsync(sessionId) {
    // Check loaded sessions first
    for (const session of this.loadedSessions.values()) {
      if (session.id === sessionId) {
        return session;
      }
    }

    // Check index and load if needed
    for (const index of this.sessionIndex.values()) {
      if (index.id === sessionId) {
        return await this.loadSessionFromFile(index.filePath);
      }
    }

    return null;
  }

  /**
   * Archive a session by ID
   */
  async archiveSession(sessionId) {
    const session = await this.getSessionByIdAsync(sessionId);
    if (session) {
      session.archived = true;
      session.lastAccessed = new Date().toISOString();
      await this.saveSession(session);
      console.log(`[SessionManager] Archived session: ${sessionId}`);
      return true;
    }
    return false;
  }

  /**
   * Unarchive a session by ID
   */
  async unarchiveSession(sessionId) {
    const session = await this.getSessionByIdAsync(sessionId);
    if (session) {
      session.archived = false;
      session.lastAccessed = new Date().toISOString();
      await this.saveSession(session);
      console.log(`[SessionManager] Unarchived session: ${sessionId}`);
      return true;
    }
    return false;
  }

  /**
   * Delete a session by ID
   */
  async deleteSessionById(sessionId) {
    const session = await this.getSessionByIdAsync(sessionId);
    if (!session) return false;

    // Close active SDK session if any
    if (this.activeSessions.has(session.key)) {
      const activeSession = this.activeSessions.get(session.key);
      try {
        activeSession.close();
      } catch (e) {
        // Ignore
      }
      this.activeSessions.delete(session.key);
    }

    // Delete the file
    if (session.filePath) {
      try {
        await fs.unlink(session.filePath);
      } catch (e) {
        // Ignore if file doesn't exist
      }
    }

    this.loadedSessions.delete(session.key);
    this.sessionIndex.delete(session.key);
    console.log(`[SessionManager] Deleted session by ID: ${sessionId}`);
    return true;
  }

  /**
   * Store active SDK session object
   */
  setActiveSession(sessionKey, sdkSession) {
    this.activeSessions.set(sessionKey, sdkSession);
  }

  /**
   * Get active SDK session object
   */
  getActiveSession(sessionKey) {
    return this.activeSessions.get(sessionKey);
  }

  /**
   * Evict stale sessions from memory cache
   */
  evictStaleSessions() {
    const now = Date.now();
    let evicted = 0;

    for (const [key, session] of this.loadedSessions) {
      const lastAccess = new Date(session.lastAccessed).getTime();
      if (now - lastAccess > this.cacheMaxAge) {
        this.loadedSessions.delete(key);
        evicted++;
      }
    }

    if (evicted > 0) {
      console.log(`[SessionManager] Evicted ${evicted} stale sessions from cache`);
    }

    return evicted;
  }

  /**
   * Clean up old sessions (archive sessions older than N days)
   */
  async cleanupOldSessions(maxAgeDays = 30) {
    // Evict stale sessions from memory
    this.evictStaleSessions();

    // For markdown storage, we keep files but could archive old ones
    // For now, just log
    const cutoff = Date.now() - (maxAgeDays * 24 * 60 * 60 * 1000);
    let oldCount = 0;

    for (const index of this.sessionIndex.values()) {
      const lastAccessed = new Date(index.lastAccessed).getTime();
      if (lastAccessed < cutoff) {
        oldCount++;
      }
    }

    if (oldCount > 0) {
      console.log(`[SessionManager] ${oldCount} sessions older than ${maxAgeDays} days`);
    }

    return 0; // Don't actually delete - keep for history
  }

  /**
   * Get session stats for debugging
   */
  getStats() {
    return {
      indexedSessions: this.sessionIndex.size,
      loadedSessions: this.loadedSessions.size,
      activeSdkSessions: this.activeSessions.size,
      cacheMaxAge: this.cacheMaxAge,
      contextTokenBudget: this.contextTokenBudget
    };
  }
}

export default SessionManager;
