# Git-Friendly Storage Alternatives to SQLite

**Research Date**: November 13, 2025
**Context**: Parachute's Space Knowledge Links currently use SQLite (`space.sqlite`) which doesn't diff/merge well in Git

---

## The Problem

**Current Implementation:**
- Each space has a `space.sqlite` database
- Links captures to spaces with context/tags
- Syncs via Git

**Issue:**
- SQLite is binary format
- Git can't show meaningful diffs
- Merge conflicts are opaque ("binary file changed")
- No automatic conflict resolution
- Manual merge requires exporting, diffing, re-importing

---

## Alternatives Researched

### 1. **CRDT-Enhanced SQLite** ⭐

#### cr-sqlite (vlcn.io)
**What it is:** SQLite extension adding CRDT (Conflict-free Replicated Data Types) support

**How it works:**
- Adds metadata tables and triggers to your schema
- Automatic conflict resolution via CRDT rules
- Multi-writer, partition tolerant
- Merges happen between arbitrary number of peers
- Eventually consistent convergence guaranteed

**CRDT Types Supported:**
- Last-write-wins (LWW)
- Counters
- Fractional indexes
- Multi-value registers (planned)
- RGA (planned)

**Pros:**
- ✅ Keep using SQLite (familiar, battle-tested)
- ✅ Automatic conflict resolution (no user intervention)
- ✅ Multi-device sync without coordination
- ✅ Mathematically guaranteed convergence
- ✅ Works with existing schemas (just adds metadata)

**Cons:**
- ❌ Still binary (Git diffs still opaque)
- ❌ 2.5x slower inserts than vanilla SQLite
- ❌ Increased storage (CRDT metadata)
- ❌ Learning curve for CRDT concepts
- ❌ No official Dart/Flutter bindings (FFI required)

**Best For:**
- Apps needing multi-writer without coordination
- Scenarios where conflicts are common
- When Git diff visibility is less important than automatic merging

**Git Compatibility:** ⚠️ Improved (handles conflicts) but still binary

---

### 2. **JSON Lines (JSONL/NDJSON)** ⭐⭐

#### What it is
Line-delimited JSON where each line is a complete JSON object

**How it works:**
```jsonl
{"id":"uuid1","capture_id":"cap1","context":"farming notes","tags":["rotation"]}
{"id":"uuid2","capture_id":"cap2","context":"business ideas","tags":["revenue"]}
{"id":"uuid3","capture_id":"cap3","context":"research","tags":["analysis","data"]}
```

**Schema for Parachute:**
```jsonl
# space_links.jsonl (one file per space)
{"id":"..","capture_id":"..","note_path":"..","linked_at":...,"context":"..","tags":[..],"metadata":{..}}
```

**Pros:**
- ✅ **Perfect Git diffs** - line-by-line changes visible
- ✅ **Easy merges** - each line independent
- ✅ **Human readable** - can inspect/edit manually
- ✅ **Append-only** - fast inserts, no file rewrite
- ✅ **Simple** - no external dependencies
- ✅ **Interoperable** - works with any tool
- ✅ **Easy backups** - just text files

**Cons:**
- ❌ No indexes (must scan entire file)
- ❌ Slower queries than SQLite
- ❌ No SQL querying
- ❌ Updates/deletes require rewrite
- ❌ Manual conflict resolution still needed
- ❌ Larger file sizes than binary

**Implementation:**
```dart
// Simple Dart implementation
class JsonLinesStorage {
  Future<void> addLink(LinkedCapture capture) async {
    final file = File(spacePath + '/space_links.jsonl');
    await file.writeAsString(
      jsonEncode(capture.toMap()) + '\n',
      mode: FileMode.append,
    );
  }

  Future<List<LinkedCapture>> getLinks() async {
    final file = File(spacePath + '/space_links.jsonl');
    final lines = await file.readAsLines();
    return lines
        .where((l) => l.isNotEmpty)
        .map((l) => LinkedCapture.fromJson(jsonDecode(l)))
        .toList();
  }
}
```

**Best For:**
- Simple data models (like our links)
- Append-heavy workloads
- When Git visibility is critical
- Small-medium datasets (< 100k records)

**Git Compatibility:** ✅ Excellent (text-based, line-by-line diffs)

---

### 3. **Automerge** ⭐

#### What it is
JSON-like CRDT data structure for collaborative editing

**How it works:**
- Documents stored as CRDT
- Automatic conflict resolution
- Op-based sync (only sends changes)
- Built for real-time collaboration

**Pros:**
- ✅ Automatic conflict resolution (CRDT)
- ✅ Rich data types (maps, lists, text)
- ✅ Efficient sync protocol
- ✅ Mature project (v3.0 in 2024)
- ✅ JavaScript + Rust + C bindings

**Cons:**
- ❌ No native Dart support (FFI required)
- ❌ JSON-only (not relational)
- ❌ Still binary storage format
- ❌ Complex API for simple use cases
- ❌ Overkill for our use case

**Best For:**
- Real-time collaborative apps (Google Docs style)
- Complex nested documents
- When you need CRDT + rich data types

**Git Compatibility:** ⚠️ Binary (similar to SQLite)

---

### 4. **ElectricSQL** ⭐

#### What it is
Active-active sync between PostgreSQL and SQLite

**How it works:**
- Sync layer in front of Postgres
- Bidirectional replication to SQLite
- Uses "shapes" for partial replication
- CRDT-based conflict resolution

**Pros:**
- ✅ Best of both worlds (Postgres + SQLite)
- ✅ Automatic sync
- ✅ Powerful Postgres on server
- ✅ Fast SQLite on client
- ✅ Production-ready

**Cons:**
- ❌ Requires Postgres server (not local-first for us)
- ❌ Read-path only (writes need handling)
- ❌ Complex architecture
- ❌ Doesn't solve Git diff problem
- ❌ Overkill for our local-first model

**Best For:**
- Apps with server backend
- Need Postgres features + local-first
- Large teams with infrastructure

**Git Compatibility:** ❌ Not designed for Git sync

---

### 5. **Dolt** ⭐

#### What it is
"Git for data" - SQL database with Git-like versioning built-in

**How it works:**
- MySQL-compatible database
- Native Git operations (branch, merge, commit, push, pull)
- Content-addressed storage
- Diff queries via SQL

**Pros:**
- ✅ Git semantics for data
- ✅ SQL querying
- ✅ Flutter/Dart support (mysql.dart)
- ✅ Branch/merge at database level
- ✅ Query diffs via SQL

**Cons:**
- ❌ Server-based (not embedded like SQLite)
- ❌ Requires running Dolt server
- ❌ Storage format still binary
- ❌ Network overhead for local operations
- ❌ Not designed for Git file sync

**Best For:**
- Teams wanting Git workflows for data
- When you need SQL + versioning
- Server-based architectures

**Git Compatibility:** ⚠️ Has its own versioning (not Git file sync)

---

### 6. **CSV/TSV** (Text Files)

#### What it is
Simple comma/tab separated values

**Pros:**
- ✅ Perfect Git diffs
- ✅ Universal compatibility
- ✅ Human readable
- ✅ Excel/spreadsheet friendly

**Cons:**
- ❌ No nested data (flat only)
- ❌ Escaping hell for complex strings
- ❌ No data types
- ❌ Inefficient for queries

**Best For:**
- Very simple tabular data
- When Excel compatibility needed

**Git Compatibility:** ✅ Excellent (but limited data model)

---

## Comparison Matrix

| Solution | Git Diffs | Queries | Conflicts | Complexity | Flutter Support |
|----------|-----------|---------|-----------|------------|----------------|
| **SQLite (current)** | ❌ Binary | ✅✅ Fast | ❌ Manual | ✅ Simple | ✅✅ Native |
| **cr-sqlite** | ❌ Binary | ✅✅ Fast | ✅ Auto | ⚠️ Medium | ⚠️ FFI |
| **JSONL** | ✅✅ Perfect | ⚠️ Scan | ❌ Manual | ✅ Simple | ✅✅ Easy |
| **Automerge** | ❌ Binary | ⚠️ No SQL | ✅ Auto | ⚠️ Complex | ⚠️ FFI |
| **ElectricSQL** | N/A | ✅✅ Fast | ✅ Auto | ❌ Complex | ✅ Yes |
| **Dolt** | ⚠️ Own | ✅✅ SQL | ✅ Auto | ⚠️ Medium | ✅ MySQL |
| **CSV** | ✅ Good | ❌ Scan | ❌ Manual | ✅ Simple | ✅ Easy |

---

## Recommendations for Parachute

### Option A: **JSON Lines (JSONL)** - Recommended ⭐⭐⭐

**Why:**
1. **Perfect Git integration** - Line-by-line diffs, easy merges
2. **Simple implementation** - ~100 lines of Dart code
3. **Human readable** - Can inspect/debug easily
4. **Good enough performance** - Our datasets are small (< 1000 links per space typically)
5. **No dependencies** - Pure Dart, no FFI

**Implementation:**
```
~/Parachute/spaces/personal/
├── space.json              # Space metadata
├── CLAUDE.md               # System prompt
├── space_links.jsonl       # 🆕 Links (one line per link)
└── files/
```

**Migration Path:**
1. Add JSONL storage alongside SQLite
2. Test in parallel
3. Migrate existing data
4. Remove SQLite dependency

**Trade-offs:**
- Queries slower than SQLite (but fast enough for our scale)
- Updates require file rewrite (but we mostly append)
- No indexes (but we can cache in memory)

---

### Option B: **Hybrid: JSONL + In-Memory Cache** - Best of Both ⭐⭐⭐

**Architecture:**
```dart
class SpaceKnowledgeService {
  final Map<String, List<LinkedCapture>> _cache = {};

  // Read from JSONL on load
  Future<List<LinkedCapture>> getLinkedCaptures(String spacePath) async {
    if (_cache.containsKey(spacePath)) {
      return _cache[spacePath]!;
    }

    // Load from JSONL
    final links = await _loadFromJsonl(spacePath);
    _cache[spacePath] = links;
    return links;
  }

  // Write to JSONL immediately
  Future<void> linkCapture(LinkedCapture link) async {
    await _appendToJsonl(link);
    _cache[spacePath]?.add(link);
  }
}
```

**Benefits:**
- ✅ Fast queries (in-memory)
- ✅ Git-friendly storage (JSONL)
- ✅ Simple implementation
- ✅ Best of both worlds

---

### Option C: **cr-sqlite** - If We Need Advanced Features ⭐

**When to use:**
- Multiple people editing same space simultaneously
- Conflicts happen frequently
- Need SQL querying performance
- Willing to sacrifice Git diff visibility

**Implementation:**
- Add cr-sqlite via FFI
- Keep current schema
- Add CRDT metadata
- Handle conflicts automatically

**Complexity:** Higher (FFI, CRDT concepts)

---

### Option D: **Keep SQLite, Add Git Diff Tools** ⭐

**Pragmatic approach:**
- Keep current SQLite implementation
- Add git-sqlite custom diff/merge driver
- Export to JSONL for viewing diffs
- Accept manual conflict resolution

**Tools:**
- git-sqlite (custom diff driver)
- sqlite-diffable (Datasette tool)

**Pros:**
- No code changes needed
- Minimal risk
- Can improve incrementally

**Cons:**
- Still binary
- Custom tooling required
- Doesn't solve core problem

---

## Recommended Path Forward

### Immediate (This Week)
1. **Prototype JSONL storage** (~2 hours)
   - Write simple JSONL read/write
   - Test with current data model
   - Compare performance

2. **Compare side-by-side** (~1 hour)
   - SQLite vs JSONL for our use case
   - Measure query times
   - Test Git diffs

3. **Make decision** based on data

### Short-Term (Next Sprint)
If JSONL works well:
1. Implement full `SpaceKnowledgeService` with JSONL
2. Add in-memory caching
3. Migrate existing spaces
4. Remove SQLite dependency

### Long-Term (Future)
- Monitor performance at scale
- Consider cr-sqlite if conflicts become issue
- Evaluate Automerge if we add real-time collab

---

## Conclusion

**For Parachute's use case (space knowledge links), JSON Lines is the sweet spot:**

✅ **Solves the core problem** (Git diffs/merges)
✅ **Simple to implement** (pure Dart)
✅ **Good enough performance** (our data is small)
✅ **Human readable** (debugging, inspection)
✅ **No new dependencies**

**The binary SQLite file is overkill for:**
- Simple key-value like data (links)
- Append-heavy workload
- Small datasets
- Git-based sync

**Reserve SQLite/CRDTs for:**
- Large datasets (> 100k records)
- Complex queries with joins
- Real-time multi-writer scenarios
- When Git visibility isn't important

---

## Next Steps

1. **Prototype JSONL** (recommended)
2. **Benchmark** against SQLite
3. **Test Git workflow** (create conflicts, merge)
4. **Decide** based on results

Would you like me to implement the JSONL prototype?
