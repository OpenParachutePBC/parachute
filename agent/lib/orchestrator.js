/**
 * Agent Orchestrator
 *
 * Central controller that manages agent execution:
 * - Loads agents from markdown definitions
 * - Manages the execution queue
 * - Runs agents via Claude Agent SDK
 * - Handles spawn requests with depth limiting
 * - Enforces permissions
 */

import { query } from '@anthropic-ai/claude-agent-sdk';
import path from 'path';
import fs from 'fs/promises';
import { loadAgent, buildSystemPrompt, hasPermission, matchesPatterns, loadAllAgents, AgentType } from './agent-loader.js';
import { AgentQueue, Status, Priority } from './queue.js';
import { DocumentScanner, AgentStatus, parseTrigger, shouldTriggerFire } from './document-scanner.js';
import { SessionManager } from './session-manager.js';
import { loadAgentContext, formatContextForPrompt } from './context-loader.js';
import { loadMcpServers, resolveMcpServers, listMcpServers, addMcpServer, removeMcpServer } from './mcp-loader.js';
import { discoverSkills, loadSkill, createSkill, deleteSkill, ensureSkillsDir } from './skills-loader.js';
import { EventEmitter } from 'events';
import { orchestratorLogger as log } from './logger.js';

/**
 * Default orchestrator configuration
 */
const DEFAULT_CONFIG = {
  maxDepth: 3,           // Max agent spawn depth
  maxConcurrent: 1,      // Max concurrent agent executions
  defaultTimeout: 300,   // Default timeout in seconds
  persistQueue: true     // Persist queue to disk
};

/**
 * Agent Orchestrator class
 */
export class Orchestrator extends EventEmitter {
  constructor(vaultPath, config = {}) {
    super();
    this.vaultPath = vaultPath;
    this.config = { ...DEFAULT_CONFIG, ...config };

    // Initialize queue
    this.queue = new AgentQueue({
      maxSize: 100,
      persistPath: this.config.persistQueue
        ? path.join(vaultPath, '.queue', 'queue.json')
        : null,
      keepCompleted: 50
    });

    // Track running executions
    this.running = new Map();

    // Processing state
    this.isProcessing = false;

    // Document scanner
    this.documentScanner = new DocumentScanner(vaultPath);

    // Session manager for chatbot agents
    this.sessionManager = new SessionManager(vaultPath);

    // Pending permission requests (for interactive approval flow)
    this.pendingPermissions = new Map();

    // Queue item event streams (for watching running queue items)
    // Map<queueItemId, EventEmitter>
    this.queueStreams = new Map();

    // Permission cleanup interval (to prevent memory leaks)
    this.permissionCleanupInterval = null;
  }

  /**
   * Permission tiers for tool access:
   * - TIER 1 (always allow): Read-only tools
   * - TIER 2 (configurable): Write tools - ask if outside allowed paths
   * - TIER 3 (ask first): MCP tools - ask unless pre-approved for session
   */
  // TIER 1: Read-only tools - always allow
  static TIER1_ALWAYS_ALLOW = [
    'Read', 'Glob', 'Grep', 'LS',           // File reading & search
    'WebSearch', 'WebFetch',                 // Web access
    'NotebookRead',                          // Notebook reading
    'Task'                                   // Sub-agent spawning (for complex tasks)
  ];
  // TIER 2: Write tools - check against allowed paths
  static TIER2_WRITE_TOOLS = [
    'Write', 'Edit', 'MultiEdit',            // File writing
    'Bash',                                  // Command execution
    'NotebookEdit'                           // Notebook editing
  ];

  /**
   * Create a canUseTool callback for an agent that enforces permissions
   * and can request user approval for out-of-bounds operations.
   *
   * This callback will BLOCK and wait for user approval when a write
   * operation is attempted outside the allowed paths, or when an MCP
   * tool is used for the first time in a session.
   *
   * @param {object} agent - Agent definition
   * @param {string} sessionId - Session ID for tracking
   * @param {Function} onDenial - Callback when permission is denied
   * @param {object} sessionSettings - Session-level settings (approved MCPs, etc.)
   */
  createPermissionHandler(agent, sessionId, onDenial = null, sessionSettings = {}) {
    // Track MCPs approved during this session
    const approvedMcpsThisSession = new Set(sessionSettings.approvedMcps || []);

    return async (toolName, input, options) => {
      // Log ALL tool calls for debugging
      console.log(`[Orchestrator] canUseTool called: ${toolName}`, JSON.stringify({
        input: typeof input === 'object' ? Object.keys(input) : input,
        blockedPath: options?.blockedPath,
        decisionReason: options?.decisionReason
      }));

      // ─────────────────────────────────────────────────────────────────
      // TIER 1: Always allow read-only tools
      // ─────────────────────────────────────────────────────────────────
      if (Orchestrator.TIER1_ALWAYS_ALLOW.includes(toolName)) {
        console.log(`[Orchestrator] TIER 1 auto-allow: ${toolName}`);
        return { behavior: 'allow', updatedInput: input };
      }

      // ─────────────────────────────────────────────────────────────────
      // TIER 3: MCP tools - ask first unless pre-approved
      // MCP tools have names like mcp__servername__toolname
      // ─────────────────────────────────────────────────────────────────
      if (toolName.startsWith('mcp__')) {
        const mcpParts = toolName.split('__');
        const mcpServerName = mcpParts[1];
        const mcpToolName = mcpParts[2] || 'unknown';

        // Check if this MCP server is pre-approved for this session
        if (approvedMcpsThisSession.has(mcpServerName)) {
          console.log(`[Orchestrator] MCP auto-allow (session-approved): ${toolName}`);
          return { behavior: 'allow', updatedInput: input };
        }

        // Check if globally approved in agent config
        const approvedMcps = agent.permissions?.approvedMcps || [];
        if (approvedMcps.includes(mcpServerName) || approvedMcps.includes('*')) {
          console.log(`[Orchestrator] MCP auto-allow (agent config): ${toolName}`);
          return { behavior: 'allow', updatedInput: input };
        }

        // Request permission for this MCP tool
        console.log(`[Orchestrator] MCP requires approval: ${toolName}`);

        const requestId = `${sessionId}-${options?.toolUseID || Date.now()}`;
        const { promise, resolve } = this.createPermissionPromise(requestId);

        const permissionRequest = {
          id: requestId,
          type: 'mcp',
          toolName,
          mcpServer: mcpServerName,
          mcpTool: mcpToolName,
          input,
          agentName: agent.name,
          agentPath: agent.path,
          timestamp: Date.now(),
          status: 'pending',
          resolve
        };

        this.pendingPermissions.set(requestId, permissionRequest);
        this.emit('permissionRequest', {
          ...permissionRequest,
          resolve: undefined
        });

        const timeoutMs = 120000;
        const decision = await Promise.race([
          promise,
          new Promise(r => setTimeout(() => r('timeout'), timeoutMs))
        ]);

        console.log(`[Orchestrator] MCP permission decision for ${requestId}: ${decision}`);
        this.pendingPermissions.delete(requestId);

        if (decision === 'granted' || decision === 'allow_session') {
          // If allow_session, remember for future calls in this session
          if (decision === 'allow_session') {
            approvedMcpsThisSession.add(mcpServerName);
            console.log(`[Orchestrator] MCP ${mcpServerName} approved for session`);
          }
          return { behavior: 'allow', updatedInput: input };
        } else if (decision === 'timeout') {
          if (onDenial) onDenial({ toolName, mcpServer: mcpServerName, reason: 'timeout' });
          return {
            behavior: 'deny',
            message: `MCP tool approval timed out.`,
            interrupt: false
          };
        } else {
          if (onDenial) onDenial({ toolName, mcpServer: mcpServerName, reason: 'denied' });
          return {
            behavior: 'deny',
            message: `MCP tool ${mcpToolName} denied by user.`,
            interrupt: false
          };
        }
      }

      // ─────────────────────────────────────────────────────────────────
      // TIER 2: Write tools - check against allowed paths
      // ─────────────────────────────────────────────────────────────────
      let filePath = input.file_path || input.path;

      // Convert absolute paths to relative paths for permission matching
      // SDK provides absolute paths but permissions use relative patterns
      if (filePath && filePath.startsWith(this.vaultPath)) {
        filePath = filePath.slice(this.vaultPath.length).replace(/^\//, '');
        console.log(`[Orchestrator] Converted to relative path: ${filePath}`);
      }

      // Check if this is a write operation (uses TIER2 tools)
      const isWriteOp = Orchestrator.TIER2_WRITE_TOOLS.includes(toolName);

      // For Bash, check if agent has unrestricted write permissions
      // If write: ['*'], auto-approve Bash. Otherwise request approval.
      if (toolName === 'Bash' && input.command) {
        const cmd = input.command;
        const writePatterns = agent.permissions?.write || ['*'];
        const hasFullWriteAccess = writePatterns.includes('*');

        if (hasFullWriteAccess) {
          // Agent has full write access, auto-approve Bash
          console.log(`[Orchestrator] Bash auto-approved (agent has write: ['*']): ${cmd}`);
          return { behavior: 'allow', updatedInput: input };
        }

        // Agent has restricted write access, request approval for Bash
        console.log(`[Orchestrator] Bash command requires approval: ${cmd}`);

        const requestId = `${sessionId}-${options.toolUseID}`;
        const { promise, resolve } = this.createPermissionPromise(requestId);

        const permissionRequest = {
          id: requestId,
          toolName: 'Bash',
          filePath: cmd,  // Use command as the "path" for display
          input,
          agentName: agent.name,
          agentPath: agent.path,
          allowedPatterns: writePatterns,
          timestamp: Date.now(),
          status: 'pending',
          resolve
        };

        this.pendingPermissions.set(requestId, permissionRequest);
        this.emit('permissionRequest', {
          ...permissionRequest,
          resolve: undefined
        });

        const timeoutMs = 120000;
        const decision = await Promise.race([
          promise,
          new Promise(r => setTimeout(() => r('timeout'), timeoutMs))
        ]);

        console.log(`[Orchestrator] Bash permission decision for ${requestId}: ${decision}`);

        // Clean up the permission request immediately after decision
        this.pendingPermissions.delete(requestId);

        if (decision === 'granted') {
          return { behavior: 'allow', updatedInput: input };
        } else if (decision === 'timeout') {
          if (onDenial) onDenial({ toolName: 'Bash', filePath: cmd, reason: 'timeout' });
          return {
            behavior: 'deny',
            message: `Bash command approval timed out.`,
            interrupt: false
          };
        } else {
          if (onDenial) onDenial({ toolName: 'Bash', filePath: cmd, reason: 'denied' });
          return {
            behavior: 'deny',
            message: `Bash command denied by user.`,
            interrupt: false
          };
        }
      }

      if (isWriteOp && filePath) {
        const writePatterns = agent.permissions?.write || ['*'];
        const isAllowed = matchesPatterns(filePath, writePatterns);

        if (!isAllowed) {
          console.log(`[Orchestrator] Permission check: ${toolName} to ${filePath} - needs approval`);

          // Create a permission request
          const requestId = `${sessionId}-${options.toolUseID}`;

          // Create a promise that will resolve when user responds
          const { promise, resolve } = this.createPermissionPromise(requestId);

          const permissionRequest = {
            id: requestId,
            toolName,
            filePath,
            input,
            agentName: agent.name,
            agentPath: agent.path,
            allowedPatterns: writePatterns,
            timestamp: Date.now(),
            status: 'pending',
            resolve  // Store resolver so grant/deny can call it
          };

          // Store the pending request
          this.pendingPermissions.set(requestId, permissionRequest);

          // Emit event for listeners (SSE, WebSocket, etc.)
          this.emit('permissionRequest', {
            ...permissionRequest,
            resolve: undefined  // Don't send the resolver
          });

          console.log(`[Orchestrator] Waiting for user approval on ${requestId}...`);

          // Wait for user decision (with timeout)
          const timeoutMs = 120000; // 2 minutes
          const decision = await Promise.race([
            promise,
            new Promise(r => setTimeout(() => r('timeout'), timeoutMs))
          ]);

          console.log(`[Orchestrator] Permission decision for ${requestId}: ${decision}`);

          // Clean up the permission request immediately after decision
          this.pendingPermissions.delete(requestId);

          if (decision === 'granted') {
            // User approved - allow the operation
            return {
              behavior: 'allow',
              updatedInput: input
            };
          } else if (decision === 'timeout') {
            // Track this denial
            if (onDenial) onDenial({ toolName, filePath, reason: 'timeout' });
            return {
              behavior: 'deny',
              message: `Permission request timed out after ${timeoutMs/1000} seconds. The user did not respond.`,
              interrupt: false
            };
          } else {
            // User denied or other - track this denial
            if (onDenial) onDenial({ toolName, filePath, reason: 'denied' });
            return {
              behavior: 'deny',
              message: `Write permission denied by user for "${filePath}".`,
              interrupt: false
            };
          }
        }

        console.log(`[Orchestrator] Permission check: ${toolName} to ${filePath} - ALLOWED by policy`);
      }

      // Allow the operation
      return {
        behavior: 'allow',
        updatedInput: input
      };
    };
  }

  /**
   * Create a promise that can be resolved externally (for permission requests)
   */
  createPermissionPromise(requestId) {
    let resolve;
    const promise = new Promise(r => { resolve = r; });
    return { promise, resolve };
  }

  /**
   * Grant a pending permission request (called from API when user approves)
   */
  grantPermission(requestId) {
    const request = this.pendingPermissions.get(requestId);
    if (request && request.status === 'pending') {
      request.status = 'granted';
      // Resolve the waiting promise
      if (request.resolve) {
        request.resolve('granted');
      }
      this.pendingPermissions.set(requestId, request);
      this.emit('permissionGranted', request);
      console.log(`[Orchestrator] Permission GRANTED: ${requestId}`);
      return true;
    }
    return false;
  }

  /**
   * Deny a pending permission request
   */
  denyPermission(requestId) {
    const request = this.pendingPermissions.get(requestId);
    if (request && request.status === 'pending') {
      request.status = 'denied';
      // Resolve the waiting promise
      if (request.resolve) {
        request.resolve('denied');
      }
      this.pendingPermissions.set(requestId, request);
      this.emit('permissionDenied', request);
      console.log(`[Orchestrator] Permission DENIED: ${requestId}`);
      return true;
    }
    return false;
  }

  /**
   * Get all pending permission requests
   */
  getPendingPermissions() {
    return Array.from(this.pendingPermissions.values())
      .filter(p => p.status === 'pending');
  }

  /**
   * Clean up stale permission requests (older than maxAge)
   * @param {number} maxAge - Maximum age in milliseconds (default 5 minutes)
   * @returns {number} Number of cleaned up requests
   */
  cleanupStalePermissions(maxAge = 5 * 60 * 1000) {
    const now = Date.now();
    let cleaned = 0;

    for (const [id, request] of this.pendingPermissions) {
      const age = now - request.timestamp;

      // Remove requests older than maxAge, or completed/denied requests older than 1 minute
      if (age > maxAge || (request.status !== 'pending' && age > 60000)) {
        this.pendingPermissions.delete(id);
        cleaned++;
      }
    }

    if (cleaned > 0) {
      console.log(`[Orchestrator] Cleaned up ${cleaned} stale permission requests`);
    }

    return cleaned;
  }

  /**
   * Start periodic permission cleanup
   */
  startPermissionCleanupLoop() {
    // Clean up every 2 minutes
    this.permissionCleanupInterval = setInterval(() => {
      this.cleanupStalePermissions();
    }, 2 * 60 * 1000);

    // Also run cleanup on startup (after 30 seconds)
    setTimeout(() => this.cleanupStalePermissions(), 30000);
  }

  /**
   * Initialize the orchestrator
   */
  async initialize() {
    // Load persisted queue
    await this.queue.load();

    // Initialize session manager
    await this.sessionManager.initialize();

    // Start processing loop
    this.startProcessingLoop();

    // Start document trigger loop
    this.startTriggerLoop();

    // Start session cleanup loop
    this.startSessionCleanupLoop();

    // Start permission cleanup loop (prevents memory leaks)
    this.startPermissionCleanupLoop();

    log.info('Initialized', { vaultPath: this.vaultPath });
  }

  /**
   * Enqueue an agent for execution
   *
   * @param {string} agentPath - Path to agent markdown file
   * @param {object} context - Execution context
   * @param {object} options - Queue options
   * @returns {Promise<string>} Queue item ID
   */
  async enqueue(agentPath, context = {}, options = {}) {
    // Check depth limit
    const depth = options.depth || 0;
    if (depth >= this.config.maxDepth) {
      throw new Error(`Max spawn depth (${this.config.maxDepth}) reached`);
    }

    // Load agent definition
    const agent = await loadAgent(agentPath, this.vaultPath);

    // Add to queue
    const item = this.queue.enqueue({
      agentPath,
      agent,
      context,
      priority: options.priority || Priority.NORMAL,
      depth,
      spawnedBy: options.spawnedBy || null,
      scheduledFor: options.scheduledFor || null
    });

    console.log(`[Orchestrator] Enqueued: ${agent.name} (${item.id})`);

    // Trigger processing
    this.processQueue();

    return item.id;
  }

  /**
   * Run an agent immediately (bypass queue)
   *
   * @param {string} agentPath - Path to agent or null for vault agent
   * @param {string} message - User message
   * @param {object} additionalContext - Extra context (documentPath for doc agents)
   * @returns {Promise<object>} Execution result
   */
  async runImmediate(agentPath, message, additionalContext = {}) {
    let agent;
    let systemPrompt;

    if (agentPath) {
      // Load specific agent
      agent = await loadAgent(agentPath, this.vaultPath);
      log.info('Loaded agent', {
        name: agent.name,
        path: agentPath,
        tools: agent.permissions?.tools || agent.tools
      });
      systemPrompt = buildSystemPrompt(agent, additionalContext);

      // Load context/knowledge if agent has context configuration
      if (agent.context && (agent.context.knowledge_file || agent.context.include)) {
        try {
          const contextResult = await loadAgentContext(agent.context, this.vaultPath, {
            max_tokens: agent.context.max_tokens
          });
          if (contextResult.content) {
            systemPrompt += formatContextForPrompt(contextResult);
            console.log(`[Orchestrator] Loaded ${contextResult.files.length} context files (~${contextResult.totalTokens} tokens)`);
          }
        } catch (e) {
          console.warn(`[Orchestrator] Failed to load context for ${agent.name}:`, e.message);
        }
      }
    } else {
      // Use default vault agent
      agent = this.createVaultAgent();
      systemPrompt = await this.buildVaultSystemPrompt(additionalContext);
    }

    // Determine agent type - default to chatbot for interactive use
    const agentType = agent.type || AgentType.CHATBOT;

    switch (agentType) {
      case AgentType.CHATBOT:
        // Use session-based execution for conversation continuity
        return this.executeChatbotAgent(agent, agentPath, message, systemPrompt, additionalContext);

      case AgentType.DOC:
        // Doc agents require a document - include document content in message
        if (additionalContext.documentPath) {
          const doc = await this.readDocument(additionalContext.documentPath);
          if (doc) {
            const docMessage = `Process this document: ${additionalContext.documentPath}\n\n---\n${doc.body}\n---\n\n${message || 'Process this document.'}`;
            return this.executeAgent(agent, docMessage, systemPrompt, 0);
          }
        }
        // Fall through if no document provided
        return this.executeAgent(agent, message, systemPrompt, 0);

      case AgentType.STANDALONE:
      default:
        // Standalone agents run independently
        return this.executeAgent(agent, message || 'Execute your primary function.', systemPrompt, 0);
    }
  }

  /**
   * Execute a chatbot agent with streaming (yields events for SSE)
   * This is a generator function that yields events as they happen.
   */
  async *executeChatbotAgentStreaming(agent, agentPath, message, systemPrompt, context) {
    const effectivePath = agentPath || 'vault-agent';

    const chatbotContext = {};
    if (context.sessionId) {
      chatbotContext.sessionId = context.sessionId;
    }
    if (context.workingDirectory) {
      chatbotContext.workingDirectory = context.workingDirectory;
    }

    const { session, resumeInfo } = await this.sessionManager.getSession(effectivePath, chatbotContext);
    const sessionKey = this.sessionManager.getSessionKey(effectivePath, chatbotContext);

    // Determine the working directory for this session
    const effectiveCwd = session.workingDirectory || this.vaultPath;

    log.info('Streaming chat session', { sessionId: session.id, agentPath: effectivePath, cwd: effectiveCwd });

    // Yield session info first
    yield {
      type: 'session',
      sessionId: session.id,
      workingDirectory: session.workingDirectory || null,
      resumeInfo: resumeInfo.toJSON()
    };

    // Handle initial context for new sessions (e.g., voice transcript, document)
    // If initialContext is provided without a message, the context IS the message
    // If both are provided, context is prepended to the message
    let actualMessage = message;
    if (context.initialContext && session.messages.length === 0) {
      if (!message || message.trim() === '') {
        // Context is the entire message
        actualMessage = context.initialContext;
        console.log(`[Orchestrator] Using initial context as message (${context.initialContext.length} chars)`);
      } else {
        // Both provided - prepend context
        actualMessage = `## Context\n\n${context.initialContext}\n\n---\n\n## Request\n\n${message}`;
        console.log(`[Orchestrator] Prepending initial context (${context.initialContext.length} chars)`);
      }
    }

    await this.sessionManager.addMessage(sessionKey, 'user', actualMessage);

    const startTime = Date.now();
    let result = '';
    let toolCalls = [];
    const requestPermissionDenials = [];

    try {
      const agentTools = agent.permissions?.tools || agent.tools || [];

      // Load global MCP servers and resolve agent references
      const globalMcpServers = await loadMcpServers(this.vaultPath);
      const resolvedMcpServers = resolveMcpServers(agent.mcpServers, globalMcpServers);

      const queryOptions = {
        systemPrompt,
        cwd: effectiveCwd,
        permissionMode: 'default',
        canUseTool: this.createPermissionHandler(agent, session.id, (denial) => {
          requestPermissionDenials.push(denial);
        }),
        tools: agentTools.length > 0 ? agentTools : undefined,
        // Enable skills from the vault's .claude/skills directory
        settingSources: ['project'],
        // MCP servers (resolved from .mcp.json or inline)
        mcpServers: resolvedMcpServers
      };

      const { prompt: preparedPrompt, queryOptions: contextQueryOptions } =
        this.sessionManager.preparePromptWithContext(session, actualMessage, resumeInfo);

      Object.assign(queryOptions, contextQueryOptions);

      console.log(`[Orchestrator] Streaming query for ${agent.name}`);

      const response = query({
        prompt: preparedPrompt,
        options: queryOptions
      });

      let capturedSessionId = null;
      let currentText = '';

      for await (const msg of response) {
        if (msg.session_id) {
          capturedSessionId = msg.session_id;
        }

        if (msg.type === 'system' && msg.subtype === 'init') {
          yield {
            type: 'init',
            tools: msg.tools || [],
            permissionMode: msg.permissionMode
          };
        }

        if (msg.type === 'assistant' && msg.message?.content) {
          for (const block of msg.message.content) {
            if (block.type === 'text') {
              // Yield text delta (difference from previous)
              const newText = block.text;
              if (newText !== currentText) {
                yield {
                  type: 'text',
                  content: newText,
                  delta: newText.slice(currentText.length)
                };
                currentText = newText;
                result = newText;
              }
            }
            if (block.type === 'tool_use') {
              const toolCall = {
                id: block.id,
                name: block.name,
                input: block.input
              };
              toolCalls.push(toolCall);
              yield {
                type: 'tool_use',
                tool: toolCall
              };
            }
          }
        } else if (msg.type === 'result') {
          if (msg.result) {
            result = msg.result;
            yield {
              type: 'text',
              content: result,
              delta: result.slice(currentText.length)
            };
          }
          if (msg.session_id) {
            capturedSessionId = msg.session_id;
          }
        }
      }

      if (capturedSessionId && capturedSessionId !== session.sdkSessionId) {
        await this.sessionManager.updateSdkSessionId(sessionKey, capturedSessionId);
      }

      await this.sessionManager.addMessage(sessionKey, 'assistant', result);

      // Generate title asynchronously if session doesn't have one yet
      const agentName = agent.name || effectivePath.replace('agents/', '').replace('.md', '');
      this.sessionManager.maybeGenerateTitle(sessionKey, agentName).catch(err => {
        console.error(`[Orchestrator] Title generation error:`, err.message);
      });

      const spawnRequests = this.parseSpawnRequests(result, agent, 0);

      for (const spawn of spawnRequests) {
        if (this.config.maxDepth > 1) {
          await this.enqueue(spawn.agent, {
            userMessage: spawn.message,
            parentContext: { parentAgent: agent.name, parentResult: result }
          }, {
            depth: 1,
            priority: spawn.priority || Priority.NORMAL
          });
        }
      }

      const duration = Date.now() - startTime;

      // Clean up pending permissions
      for (const [key, _] of this.pendingPermissions) {
        if (key.startsWith(session.id)) {
          this.pendingPermissions.delete(key);
        }
      }

      // Yield final completion event
      yield {
        type: 'done',
        response: result,
        spawned: spawnRequests.map(s => s.agent),
        durationMs: duration,
        sessionId: session.id,
        workingDirectory: session.workingDirectory || null,
        messageCount: session.messages.length,
        toolCalls: toolCalls.length > 0 ? toolCalls : undefined,
        permissionDenials: requestPermissionDenials.length > 0 ? requestPermissionDenials : undefined,
        sessionResume: resumeInfo.toJSON()
      };

    } catch (error) {
      log.error('Streaming error', { agentPath: effectivePath, error: error.message });
      await this.sessionManager.addMessage(sessionKey, 'system', `Error: ${error.message}`);

      yield {
        type: 'error',
        error: error.message,
        sessionId: session.id
      };
    }
  }

  /**
   * Execute a chatbot agent with session continuity
   */
  async executeChatbotAgent(agent, agentPath, message, systemPrompt, context) {
    const effectivePath = agentPath || 'vault-agent';

    // For chatbot agents, use sessionId for unique conversations (from plugin)
    // Each chat gets its own session, identified by sessionId
    const chatbotContext = {};
    if (context.sessionId) {
      chatbotContext.sessionId = context.sessionId;
    }
    if (context.workingDirectory) {
      chatbotContext.workingDirectory = context.workingDirectory;
    }

    // Get or create session (now returns { session, resumeInfo })
    const { session, resumeInfo } = await this.sessionManager.getSession(effectivePath, chatbotContext);
    const sessionKey = this.sessionManager.getSessionKey(effectivePath, chatbotContext);

    // Determine the working directory for this session
    const effectiveCwd = session.workingDirectory || this.vaultPath;

    log.info('Chat session', {
      sessionId: session.id,
      agentPath: effectivePath,
      cwd: effectiveCwd,
      loadMethod: resumeInfo.cacheHit ? 'cache hit' : resumeInfo.loadedFromDisk ? 'loaded from disk' : 'new session'
    });

    // Handle initial context for new sessions (e.g., voice transcript, document)
    // If initialContext is provided without a message, the context IS the message
    // If both are provided, context is prepended to the message
    let actualMessage = message;
    if (context.initialContext && session.messages.length === 0) {
      if (!message || message.trim() === '') {
        // Context is the entire message
        actualMessage = context.initialContext;
        console.log(`[Orchestrator] Using initial context as message (${context.initialContext.length} chars)`);
      } else {
        // Both provided - prepend context
        actualMessage = `## Context\n\n${context.initialContext}\n\n---\n\n## Request\n\n${message}`;
        console.log(`[Orchestrator] Prepending initial context (${context.initialContext.length} chars)`);
      }
    }

    // Add user message to local history
    await this.sessionManager.addMessage(sessionKey, 'user', actualMessage);

    const startTime = Date.now();
    let result = '';
    let spawnRequests = [];
    let toolCalls = [];

    // Track permission denials for THIS request only
    const requestPermissionDenials = [];

    try {
      // Build query options
      //
      // IMPORTANT: The SDK has two related options:
      // - `tools`: Sets the BASE set of available tools (defaults to claude_code preset if not set)
      // - `allowedTools`: RESTRICTS which tools from the base set are available
      //
      // We use `tools` to explicitly set only the tools we want available,
      // rather than relying on allowedTools to restrict from the full preset.
      const agentTools = agent.permissions?.tools || agent.tools || [];

      // Load global MCP servers and resolve agent references
      const globalMcpServers = await loadMcpServers(this.vaultPath);
      const resolvedMcpServers = resolveMcpServers(agent.mcpServers, globalMcpServers);

      const queryOptions = {
        systemPrompt,
        cwd: effectiveCwd,
        // Use 'default' permission mode so canUseTool callback is invoked
        // 'acceptEdits' auto-accepts and bypasses canUseTool!
        permissionMode: 'default',
        // Add permission handler for fine-grained path-based write permissions
        // Pass callback to track denials for this request
        canUseTool: this.createPermissionHandler(agent, session.id, (denial) => {
          requestPermissionDenials.push(denial);
        }),
        // Explicitly set available tools - this is the primary restriction mechanism
        tools: agentTools.length > 0 ? agentTools : undefined,
        // Enable skills from the vault's .claude/skills directory
        settingSources: ['project'],
        // MCP servers (resolved from .mcp.json or inline)
        mcpServers: resolvedMcpServers
      };

      if (agentTools.length > 0) {
        console.log(`[Orchestrator] Tools for ${agent.name}: ${agentTools.join(', ')}`);
      } else {
        console.log(`[Orchestrator] Using default claude_code tools for ${agent.name}`);
      }

      // Log MCP servers if configured
      if (resolvedMcpServers) {
        const serverNames = Object.keys(resolvedMcpServers);
        console.log(`[Orchestrator] MCP servers for ${agent.name}: ${serverNames.join(', ')}`);
      }

      // Log write permissions for debugging
      const writePatterns = agent.permissions?.write || ['*'];
      console.log(`[Orchestrator] Write permissions for ${agent.name}: ${writePatterns.join(', ')}`);

      // Prepare prompt with context injection if SDK session is unavailable
      const { prompt: preparedPrompt, queryOptions: contextQueryOptions } =
        this.sessionManager.preparePromptWithContext(session, actualMessage, resumeInfo);

      // Merge context query options (may include resume)
      Object.assign(queryOptions, contextQueryOptions);

      // Log session resumption method
      console.log(`[Orchestrator] Session method: ${resumeInfo.toString()}`);

      console.log(`[Orchestrator] Query options:`, JSON.stringify({
        ...queryOptions,
        systemPrompt: systemPrompt ? `[${systemPrompt.length} chars]` : null,
        canUseTool: queryOptions.canUseTool ? '[function]' : undefined,
        resume: queryOptions.resume ? `${queryOptions.resume.slice(0, 20)}...` : undefined
      }, null, 2));

      // Execute via Claude Agent SDK
      const response = query({
        prompt: preparedPrompt,
        options: queryOptions
      });

      // Collect response and capture session ID
      let capturedSessionId = null;

      for await (const msg of response) {
        // Try to capture session ID from messages
        if (msg.session_id) {
          capturedSessionId = msg.session_id;
        }

        // Log system init message to see what tools the SDK actually loaded
        if (msg.type === 'system' && msg.subtype === 'init') {
          console.log(`[Orchestrator] SDK initialized with tools: ${msg.tools?.join(', ') || 'none'}`);
          console.log(`[Orchestrator] SDK permission mode: ${msg.permissionMode}`);
        }

        if (msg.type === 'assistant' && msg.message?.content) {
          for (const block of msg.message.content) {
            if (block.type === 'text') {
              result = block.text;
            }
            // Capture tool calls
            if (block.type === 'tool_use') {
              toolCalls.push({
                name: block.name,
                input: block.input
              });
            }
          }
        } else if (msg.type === 'result') {
          if (msg.result) {
            result = msg.result;
          }
          // Session ID might be in the result
          if (msg.session_id) {
            capturedSessionId = msg.session_id;
          }
        }
      }

      // Update session with SDK session ID if we captured one
      if (capturedSessionId && capturedSessionId !== session.sdkSessionId) {
        await this.sessionManager.updateSdkSessionId(sessionKey, capturedSessionId);
        console.log(`[Orchestrator] Stored SDK session ID: ${capturedSessionId}`);
      }

      // Add assistant response to local history
      await this.sessionManager.addMessage(sessionKey, 'assistant', result);

      // Generate title asynchronously if session doesn't have one yet
      const agentName = agent.name || effectivePath.replace('agents/', '').replace('.md', '');
      this.sessionManager.maybeGenerateTitle(sessionKey, agentName).catch(err => {
        console.error(`[Orchestrator] Title generation error:`, err.message);
      });

      // Parse spawn requests from response
      spawnRequests = this.parseSpawnRequests(result, agent, 0);

      // Process spawn requests
      for (const spawn of spawnRequests) {
        if (this.config.maxDepth > 1) {
          await this.enqueue(spawn.agent, {
            userMessage: spawn.message,
            parentContext: { parentAgent: agent.name, parentResult: result }
          }, {
            depth: 1,
            priority: spawn.priority || Priority.NORMAL
          });
        }
      }

      const duration = Date.now() - startTime;
      log.info('Chat completed', {
        agentPath: effectivePath,
        durationMs: duration,
        toolCalls: toolCalls.length
      });

      // Clean up any pending permissions for this session from the global map
      for (const [key, _] of this.pendingPermissions) {
        if (key.startsWith(session.id)) {
          this.pendingPermissions.delete(key);
        }
      }

      return {
        success: true,
        response: result,
        spawned: spawnRequests.map(s => s.agent),
        durationMs: duration,
        sessionId: session.id,
        workingDirectory: session.workingDirectory || null,
        messageCount: session.messages.length,
        toolCalls: toolCalls.length > 0 ? toolCalls : undefined,
        // Use the per-request denials instead of querying global map
        permissionDenials: requestPermissionDenials.length > 0 ? requestPermissionDenials : undefined,
        // Session resumption debug info
        sessionResume: resumeInfo.toJSON(),
        debug: {
          systemPromptLength: systemPrompt.length,
          messageLength: message.length,
          agentPath: effectivePath,
          model: agent.model || 'default',
          toolsAvailable: agentTools.length > 0 ? agentTools : ['(default)'],
          writePermissions: agent.permissions?.write || ['*'],
          // Enhanced session debug
          sessionMethod: resumeInfo.method,
          sessionCacheHit: resumeInfo.cacheHit,
          sessionLoadedFromDisk: resumeInfo.loadedFromDisk,
          contextInjected: resumeInfo.contextInjected,
          messagesInjected: resumeInfo.messagesInjected,
          tokensEstimate: resumeInfo.tokensEstimate
        }
      };

    } catch (error) {
      log.error('Chat error', {
        agentPath: effectivePath,
        error: error.message,
        stack: error.stack,
        cause: error.cause
      });

      // Add error to history
      await this.sessionManager.addMessage(sessionKey, 'system', `Error: ${error.message}`);

      return {
        success: false,
        error: error.message,
        response: '',
        spawned: [],
        durationMs: Date.now() - startTime,
        sessionId: session.id
      };
    }
  }

  /**
   * Clear a chat session (start fresh)
   */
  async clearChatSession(agentPath, context = {}) {
    await this.sessionManager.clearSession(agentPath || 'vault-agent', context);
  }

  /**
   * Get chat history for an agent
   */
  getChatHistory(agentPath, context = {}) {
    const sessionKey = this.sessionManager.getSessionKey(agentPath || 'vault-agent', context);
    return this.sessionManager.getMessages(sessionKey);
  }

  /**
   * List all chat sessions
   */
  listChatSessions() {
    return this.sessionManager.listSessions();
  }

  /**
   * Get a specific session by ID
   */
  getSessionById(sessionId) {
    return this.sessionManager.getSessionById(sessionId);
  }

  /**
   * Get a specific session by ID (async - loads from disk if needed)
   */
  async getSessionByIdAsync(sessionId) {
    return this.sessionManager.getSessionByIdAsync(sessionId);
  }

  /**
   * Archive a session by ID
   */
  async archiveSession(sessionId) {
    return this.sessionManager.archiveSession(sessionId);
  }

  /**
   * Unarchive a session by ID
   */
  async unarchiveSession(sessionId) {
    return this.sessionManager.unarchiveSession(sessionId);
  }

  /**
   * Delete a session by ID
   */
  async deleteSessionById(sessionId) {
    return this.sessionManager.deleteSessionById(sessionId);
  }

  /**
   * Get session manager stats for debugging
   */
  getSessionStats() {
    return this.sessionManager.getStats();
  }

  // ============================================================================
  // MCP SERVER MANAGEMENT
  // ============================================================================

  /**
   * List all configured MCP servers
   */
  async listMcpServers() {
    return listMcpServers(this.vaultPath);
  }

  /**
   * Add or update an MCP server
   */
  async addMcpServer(name, config) {
    return addMcpServer(this.vaultPath, name, config);
  }

  /**
   * Remove an MCP server
   */
  async removeMcpServer(name) {
    return removeMcpServer(this.vaultPath, name);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Skills Management
  // ─────────────────────────────────────────────────────────────────────────

  /**
   * List all available skills in the vault
   * Skills are discovered from .claude/skills/ directory
   */
  async listSkills() {
    return discoverSkills(this.vaultPath);
  }

  /**
   * Get full content of a specific skill
   * @param {string} skillName - Name of the skill directory
   */
  async getSkill(skillName) {
    return loadSkill(this.vaultPath, skillName);
  }

  /**
   * Create a new skill
   * @param {string} skillName - Directory name for the skill
   * @param {object} skillData - { name, description, content, allowedTools? }
   */
  async createSkill(skillName, skillData) {
    return createSkill(this.vaultPath, skillName, skillData);
  }

  /**
   * Delete a skill
   * @param {string} skillName - Name of the skill directory to delete
   */
  async deleteSkill(skillName) {
    return deleteSkill(this.vaultPath, skillName);
  }

  /**
   * Ensure skills directory exists
   */
  async ensureSkillsDir() {
    return ensureSkillsDir(this.vaultPath);
  }

  /**
   * Run an agent with streaming (yields SSE events)
   * Use this for real-time UI updates
   */
  async *runImmediateStreaming(agentPath, message, additionalContext = {}) {
    let agent;
    let systemPrompt;

    if (agentPath) {
      agent = await loadAgent(agentPath, this.vaultPath);
      console.log(`[Orchestrator] Streaming agent: ${agent.name} from ${agentPath}`);
      systemPrompt = buildSystemPrompt(agent, additionalContext);

      if (agent.context && (agent.context.knowledge_file || agent.context.include)) {
        try {
          const contextResult = await loadAgentContext(agent.context, this.vaultPath, {
            max_tokens: agent.context.max_tokens
          });
          if (contextResult.content) {
            systemPrompt += formatContextForPrompt(contextResult);
          }
        } catch (e) {
          console.warn(`[Orchestrator] Failed to load context for ${agent.name}:`, e.message);
        }
      }
    } else {
      agent = this.createVaultAgent();
      systemPrompt = await this.buildVaultSystemPrompt(additionalContext);
    }

    const agentType = agent.type || AgentType.CHATBOT;

    // Use streaming execution for chatbot and doc agents
    // Standalone agents may have different requirements
    if (agentType === AgentType.CHATBOT || agentType === AgentType.DOC) {
      yield* this.executeChatbotAgentStreaming(agent, agentPath, message, systemPrompt, additionalContext);
    } else {
      // For other agent types (e.g., standalone), fall back to non-streaming execution
      const result = await this.runImmediate(agentPath, message, additionalContext);
      yield {
        type: 'done',
        ...result
      };
    }
  }

  /**
   * Create a default vault agent for general queries
   */
  createVaultAgent() {
    // Full tool set - let the permission handler gate dangerous operations
    // Claude Code tools: https://docs.anthropic.com/en/docs/claude-code
    const fullToolSet = [
      // File operations
      'Read', 'Write', 'Edit', 'MultiEdit',
      // Search & navigation
      'Glob', 'Grep', 'LS',
      // Execution
      'Bash', 'Task',
      // Notebook support
      'NotebookRead', 'NotebookEdit',
      // Web access
      'WebSearch', 'WebFetch',
      // Skills (custom vault extensions)
      'Skill'
    ];

    return {
      name: 'vault-agent',
      description: 'General vault assistant',
      model: 'sonnet',
      tools: fullToolSet,
      // Load all MCP servers from .mcp.json by default
      mcpServers: 'all',
      permissions: {
        read: ['*'],
        write: ['*'],
        spawn: ['agents/*'],
        tools: fullToolSet
      },
      constraints: {
        max_spawns: 3,
        timeout: 300
      },
      spawns: [],
      systemPrompt: ''
    };
  }

  /**
   * Load AGENTS.md from vault root if it exists
   * @returns {Promise<string|null>} Content of AGENTS.md or null
   */
  async loadAgentsMd() {
    const agentsMdPath = path.join(this.vaultPath, 'AGENTS.md');
    try {
      const content = await fs.readFile(agentsMdPath, 'utf-8');
      log.info('Loaded AGENTS.md', { path: agentsMdPath, length: content.length });
      return content;
    } catch (e) {
      if (e.code === 'ENOENT') {
        log.debug('No AGENTS.md found', { path: agentsMdPath });
        return null;
      }
      log.error('Error loading AGENTS.md', { error: e.message });
      return null;
    }
  }

  /**
   * Build system prompt for vault agent
   * Uses AGENTS.md if present, otherwise falls back to default prompt
   */
  async buildVaultSystemPrompt(context = {}) {
    // Try to load AGENTS.md first - this is the preferred source
    const agentsMd = await this.loadAgentsMd();

    if (agentsMd) {
      // AGENTS.md is the system prompt
      // Optionally append tools context if needed
      let prompt = agentsMd;

      // Add vault location for context
      prompt += `\n\n---\n\n## Environment\n\nVault location: ${this.vaultPath}`;

      return prompt;
    }

    // Fallback: default prompt when no AGENTS.md exists
    return this.buildDefaultVaultPrompt(context);
  }

  /**
   * Build default vault prompt (fallback when no AGENTS.md)
   */
  async buildDefaultVaultPrompt(context = {}) {
    const agents = await loadAllAgents(this.vaultPath);
    const files = await this.listVaultFiles();

    let prompt = `You are a knowledge companion helping the user with their personal vault.

You are NOT primarily a coding assistant. Your core purpose is to help the user:
- Think through ideas and problems
- Find and connect information in their vault
- Remember context from past conversations

## Environment

VAULT LOCATION: ${this.vaultPath}

VAULT FILES (${files.length} total):
${files.slice(0, 20).join('\n')}
${files.length > 20 ? `\n... and ${files.length - 20} more` : ''}

## Available Tools

You have access to tools for reading, searching, and modifying files in the vault.
Use your search tools to find relevant context before answering questions.

Be helpful and concise. Ask clarifying questions when needed.`;

    // Add agent info if any exist
    if (agents.length > 0) {
      prompt += `\n\n## Specialized Agents Available\n${agents.map(a => `- ${a.path}: ${a.description || a.name}`).join('\n')}`;
    }

    return prompt;
  }

  /**
   * Execute an agent
   *
   * @param {AgentDefinition} agent
   * @param {string} message
   * @param {string} systemPrompt
   * @param {number} depth
   * @returns {Promise<object>}
   */
  async executeAgent(agent, message, systemPrompt, depth) {
    console.log(`[Orchestrator] Executing: ${agent.name} (depth: ${depth})`);

    const startTime = Date.now();
    let result = '';
    let spawnRequests = [];

    try {
      // Build query options
      const queryOptions = {
        systemPrompt,
        cwd: this.vaultPath,
        allowedTools: agent.permissions?.tools || agent.tools,
        permissionMode: 'acceptEdits'
      };

      // Pass model if specified in agent definition
      if (agent.model) {
        queryOptions.model = agent.model;
      }

      // Execute via Claude Agent SDK
      const response = query({
        prompt: message,
        options: queryOptions
      });

      // Collect response
      for await (const msg of response) {
        if (msg.type === 'assistant' && msg.message?.content) {
          for (const block of msg.message.content) {
            if (block.type === 'text') {
              result = block.text;
            }
          }
        } else if (msg.type === 'result') {
          if (msg.result) {
            result = msg.result;
          }
        }
      }

      // Parse spawn requests from response
      spawnRequests = this.parseSpawnRequests(result, agent, depth);

      // Process spawn requests
      for (const spawn of spawnRequests) {
        if (depth + 1 < this.config.maxDepth) {
          await this.enqueue(spawn.agent, {
            userMessage: spawn.message,
            parentContext: { parentAgent: agent.name, parentResult: result }
          }, {
            depth: depth + 1,
            priority: spawn.priority || Priority.NORMAL
          });
        } else {
          console.warn(`[Orchestrator] Spawn blocked: max depth reached`);
        }
      }

      const duration = Date.now() - startTime;
      console.log(`[Orchestrator] Completed: ${agent.name} in ${duration}ms`);

      return {
        success: true,
        response: result,
        spawned: spawnRequests.map(s => s.agent),
        durationMs: duration
      };

    } catch (error) {
      console.error(`[Orchestrator] Error executing ${agent.name}:`, error);

      return {
        success: false,
        error: error.message,
        response: '',
        spawned: [],
        durationMs: Date.now() - startTime
      };
    }
  }

  /**
   * Parse spawn requests from agent response
   *
   * @param {string} response
   * @param {AgentDefinition} agent
   * @param {number} depth
   * @returns {SpawnRequest[]}
   */
  parseSpawnRequests(response, agent, depth) {
    const requests = [];
    const spawnRegex = /```spawn\n([\s\S]*?)```/g;

    let match;
    while ((match = spawnRegex.exec(response)) !== null) {
      try {
        const spawnData = JSON.parse(match[1].trim());

        // Validate spawn permission
        if (!hasPermission(agent, 'spawn', spawnData.agent)) {
          console.warn(`[Orchestrator] Spawn denied: ${agent.name} cannot spawn ${spawnData.agent}`);
          continue;
        }

        requests.push({
          agent: spawnData.agent,
          message: spawnData.message || 'Execute your primary function',
          priority: spawnData.priority || Priority.NORMAL,
          context: spawnData.context || {}
        });

      } catch (e) {
        console.warn('[Orchestrator] Failed to parse spawn request:', e.message);
      }
    }

    return requests;
  }

  /**
   * Process the queue
   */
  async processQueue() {
    if (this.isProcessing) return;
    if (this.running.size >= this.config.maxConcurrent) return;
    if (!this.queue.hasPending()) return;

    this.isProcessing = true;

    try {
      while (
        this.running.size < this.config.maxConcurrent &&
        this.queue.hasPending()
      ) {
        const item = this.queue.getNext();
        if (!item) break;

        // Mark as running
        this.queue.markRunning(item.id);
        this.running.set(item.id, item);

        // Execute (don't await - allow concurrent processing)
        this.executeQueueItem(item).finally(() => {
          this.running.delete(item.id);
          // Trigger next processing
          setTimeout(() => this.processQueue(), 100);
        });
      }
    } finally {
      this.isProcessing = false;
    }
  }

  /**
   * Get or create an event emitter for streaming a queue item's execution
   * @param {string} itemId - The queue item ID
   * @returns {EventEmitter} - The event emitter for this queue item
   */
  getQueueStream(itemId) {
    if (!this.queueStreams.has(itemId)) {
      this.queueStreams.set(itemId, new EventEmitter());
    }
    return this.queueStreams.get(itemId);
  }

  /**
   * Emit an event for a queue item (used during execution)
   * @param {string} itemId - The queue item ID
   * @param {string} type - Event type (text, tool_use, done, error)
   * @param {object} data - Event data
   */
  emitQueueEvent(itemId, type, data) {
    const stream = this.queueStreams.get(itemId);
    if (stream) {
      stream.emit('event', { type, ...data });
    }
  }

  /**
   * Clean up event emitter for a queue item
   * @param {string} itemId - The queue item ID
   */
  cleanupQueueStream(itemId) {
    const stream = this.queueStreams.get(itemId);
    if (stream) {
      stream.emit('event', { type: 'close' });
      stream.removeAllListeners();
      this.queueStreams.delete(itemId);
    }
  }

  /**
   * Execute a queue item with streaming events
   */
  async executeQueueItem(item) {
    const { agent, context, depth } = item;

    // Create event stream for this queue item
    this.getQueueStream(item.id);

    try {
      let systemPrompt = buildSystemPrompt(agent, context);

      // Emit init event
      this.emitQueueEvent(item.id, 'init', {
        agentName: agent.name,
        agentPath: item.agentPath,
        documentPath: context.documentPath
      });

      // Load context/knowledge if agent has context configuration
      if (agent.context && (agent.context.knowledge_file || agent.context.include)) {
        try {
          const contextResult = await loadAgentContext(agent.context, this.vaultPath, {
            max_tokens: agent.context.max_tokens
          });
          if (contextResult.content) {
            systemPrompt += formatContextForPrompt(contextResult);
            console.log(`[Orchestrator] Loaded ${contextResult.files.length} context files for ${agent.name}`);
          }
        } catch (e) {
          console.warn(`[Orchestrator] Failed to load context for ${agent.name}:`, e.message);
        }
      }

      let message = context.userMessage || 'Execute your primary function.';

      // Handle doc agents - include document content in message
      const agentType = agent.type || AgentType.STANDALONE;
      if (agentType === AgentType.DOC && context.documentPath) {
        const doc = await this.readDocument(context.documentPath);
        if (doc) {
          message = `Process this document: ${context.documentPath}\n\n---\n${doc.body}\n---\n\n${message}`;
          console.log(`[Orchestrator] Doc agent processing: ${context.documentPath}`);
        }
      }

      // Execute with streaming events
      const result = await this.executeAgentWithEvents(agent, message, systemPrompt, depth, item.id);

      if (result.success) {
        this.queue.markCompleted(item.id, result);
        // Save as markdown log
        await this.saveAgentLog(item, result);
        this.emitQueueEvent(item.id, 'done', result);
      } else {
        this.queue.markFailed(item.id, result.error);
        this.emitQueueEvent(item.id, 'error', { error: result.error });
      }

      // Cleanup stream after a short delay to allow final events to be read
      setTimeout(() => this.cleanupQueueStream(item.id), 5000);

      return result;

    } catch (error) {
      this.queue.markFailed(item.id, error);
      this.emitQueueEvent(item.id, 'error', { error: error.message });
      setTimeout(() => this.cleanupQueueStream(item.id), 5000);
      throw error;
    }
  }

  /**
   * Execute an agent with streaming events for queue watching
   *
   * @param {AgentDefinition} agent
   * @param {string} message
   * @param {string} systemPrompt
   * @param {number} depth
   * @param {string} queueItemId - The queue item ID for event emission
   * @returns {Promise<object>}
   */
  async executeAgentWithEvents(agent, message, systemPrompt, depth, queueItemId) {
    console.log(`[Orchestrator] Executing with events: ${agent.name} (depth: ${depth})`);

    const startTime = Date.now();
    let result = '';
    let spawnRequests = [];
    let currentText = '';
    let toolCalls = [];

    try {
      // Load global MCP servers and resolve agent references
      const globalMcpServers = await loadMcpServers(this.vaultPath);
      const resolvedMcpServers = resolveMcpServers(agent.mcpServers, globalMcpServers);

      if (resolvedMcpServers && Object.keys(resolvedMcpServers).length > 0) {
        console.log(`[Orchestrator] Resolved MCP servers for ${agent.name}:`, Object.keys(resolvedMcpServers));
      }

      // Build query options
      const queryOptions = {
        systemPrompt,
        cwd: this.vaultPath,
        allowedTools: agent.permissions?.tools || agent.tools,
        permissionMode: 'acceptEdits',
        // Enable skills from the vault's .claude/skills directory
        settingSources: ['project'],
        // MCP servers (resolved from .mcp.json or inline)
        mcpServers: resolvedMcpServers
      };

      // Pass model if specified in agent definition
      if (agent.model) {
        queryOptions.model = agent.model;
      }

      // Execute via Claude Agent SDK
      const response = query({
        prompt: message,
        options: queryOptions
      });

      // Collect response with event emission
      for await (const msg of response) {
        if (msg.type === 'assistant' && msg.message?.content) {
          for (const block of msg.message.content) {
            if (block.type === 'text') {
              const newText = block.text;
              if (newText !== currentText) {
                this.emitQueueEvent(queueItemId, 'text', {
                  content: newText,
                  delta: newText.slice(currentText.length)
                });
                currentText = newText;
                result = newText;
              }
            }
            if (block.type === 'tool_use') {
              const toolCall = {
                id: block.id,
                name: block.name,
                input: block.input
              };
              toolCalls.push(toolCall);
              this.emitQueueEvent(queueItemId, 'tool_use', { tool: toolCall });
            }
          }
        } else if (msg.type === 'result') {
          if (msg.result) {
            result = msg.result;
            if (result !== currentText) {
              this.emitQueueEvent(queueItemId, 'text', {
                content: result,
                delta: result.slice(currentText.length)
              });
            }
          }
        }
      }

      // Parse spawn requests from response
      spawnRequests = this.parseSpawnRequests(result, agent, depth);

      // Process spawn requests
      for (const spawn of spawnRequests) {
        if (depth + 1 < this.config.maxDepth) {
          await this.enqueue(spawn.agent, {
            userMessage: spawn.message,
            parentContext: { parentAgent: agent.name, parentResult: result }
          }, {
            depth: depth + 1,
            priority: spawn.priority || Priority.NORMAL
          });
        } else {
          console.warn(`[Orchestrator] Spawn blocked: max depth reached`);
        }
      }

      const duration = Date.now() - startTime;
      console.log(`[Orchestrator] Completed: ${agent.name} in ${duration}ms`);

      return {
        success: true,
        response: result,
        spawned: spawnRequests.map(s => s.agent),
        durationMs: duration,
        toolCalls: toolCalls.length > 0 ? toolCalls : undefined
      };

    } catch (error) {
      console.error(`[Orchestrator] Error executing ${agent.name}:`, error);

      return {
        success: false,
        error: error.message,
        response: '',
        spawned: [],
        durationMs: Date.now() - startTime
      };
    }
  }

  /**
   * Save an agent run as a markdown log file
   */
  async saveAgentLog(item, result) {
    try {
      const logsPath = path.join(this.vaultPath, 'agent-logs');
      const today = new Date().toISOString().split('T')[0];
      const dayPath = path.join(logsPath, today);

      await fs.mkdir(dayPath, { recursive: true });

      const agentName = item.agentPath.replace('agents/', '').replace('.md', '');
      const timestamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);

      let fileName = `${timestamp}-${agentName}`;
      if (item.context?.documentPath) {
        const docName = item.context.documentPath.replace(/\//g, '-').replace('.md', '');
        fileName += `-on-${docName}`;
      }
      fileName += '.md';

      const filePath = path.join(dayPath, fileName);

      const durationMs = result.durationMs || 0;
      const durationSec = (durationMs / 1000).toFixed(1);

      let markdown = `---
run_id: "${item.id}"
agent: "${item.agentPath}"
agent_name: "${agentName}"
type: "${item.agent?.type || 'standalone'}"
status: "${result.success ? 'completed' : 'failed'}"
timestamp: "${new Date().toISOString()}"
duration_ms: ${durationMs}
duration: "${durationSec}s"
`;

      if (item.context?.documentPath) {
        markdown += `target_document: "${item.context.documentPath}"\n`;
      }

      markdown += `---

# Agent Run: ${agentName}

`;

      if (item.context?.documentPath) {
        markdown += `> Target: [[${item.context.documentPath}]]\n\n`;
      }

      markdown += `## Result

${result.response || 'No response'}

---

*Completed in ${durationSec}s*
`;

      await fs.writeFile(filePath, markdown, 'utf-8');
      console.log(`[Orchestrator] Saved log: ${filePath}`);

    } catch (e) {
      console.error('[Orchestrator] Failed to save agent log:', e.message);
    }
  }

  /**
   * Start background processing loop
   */
  startProcessingLoop() {
    setInterval(() => {
      this.processQueue();
    }, 5000); // Check every 5 seconds
  }

  /**
   * List vault files
   */
  async listVaultFiles(dir = this.vaultPath, files = []) {
    const entries = await fs.readdir(dir, { withFileTypes: true });

    for (const entry of entries) {
      const fullPath = path.join(dir, entry.name);

      if (entry.isDirectory() && !entry.name.startsWith('.')) {
        await this.listVaultFiles(fullPath, files);
      } else if (entry.name.endsWith('.md')) {
        files.push(path.relative(this.vaultPath, fullPath));
      }
    }

    return files;
  }

  /**
   * Read a document
   */
  async readDocument(relativePath) {
    const fullPath = path.join(this.vaultPath, relativePath);
    try {
      const content = await fs.readFile(fullPath, 'utf-8');
      const matter = await import('gray-matter');
      const { data: frontmatter, content: body } = matter.default(content);
      return { path: relativePath, frontmatter, body, raw: content };
    } catch (e) {
      return null;
    }
  }

  /**
   * Get queue state
   */
  getQueueState() {
    return this.queue.getState();
  }

  /**
   * Get all loaded agents
   */
  async getAgents() {
    return loadAllAgents(this.vaultPath);
  }

  // ============================================================================
  // DOCUMENT PROCESSING
  // ============================================================================

  /**
   * Start the trigger check loop
   * Checks documents with waiting status for trigger conditions
   */
  startTriggerLoop() {
    setInterval(async () => {
      await this.checkTriggers();
    }, 60000); // Check every minute

    // Also check immediately on startup
    setTimeout(() => this.checkTriggers(), 5000);
  }

  /**
   * Start the session cleanup loop
   * Cleans up old/stale chat sessions periodically
   */
  startSessionCleanupLoop() {
    // Run cleanup once per hour
    setInterval(async () => {
      try {
        const cleaned = await this.sessionManager.cleanupOldSessions();
        if (cleaned > 0) {
          console.log(`[Orchestrator] Cleaned up ${cleaned} old sessions`);
        }
      } catch (error) {
        console.error('[Orchestrator] Error cleaning sessions:', error);
      }
    }, 60 * 60 * 1000); // Every hour

    // Also run cleanup on startup (after 30 seconds)
    setTimeout(async () => {
      try {
        const cleaned = await this.sessionManager.cleanupOldSessions();
        if (cleaned > 0) {
          console.log(`[Orchestrator] Initial cleanup: ${cleaned} old sessions`);
        }
      } catch (error) {
        console.error('[Orchestrator] Error in initial cleanup:', error);
      }
    }, 30000);
  }

  /**
   * Check all document triggers and update statuses
   */
  async checkTriggers() {
    try {
      // Find all agent-document pairs whose triggers should fire
      const triggered = await this.documentScanner.findTriggeredAgents();

      for (const pair of triggered) {
        console.log(`[Orchestrator] Trigger fired: ${pair.agentPath} on ${pair.documentPath}`);
        await this.documentScanner.updateAgentStatus(
          pair.documentPath,
          pair.agentPath,
          AgentStatus.NEEDS_RUN
        );
      }

      // Process any agents that need running
      await this.processTriggeredAgents();

    } catch (error) {
      console.error('[Orchestrator] Error checking triggers:', error);
    }
  }

  /**
   * Process all agent-document pairs with needs_run status
   */
  async processTriggeredAgents() {
    const pairs = await this.documentScanner.findNeedsRun();

    for (const pair of pairs) {
      console.log(`[Orchestrator] Queueing: ${pair.agentPath} for ${pair.documentPath}`);

      // Update status to running
      await this.documentScanner.updateAgentStatus(
        pair.documentPath,
        pair.agentPath,
        AgentStatus.RUNNING
      );

      // Queue the agent to run on this document
      await this.enqueue(pair.agentPath, {
        documentPath: pair.documentPath,
        documentContent: pair.document.body,
        documentFrontmatter: pair.document.frontmatter,
        userMessage: `Process the document at: ${pair.documentPath}`
      }, {
        priority: Priority.NORMAL,
        documentPath: pair.documentPath,  // Track for status updates
        agentPath: pair.agentPath
      });
    }
  }

  /**
   * Run all pending agents on a document
   */
  async runAllAgentsOnDocument(documentPath) {
    const pending = await this.documentScanner.getPendingAgents(documentPath);
    const results = [];

    for (const agentConfig of pending) {
      results.push(await this.runAgentOnDocument(documentPath, agentConfig.path));
    }

    return results;
  }

  /**
   * Run specific agents on a document
   */
  async runAgentsOnDocument(documentPath, agentPaths) {
    const results = [];

    for (const agentPath of agentPaths) {
      results.push(await this.runAgentOnDocument(documentPath, agentPath));
    }

    return results;
  }

  /**
   * Run a single agent on a document
   */
  async runAgentOnDocument(documentPath, agentPath) {
    const fullPath = path.join(this.vaultPath, documentPath);
    const doc = await this.documentScanner.parseDocument(fullPath);

    // Update status to running
    await this.documentScanner.updateAgentStatus(documentPath, agentPath, AgentStatus.RUNNING);

    try {
      // Load the agent
      const agent = await loadAgent(agentPath, this.vaultPath);

      // Build context with the document content
      const systemPrompt = buildSystemPrompt(agent, {
        documentPath,
        documentContent: doc.body,
        documentFrontmatter: doc.frontmatter
      });

      // Execute
      const result = await this.executeAgent(
        agent,
        `Process the document at: ${documentPath}\n\nDocument content:\n${doc.body}`,
        systemPrompt,
        0
      );

      // Update status to completed
      await this.documentScanner.updateAgentStatus(documentPath, agentPath, AgentStatus.COMPLETED, {
        last_result: result.success ? 'success' : 'error'
      });

      return { documentPath, agentPath, ...result };

    } catch (error) {
      await this.documentScanner.updateAgentStatus(documentPath, agentPath, AgentStatus.ERROR, {
        last_error: error.message
      });
      return { documentPath, agentPath, success: false, error: error.message };
    }
  }

  /**
   * Process a specific document with its first/primary agent (legacy support)
   */
  async processDocument(documentPath) {
    const doc = await this.documentScanner.parseDocument(
      path.join(this.vaultPath, documentPath)
    );

    if (!doc.agent) {
      throw new Error(`Document ${documentPath} has no agent assigned`);
    }

    return this.runAgentOnDocument(documentPath, doc.agent);
  }

  /**
   * Manually trigger all agents on a document
   */
  async triggerDocument(documentPath) {
    const triggered = await this.documentScanner.triggerAllAgents(documentPath);
    if (triggered.length > 0) {
      await this.processTriggeredAgents();
    }
    return triggered;
  }

  /**
   * Manually trigger specific agents on a document
   */
  async triggerDocumentAgents(documentPath, agentPaths) {
    const triggered = await this.documentScanner.triggerAgents(documentPath, agentPaths);
    if (triggered.length > 0) {
      await this.processTriggeredAgents();
    }
    return triggered;
  }

  /**
   * Reset agents on a document to pending
   */
  async resetDocumentAgents(documentPath, agentPaths = null) {
    return this.documentScanner.resetAgents(documentPath, agentPaths);
  }

  /**
   * Get pending agents for a document
   */
  async getPendingAgents(documentPath) {
    return this.documentScanner.getPendingAgents(documentPath);
  }

  /**
   * Get document statistics
   */
  async getDocumentStats() {
    return this.documentScanner.getStats();
  }

  /**
   * Get all documents with agent configurations
   */
  async getAgentDocuments() {
    return this.documentScanner.scanAll();
  }

  /**
   * Get agents configured for a specific document
   */
  async getDocumentAgents(documentPath) {
    const fullPath = path.join(this.vaultPath, documentPath);
    const doc = await this.documentScanner.parseDocument(fullPath);
    return doc.agents;
  }

  /**
   * Update agents configured for a document
   */
  async updateDocumentAgents(documentPath, agents) {
    return this.documentScanner.updateDocumentAgents(documentPath, agents);
  }
}

export default Orchestrator;
