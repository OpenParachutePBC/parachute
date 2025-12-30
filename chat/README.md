# Parachute Chat

**AI assistant that knows your vault — chat with context.**

---

## What is Parachute Chat?

Chat is an AI-powered assistant that connects to your knowledge vault. It uses Claude to help you think, find connections, and work with your notes.

- **Context-aware**: AI has access to your vault content
- **Session continuity**: Conversations persist and resume
- **Tool use**: Claude can search, read, and modify files
- **Image generation**: Create images with local or cloud backends

---

## Quick Start

Chat requires the Base server to be running:

```bash
# Terminal 1: Start the server
cd ../base
npm install
VAULT_PATH=~/Parachute npm run dev

# Terminal 2: Run the Chat app
flutter pub get
flutter run -d macos
```

---

## Features

### AI Chat
- Streaming responses with real-time updates
- Session history with markdown storage
- Context injection from vault content
- Tool execution (search, read, write)

### Vault Integration
- Search across sessions and notes
- Personal context via `contexts/` files
- Custom agents via `.agents/` definitions
- System prompt override via `AGENTS.md`

### Image Generation
- **mflux**: Local FLUX models on Apple Silicon
- **nano-banana**: Google Gemini API

---

## Data Storage

Chat stores sessions in your vault:

```
~/Parachute/
├── Chat/
│   ├── sessions/           # Chat history (markdown)
│   └── contexts/           # Personal context files
├── assets/                 # Generated images
├── .agents/                # Custom agent definitions
└── AGENTS.md               # System prompt override
```

---

## Server Connection

Default: `http://localhost:3333`

Change in Settings → AI Chat → Server URL

---

## Platforms

| Platform | Status |
|----------|--------|
| macOS | ✅ Full support |
| Android | ✅ Full support |
| iOS | 🚧 Coming soon |

---

## Development

See [CLAUDE.md](CLAUDE.md) for development documentation.

```bash
flutter analyze      # Check for issues
flutter test         # Run tests
```

---

## Part of Parachute

Chat is part of the Parachute ecosystem:

- **[Parachute Daily](../daily/)** — Local voice journaling
- **[Parachute Chat](../chat/)** — AI assistant (this app)
- **[Parachute Base](../base/)** — Backend server for Chat

---

## License

AGPL — Open source, community-first.
