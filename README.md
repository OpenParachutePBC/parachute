# Parachute

> "The mind is like a parachute, it doesn't work if it's not open" — Frank Zappa

**Open & interoperable extended mind technology — a connected tool for connected thinking**

---

## What is Parachute?

Parachute is a local-first, voice-first AI tool that gives people agency over their digital minds. We build technology that supports natural human cognition, not forces you into unnatural patterns.

**We don't compete with your note system; we feed it.**

### Why Parachute?

The biggest uncaptured market in tech is becoming the tool people trust as their primary interface with all their information. Big tech is trying to be that tool—but they all share one fatal flaw: **they're trying to keep you trapped in their ecosystem**.

Parachute is different:

- **Open source** isn't just about flexibility—it's about deserving trust
- **Local-first** means your data stays on your devices; you control what goes to the cloud
- **Voice-first** because that's how humans actually think—naturally, away from the desk

**Key insight:** "The AI that knows you best wins. But people won't share their real context with tools they don't trust."

---

## Monorepo Structure

```
parachute/
├── app/                      # Flutter mobile/desktop app
│   ├── lib/                  # Dart source code
│   ├── firmware/             # Omi device firmware
│   └── README.md             # App documentation
│
├── agent/                    # Node.js AI backend
│   ├── lib/                  # JavaScript source
│   ├── server.js             # Express API server
│   └── README.md             # Agent documentation
│
└── README.md                 # You are here
```

| Component | Description |
|-----------|-------------|
| **[app/](app/)** | Flutter app for voice capture, chat, and vault browsing (macOS, Android, iOS) |
| **[agent/](agent/)** | AI agent backend using Claude SDK, sessions stored as markdown |

---

## Quick Start

### Prerequisites

- [Flutter](https://flutter.dev/docs/get-started/install) (for the app)
- [Node.js](https://nodejs.org/) 18+ (for the agent)
- [Claude Code](https://claude.com/code) CLI (for AI authentication)

### 1. Set up authentication

```bash
npm install -g @anthropic-ai/claude-code
claude login
```

### 2. Start the agent

```bash
cd agent
npm install
VAULT_PATH=~/Parachute npm run dev
```

### 3. Run the app

```bash
cd app
flutter pub get
flutter run -d macos  # or android, chrome
```

The app connects to `http://localhost:3333` by default. Change this in Settings → AI Chat → Server URL.

---

## Core Features

### Voice-First Capture

Capture thoughts wherever you have them—on a walk, at lunch, or at your desk:

- Auto-pause recording with silence detection (hands-free journaling)
- On-device transcription (Whisper models, no cloud required)
- AI-powered title generation (Gemma models)
- Omi pendant integration (Bluetooth capture device)

### AI Chat with Your Vault

Chat with AI agents that have full context of your knowledge:

- Agents defined in markdown files with YAML frontmatter
- Sessions persisted as human-readable markdown
- SDK session resumption for long-running conversations
- Import your Claude/ChatGPT history

### Vault Compatibility

Works with your existing tools:

- Configurable vault location (default: `~/Parachute/`)
- Obsidian and Logseq compatible
- Standard markdown files
- Git-based sync to private repos

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              USER DEVICES                                    │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐             │
│  │  iPhone/Android │  │  macOS/Windows  │  │   Obsidian      │             │
│  │  (Flutter App)  │  │  (Flutter App)  │  │   (Plugin)      │             │
│  └────────┬────────┘  └────────┬────────┘  └────────┬────────┘             │
│           └────────────────────┼────────────────────┘                       │
│                                ▼                                            │
│                    ┌───────────────────────┐                                │
│                    │    HTTP/SSE Client    │                                │
└────────────────────┴───────────┬───────────┴────────────────────────────────┘
                                 │
                                 ▼ (port 3333)
┌────────────────────────────────────────────────────────────────────────────┐
│                         AGENT SERVER                                        │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │                     Express Server (server.js)                        │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐               │  │
│  │  │ /api/chat/*  │  │ /api/agents  │  │ /api/captures│               │  │
│  │  └──────┬───────┘  └──────────────┘  └──────────────┘               │  │
│  │         ▼                                                            │  │
│  │  ┌──────────────┐      ┌──────────────┐      ┌──────────────┐      │  │
│  │  │ Orchestrator │──────│ Claude SDK   │      │ Session Mgr  │      │  │
│  │  └──────────────┘      └──────────────┘      │ (markdown)   │      │  │
│  └──────────────────────────────────────────────┴──────────────┴───────┘  │
└────────────────────────────────────────────────────────────────────────────┘
                                     │
                                     ▼
                    ┌───────────────────────────┐
                    │   Knowledge Vault (local) │
                    │                           │
                    │  ~/Parachute/             │
                    │  ├── agent-sessions/      │  ← Chat history
                    │  ├── captures/            │  ← Voice recordings
                    │  ├── .agents/             │  ← Agent definitions
                    │  └── AGENTS.md            │  ← Personal context
                    │                           │
                    │  (synced via Git/Syncthing)│
                    └───────────────────────────┘
```

---

## Documentation

| Document | Description |
|----------|-------------|
| [app/README.md](app/README.md) | Flutter app features, platforms, roadmap |
| [agent/README.md](agent/README.md) | Agent API, configuration, authentication |
| [CLAUDE.md](CLAUDE.md) | Developer guide for AI assistants |
| [app/CLAUDE.md](app/CLAUDE.md) | Flutter development patterns |
| [agent/claude.md](agent/claude.md) | Agent backend internals |

---

## Current Status

**Active Development** — December 2025

### Recent

- Chat import from Claude/ChatGPT exports
- Session continuation with prior message loading
- Vault initialization onboarding flow
- Personal context via AGENTS.md

### Primary Platforms

- **macOS** — Full feature support
- **Android** — Full feature support
- **iOS** — Coming soon

---

## Competitive Comparison

| Feature               | Parachute | Claude Desktop | Voice Memos | Obsidian |
| --------------------- | --------- | -------------- | ----------- | -------- |
| Voice-First           | Yes | No             | Yes          | No       |
| Local-First           | Yes | No             | Yes          | Yes       |
| AI Transcription      | Yes | No             | No          | No       |
| AI Chat with Context  | Yes | Partial        | No          | Plugin   |
| Git Sync              | Yes | No             | No          | Plugin   |
| Obsidian Compatible   | Yes | No             | No          | Yes       |
| Open Source           | Yes | No             | No          | No       |

---

## Contributing

This is currently in early development. Once we reach stable MVP, we'll open up for contributions.

The vision: Small core team, rich community contribution ecosystem (Obsidian model).

---

## Company

**Parachute** is a Colorado Public Benefit Corporation—legally bound to mission, not just profit maximization.

---

## License

**AGPL** — Ensures the tool remains by and for the community.

---

## Attribution

### Google Gemma
Gemma models for on-device title generation under [Gemma Terms of Use](https://ai.google.dev/gemma/terms).

### OpenAI Whisper
Whisper models for transcription under MIT License.

---

**Last Updated:** December 22, 2025
