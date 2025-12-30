# Parachute Chat - Development Guide

**AI chat assistant that connects to Parachute Base server for Claude SDK integration.**

---

## Overview

Parachute Chat is a Flutter app that provides AI-powered chat with your knowledge vault. Unlike Parachute Daily (which runs standalone), Chat requires the Base server for AI features.

**Key Characteristics:**
- Requires Base server connection (`http://localhost:3333` by default)
- Sessions stored as markdown in `Chat/sessions/`
- Riverpod for state management
- SSE streaming for real-time AI responses

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        PARACHUTE CHAT                            │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                    UI Layer (Screens)                     │   │
│  │  ChatScreen, SettingsScreen, VaultScreen                 │   │
│  └────────────────────────┬─────────────────────────────────┘   │
│                           │                                      │
│  ┌────────────────────────▼─────────────────────────────────┐   │
│  │                 State Layer (Riverpod)                    │   │
│  │  chatSessionProvider, messagesProvider, settingsProvider │   │
│  └────────────────────────┬─────────────────────────────────┘   │
│                           │                                      │
│  ┌────────────────────────▼─────────────────────────────────┐   │
│  │                  Service Layer                            │   │
│  │  ChatService (HTTP/SSE), FileSystemService (paths)       │   │
│  └────────────────────────┬─────────────────────────────────┘   │
│                           │                                      │
└───────────────────────────┼──────────────────────────────────────┘
                            │
                            ▼ HTTP/SSE (port 3333)
                   ┌─────────────────┐
                   │  BASE SERVER    │
                   └─────────────────┘
```

---

## Directory Structure

```
chat/lib/
├── main.dart                    # App entry point
├── core/                        # Shared infrastructure
│   ├── config/                  # App configuration
│   ├── constants/               # App-wide constants
│   ├── errors/                  # Error types
│   ├── models/                  # Shared models
│   ├── providers/               # Core Riverpod providers
│   ├── services/                # Core services
│   ├── theme/                   # Design tokens, themes
│   └── widgets/                 # Reusable widgets
│
└── features/                    # Feature modules
    ├── chat/                    # Main chat feature
    │   ├── models/              # ChatSession, ChatMessage
    │   ├── providers/           # Chat state providers
    │   ├── screens/             # ChatScreen
    │   ├── services/            # ChatService, LocalSessionReader
    │   └── widgets/             # MessageBubble, etc.
    │
    ├── settings/                # App settings
    │   ├── models/              # Settings models
    │   ├── screens/             # SettingsScreen
    │   ├── services/            # Settings persistence
    │   └── widgets/             # Settings sections
    │
    ├── context/                 # Personal context management
    │   ├── models/              # Context models
    │   ├── providers/           # Context state
    │   ├── services/            # Context loading
    │   └── widgets/             # Context UI
    │
    ├── vault/                   # Vault browsing
    │   ├── providers/           # Vault state
    │   ├── screens/             # VaultScreen
    │   └── widgets/             # File browser
    │
    ├── files/                   # File operations
    │   └── providers/           # File state
    │
    ├── recorder/                # Voice input (shared with Daily)
    │   ├── models/              # Recording models
    │   ├── providers/           # Recording state
    │   ├── services/            # Audio, transcription
    │   └── widgets/             # Recording UI
    │
    └── onboarding/              # First-run setup
        └── screens/             # Onboarding flow
```

---

## Key Files

| File | Purpose |
|------|---------|
| `lib/main.dart` | App entry point, provider scope setup |
| `lib/features/chat/services/chat_service.dart` | HTTP/SSE communication with Base server |
| `lib/features/chat/providers/chat_providers.dart` | Main chat state management |
| `lib/features/chat/models/chat_session.dart` | Session model with messages |
| `lib/core/services/file_system_service.dart` | Vault paths, file operations |
| `lib/core/providers/backend_health_provider.dart` | Server connection status |

---

## State Management (Riverpod)

### Core Providers

```dart
// Server connection state
final backendHealthProvider = StreamProvider<BackendHealth>((ref) {
  return BackendHealthService.healthStream;
});

// Current chat session
final chatSessionProvider = StateNotifierProvider<ChatSessionNotifier, ChatSession?>((ref) {
  return ChatSessionNotifier(ref);
});

// Messages for current session
final messagesProvider = Provider<List<ChatMessage>>((ref) {
  return ref.watch(chatSessionProvider)?.messages ?? [];
});

// Session list from server
final sessionsProvider = FutureProvider<List<SessionSummary>>((ref) async {
  return ref.read(chatServiceProvider).listSessions();
});
```

### Provider Pattern

1. **Services** are created via `Provider` (singleton)
2. **UI State** uses `StateNotifierProvider` for mutations
3. **Async data** uses `FutureProvider` or `StreamProvider`
4. **Derived state** uses plain `Provider` with `ref.watch`

---

## Chat Flow

### Sending a Message

```
User types message
       │
       ▼
ChatScreen calls sendMessage()
       │
       ▼
ChatService.sendMessageStreaming()
       │
       ▼
POST /api/chat/stream (SSE)
       │
       ▼
Stream events: session → init → text → tool_use → done
       │
       ▼
ChatSessionNotifier updates state
       │
       ▼
UI rebuilds via Riverpod watch
```

### SSE Event Types

| Event | Purpose |
|-------|---------|
| `session` | Session ID and resume info |
| `init` | Available tools list |
| `text` | AI response text (streaming) |
| `tool_use` | Tool being executed |
| `tool_result` | Tool execution result |
| `done` | Final response, session metadata |
| `error` | Error message |

---

## Data Paths

The Chat app uses these vault paths:

| Path | Contents |
|------|----------|
| `Chat/sessions/` | Chat session markdown files |
| `Chat/sessions/vault-agent/` | Sessions by agent |
| `Chat/contexts/` | Personal context files |
| `Chat/assets/` | Generated images, audio |
| `.agents/` | Custom agent definitions |
| `AGENTS.md` | System prompt override |

Configured in `FileSystemService`:
```dart
// Default root: ~/Parachute/Chat/
static const String _defaultSessionsFolderName = 'sessions';
static const String _defaultAssetsFolderName = 'assets';
static const String _contextsFolderName = 'contexts';
```

---

## Commands

```bash
cd chat
flutter pub get                 # Install dependencies
flutter run -d macos            # Run on macOS
flutter run -d android          # Run on Android
flutter analyze                 # Check for issues
flutter test                    # Run tests
```

---

## Server Communication

### ChatService API Methods

```dart
// Send message with streaming response
Stream<ChatEvent> sendMessageStreaming(String message, {String? sessionId});

// List sessions (paginated)
Future<List<SessionSummary>> listSessions({int offset = 0, int limit = 50});

// Get session by ID with full messages
Future<ChatSession?> getSession(String sessionId);

// Archive/unarchive sessions
Future<void> archiveSession(String sessionId);
Future<void> unarchiveSession(String sessionId);

// Delete session
Future<void> deleteSession(String sessionId);
```

### Server URL Configuration

Default: `http://localhost:3333`

Change via Settings → AI Chat → Server URL

Stored in: `SharedPreferences` key `backendUrl`

---

## Adding Features

### New Chat Widget

1. Create widget in `lib/features/chat/widgets/`
2. Use `ref.watch` for reactive state
3. Access services via `ref.read(chatServiceProvider)`

### New Settings Section

1. Create widget in `lib/features/settings/widgets/`
2. Add to `SettingsScreen` build method
3. Use `SharedPreferences` for persistence

### New Provider

1. Define in appropriate `providers/` directory
2. Follow naming: `thingProvider` for state, `thingServiceProvider` for services
3. Document in this file

---

## Debugging

### Server Connection Issues

```dart
// Check backend health
ref.watch(backendHealthProvider).when(
  data: (health) => print('Server: ${health.isHealthy}'),
  loading: () => print('Checking...'),
  error: (e, _) => print('Error: $e'),
);
```

### Session State Issues

```dart
// Inspect current session
final session = ref.read(chatSessionProvider);
print('Session ID: ${session?.id}');
print('Messages: ${session?.messages.length}');
```

### Enable Debug Logging

```dart
// In ChatService
debugPrint('[ChatService] Sending: $message');
debugPrint('[ChatService] Response: $event');
```

---

## Related Documentation

| Path | Description |
|------|-------------|
| `../CLAUDE.md` | Monorepo overview |
| `../base/claude.md` | Server API documentation |
| `../base/DESIGN.md` | Architectural decisions |
| `../daily/CLAUDE.md` | Daily app (for shared patterns) |

---

**Last Updated:** December 30, 2025
