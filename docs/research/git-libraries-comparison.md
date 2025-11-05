# Flutter Git Libraries Comparison

**Research Date**: November 5, 2025
**Purpose**: Evaluate Git libraries for Parachute's local-first sync strategy

---

## Final Recommendation: git2dart

**Choice**: Use `git2dart` for Parachute

### Reasoning

1. **Mobile is primary target** - git2dart is the only viable option for iOS/Android
2. **Performance matters** - Frequent Git operations (auto-commit after capture) need speed  
3. **Production ready** - Built on battle-tested libgit2
4. **Future-proof** - Full Git feature set for advanced scenarios
5. **Flutter integration** - Auto-bundling in release builds

### Accepted Trade-offs

1. **Native dependencies** - Worth it for performance and reliability
2. **Binary size** - 1-2MB is acceptable for core functionality
3. **Platform complexity** - One-time setup cost, well-documented

---

## Options Evaluated

### 1. git2dart (libgit2 Bindings) ⭐⭐⭐⭐⭐ RECOMMENDED

**Package**: `git2dart` v0.3.0
**Type**: Native libgit2 bindings via FFI

**Pros**:
- ✅ Native performance (C library bindings)
- ✅ Full Git functionality
- ✅ Auto-bundled in Flutter release builds
- ✅ Cross-platform (Windows, Linux, macOS, iOS, Android)
- ✅ Mature foundation (libgit2)

**Cons**:
- ❌ Native dependencies required
- ❌ Platform complexity
- ❌ ~1-2MB binary size

**Verdict**: Best choice for production mobile app

---

### 2. dart_git (Pure Dart) ⭐⭐ NOT RECOMMENDED

**Status**: Experimental, no pub.dev release

**Pros**:
- ✅ No native dependencies
- ✅ Pure Dart

**Cons**:
- ❌ Experimental/not production-ready
- ❌ Limited feature set
- ❌ Performance concerns
- ❌ Small community

**Verdict**: Too experimental for production

---

### 3. git (CLI Wrapper) ⭐ NOT SUITABLE

**Dealbreaker**: Requires Git CLI (not available on mobile)

**Verdict**: Desktop/server only, not viable for mobile app

---

## Implementation Timeline

- **Phase 1** (1-2 days): Setup and basic testing
- **Phase 2** (3-5 days): Core Git operations (clone, commit, push/pull)
- **Phase 3** (5-7 days): Integration with recording flow
- **Phase 4** (3-5 days): Testing and polish

**Total**: 12-19 days for full Git sync

---

**Decision**: Proceed with **git2dart**
