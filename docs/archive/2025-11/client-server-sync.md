# Client-Server File Sync Architecture

**Purpose:** Define how Flutter app syncs files with Go backend's canonical `~/Parachute/` folder

**Philosophy:** Backend owns the truth, Flutter is a lightweight sync client

---

## Core Principle

```
┌─────────────────┐                    ┌──────────────────┐
│  Flutter App    │                    │   Go Backend     │
│                 │                    │                  │
│  Local Cache    │  ◄──── HTTP ────►  │  ~/Parachute/    │
│  (Temporary)    │     WebSocket      │  (Source of      │
│                 │                    │   Truth)         │
└─────────────────┘                    └──────────────────┘
```

**Backend:**
- Owns `~/Parachute/` folder structure
- Manages all file operations
- Provides HTTP API for file upload/download
- Broadcasts changes via WebSocket
- Single source of truth

**Flutter:**
- Uses app documents directory for cache only
- Uploads recordings immediately after capture
- Downloads files on-demand for playback
- Lightweight - can clear cache anytime
- Subscribes to backend changes via WebSocket

---

## Backend File Structure

```
~/Parachute/                          # Backend manages this
├── captures/
│   ├── 2025-10-25_14-30-22.wav      # Uploaded from any device
│   ├── 2025-10-25_14-30-22.md       # Transcript
│   └── 2025-10-25_14-30-22.json     # Metadata
│
└── spaces/
    ├── work/
    │   ├── CLAUDE.md
    │   ├── .space.json
    │   ├── files/
    │   └── conversations/
    │       └── 2025-10-25_project-planning.md
    └── personal/
        └── ...
```

---

## Flutter Cache Structure

```
<app_documents>/                      # Flutter cache (ephemeral)
├── cache/
│   ├── captures/
│   │   └── 2025-10-25_14-30-22.wav  # Downloaded for playback
│   └── thumbnails/                   # Generated locally
└── pending_uploads/
    └── temp_recording.wav            # Waiting to upload
```

---

## Backend API Design

### File Management Endpoints

#### 1. Upload Capture
```
POST /api/captures/upload
Content-Type: multipart/form-data

Fields:
- audio: File (required)
- timestamp: ISO8601 string (required)
- source: string (phone|omi|desktop)
- deviceId: string (optional)
- duration: number (seconds)

Response:
{
  "id": "uuid",
  "path": "captures/2025-10-25_14-30-22.wav",
  "url": "/api/captures/2025-10-25_14-30-22.wav",
  "created_at": "2025-10-25T14:30:22Z"
}
```

#### 2. Upload Transcript
```
POST /api/captures/:filename/transcript
Content-Type: application/json

Body:
{
  "transcript": "transcribed text",
  "transcriptionMode": "api|local",
  "modelUsed": "whisper-1"
}

Response:
{
  "success": true,
  "transcriptPath": "captures/2025-10-25_14-30-22.md"
}
```

#### 3. List Captures
```
GET /api/captures?limit=50&offset=0

Response:
{
  "captures": [
    {
      "filename": "2025-10-25_14-30-22.wav",
      "timestamp": "2025-10-25T14:30:22Z",
      "duration": 125.5,
      "hasTranscript": true,
      "source": "phone",
      "size": 2048000,
      "audioUrl": "/api/captures/2025-10-25_14-30-22.wav",
      "transcriptUrl": "/api/captures/2025-10-25_14-30-22.md"
    }
  ],
  "total": 42,
  "hasMore": false
}
```

#### 4. Download Capture
```
GET /api/captures/:filename

Response: Binary audio file with proper Content-Type
```

#### 5. Download Transcript
```
GET /api/captures/:filename/transcript

Response: Markdown text
```

#### 6. Delete Capture
```
DELETE /api/captures/:filename

Deletes:
- Audio file
- Transcript (if exists)
- Metadata JSON (if exists)

Response:
{
  "success": true
}
```

### Space File Endpoints

#### 1. Create Conversation
```
POST /api/spaces/:spaceId/conversations
Content-Type: application/json

Body:
{
  "title": "Project Planning",
  "content": "# Conversation markdown...",
  "linkedCaptures": ["2025-10-25_14-30-22"]
}

Response:
{
  "id": "uuid",
  "filename": "2025-10-25_project-planning.md",
  "path": "spaces/work/conversations/2025-10-25_project-planning.md",
  "created_at": "2025-10-25T14:30:22Z"
}
```

#### 2. Update Conversation
```
PUT /api/spaces/:spaceId/conversations/:conversationId
Content-Type: application/json

Body:
{
  "content": "# Updated markdown..."
}
```

#### 3. Upload Space File
```
POST /api/spaces/:spaceId/files
Content-Type: multipart/form-data

Fields:
- file: File
- path: string (relative path within space/files/)

Response:
{
  "path": "spaces/work/files/document.pdf",
  "url": "/api/spaces/work/files/document.pdf",
  "size": 1024000
}
```

---

## WebSocket Real-Time Sync

### Subscribe to Changes
```json
{
  "type": "subscribe",
  "channels": ["captures", "spaces"]
}
```

### File Change Notifications
```json
{
  "type": "file.created",
  "path": "captures/2025-10-25_14-30-22.wav",
  "timestamp": "2025-10-25T14:30:22Z",
  "source": "device-abc123"
}

{
  "type": "file.updated",
  "path": "spaces/work/conversations/2025-10-25_project-planning.md",
  "timestamp": "2025-10-25T15:45:10Z"
}

{
  "type": "file.deleted",
  "path": "captures/2025-10-25_14-30-22.wav",
  "timestamp": "2025-10-25T16:00:00Z"
}
```

---

## Flutter Sync Strategy

### Recording Flow

**1. Capture Audio**
```dart
// Record to temp file
final tempPath = '${appDocs}/pending_uploads/temp_${timestamp}.wav';
await audioRecorder.stop(path: tempPath);
```

**2. Upload Immediately**
```dart
// Upload to backend
final response = await httpClient.post(
  '/api/captures/upload',
  files: {'audio': File(tempPath)},
  fields: {
    'timestamp': timestamp.toIso8601String(),
    'source': 'phone',
    'duration': duration.inSeconds.toString(),
  },
);

// Delete local temp file after successful upload
await File(tempPath).delete();
```

**3. Backend Saves to ~/Parachute/captures/**
```go
// Backend receives upload
audioFile, _ := c.FormFile("audio")
timestamp := c.FormValue("timestamp")

// Parse timestamp and generate filename
filename := formatTimestampForFilename(timestamp) + ".wav"
savePath := filepath.Join(parachuteDir, "captures", filename)

// Save file
audioFile.SaveAs(savePath)

// Broadcast to other clients
websocket.Broadcast(FileCreatedEvent{
  Path: "captures/" + filename,
  Timestamp: timestamp,
})
```

**4. Other Devices Receive Notification**
```dart
// Flutter receives WebSocket notification
websocket.listen((event) {
  if (event['type'] == 'file.created' &&
      event['path'].startsWith('captures/')) {
    // Refresh captures list (metadata only)
    await refreshCapturesList();
  }
});
```

**5. Download for Playback (On-Demand)**
```dart
// User taps to play recording
Future<void> playRecording(String filename) async {
  // Check if already cached
  final cachePath = '${appDocs}/cache/captures/$filename';
  if (!await File(cachePath).exists()) {
    // Download from backend
    final response = await httpClient.get('/api/captures/$filename');
    await File(cachePath).writeAsBytes(response.bodyBytes);
  }

  // Play from cache
  await audioPlayer.play(DeviceFileSource(cachePath));
}
```

### Transcription Flow

**Option A: Local Transcription → Upload**
```dart
// Transcribe locally
final transcript = await whisperService.transcribe(audioPath);

// Upload transcript to backend
await httpClient.post(
  '/api/captures/$filename/transcript',
  body: jsonEncode({
    'transcript': transcript,
    'transcriptionMode': 'local',
    'modelUsed': 'base',
  }),
);
```

**Option B: Backend Transcription**
```dart
// Upload audio with transcription request
await httpClient.post(
  '/api/captures/upload',
  fields: {
    ...
    'autoTranscribe': 'true',
  },
);

// Backend transcribes and saves .md file
// Frontend receives WebSocket notification when ready
```

---

## Backend Implementation

### Environment Configuration
```bash
# .env
PARACHUTE_ROOT=/Users/alice/Parachute
SPACES_BASE_PATH=/Users/alice/Parachute/spaces
```

### File Service (New)
```go
// internal/domain/file/service.go
type FileService struct {
  rootPath string
}

func (s *FileService) SaveCapture(
  audioFile multipart.File,
  timestamp time.Time,
  metadata CaptureMetadata,
) error {
  // Generate filename
  filename := formatTimestamp(timestamp) + ".wav"

  // Save audio
  audioPath := filepath.Join(s.rootPath, "captures", filename)
  saveFile(audioFile, audioPath)

  // Save JSON metadata
  jsonPath := filepath.Join(s.rootPath, "captures", formatTimestamp(timestamp) + ".json")
  saveJSON(metadata, jsonPath)

  return nil
}

func (s *FileService) SaveTranscript(filename string, transcript string) error {
  // Remove .wav extension, add .md
  mdFilename := strings.TrimSuffix(filename, ".wav") + ".md"
  mdPath := filepath.Join(s.rootPath, "captures", mdFilename)

  // Generate markdown
  markdown := generateTranscriptMarkdown(transcript, metadata)

  return os.WriteFile(mdPath, []byte(markdown), 0644)
}

func (s *FileService) ListCaptures(limit, offset int) ([]CaptureInfo, error) {
  capturesDir := filepath.Join(s.rootPath, "captures")

  // Read directory
  entries, _ := os.ReadDir(capturesDir)

  captures := []CaptureInfo{}
  for _, entry := range entries {
    if strings.HasSuffix(entry.Name(), ".wav") {
      // Read metadata from .json file
      jsonPath := strings.TrimSuffix(entry.Name(), ".wav") + ".json"
      metadata := readMetadata(jsonPath)

      captures = append(captures, CaptureInfo{
        Filename: entry.Name(),
        Timestamp: metadata.Timestamp,
        Duration: metadata.Duration,
        HasTranscript: fileExists(strings.TrimSuffix(entry.Name(), ".wav") + ".md"),
        ...
      })
    }
  }

  // Sort by timestamp desc
  sort.Slice(captures, func(i, j int) bool {
    return captures[i].Timestamp.After(captures[j].Timestamp)
  })

  // Paginate
  return paginate(captures, limit, offset), nil
}

func (s *FileService) GetCapture(filename string) (io.ReadCloser, error) {
  audioPath := filepath.Join(s.rootPath, "captures", filename)
  return os.Open(audioPath)
}
```

### File Handler (New)
```go
// internal/api/handlers/file_handler.go
type FileHandler struct {
  fileService *file.FileService
  wsHub       *websocket.Hub
}

func (h *FileHandler) UploadCapture(c *fiber.Ctx) error {
  // Parse multipart form
  audioFile, _ := c.FormFile("audio")
  timestamp := c.FormValue("timestamp")

  // Save file
  err := h.fileService.SaveCapture(audioFile, timestamp, metadata)
  if err != nil {
    return err
  }

  // Broadcast to WebSocket clients
  h.wsHub.Broadcast(FileCreatedEvent{
    Type: "file.created",
    Path: "captures/" + filename,
    Timestamp: timestamp,
  })

  return c.JSON(fiber.Map{
    "id": uuid.New().String(),
    "path": "captures/" + filename,
    "url": "/api/captures/" + filename,
  })
}

func (h *FileHandler) ListCaptures(c *fiber.Ctx) error {
  limit := c.QueryInt("limit", 50)
  offset := c.QueryInt("offset", 0)

  captures, err := h.fileService.ListCaptures(limit, offset)
  if err != nil {
    return err
  }

  return c.JSON(fiber.Map{
    "captures": captures,
    "total": len(captures),
  })
}

func (h *FileHandler) DownloadCapture(c *fiber.Ctx) error {
  filename := c.Params("filename")

  file, err := h.fileService.GetCapture(filename)
  if err != nil {
    return fiber.NewError(404, "File not found")
  }
  defer file.Close()

  c.Set("Content-Type", "audio/wav")
  return c.SendStream(file)
}
```

### Routes
```go
// cmd/server/main.go
func setupRoutes(app *fiber.App, handlers *api.Handlers) {
  api := app.Group("/api")

  // Captures
  captures := api.Group("/captures")
  captures.Post("/upload", handlers.File.UploadCapture)
  captures.Get("/", handlers.File.ListCaptures)
  captures.Get("/:filename", handlers.File.DownloadCapture)
  captures.Post("/:filename/transcript", handlers.File.UploadTranscript)
  captures.Get("/:filename/transcript", handlers.File.DownloadTranscript)
  captures.Delete("/:filename", handlers.File.DeleteCapture)

  // Spaces (existing, update for file operations)
  spaces := api.Group("/spaces")
  spaces.Post("/:spaceId/conversations", handlers.Space.CreateConversation)
  spaces.Post("/:spaceId/files", handlers.Space.UploadFile)
}
```

---

## Flutter Implementation

### File Sync Service
```dart
// lib/core/services/file_sync_service.dart
class FileSyncService {
  final HttpClient _http;
  final WebSocketClient _ws;
  final FileSystemService _fileSystem;

  /// Upload recording to backend
  Future<String> uploadRecording({
    required File audioFile,
    required DateTime timestamp,
    required String source,
    double? duration,
  }) async {
    final response = await _http.post(
      '/api/captures/upload',
      files: {'audio': audioFile},
      fields: {
        'timestamp': timestamp.toIso8601String(),
        'source': source,
        if (duration != null) 'duration': duration.toString(),
      },
    );

    final data = jsonDecode(response.body);
    return data['path'];
  }

  /// Upload transcript
  Future<void> uploadTranscript({
    required String filename,
    required String transcript,
    required String mode,
  }) async {
    await _http.post(
      '/api/captures/$filename/transcript',
      body: jsonEncode({
        'transcript': transcript,
        'transcriptionMode': mode,
      }),
    );
  }

  /// List captures from backend
  Future<List<Capture>> listCaptures({int limit = 50, int offset = 0}) async {
    final response = await _http.get(
      '/api/captures?limit=$limit&offset=$offset',
    );

    final data = jsonDecode(response.body);
    return (data['captures'] as List)
        .map((json) => Capture.fromJson(json))
        .toList();
  }

  /// Download capture for playback
  Future<String> downloadCapture(String filename) async {
    // Check cache first
    final cachePath = await _getCachePath(filename);
    if (await File(cachePath).exists()) {
      return cachePath;
    }

    // Download from backend
    final response = await _http.get('/api/captures/$filename');
    await File(cachePath).writeAsBytes(response.bodyBytes);

    return cachePath;
  }

  Future<String> _getCachePath(String filename) async {
    final appDocs = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${appDocs.path}/cache/captures');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return '${cacheDir.path}/$filename';
  }
}
```

### Updated Storage Service
```dart
// Update existing StorageService to use FileSyncService
class StorageService {
  final FileSyncService _sync;

  Future<List<Recording>> getRecordings() async {
    // Fetch from backend instead of local filesystem
    final captures = await _sync.listCaptures();

    return captures.map((c) => Recording(
      id: c.filename,
      title: c.title,
      filePath: '', // No local path until downloaded
      timestamp: c.timestamp,
      ...
    )).toList();
  }

  Future<void> saveRecording(Recording recording, File audioFile) async {
    // Upload to backend
    await _sync.uploadRecording(
      audioFile: audioFile,
      timestamp: recording.timestamp,
      source: recording.source.toString(),
      duration: recording.duration.inSeconds.toDouble(),
    );

    // Delete local temp file
    await audioFile.delete();
  }
}
```

---

## Migration Strategy

### Phase 1: Backend Setup
1. Add `PARACHUTE_ROOT` environment variable
2. Implement FileService
3. Add file upload/download endpoints
4. Test with curl/Postman

### Phase 2: Flutter Integration
1. Create FileSyncService
2. Update RecordingScreen to upload after recording
3. Update HomeScreen to fetch from backend
4. Update playback to download on-demand

### Phase 3: Real-Time Sync
1. Add WebSocket file change events
2. Flutter subscribes to changes
3. Auto-refresh when other devices upload

### Phase 4: Cleanup
1. Remove local FileSystemService usage from recorder
2. Keep FileSystemService for spaces (future use)
3. Clear old cache files

---

## Benefits

### For Backend
✅ **Single source of truth** - All files in one place
✅ **Easy backup** - Just backup ~/Parachute/
✅ **Multi-device sync** - Automatic via backend
✅ **File watching** - Can watch folder for external changes

### For Flutter
✅ **Lightweight** - No large local storage needed
✅ **Fast startup** - Don't need to scan filesystem
✅ **On-demand loading** - Download files when needed
✅ **Cross-device** - Works seamlessly across devices

---

## Next Steps

1. Set up `PARACHUTE_ROOT=/Users/yourname/Parachute` in backend
2. Implement FileService in Go
3. Add file upload/download endpoints
4. Update Flutter to use backend sync
5. Test end-to-end flow

---

**Status:** 📝 Design Complete
**Last Updated:** 2025-10-25
