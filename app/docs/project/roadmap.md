# Parachute - Implementation Roadmap

**Last Updated:** October 20, 2025
**Status:** Foundation Phase

---

## Overview

This roadmap breaks down Parachute development into phases, with clear milestones and success criteria.

---

## Phase 1: Foundation (Weeks 1-2)

**Goal:** Solid project structure, working skeleton applications, complete documentation

### Tasks

- [x] Create project structure (monorepo)
- [x] Create core documentation
  - [x] README.md
  - [x] ARCHITECTURE.md
  - [x] SETUP.md
  - [x] DEVELOPMENT-WORKFLOW.md
  - [x] ROADMAP.md
- [ ] Initialize backend Go project
  - [ ] Create directory structure
  - [ ] Create CLAUDE.md
  - [ ] Create minimal main.go
  - [ ] Create .env.example
  - [ ] Create Makefile
  - [ ] Create dev-docs structure
- [ ] Initialize frontend Flutter project
  - [ ] Run flutter create
  - [ ] Create directory structure
  - [ ] Create CLAUDE.md
  - [ ] Create minimal app
  - [ ] Add dependencies to pubspec.yaml
  - [ ] Create dev-docs structure
- [ ] Verify environment
  - [ ] Go, Flutter, Node.js all installed
  - [ ] Backend runs and responds to health check
  - [ ] Frontend runs on iOS/Android/Web
  - [ ] Both can communicate (ping endpoint)

### Success Criteria

- ✅ Documentation complete and clear
- ✅ Backend server starts and responds to /health
- ✅ Flutter app launches on at least one platform
- ✅ Simple HTTP request from Flutter → Backend works
- ✅ All team members can set up environment

### Deliverables

- Working backend skeleton (Go + Fiber)
- Working frontend skeleton (Flutter + Riverpod)
- Complete documentation structure
- Development workflow established

---

## Phase 2: ACP Integration (Weeks 3-4)

**Goal:** Backend can communicate with Claude via ACP

### Tasks

- [ ] Backend: ACP client implementation
  - [ ] Spawn claude-code-acp subprocess
  - [ ] JSON-RPC 2.0 communication (stdin/stdout)
  - [ ] Implement `initialize` method
  - [ ] Implement `new_session` method
  - [ ] Implement `session/prompt` method
  - [ ] Handle `session/update` notifications
- [ ] Backend: Process management
  - [ ] Lifecycle: start, stop, restart
  - [ ] Error handling and recovery
  - [ ] Graceful shutdown
- [ ] Backend: Basic testing
  - [ ] Unit tests for JSON-RPC client
  - [ ] Integration test: send prompt, get response
  - [ ] Test error scenarios
- [ ] Documentation
  - [ ] Complete `backend/dev-docs/ACP-INTEGRATION.md`
  - [ ] Document learnings in CLAUDE.md
  - [ ] Create examples

### Success Criteria

- ✅ Backend can spawn claude-code-acp
- ✅ Backend can send prompts and receive responses
- ✅ Streaming works (session/update notifications)
- ✅ Error handling works (invalid API key, network issues)
- ✅ Tests pass

### Deliverables

- Working ACP client in Go
- Integration tests proving ACP communication
- Complete ACP integration documentation

---

## Phase 3: Core Features (Weeks 5-7)

**Goal:** Basic Space management and chat functionality

### Tasks

- [ ] Backend: Database setup
  - [ ] SQLite integration
  - [ ] Migrations system
  - [ ] Create schema (spaces, conversations, messages, sessions)
  - [ ] Repository layer
- [ ] Backend: Space management
  - [ ] Create Space API endpoints
  - [ ] CRUD operations
  - [ ] CLAUDE.md file management
  - [ ] .mcp.json loading (basic)
- [ ] Backend: Conversation & Message handling
  - [ ] Create Conversation API endpoints
  - [ ] Message persistence
  - [ ] Conversation history retrieval
- [ ] Backend: WebSocket setup
  - [ ] WebSocket endpoint
  - [ ] Connection management
  - [ ] Basic event broadcasting
- [ ] Frontend: State management setup
  - [ ] Riverpod providers structure
  - [ ] API service (Dio)
  - [ ] Error handling
- [ ] Frontend: Space management UI
  - [ ] Space list screen
  - [ ] Create Space form
  - [ ] Switch between Spaces
  - [ ] Delete/edit Space
- [ ] Frontend: Chat UI skeleton
  - [ ] Chat screen layout
  - [ ] Message list
  - [ ] Input field
  - [ ] Send button
- [ ] Integration
  - [ ] Flutter can list Spaces
  - [ ] Flutter can create Space
  - [ ] Flutter can switch Spaces

### Success Criteria

- ✅ User can create a Space (name + directory path)
- ✅ User can see list of Spaces
- ✅ User can switch between Spaces
- ✅ Database persists all data
- ✅ Backend APIs work and are tested
- ✅ Flutter UI is responsive and looks good
- ✅ Basic navigation works

### Deliverables

- Space management (backend + frontend)
- Database with migrations
- Chat UI skeleton
- Working navigation

---

## Phase 4: Streaming & Tool Execution (Weeks 8-10)

**Goal:** Full chat experience with streaming messages and tool execution

### Tasks

- [ ] Backend: Streaming implementation
  - [ ] Process session/update events from ACP
  - [ ] Emit WebSocket events to Flutter
  - [ ] Event types: message_chunk, tool_call, permission_request, message_complete
- [ ] Backend: Tool execution flow
  - [ ] Detect tool calls in ACP responses
  - [ ] Emit tool call events to Flutter
  - [ ] Receive permission responses from Flutter
  - [ ] Send permission responses to ACP
  - [ ] Handle auto-approval for safe operations
- [ ] Frontend: WebSocket service
  - [ ] Connect to backend WebSocket
  - [ ] Event stream handling
  - [ ] Automatic reconnection
  - [ ] Error handling
- [ ] Frontend: Streaming messages
  - [ ] Display streaming text chunks
  - [ ] Smooth animations
  - [ ] Handle message completion
- [ ] Frontend: Tool call UI
  - [ ] Tool call cards (show tool name, status)
  - [ ] Permission dialogs
  - [ ] Approve/deny buttons
  - [ ] Show tool results
- [ ] Frontend: Message bubbles
  - [ ] User message bubbles
  - [ ] Assistant message bubbles
  - [ ] Markdown rendering
  - [ ] Code blocks with syntax highlighting
- [ ] Integration: Full chat flow
  - [ ] User sends message
  - [ ] Backend processes via ACP
  - [ ] Flutter receives streaming response
  - [ ] Tool calls work end-to-end
  - [ ] Conversation persists

### Success Criteria

- ✅ User can send message and see streaming response
- ✅ Messages display correctly (user + assistant)
- ✅ Tool calls shown with proper UI
- ✅ User can approve/deny permissions
- ✅ Tool execution completes and shows results
- ✅ Conversations persist and can be restored
- ✅ Markdown renders correctly
- ✅ UI feels smooth and responsive

### Deliverables

- Complete chat experience
- Streaming message display
- Tool execution flow
- Permission handling system

---

## Phase 5: Context & Persistence (Weeks 11-12)

**Goal:** Context restoration, CLAUDE.md integration, app restart handling

### Tasks

- [ ] Backend: Context restoration
  - [ ] On app restart, load conversation history
  - [ ] Include history in first prompt after restart
  - [ ] Session management (active/inactive)
- [ ] Backend: CLAUDE.md integration
  - [ ] Read CLAUDE.md file from Space directory
  - [ ] Include in every prompt's context
  - [ ] Handle missing CLAUDE.md (use default)
  - [ ] Watch for CLAUDE.md changes (optional)
- [ ] Backend: MCP configuration
  - [ ] Read .mcp.json from Space directory
  - [ ] Parse MCP server configs
  - [ ] Pass to ACP (if supported)
  - [ ] Document MCP setup process
- [ ] Frontend: Conversation list
  - [ ] List conversations in current Space
  - [ ] Switch between conversations
  - [ ] New conversation button
  - [ ] Delete conversation
  - [ ] Rename conversation
- [ ] Frontend: Settings screen
  - [ ] API key management
  - [ ] App preferences (theme, etc.)
  - [ ] About screen
  - [ ] Links to docs
- [ ] Testing: End-to-end flows
  - [ ] Create Space → Chat → Restart app → Continue chat
  - [ ] CLAUDE.md affects behavior
  - [ ] Multiple conversations in one Space
  - [ ] File operations work (Claude can read/write)

### Success Criteria

- ✅ Conversations restore correctly after app restart
- ✅ CLAUDE.md content is used in prompts
- ✅ User can manage multiple conversations per Space
- ✅ Settings screen works
- ✅ File operations work (read, write, edit)
- ✅ App handles errors gracefully
- ✅ All major flows tested end-to-end

### Deliverables

- Context restoration system
- CLAUDE.md integration
- Conversation management UI
- Settings screen
- End-to-end tests

---

## Phase 6: Polish & Testing (Weeks 13-14)

**Goal:** Bug fixes, polish, performance, prepare for MVP release

### Tasks

- [ ] Backend: Performance optimization
  - [ ] Profile and optimize hot paths
  - [ ] Database query optimization
  - [ ] WebSocket connection limits
  - [ ] Memory leak checks
- [ ] Backend: Error handling
  - [ ] Comprehensive error messages
  - [ ] Logging strategy
  - [ ] Graceful degradation
- [ ] Frontend: UI polish
  - [ ] Animations and transitions
  - [ ] Loading states
  - [ ] Empty states
  - [ ] Error states
  - [ ] Responsive design (phone, tablet, desktop)
- [ ] Frontend: Dark mode
  - [ ] Dark theme
  - [ ] Theme switcher
  - [ ] Persist preference
- [ ] Mobile-specific features
  - [ ] iOS: Proper safe area handling
  - [ ] iOS: Native feel (Cupertino widgets where appropriate)
  - [ ] Android: Material Design 3
  - [ ] Android: Back button handling
  - [ ] Keyboard handling
  - [ ] Focus management
- [ ] Testing
  - [ ] Backend: Unit test coverage >70%
  - [ ] Frontend: Widget test coverage >60%
  - [ ] Integration tests for all major flows
  - [ ] Manual testing on iOS and Android
- [ ] Documentation
  - [ ] User guide
  - [ ] API documentation
  - [ ] Deployment guide
  - [ ] Troubleshooting guide

### Success Criteria

- ✅ App feels fast and responsive
- ✅ UI looks polished on iOS and Android
- ✅ Dark mode works everywhere
- ✅ No critical bugs
- ✅ Test coverage meets targets
- ✅ Documentation complete
- ✅ Ready for beta users

### Deliverables

- Polished, tested MVP
- Complete user documentation
- Deployment-ready builds

---

## Phase 7: MVP Release (Week 15)

**Goal:** Deploy and share with first users

### Tasks

- [ ] Deployment
  - [ ] Set up production backend (Render, Mac Mini, or Fly.io)
  - [ ] Configure environment variables
  - [ ] Set up monitoring/logging
- [ ] Mobile builds
  - [ ] iOS: TestFlight setup
  - [ ] Android: Build APK/AAB
  - [ ] Test on real devices
- [ ] Documentation
  - [ ] Update README with real URLs
  - [ ] Create user onboarding guide
  - [ ] FAQ
  - [ ] Known issues
- [ ] Launch
  - [ ] Invite first beta users
  - [ ] Monitor for issues
  - [ ] Gather feedback
  - [ ] Iterate

### Success Criteria

- ✅ Backend deployed and stable
- ✅ iOS app on TestFlight
- ✅ Android app available (APK or Play Store beta)
- ✅ 5-10 active beta users
- ✅ No critical bugs in production
- ✅ Positive initial feedback

### Deliverables

- Live backend service
- iOS app on TestFlight
- Android app (APK or Play Store)
- Beta user program started

---

## Future Phases (Post-MVP)

### Phase 8: Enhanced Features (Weeks 16-20)

- MCP server UI management
- Advanced context strategies (summarization)
- Search within conversations
- Export conversations
- Keyboard shortcuts
- Command palette

### Phase 9: Cloud Sync (Weeks 21-28)

- User accounts and authentication
- Cloud database
- End-to-end encryption
- Multi-device sync
- Conflict resolution
- Backup and restore

### Phase 10: Team Features (Weeks 29-36)

- Shared Spaces
- Team member management
- Role-based permissions
- Team activity feed
- Collaborative editing

---

## Risk Management

### High Risk Items

**Risk:** ACP integration more complex than expected
**Mitigation:** Reference Zed and current Rust implementation, allocate extra time for Phase 2

**Risk:** Mobile performance issues
**Mitigation:** Profile early, optimize during Phase 6, consider pagination

**Risk:** Context window limits
**Mitigation:** Implement summarization strategy, allow user to clear history

**Risk:** WebSocket connection stability on mobile
**Mitigation:** Implement automatic reconnection, offline queue

### Dependencies

**External:**
- claude-code-acp availability and stability
- Anthropic API availability
- Flutter stability on all platforms

**Internal:**
- Team member availability
- Development environment setup
- Learning curve for new technologies

---

## Timeline Estimates

### Optimistic (AI-assisted, full-time, experienced)
- **Phases 1-6:** 10-12 weeks
- **Phase 7 (MVP):** Week 13
- **Total:** ~3 months

### Realistic (AI-assisted, part-time, learning)
- **Phases 1-6:** 16-20 weeks
- **Phase 7 (MVP):** Week 21
- **Total:** ~5 months

### Conservative (part-time, lots of learning)
- **Phases 1-6:** 24-28 weeks
- **Phase 7 (MVP):** Week 29
- **Total:** ~7 months

---

## Progress Tracking

### Current Phase: 1 - Foundation

**Completed:**
- [x] Project structure created
- [x] Core documentation complete
- [ ] Backend skeleton initialized
- [ ] Frontend skeleton initialized
- [ ] Environment verified

**Next Up:**
- Initialize backend Go project
- Initialize Flutter project
- Test both applications
- Move to Phase 2 (ACP Integration)

---

## Definition of Done

**For Each Phase:**
- [ ] All tasks complete
- [ ] Tests passing
- [ ] Documentation updated
- [ ] Code reviewed
- [ ] Demo-able feature

**For MVP (Phase 7):**
- [ ] All Phase 1-6 deliverables complete
- [ ] Deployed and accessible
- [ ] Beta users can use it
- [ ] No critical bugs
- [ ] Documentation for users

---

## Notes

- This roadmap is a living document - update as we learn
- Timeline estimates are guidelines, not deadlines
- Quality over speed - better to take extra time than ship buggy MVP
- Celebrate milestones!

---

**Last Updated:** October 20, 2025
**Current Phase:** 1 - Foundation
**Next Milestone:** Backend and Frontend skeletons complete
