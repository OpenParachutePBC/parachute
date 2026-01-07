# Parachute

> "The mind is like a parachute, it doesn't work if it's not open" — Frank Zappa

**Open & interoperable extended mind technology — connected tools for connected thinking**

---

## What is Parachute?

Parachute is local-first, voice-first AI tooling that gives people agency over their digital minds. Technology that supports natural human cognition, not forces you into unnatural patterns.

**Core Principles:**
- **Local-First** — Your data stays on your devices; you control what goes to the cloud
- **Voice-First** — Capture thoughts naturally, away from the desk
- **Open & Interoperable** — Standard formats (markdown), works with Obsidian/Logseq
- **Prosocial** — You control what's captured and where it goes

---

## Components

| Component | Description | Repository |
|-----------|-------------|------------|
| **Daily** | Voice journaling (standalone, local-first) | [parachute-daily](https://github.com/OpenParachutePBC/parachute-daily) |
| **Chat** | AI assistant (requires Base server) | [parachute-chat](https://github.com/OpenParachutePBC/parachute-chat) |
| **Base** | Backend server (Python/FastAPI) | [parachute-base](https://github.com/OpenParachutePBC/parachute-base) |

---

## Quick Start

```bash
# Clone the repos you need
git clone https://github.com/OpenParachutePBC/parachute-daily.git
git clone https://github.com/OpenParachutePBC/parachute-chat.git
git clone https://github.com/OpenParachutePBC/parachute-base.git

# Run Daily (standalone, no server needed)
cd parachute-daily && flutter run -d macos

# Run Chat (requires Base server)
cd parachute-base && ./parachute.sh start
cd parachute-chat && flutter run -d macos
```

See each component repo's `AGENTS.md` for detailed setup and development guidance.

---

## Development

**All development is tracked in this repo:**
- [GitHub Issues](https://github.com/OpenParachutePBC/parachute/issues) — Bugs, features, and tasks
- [Project Board](https://github.com/orgs/OpenParachutePBC/projects) — Kanban view of work in progress

Issues are labeled by component (`daily`, `chat`, `base`) and priority (`P0`, `P1`, `P2`).

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              USER DEVICES                                    │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐             │
│  │ Parachute Daily │  │ Parachute Chat  │  │   Obsidian      │             │
│  │ (standalone)    │  │ (needs server)  │  │   (optional)    │             │
│  └────────┬────────┘  └────────┬────────┘  └────────┬────────┘             │
│           │                    │                    │                       │
│           │   Local Only       │                    │                       │
│           ▼                    ▼ (port 3333)        ▼                       │
└───────────┼────────────────────┼────────────────────┼───────────────────────┘
            │                    │                    │
            │    ┌───────────────┴───────────────┐    │
            │    │     PARACHUTE BASE SERVER     │    │
            │    │  FastAPI + Claude SDK         │    │
            │    │  Session Manager (SQLite)     │    │
            │    └───────────────┬───────────────┘    │
            │                    │                    │
            ▼                    ▼                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         KNOWLEDGE VAULT (local)                              │
│  ~/Parachute/                                                                │
│  ├── Daily/journals/    ← Voice journal entries (markdown)                  │
│  ├── Chat/              ← Chat sessions (SQLite + markdown)                 │
│  ├── assets/            ← Audio, images                                     │
│  └── AGENTS.md          ← Personal context                                  │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Company

**Open Parachute, PBC** — Colorado Public Benefit Corporation

Mission: Build prosocial AI tools that extend human cognition.

---

## License

**AGPL** — Ensures the tool remains by and for the community.
