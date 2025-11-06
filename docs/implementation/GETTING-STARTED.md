# Parachute - Getting Started

**Welcome to Parachute!** 🪂

This document will help you get oriented and start building.

**Last Updated:** October 20, 2025
**Status:** Foundation Phase Complete ✅

---

## What We've Built Today

### ✅ Complete Project Structure

```
parachute/
├── README.md                    # Project overview
├── ARCHITECTURE.md              # System design
├── GETTING-STARTED.md          # This file
├── docs/                        # Shared documentation
│   ├── BRANDING.md             # Brand identity
│   ├── LAUNCH-GUIDE.md         # Original comprehensive guide
│   ├── SETUP.md                # Environment setup
│   ├── DEVELOPMENT-WORKFLOW.md # Day-to-day workflow
│   └── ROADMAP.md              # Implementation phases
├── backend/                     # Go backend
│   ├── cmd/server/main.go      # Working server ✅
│   ├── CLAUDE.md               # Backend AI context
│   ├── README.md
│   ├── Makefile
│   ├── .env.example
│   ├── .gitignore
│   ├── go.mod
│   ├── internal/               # Source code structure
│   └── dev-docs/               # Backend documentation
│       ├── README.md
│       ├── ACP-INTEGRATION.md
│       ├── DATABASE.md
│       ├── WEBSOCKET-PROTOCOL.md
│       ├── TESTING.md
│       └── DEPLOYMENT.md
└── app/                         # Flutter frontend
    ├── lib/main.dart           # Working app ✅
    ├── CLAUDE.md               # Frontend AI context
    ├── README.md
    ├── pubspec.yaml            # Dependencies configured
    ├── .gitignore
    ├── lib/                    # Source code structure
    └── dev-docs/               # Frontend documentation (to be filled)
```

---

## What You Can Do Right Now

### 1. Explore the Documentation

**Start here:**
- Read [README.md](README.md) - Project overview
- Read [ARCHITECTURE.md](ARCHITECTURE.md) - System design
- Read [docs/ROADMAP.md](docs/ROADMAP.md) - See what's next

**For deeper understanding:**
- [docs/BRANDING.md](docs/BRANDING.md) - Brand philosophy and positioning
- [docs/LAUNCH-GUIDE.md](docs/LAUNCH-GUIDE.md) - Original comprehensive guide
- [backend/CLAUDE.md](backend/CLAUDE.md) - Backend development context
- [app/CLAUDE.md](app/CLAUDE.md) - Frontend development context

### 2. Set Up Your Environment

**Prerequisites to install:**
- Go 1.25+
- Flutter 3.24+
- Node.js 18+

**Follow the guide:**
- [docs/SETUP.md](docs/SETUP.md) - Complete setup instructions

### 3. Run the Backend (if Go is installed)

```bash
cd backend

# Install dependencies (once Go is installed)
go mod download

# Create data directories
mkdir -p data/spaces

# Copy environment template
cp .env.example .env
# Edit .env and add your Anthropic API key

# Run the server
go run cmd/server/main.go
```

**Test it:**
```bash
curl http://localhost:8080/health
# Should return: {"status":"ok","service":"parachute-backend","version":"0.1.0"}
```

### 4. Run the Frontend

```bash
cd app

# Get dependencies
flutter pub get

# Run on your preferred platform
flutter run                 # Choose device
flutter run -d chrome       # Web
flutter run -d macos        # macOS desktop
```

**You should see:**
A beautiful splash screen with "Parachute - Your open second brain"

---

## Next Steps (Priority Order)

### Immediate (Today/This Week)

1. **Install prerequisites** (if not already done)
   - Install Go: https://go.dev/doc/install
   - Install Flutter: https://docs.flutter.dev/get-started/install
   - Install Node.js: https://nodejs.org/

2. **Verify environment**
   ```bash
   go version              # Should show 1.25+
   flutter doctor          # Should show Flutter 3.24+
   node -v                 # Should show 18+
   npx @zed-industries/claude-code-acp --version  # Should work
   ```

3. **Test both applications**
   - Backend: `cd backend && go run cmd/server/main.go`
   - Frontend: `cd app && flutter run`

4. **Read the documentation**
   - Understand the architecture
   - Review the roadmap
   - Familiarize yourself with the tech stack

### Phase 2: ACP Integration (Next 1-2 Weeks)

**Goal:** Backend can communicate with Claude AI via ACP

**Tasks:**
- Implement ACP client (`backend/internal/acp/`)
- Spawn and manage claude-code-acp subprocess
- JSON-RPC 2.0 communication
- Handle initialize, new_session, session/prompt
- Process session/update notifications (streaming)

**Resources:**
- [backend/dev-docs/ACP-INTEGRATION.md](backend/dev-docs/ACP-INTEGRATION.md)
- ACP Spec: https://agentclientprotocol.com/
- Reference Rust code: `~/Symbols/Codes/para-claude-v2/src-tauri/src/acp_v2/`

### Phase 3: Core Features (Next 2-3 Weeks)

**Goal:** Basic Space management and chat functionality

**Backend:**
- SQLite database setup
- Space CRUD API
- Conversation & message handling
- WebSocket endpoint

**Frontend:**
- Space list screen
- Create Space form
- Chat screen UI
- API service (Dio)
- Navigation (go_router)

**Resources:**
- [backend/dev-docs/DATABASE.md](backend/dev-docs/DATABASE.md)
- [backend/dev-docs/WEBSOCKET-PROTOCOL.md](backend/dev-docs/WEBSOCKET-PROTOCOL.md)

### Phase 4: Streaming & Tools (Next 2-3 Weeks)

**Goal:** Full chat experience with streaming and tool execution

- Streaming message display
- Tool call UI
- Permission dialogs
- End-to-end message flow

---

## Development Workflow

### Daily Development

**Terminal 1 - Backend:**
```bash
cd backend
go run cmd/server/main.go
# Or with hot reload: air
```

**Terminal 2 - Frontend:**
```bash
cd app
flutter run
# Press 'r' for hot reload, 'R' for hot restart
```

**Terminal 3 - Commands:**
```bash
# Run tests, make changes, etc.
```

### Making Changes

**Backend:**
- Edit Go files in `internal/`
- Follow domain-driven design
- Write tests as you go
- Update `backend/CLAUDE.md` for major changes

**Frontend:**
- Edit Dart files in `lib/`
- Use feature-first organization
- Hot reload for quick iteration
- Update `app/CLAUDE.md` for major changes

### Git Workflow

```bash
# Create feature branch
git checkout -b feature/acp-integration

# Make changes, commit frequently
git add .
git commit -m "feat: implement ACP client initialization"

# Push and create PR
git push origin feature/acp-integration
```

**Commit conventions:**
- `feat:` - New feature
- `fix:` - Bug fix
- `docs:` - Documentation only
- `refactor:` - Code refactoring
- `test:` - Adding tests
- `chore:` - Maintenance

---

## Key Documentation Files

### For AI Assistants (Claude, Cursor, etc.)

When working with AI coding assistants, share these files for context:

**Backend work:**
- `backend/CLAUDE.md` - Complete backend context
- `backend/dev-docs/[relevant-doc].md` - Specific subsystem docs
- `ARCHITECTURE.md` - Overall system design

**Frontend work:**
- `app/CLAUDE.md` - Complete frontend context
- `ARCHITECTURE.md` - Overall system design

**General:**
- `docs/DEVELOPMENT-WORKFLOW.md` - How we work
- `docs/ROADMAP.md` - What we're building

### For Humans

**Getting oriented:**
1. `README.md` - Start here
2. `ARCHITECTURE.md` - Understand the system
3. `docs/ROADMAP.md` - See the plan

**Setting up:**
1. `docs/SETUP.md` - Install everything
2. `docs/DEVELOPMENT-WORKFLOW.md` - Learn the workflow

**Building features:**
1. Check `docs/ROADMAP.md` for priority
2. Read relevant `dev-docs/` for subsystem details
3. Update documentation as you go

---

## Troubleshooting

### Backend Won't Start

**Problem:** `go: command not found`
**Solution:** Install Go: https://go.dev/doc/install

**Problem:** Port 8080 already in use
**Solution:** `lsof -i :8080` to find process, kill it or change port in `.env`

**Problem:** Module errors
**Solution:** `cd backend && go mod tidy`

### Frontend Won't Build

**Problem:** `flutter: command not found`
**Solution:** Install Flutter: https://docs.flutter.dev/get-started/install

**Problem:** Dependencies not found
**Solution:** `cd app && flutter pub get`

**Problem:** Build errors after adding dependencies
**Solution:**
```bash
cd app
flutter clean
flutter pub get
flutter run
```

### Environment Issues

**Check everything:**
```bash
go version              # Go 1.25+
flutter doctor          # Flutter 3.24+
node -v                 # Node 18+
npx @zed-industries/claude-code-acp --version
```

See [docs/SETUP.md](docs/SETUP.md) for detailed troubleshooting.

---

## What Makes Parachute Special

### The Four Opens

1. **Open Protocols** - Built on ACP & MCP (not proprietary)
2. **Open Data** - Your files, your control, standard formats
3. **Open Platforms** - iOS, Android, Web, Desktop
4. **Open Integration** - Connect to anything via MCP

### Our Differentiator

| Feature | Parachute | Claude Desktop | Claude Code |
|---------|-----------|---------------|-------------|
| Mobile Access | ✅ | ❌ | ❌ |
| File Access | ✅ | ❌ | ✅ |
| MCP Servers | ✅ | ❌ | ✅ |
| Spaces/Context | ✅ | ❌ | ⚠️ |
| Open Protocol | ✅ | ❌ | ✅ |

**We're the only open, cross-platform second brain for Claude AI.**

---

## Success Criteria for MVP

### Backend
- [ ] Go server runs and serves REST API
- [ ] ACP integration works (spawn, send/receive)
- [ ] WebSocket streaming works
- [ ] SQLite persists data
- [ ] Spaces CRUD complete

### Frontend
- [ ] Flutter app runs on iOS, Android, Web
- [ ] Space list and creation work
- [ ] Chat screen functional
- [ ] Streaming messages display
- [ ] Tool calls shown with UI

### Integration
- [ ] End-to-end: Send message → Get response
- [ ] Conversations persist across restarts
- [ ] File operations work
- [ ] MCP configs can be loaded

**Timeline:** 12-16 weeks (realistic, AI-assisted, part-time)

See [docs/ROADMAP.md](docs/ROADMAP.md) for detailed phases.

---

## Resources

### Technology
- **Go:** https://go.dev/doc/
- **Flutter:** https://docs.flutter.dev/
- **ACP Spec:** https://agentclientprotocol.com/
- **MCP Spec:** https://modelcontextprotocol.io/
- **Fiber (Go):** https://docs.gofiber.io/
- **Riverpod:** https://riverpod.dev/

### Reference Code
- **Current Rust version:** `~/Symbols/Codes/para-claude-v2/`
- **Zed's implementation:** `~/Symbols/Codes/zed/`

### Community
- Create issues in GitHub
- Document learnings in dev-docs
- Update CLAUDE.md files as you go

---

## Questions?

**Setup issues?**
→ See [docs/SETUP.md](docs/SETUP.md)

**How does X work?**
→ Check [ARCHITECTURE.md](ARCHITECTURE.md) or relevant dev-docs

**What to build next?**
→ See [docs/ROADMAP.md](docs/ROADMAP.md)

**Daily workflow?**
→ See [docs/DEVELOPMENT-WORKFLOW.md](docs/DEVELOPMENT-WORKFLOW.md)

**Backend context?**
→ See [backend/CLAUDE.md](backend/CLAUDE.md)

**Frontend context?**
→ See [app/CLAUDE.md](app/CLAUDE.md)

---

## Celebrate! 🎉

**You've completed the Foundation Phase!**

✅ Project structure created
✅ Documentation complete
✅ Backend skeleton working
✅ Frontend skeleton working
✅ Development workflow established

**Next up:** Phase 2 - ACP Integration

---

**Ready to start building?**

1. Install prerequisites (Go, Flutter, Node.js)
2. Read [backend/dev-docs/ACP-INTEGRATION.md](backend/dev-docs/ACP-INTEGRATION.md)
3. Start implementing the ACP client
4. Update documentation as you learn

**Good luck, and enjoy the journey!** 🚀

---

**Last Updated:** October 20, 2025
**Current Phase:** 1 - Foundation (Complete ✅)
**Next Phase:** 2 - ACP Integration
