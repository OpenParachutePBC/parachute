# Parachute Stability Action Plan

**Created:** December 27, 2025
**Based on:** Deep audit of agent server, Flutter app, and client-server communication

---

## Executive Summary

The audit identified **5 critical issues** that can cause data loss or app freezes, **6 high-priority issues** that cause memory leaks or degraded performance, and **8 medium-priority issues** for long-term health. This plan organizes fixes into phases.

---

## Phase 1: Critical Stability (Do First)

These issues can cause immediate user-facing problems: frozen UI, lost messages, or corrupted sessions.

### 1.1 Add Streaming Request Timeout
**File:** `app/lib/features/chat/services/chat_service.dart`
**Risk:** App freezes indefinitely if server hangs mid-stream
**Effort:** Small

```dart
// Current (line 388):
final streamedResponse = await _client.send(request);

// Fixed:
final streamedResponse = await _client.send(request)
    .timeout(const Duration(minutes: 10), onTimeout: () {
      throw TimeoutException('Stream request timed out');
    });

// Also add per-chunk timeout (line 400):
await for (final chunk in streamedResponse.stream
    .timeout(const Duration(seconds: 30))
    .transform(utf8.decoder)) {
```

### 1.2 Fix Concurrent Session Write Race Condition
**File:** `agent/lib/session-manager-v2.js`
**Risk:** Two concurrent `addMessage()` calls lose one message
**Effort:** Medium

```javascript
// Add a write lock per session
class SessionManager {
  constructor() {
    this.writeLocks = new Map(); // sessionId -> Promise
  }

  async addMessage(session, role, content) {
    const lockKey = session.sdkSessionId;

    // Wait for any pending write
    while (this.writeLocks.has(lockKey)) {
      await this.writeLocks.get(lockKey);
    }

    // Create our write lock
    let releaseLock;
    const lockPromise = new Promise(r => releaseLock = r);
    this.writeLocks.set(lockKey, lockPromise);

    try {
      session.messages.push({...});
      session.lastAccessed = new Date().toISOString();
      await this.saveSession(session);
    } finally {
      this.writeLocks.delete(lockKey);
      releaseLock();
    }
  }
}
```

### 1.3 Add Bounds Checking to Unbounded Maps
**File:** `agent/lib/orchestrator.js`
**Risk:** Memory exhaustion under sustained load or attack
**Effort:** Small

```javascript
// Add constants
const MAX_PENDING_PERMISSIONS = 100;
const MAX_QUEUE_STREAMS = 50;

// In permission request handling (line ~160):
if (this.pendingPermissions.size >= MAX_PENDING_PERMISSIONS) {
  console.warn('[Orchestrator] Too many pending permissions, denying');
  return { behavior: 'deny', message: 'Server overloaded', interrupt: false };
}

// In queue stream creation:
if (this.queueStreams.size >= MAX_QUEUE_STREAMS) {
  console.warn('[Orchestrator] Too many queue streams, rejecting');
  throw new Error('Queue capacity exceeded');
}
```

### 1.4 Fix Session Finalization Race
**File:** `agent/lib/orchestrator.js`
**Risk:** Two requests to new session create inconsistent state
**Effort:** Medium

```javascript
// Add finalization lock
this.finalizingSessionIds = new Set();

async finalizeSession(session, sdkSessionId) {
  const lockKey = session.id || session.sdkSessionId;

  if (this.finalizingSessionIds.has(lockKey)) {
    // Already being finalized, wait a bit and return
    await new Promise(r => setTimeout(r, 100));
    return;
  }

  this.finalizingSessionIds.add(lockKey);
  try {
    session.sdkSessionId = sdkSessionId;
    await this.sessionManager.saveSession(session);
  } finally {
    this.finalizingSessionIds.delete(lockKey);
  }
}
```

---

## Phase 2: Resource Leaks (Memory & Connections)

These issues degrade performance over time and can eventually crash the app.

### 2.1 Add Client Disconnect Detection
**File:** `agent/server.js`
**Risk:** Server continues expensive operations for dead clients
**Effort:** Small

```javascript
// In POST /api/chat/stream handler (around line 263):
app.post('/api/chat/stream', async (req, res) => {
  // Create abort signal
  const abortController = new AbortController();
  let clientDisconnected = false;

  req.on('close', () => {
    clientDisconnected = true;
    abortController.abort();
    log.info('Client disconnected from stream');
  });

  // Pass to orchestrator
  const context = {
    ...existingContext,
    signal: abortController.signal,
  };

  // In the streaming loop:
  for await (const event of stream) {
    if (clientDisconnected) {
      log.info('Stopping stream - client disconnected');
      break;
    }
    res.write(`data: ${JSON.stringify(event)}\n\n`);
  }
});
```

### 2.2 Fix Orphaned SSE Permission Listeners
**File:** `agent/server.js`
**Risk:** Event listeners accumulate, memory leak
**Effort:** Small

```javascript
// In GET /api/permissions/stream (around line 1013):
app.get('/api/permissions/stream', (req, res) => {
  // Add timeout for dead connections
  const STREAM_TIMEOUT = 30 * 60 * 1000; // 30 minutes max
  const timeoutId = setTimeout(() => {
    cleanup();
    res.end();
  }, STREAM_TIMEOUT);

  const cleanup = () => {
    clearTimeout(timeoutId);
    orchestrator.off('permissionRequest', onPermissionRequest);
    orchestrator.off('permissionGranted', onPermissionGranted);
    orchestrator.off('permissionDenied', onPermissionDenied);
  };

  req.on('close', cleanup);
  req.on('error', cleanup);

  // ... rest of handler
});
```

### 2.3 Fix Periodic Health Stream Leak
**File:** `app/lib/core/providers/backend_health_provider.dart`
**Risk:** Stream never cancelled, wasted resources
**Effort:** Small

```dart
final periodicServerHealthProvider = StreamProvider<ServerHealthStatus?>((ref) async* {
  final healthService = ref.watch(healthServiceProvider);
  final serverUrl = ref.watch(agentServerUrlProvider);

  // Initial check
  yield await healthService.checkHealth(serverUrl);

  // Periodic checks with proper cancellation
  await for (final _ in Stream.periodic(const Duration(seconds: 30))) {
    // Check if provider is still active
    if (ref.state.isRefreshing) break;

    try {
      yield await healthService.checkHealth(serverUrl);
    } catch (e) {
      yield ServerHealthStatus.unknown();
    }
  }
});
```

### 2.4 Clean Up Permission Timeout Dangling Promises
**File:** `agent/lib/orchestrator.js`
**Risk:** Timed-out promises never garbage collected
**Effort:** Small

```javascript
async waitForPermission(requestId, promise) {
  const timeoutMs = 120000;
  let timeoutId;

  const timeoutPromise = new Promise((resolve) => {
    timeoutId = setTimeout(() => resolve('timeout'), timeoutMs);
  });

  try {
    const decision = await Promise.race([promise, timeoutPromise]);
    clearTimeout(timeoutId);
    return decision;
  } catch (error) {
    clearTimeout(timeoutId);
    throw error;
  } finally {
    // Always clean up the pending permission
    this.pendingPermissions.delete(requestId);
  }
}
```

---

## Phase 3: Error Handling & Resilience

These issues cause silent failures or poor error recovery.

### 3.1 Wrap Critical Widgets in ErrorBoundary
**File:** `app/lib/features/chat/screens/chat_screen.dart`
**Risk:** Unhandled widget exceptions crash entire app
**Effort:** Small

```dart
// In chat_screen.dart build method:
@override
Widget build(BuildContext context) {
  return ErrorBoundary(
    onError: (error, stack) {
      log.error('Chat screen error', error: error, stackTrace: stack);
    },
    child: Scaffold(
      // ... existing scaffold content
    ),
  );
}

// Also wrap MessageBubble in message_list.dart:
ErrorBoundary(
  child: MessageBubble(message: message),
)
```

### 3.2 Add Logging for Stream Parse Failures
**File:** `app/lib/features/chat/services/chat_service.dart`
**Risk:** Malformed events silently dropped
**Effort:** Small

```dart
final event = StreamEvent.parse(line);
if (event != null) {
  yield event;
} else if (line.isNotEmpty && !line.startsWith(':')) {
  // Log unexpected parse failures (ignore SSE comments)
  debugPrint('[ChatService] Failed to parse SSE line: ${line.substring(0, line.length.clamp(0, 100))}');
}
```

### 3.3 Add Stack Traces to Error Logs
**File:** `app/lib/features/chat/providers/chat_providers.dart`
**Risk:** Cannot debug production issues
**Effort:** Small

```dart
} catch (e, stackTrace) {
  debugPrint('[ChatMessagesNotifier] Stream error: $e');
  debugPrint('[ChatMessagesNotifier] Stack trace: $stackTrace');
  state = state.copyWith(
    isStreaming: false,
    error: e.toString(),
  );
}
```

### 3.4 Add Session Save Retry Logic
**File:** `agent/lib/session-manager-v2.js`
**Risk:** Transient disk errors cause permanent message loss
**Effort:** Medium

```javascript
async saveSession(session, retries = 3) {
  for (let attempt = 1; attempt <= retries; attempt++) {
    try {
      await this._doSaveSession(session);
      return;
    } catch (error) {
      console.error(`[SessionManager] Save attempt ${attempt} failed:`, error.message);
      if (attempt === retries) {
        throw error;
      }
      // Exponential backoff
      await new Promise(r => setTimeout(r, 100 * Math.pow(2, attempt)));
    }
  }
}
```

---

## Phase 4: Performance & Observability

These are nice-to-have improvements for long-term health.

### 4.1 Add SSE Heartbeat
**File:** `agent/server.js`
**Risk:** Network proxies close idle connections
**Effort:** Small

```javascript
// In streaming handler, send periodic heartbeat:
const heartbeatInterval = setInterval(() => {
  if (!clientDisconnected) {
    res.write(': heartbeat\n\n');
  }
}, 15000); // Every 15 seconds

// Clean up on end:
clearInterval(heartbeatInterval);
```

### 4.2 Add Session Index Cleanup
**File:** `agent/lib/session-manager-v2.js`
**Risk:** Index grows indefinitely
**Effort:** Small

```javascript
// Add periodic index cleanup
cleanupSessionIndex() {
  const maxIndexSize = 1000;
  if (this.sessionIndex.size > maxIndexSize) {
    // Keep most recently accessed
    const sorted = [...this.sessionIndex.entries()]
      .sort((a, b) => new Date(b[1].lastAccessed) - new Date(a[1].lastAccessed));

    this.sessionIndex = new Map(sorted.slice(0, maxIndexSize));
    console.log(`[SessionManager] Trimmed session index to ${maxIndexSize} entries`);
  }
}
```

### 4.3 Add Request Timeouts to All HTTP Calls
**File:** `app/lib/features/chat/services/chat_service.dart`
**Risk:** Any HTTP call can hang indefinitely
**Effort:** Medium

```dart
// Create a helper method
Future<http.Response> _get(String path) async {
  return await _client.get(
    Uri.parse('$baseUrl$path'),
    headers: {'Content-Type': 'application/json'},
  ).timeout(
    const Duration(seconds: 30),
    onTimeout: () => throw TimeoutException('Request to $path timed out'),
  );
}

// Use throughout:
Future<List<ChatSession>> getSessions() async {
  final response = await _get('/api/chat/sessions');
  // ...
}
```

### 4.4 Add Infinite Recursion Protection
**File:** `agent/lib/orchestrator.js`
**Risk:** Symlink loops cause stack overflow
**Effort:** Small

```javascript
async listVaultFiles(dir = this.vaultPath, files = [], depth = 0) {
  const MAX_DEPTH = 20;
  if (depth > MAX_DEPTH) {
    console.warn(`[Orchestrator] Max directory depth exceeded at ${dir}`);
    return files;
  }

  // ... existing code, pass depth + 1 to recursive calls
}
```

---

## Implementation Order

| Order | Issue | Phase | Effort | Impact |
|-------|-------|-------|--------|--------|
| 1 | Streaming timeout | 1.1 | Small | Critical |
| 2 | Concurrent write lock | 1.2 | Medium | Critical |
| 3 | Map bounds checking | 1.3 | Small | Critical |
| 4 | Session finalization lock | 1.4 | Medium | Critical |
| 5 | Client disconnect detection | 2.1 | Small | High |
| 6 | Permission listener cleanup | 2.2 | Small | High |
| 7 | Health stream cancellation | 2.3 | Small | Medium |
| 8 | ErrorBoundary wrappers | 3.1 | Small | High |
| 9 | Parse failure logging | 3.2 | Small | Medium |
| 10 | Stack trace logging | 3.3 | Small | Medium |
| 11 | SSE heartbeat | 4.1 | Small | Low |
| 12 | Session index cleanup | 4.2 | Small | Low |

---

## Testing Strategy

After implementing each fix:

1. **Phase 1 (Critical):**
   - Test streaming with network interruption (disconnect WiFi mid-stream)
   - Send two rapid messages to same new session, verify both saved
   - Simulate 100+ pending permissions, verify bounds work

2. **Phase 2 (Resource Leaks):**
   - Monitor memory usage over 1-hour session
   - Open/close SSE permission stream repeatedly
   - Verify health checks stop when app backgrounded

3. **Phase 3 (Error Handling):**
   - Inject malformed SSE events, verify logged
   - Crash a component, verify ErrorBoundary catches it
   - Fail disk write, verify retry works

---

## Success Metrics

After all fixes:

- [ ] No app freezes during 1-hour chat session
- [ ] Memory usage stays flat over 8+ hours
- [ ] All errors logged with stack traces
- [ ] No message loss under concurrent writes
- [ ] Clean shutdown with no orphaned resources

---

**Next Steps:** Start with Phase 1 items in order. Each fix should be tested before moving to the next.
