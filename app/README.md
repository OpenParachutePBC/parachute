# Parachute

> "The mind is like a parachute, it doesn't work if it's not open" — Frank Zappa

**Open & interoperable extended mind technology — a connected tool for connected thinking**

---

## What is Parachute?

Parachute is a local-first, voice-first capture tool that gives people agency over their digital minds. We build AI tooling that supports natural human cognition, not forces you into unnatural patterns.

**We don't compete with your note system; we feed it.**

### Why Parachute?

The biggest uncaptured market in tech is becoming the tool people trust as their primary interface with all their information. Big tech is trying to be that tool—but they all share one fatal flaw: **they're trying to keep you trapped in their ecosystem**.

Parachute is different:

- **Open source** isn't just about flexibility—it's about deserving trust
- **Local-first** means your data stays on your devices; you control what goes to the cloud
- **Voice-first** because that's how humans actually think—naturally, away from the desk

**Key insight:** "The AI that knows you best wins. But people won't share their real context with tools they don't trust."

---

## Core Features

### Voice-First Capture

Capture thoughts wherever you have them—on a walk, at lunch, or at your desk:

- Auto-pause recording with silence detection (hands-free journaling)
- On-device transcription (Whisper models, no cloud required)
- AI-powered title generation (Gemma models)
- Omi pendant integration (Bluetooth capture device)

### Spheres

Organize your captures into themed knowledge containers:

- Each sphere has a `CLAUDE.md` system prompt for AI conversations
- Link captures to multiple spheres with different context
- Cross-pollination of ideas between spheres

### Git-Based Sync

Multi-device synchronization that respects your privacy:

- Auto-commit after save
- Periodic background sync to GitHub
- Works with private repositories
- Standard Git—no proprietary sync service

### Vault Compatibility

Works with your existing tools:

- Configurable vault location (default: `~/Parachute/`)
- Obsidian and Logseq compatible
- Standard markdown files
- No lock-in, portable data

---

## Technology

- **App:** Flutter (macOS, Android primary; iOS coming soon)
- **Backend:** [parachute-agent](https://github.com/OpenParachutePBC/parachute-agent) (Node.js, separate repo)
- **Transcription:** Whisper (on-device)
- **Title Generation:** Gemma (on-device)
- **Sync:** Git via git2dart (native libgit2)

---

## Quick Start

```bash
flutter pub get
flutter run -d macos  # or android, chrome
```

The app includes three main tabs:

- **Recorder** - Voice capture with real-time transcription
- **Spheres** - Organize and browse knowledge spheres
- **Files** - Browse your entire vault

---

## Current Status

**Active Development** - Stability Focus (Nov 24, 2025)

**Primary Platforms:** macOS and Android

### Recently Completed

- Auto-pause voice recording with VAD-based silence detection
- Git sync on macOS and Android
- Memory leak fixes and reliability improvements
- 116 unit tests for audio pipeline

### Coming Soon

- Sphere management with JSONL metadata
- Export integrations (to ChatGPT, Claude, etc.)
- iOS Git support

See [ROADMAP.md](ROADMAP.md) for detailed progress.

---

## Why Not [Competitor]?

### vs. Voice-First Hardware (Friend, Omi)

They're focused on always-on recording → **privacy nightmare**

Parachute: Local-first = you control what's captured and where it goes. **Prosocial, not surveillance.**

### vs. Note-Taking Tools (Obsidian, Notion)

Desktop-first → **not where thinking actually happens**

Parachute: Voice-first capture that exports to wherever you work. We don't compete; we feed your existing tools.

### vs. AI Assistants (ChatGPT, Claude)

Cloud-dependent → **no privacy, no offline use**

Parachute: Local-first with your actual context. Open source = you can leave anytime but won't want to.

---

## Competitive Comparison

| Feature               | Parachute | Claude Desktop | Voice Memos | Obsidian |
| --------------------- | --------- | -------------- | ----------- | -------- |
| Voice-First           | ✅        | ❌             | ✅          | ❌       |
| Local-First           | ✅        | ❌             | ✅          | ✅       |
| AI Transcription      | ✅        | ❌             | ❌          | ❌       |
| Git Sync              | ✅        | ❌             | ❌          | Plugin   |
| Obsidian Compatible   | ✅        | ❌             | ❌          | ✅       |
| Cross-Platform        | ✅        | Partial        | Apple only  | ✅       |
| Open Source           | ✅        | ❌             | ❌          | ❌       |

**Our position:** Free voice capture tool that exports to wherever you work. Build trust first; personalized AI later.

---

## Documentation

- **[Architecture](ARCHITECTURE.md)** - System design and technical decisions
- **[Roadmap](ROADMAP.md)** - Implementation progress and future plans
- **[Developer Guide](CLAUDE.md)** - Working with the codebase
- **[Recorder Docs](docs/recorder/)** - Voice recording and Omi integration

---

## Project Structure

```
parachute-app/
├── lib/              # Flutter source code
├── test/             # Unit tests
├── ios/              # iOS platform code
├── android/          # Android platform code
├── macos/            # macOS platform code
├── assets/           # Firmware and models
├── docs/             # Documentation
└── firmware/         # Omi device firmware source
```

## Related Repos

- **[parachute-agent](https://github.com/OpenParachutePBC/parachute-agent)** - AI agent backend (Node.js)

---

## Contributing

This is currently in early development. Once we reach stable MVP, we'll open up for contributions.

The vision: Small core team, rich community contribution ecosystem (Obsidian model).

---

## Company

**Parachute** is a Colorado Public Benefit Corporation—legally bound to mission, not just profit maximization.

Built by engineers who spent a decade frustrated with note-taking tools that never quite work. The combination of engineering rigor + deep study of how humans actually think is exactly what's needed to build tools that serve human cognition rather than extracting from it.

---

## License

AGPL - Ensures the tool remains by and for the community.

---

## Attribution

### Google Gemma

Gemma models for on-device title generation under [Gemma Terms of Use](https://ai.google.dev/gemma/terms).

### OpenAI Whisper

Whisper models for transcription under MIT License.

---

**Status:** Active Development - Last Updated: December 8, 2025
