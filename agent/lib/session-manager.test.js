/**
 * Session Manager Tests
 *
 * Run with: node --test lib/session-manager.test.js
 */

import { test, describe, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert';
import fs from 'fs/promises';
import path from 'path';
import { SessionManager } from './session-manager.js';

const TEST_VAULT_PATH = '/tmp/test-vault-' + Date.now();

describe('SessionManager', () => {
  let sessionManager;

  beforeEach(async () => {
    await fs.mkdir(TEST_VAULT_PATH, { recursive: true });
    sessionManager = new SessionManager(TEST_VAULT_PATH);
    await sessionManager.initialize();
  });

  afterEach(async () => {
    try {
      await fs.rm(TEST_VAULT_PATH, { recursive: true, force: true });
    } catch (e) {
      // Ignore cleanup errors
    }
  });

  describe('getSessionKey', () => {
    test('generates correct key without context', () => {
      const key = sessionManager.getSessionKey('agents/daily-insights.md');
      assert.strictEqual(key, 'agents/daily-insights.md:default');
    });

    test('generates correct key with documentPath context', () => {
      const key = sessionManager.getSessionKey('agents/daily-insights.md', { documentPath: 'notes/test.md' });
      assert.strictEqual(key, 'agents/daily-insights.md:notes/test.md');
    });
  });

  describe('getSession', () => {
    test('creates a new session when none exists', async () => {
      const { session } = await sessionManager.getSession('agents/test-agent.md');

      assert.ok(session.id);
      assert.strictEqual(session.agentPath, 'agents/test-agent.md');
      assert.strictEqual(session.key, 'agents/test-agent.md:default');
      assert.deepStrictEqual(session.messages, []);
      assert.ok(session.filePath);
    });

    test('returns existing session on second call', async () => {
      const { session: session1 } = await sessionManager.getSession('agents/test-agent.md');
      const { session: session2 } = await sessionManager.getSession('agents/test-agent.md');

      assert.strictEqual(session1.id, session2.id);
    });

    test('creates session file on disk', async () => {
      const { session } = await sessionManager.getSession('agents/test-agent.md');

      const exists = await fs.access(session.filePath).then(() => true).catch(() => false);
      assert.ok(exists, 'Session file should exist');
    });
  });

  describe('addMessage', () => {
    test('adds message to session', async () => {
      const { session } = await sessionManager.getSession('agents/test-agent.md');
      await sessionManager.addMessage(session.key, 'user', 'Hello!');

      const messages = sessionManager.getMessages(session.key);
      assert.strictEqual(messages.length, 1);
      assert.strictEqual(messages[0].role, 'user');
      assert.strictEqual(messages[0].content, 'Hello!');
    });

    test('adds multiple messages', async () => {
      const { session } = await sessionManager.getSession('agents/test-agent.md');
      await sessionManager.addMessage(session.key, 'user', 'Hello!');
      await sessionManager.addMessage(session.key, 'assistant', 'Hi there!');

      const messages = sessionManager.getMessages(session.key);
      assert.strictEqual(messages.length, 2);
      assert.strictEqual(messages[0].role, 'user');
      assert.strictEqual(messages[1].role, 'assistant');
    });

    test('logs error for non-existent session', async () => {
      await sessionManager.addMessage('nonexistent:key', 'user', 'Hello!');
      // Should not throw, just log error
    });
  });

  describe('saveSession and loadSession', () => {
    test('saves and loads session with messages', async () => {
      // Create and populate session
      const { session } = await sessionManager.getSession('agents/test-agent.md');
      await sessionManager.addMessage(session.key, 'user', 'Hello!');
      await sessionManager.addMessage(session.key, 'assistant', 'Hi there!');

      // Create new session manager and load
      const sessionManager2 = new SessionManager(TEST_VAULT_PATH);
      await sessionManager2.initialize();

      const loadedSession = sessionManager2.getSessionById(session.id);
      assert.ok(loadedSession, 'Session should be loaded');
      assert.strictEqual(loadedSession.messages.length, 2);
      assert.strictEqual(loadedSession.messages[0].content, 'Hello!');
      assert.strictEqual(loadedSession.messages[1].content, 'Hi there!');
    });
  });

  describe('sessionToMarkdown and parseSessionMarkdown', () => {
    test('roundtrip preserves session data', async () => {
      const { session } = await sessionManager.getSession('agents/test-agent.md');
      await sessionManager.addMessage(session.key, 'user', 'Test message');
      await sessionManager.addMessage(session.key, 'assistant', 'Response with **bold** and *italic*');

      // Read the file back
      const content = await fs.readFile(session.filePath, 'utf-8');
      const parsed = sessionManager.parseSessionMarkdown(content, session.filePath);

      assert.strictEqual(parsed.id, session.id);
      assert.strictEqual(parsed.agentPath, session.agentPath);
      assert.strictEqual(parsed.messages.length, 2);
      assert.strictEqual(parsed.messages[0].content, 'Test message');
      assert.ok(parsed.messages[1].content.includes('**bold**'));
    });
  });

  describe('parseMessages', () => {
    test('parses timestamps with milliseconds', () => {
      const body = `## Conversation

### User | 2025-12-07T04:39:47.485Z

Hello world!

### Assistant | 2025-12-07T04:39:48.123Z

Hi there!

`;
      const messages = sessionManager.parseMessages(body);
      assert.strictEqual(messages.length, 2);
      assert.strictEqual(messages[0].role, 'user');
      assert.strictEqual(messages[0].content, 'Hello world!');
      assert.strictEqual(messages[1].role, 'assistant');
    });

    test('parses timestamps without milliseconds', () => {
      const body = `## Conversation

### User | 2025-12-07T04:39:47Z

Hello!

`;
      const messages = sessionManager.parseMessages(body);
      assert.strictEqual(messages.length, 1);
      assert.strictEqual(messages[0].content, 'Hello!');
    });
  });

  describe('listSessions', () => {
    test('returns all sessions', async () => {
      await sessionManager.getSession('agents/agent1.md');
      await sessionManager.getSession('agents/agent2.md');

      const sessions = sessionManager.listSessions();
      assert.strictEqual(sessions.length, 2);
      assert.ok(sessions.some(s => s.agentPath === 'agents/agent1.md'));
      assert.ok(sessions.some(s => s.agentPath === 'agents/agent2.md'));
    });
  });

  describe('clearSession', () => {
    test('clears messages from session', async () => {
      const { session } = await sessionManager.getSession('agents/test-agent.md');
      await sessionManager.addMessage(session.key, 'user', 'Hello!');
      await sessionManager.addMessage(session.key, 'assistant', 'Hi!');

      assert.strictEqual(session.messages.length, 2);

      await sessionManager.clearSession('agents/test-agent.md');

      const { session: clearedSession } = await sessionManager.getSession('agents/test-agent.md');
      assert.strictEqual(clearedSession.messages.length, 0);
    });
  });

  describe('validateSdkSessionId', () => {
    test('returns valid UUID string as-is', () => {
      const validId = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890';
      assert.strictEqual(sessionManager.validateSdkSessionId(validId), validId);
    });

    test('returns null for null input', () => {
      assert.strictEqual(sessionManager.validateSdkSessionId(null), null);
    });

    test('returns null for undefined input', () => {
      assert.strictEqual(sessionManager.validateSdkSessionId(undefined), null);
    });

    test('returns null for empty string', () => {
      assert.strictEqual(sessionManager.validateSdkSessionId(''), null);
    });

    test('returns null for "[object Object]" string', () => {
      assert.strictEqual(sessionManager.validateSdkSessionId('[object Object]'), null);
    });

    test('returns null for strings starting with "[object"', () => {
      assert.strictEqual(sessionManager.validateSdkSessionId('[object Array]'), null);
      assert.strictEqual(sessionManager.validateSdkSessionId('[object Null]'), null);
    });

    test('returns null for object input', () => {
      assert.strictEqual(sessionManager.validateSdkSessionId({}), null);
      assert.strictEqual(sessionManager.validateSdkSessionId({ foo: 'bar' }), null);
    });

    test('returns null for array input', () => {
      assert.strictEqual(sessionManager.validateSdkSessionId([]), null);
    });
  });

  describe('sdkSessionId persistence', () => {
    test('corrupted sdkSessionId is sanitized on load', async () => {
      const { session } = await sessionManager.getSession('agents/test-agent.md');

      // Manually corrupt the session by writing invalid sdkSessionId
      session.sdkSessionId = '[object Object]';
      await sessionManager.saveSession(session);

      // Create new session manager and reload
      const sessionManager2 = new SessionManager(TEST_VAULT_PATH);
      await sessionManager2.initialize();

      const loadedSession = sessionManager2.getSessionById(session.id);
      // Should be null, not the corrupted value
      assert.strictEqual(loadedSession.sdkSessionId, null);
    });

    test('valid sdkSessionId is preserved on save/load', async () => {
      const { session } = await sessionManager.getSession('agents/test-agent.md');
      const validId = 'valid-uuid-1234-5678-90ab';

      session.sdkSessionId = validId;
      await sessionManager.saveSession(session);

      // Check the file contains the valid ID
      const content = await fs.readFile(session.filePath, 'utf-8');
      assert.ok(content.includes(`sdk_session_id: "${validId}"`));

      // Reload and verify
      const sessionManager2 = new SessionManager(TEST_VAULT_PATH);
      await sessionManager2.initialize();

      const loadedSession = sessionManager2.getSessionById(session.id);
      assert.strictEqual(loadedSession.sdkSessionId, validId);
    });

    test('updateSdkSessionId validates before storing', async () => {
      const { session } = await sessionManager.getSession('agents/test-agent.md');

      // Try to update with invalid value
      await sessionManager.updateSdkSessionId(session.key, '[object Object]');

      // Should be null, not the invalid value
      const updatedSession = sessionManager.getSessionById(session.id);
      assert.strictEqual(updatedSession.sdkSessionId, null);

      // Now try with valid value
      await sessionManager.updateSdkSessionId(session.key, 'valid-session-id');
      assert.strictEqual(sessionManager.getSessionById(session.id).sdkSessionId, 'valid-session-id');
    });

    test('object sdkSessionId is saved as empty string', async () => {
      const { session } = await sessionManager.getSession('agents/test-agent.md');

      // Directly set to object (simulating the bug)
      session.sdkSessionId = {};
      await sessionManager.saveSession(session);

      // Check the file - should be empty, not [object Object]
      const content = await fs.readFile(session.filePath, 'utf-8');
      assert.ok(content.includes('sdk_session_id: ""'), 'Should save as empty string, not [object Object]');
      assert.ok(!content.includes('[object Object]'), 'Should not contain [object Object]');
    });
  });
});
