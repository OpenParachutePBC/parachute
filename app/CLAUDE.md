# Parachute App - Development Guide

**Essential guidance for Claude Code when working with the Parachute Flutter app.**

---

## Vision & Philosophy

**Parachute** is open & interoperable extended mind technology—a connected tool for connected thinking.

We build local-first, voice-first AI tooling that gives people agency over their digital minds. Technology should support natural human cognition, not force us into unnatural patterns.

**Core Principles:**
- **Local-First** - Your data stays on your devices; you control what goes to the cloud
- **Voice-First** - More natural than typing; meets people where they actually think
- **Open & Interoperable** - Standard formats (markdown, JSONL), works with Obsidian/Logseq
- **Prosocial, Not Surveillance** - You control what's captured and where it goes
- **Thoughtful AI** - Enhance thinking, don't replace it

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         FLUTTER APP                                  │
│                                                                      │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐              │
│  │   Recorder   │  │    Chat      │  │   Settings   │              │
│  │   Feature    │  │   Feature    │  │   Feature    │              │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘              │
│         │                 │                 │                       │
│         └─────────────────┼─────────────────┘                       │
│                           ▼                                         │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                    RIVERPOD PROVIDERS                        │   │
│  │  storageServiceProvider, chatServiceProvider, etc.          │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                           │                                         │
│         ┌─────────────────┼─────────────────┐                       │
│         ▼                 ▼                 ▼                       │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐              │
│  │ StorageService│  │ ChatService  │  │AudioService  │              │
│  │ (local files) │  │ (HTTP/SSE)   │  │ (recording)  │              │
│  └──────────────┘  └──────────────┘  └──────────────┘              │
└─────────────────────────────────────────────────────────────────────┘
         │                 │
         ▼                 ▼
┌─────────────────┐  ┌─────────────────┐
│  Local Vault    │  │  Agent Backend  │
│  ~/Parachute/   │  │  localhost:3333 │
│                 │  │                 │
│  ├─ captures/   │  │  /api/chat      │
│  ├─ spheres/    │  │  /api/agents    │
│  └─ .git/       │  │  /api/captures  │
└─────────────────┘  └─────────────────┘
```

---

## Key Files

| File | Purpose |
|------|---------|
| `lib/main.dart` | App entry point, navigation setup |
| `lib/core/config/app_config.dart` | Centralized configuration constants |
| `lib/core/services/logger_service.dart` | Structured logging with levels |
| `lib/core/errors/app_error.dart` | Custom error classes |
| `lib/core/services/file_system_service.dart` | Platform-aware file operations |
| `lib/features/recorder/services/storage_service.dart` | Recording persistence |
| `lib/features/recorder/services/audio_service.dart` | Microphone recording |
| `lib/features/recorder/services/live_transcription_service_v3.dart` | VAD + transcription |
| `lib/features/chat/services/chat_service.dart` | Agent backend API client |
| `lib/features/chat/providers/chat_providers.dart` | Chat state management |

---

## Commands

```bash
flutter pub get                        # Install dependencies
flutter run -d macos                   # Run on macOS
flutter run -d android                 # Run on Android
flutter run -d chrome --web-port=8090  # Run in browser
flutter test                           # Run tests
flutter analyze                        # Check for issues
flutter clean && flutter pub get       # Clean build
```

---

## Agent Backend API

The app communicates with [parachute-agent](https://github.com/OpenParachutePBC/parachute-agent) backend.

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/health` | GET | Health check |
| `/api/agents` | GET | List available agents |
| `/api/chat/stream` | POST | SSE streaming chat |
| `/api/chat/sessions` | GET | List all sessions |
| `/api/chat/session/:id` | GET | Get session with messages |
| `/api/chat/session/:id` | DELETE | Delete session |
| `/api/captures` | POST | Upload document |
| `/api/captures` | GET | List captures |

### SSE Stream Events

The `/api/chat/stream` endpoint returns these event types:

```
session  → { sessionId, title }           # Session info at start
init     → { tools }                       # Available tools
text     → { content }                     # Accumulated response text
tool_use → { tool: { name, input } }       # Tool execution
done     → { durationMs, title }           # Stream complete
error    → { error }                       # Error occurred
```

---

## Key Patterns

### Riverpod State Management

All state flows through Riverpod providers:

```dart
// Service providers (singletons)
final storageServiceProvider = Provider((ref) => StorageService(ref));

// Async data providers
final recordingsProvider = FutureProvider((ref) async {
  final storage = ref.watch(storageServiceProvider);
  return storage.getRecordings();
});

// State notifiers for complex state
final chatMessagesProvider = StateNotifierProvider<ChatMessagesNotifier, ChatMessagesState>(
  (ref) => ChatMessagesNotifier(ref),
);
```

**Rules:**
- Services created via Provider (singletons)
- Async data via FutureProvider or StreamProvider
- Complex mutable state via StateNotifierProvider
- Always dispose subscriptions in `ref.onDispose()`

### Structured Logging

Use the logger service instead of `debugPrint()`:

```dart
import 'package:app/core/services/logger_service.dart';

final log = logger.createLogger('MyComponent');

log.debug('Processing started', data: {'count': 42});
log.info('Operation complete');
log.warn('Resource low', error: e);
log.error('Failed', error: e, stackTrace: st);
```

### Custom Errors

Use typed errors from `lib/core/errors/app_error.dart`:

```dart
throw StorageError.notFound(path);
throw NetworkError.timeout(url);
throw RecordingError.microphonePermissionDenied();
throw ChatError.sessionNotFound(id);
```

### File System Operations

Always use `FileSystemService` for paths:

```dart
final fs = ref.read(fileSystemServiceProvider);
final capturesPath = await fs.capturesPath;
final spheresPath = await fs.spheresPath;
// NEVER hardcode: ~/Parachute/captures/
```

### Parallel I/O Pattern

For bulk file operations, use parallel batches:

```dart
const batchSize = 20;
for (int i = 0; i < files.length; i += batchSize) {
  final batch = files.skip(i).take(batchSize);
  final results = await Future.wait(batch.map((f) => loadFile(f)));
  // Process results...
}
```

### Widget Lifecycle Safety

Check `mounted` before async setState:

```dart
Future<void> _loadData() async {
  final data = await fetchData();
  if (!mounted) return;  // Widget may have been disposed
  setState(() => _data = data);
}
```

---

## Configuration

All configuration constants are in `lib/core/config/app_config.dart`:

| Category | Key Constants |
|----------|---------------|
| Backend | `defaultAgentServerUrl`, `apiTimeout`, `streamTimeout` |
| Storage | `defaultVaultName`, `defaultCapturesFolder`, `recordingCacheDuration` |
| Recording | `audioSampleRate`, `vadSilenceThreshold`, `minRecordingDurationMs` |
| Chat | `maxMessageLength`, `searchDebounceDelay` |
| Performance | `fileIoBatchSize`, `maxLogBufferSize` |

---

## CRITICAL Bug Preventions

### ⚠️ #1: Flutter Type Casting (MOST COMMON ERROR)

**NEVER do this:**
```dart
❌ final List<dynamic> data = response.data as List<dynamic>;  // CRASHES!
```

**ALWAYS do this:**
```dart
✅ final Map<String, dynamic> data = response.data as Map<String, dynamic>;
   final List<dynamic> items = data['items'] as List<dynamic>;
```

### ⚠️ #2: Riverpod ProviderScope

All widgets using providers MUST be wrapped in `ProviderScope`:
```dart
runApp(ProviderScope(child: ParachuteApp()));
```

### ⚠️ #3: File Paths

- Use `FileSystemService` for all paths - NEVER hardcode
- Vault location varies by platform
- Subfolder names are user-configurable

### ⚠️ #4: Async Lifecycle

- Check `mounted` before `setState` after async operations
- Cancel subscriptions in `dispose()`
- Use `ref.onDispose()` for provider cleanup

---

## Project Structure

```
lib/
├── core/                          # Shared infrastructure
│   ├── config/                    # App configuration
│   │   └── app_config.dart        # Centralized constants
│   ├── errors/                    # Custom error classes
│   │   └── app_error.dart         # Typed exceptions
│   ├── services/                  # Core services
│   │   ├── logger_service.dart    # Structured logging
│   │   ├── file_system_service.dart
│   │   └── api_client.dart
│   ├── providers/                 # Shared Riverpod providers
│   ├── models/                    # Shared data models
│   └── theme/                     # Design tokens, colors
│
├── features/                      # Feature modules
│   ├── recorder/                  # Voice recording
│   │   ├── models/
│   │   ├── providers/
│   │   ├── services/
│   │   ├── screens/
│   │   └── widgets/
│   ├── chat/                      # AI chat
│   │   ├── models/
│   │   ├── providers/
│   │   ├── services/
│   │   ├── screens/
│   │   └── widgets/
│   ├── settings/                  # App settings
│   └── onboarding/                # First-time setup
│
└── main.dart                      # Entry point
```

---

## Data Flow

### Recording Flow
```
User taps record
    ↓
AudioService.startRecording()
    ↓
LiveTranscriptionService processes audio
    ↓
VAD detects speech/silence
    ↓
SmartChunker segments on silence
    ↓
Whisper/Parakeet transcribes segments
    ↓
StorageService.saveRecording()
    ↓
Markdown + audio saved to vault
    ↓
Git auto-commit (if enabled)
```

### Chat Flow
```
User sends message
    ↓
ChatService.streamChat() → POST /api/chat/stream
    ↓
SSE events received:
  session → Store session ID
  text    → Update UI with content
  tool_use → Show tool execution
  done    → Mark complete, capture title
    ↓
ChatMessagesNotifier updates state
    ↓
UI rebuilds via Riverpod
```

---

## Git Workflow

**🚨 CRITICAL: DO NOT commit or push without user approval! 🚨**

1. Make code change
2. Tell user what changed
3. Ask user to test
4. Wait for confirmation
5. **Ask permission to commit**
6. Commit only after approval
7. **Ask permission to push**
8. Push only after approval

Always use `git --no-pager` to prevent pager blocking output.

---

## Testing

```bash
flutter test                           # All tests
flutter test test/features/recorder/   # Feature tests
flutter test --coverage                # With coverage
```

**Test Coverage Focus:**
- Audio pipeline (VAD, SmartChunker) - 116 tests
- Storage service operations
- Provider state transitions

---

## Platform Notes

| Platform | Vault Default | Notes |
|----------|---------------|-------|
| macOS | `~/Parachute/` | Full feature support |
| Android | External storage | Native Git via libgit2 |
| iOS | App Documents | Git support pending |
| Web | N/A | Debug/demo only |

---

## Feature Flags

Toggle features via `AppConfig`:

```dart
AppConfig.enableAiChat = true;           // AI chat feature
AppConfig.enableOmiDevice = true;        // Omi hardware support
AppConfig.enableGitSync = true;          // Git sync to GitHub
AppConfig.enableSearchIndexing = true;   // RAG search indexing
```

---

## Debugging

### View Logs
```dart
// Get recent errors
final errors = logger.getLogs(level: LogLevel.error, limit: 50);

// Get component-specific logs
final chatLogs = logger.getLogs(component: 'ChatService');

// Get log statistics
final stats = logger.getStats();
```

### Common Issues

| Issue | Solution |
|-------|----------|
| "ProviderScope not found" | Wrap app in `ProviderScope` |
| Recording not saving | Check `FileSystemService` permissions |
| Chat not connecting | Verify agent server at localhost:3333 |
| Transcription failing | Ensure model is downloaded |
| Git sync stuck | Check `isInitialized` before operations |

---

## Related Repositories

- **[parachute-agent](https://github.com/OpenParachutePBC/parachute-agent)** - Node.js backend for AI agents
- **[parachute-firmware](firmware/)** - Omi device firmware (Zephyr RTOS)

---

## Quick Reference

**Package name:** `package:app/...` (not `parachute`)

**Server URL:** `http://localhost:3333` (configurable in settings)

**Vault structure:**
```
~/Parachute/
├── captures/          # Voice recordings
│   ├── YYYY-MM-DD_HH-MM-SS.md
│   └── YYYY-MM-DD_HH-MM-SS.opus
└── spheres/           # Knowledge spheres
    └── sphere-name/
        ├── CLAUDE.md
        └── sphere.jsonl
```

---

**Last Updated**: December 12, 2025
