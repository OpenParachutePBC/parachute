import 'package:dio/dio.dart';
import '../constants/api_constants.dart';
import '../models/space.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../models/file_info.dart';
import '../models/relevant_note.dart';
import '../models/space_database_stats.dart';
import '../models/table_query_result.dart';
import '../models/registry_space.dart';
import '../models/capture.dart';
import './websocket_client.dart';

class ApiClient {
  final Dio _dio;
  final WebSocketClient wsClient;

  ApiClient({String? baseUrl})
    : _dio = Dio(
        BaseOptions(
          baseUrl: baseUrl ?? ApiConstants.baseUrl,
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 30),
          headers: {'Content-Type': 'application/json'},
        ),
      ),
      wsClient = WebSocketClient() {
    // Connect WebSocket on initialization
    wsClient.connect().catchError((error) {
      // WebSocketClient logs errors internally via logger
    });
  }

  // Spaces

  Future<List<Space>> getSpaces() async {
    try {
      final response = await _dio.get('/api/spaces');
      final Map<String, dynamic> data = response.data as Map<String, dynamic>;
      final List<dynamic> spaces = data['spaces'] as List<dynamic>;
      return spaces
          .map((json) => Space.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Space> getSpace(String id) async {
    try {
      final response = await _dio.get('/api/spaces/$id');
      return Space.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Space> createSpace({
    required String name,
    String? icon,
    String? color,
  }) async {
    try {
      final response = await _dio.post(
        '/api/spaces',
        data: {
          'name': name,
          if (icon != null) 'icon': icon,
          if (color != null) 'color': color,
        },
      );
      return Space.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Space> updateSpace({
    required String id,
    String? name,
    String? icon,
    String? color,
  }) async {
    try {
      final response = await _dio.put(
        '/api/spaces/$id',
        data: {
          if (name != null) 'name': name,
          if (icon != null) 'icon': icon,
          if (color != null) 'color': color,
        },
      );
      return Space.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> deleteSpace(String id) async {
    try {
      await _dio.delete('/api/spaces/$id');
    } catch (e) {
      throw _handleError(e);
    }
  }

  // Conversations

  Future<List<Conversation>> getConversations(String spaceId) async {
    try {
      final response = await _dio.get(
        '/api/conversations',
        queryParameters: {'space_id': spaceId},
      );
      final Map<String, dynamic> data = response.data as Map<String, dynamic>;
      final List<dynamic> conversations =
          data['conversations'] as List<dynamic>;
      return conversations
          .map((json) => Conversation.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Conversation> createConversation({
    required String spaceId,
    required String title,
  }) async {
    try {
      final response = await _dio.post(
        '/api/conversations',
        data: {'space_id': spaceId, 'title': title},
      );
      return Conversation.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Conversation> updateConversation({
    required String id,
    required String title,
  }) async {
    try {
      final response = await _dio.put(
        '/api/conversations/$id',
        data: {'title': title},
      );
      return Conversation.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      throw _handleError(e);
    }
  }

  // Messages

  Future<List<Message>> getMessages(String conversationId) async {
    try {
      final response = await _dio.get(
        '/api/messages',
        queryParameters: {'conversation_id': conversationId},
      );
      final Map<String, dynamic> data = response.data as Map<String, dynamic>;
      final List<dynamic> messages = data['messages'] as List<dynamic>;
      return messages
          .map((json) => Message.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Message> sendMessage({
    required String conversationId,
    required String content,
  }) async {
    try {
      final response = await _dio.post(
        '/api/messages',
        data: {'conversation_id': conversationId, 'content': content},
      );
      return Message.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      throw _handleError(e);
    }
  }

  // File Browser

  Future<BrowseResult> browseFiles({String path = ''}) async {
    try {
      final response = await _dio.get(
        '/api/files/browse',
        queryParameters: {'path': path},
      );
      return BrowseResult.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<String> readFile(String path) async {
    try {
      final response = await _dio.get(
        '/api/files/read',
        queryParameters: {'path': path},
      );
      final Map<String, dynamic> data = response.data as Map<String, dynamic>;
      return data['content'] as String;
    } catch (e) {
      throw _handleError(e);
    }
  }

  String getDownloadUrl(String path) {
    return '${_dio.options.baseUrl}/api/files/download?path=$path';
  }

  // Space Notes

  Future<List<RelevantNote>> getSpaceNotes(
    String spaceId, {
    List<String>? tags,
    DateTime? startDate,
    DateTime? endDate,
    int? limit,
    int? offset,
  }) async {
    try {
      final queryParams = <String, dynamic>{};
      if (tags != null && tags.isNotEmpty) {
        queryParams['tags'] = tags.join(',');
      }
      if (startDate != null) {
        queryParams['start_date'] = startDate.toIso8601String();
      }
      if (endDate != null) {
        queryParams['end_date'] = endDate.toIso8601String();
      }
      if (limit != null) {
        queryParams['limit'] = limit.toString();
      }
      if (offset != null) {
        queryParams['offset'] = offset.toString();
      }

      final response = await _dio.get(
        '/api/spaces/$spaceId/notes',
        queryParameters: queryParams,
      );
      final Map<String, dynamic> data = response.data as Map<String, dynamic>;
      final List<dynamic> notes = data['notes'] as List<dynamic>;
      return notes
          .map((json) => RelevantNote.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> linkNoteToSpace(String spaceId, LinkNoteRequest request) async {
    try {
      await _dio.post('/api/spaces/$spaceId/notes', data: request.toJson());
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> updateNoteContext(
    String spaceId,
    String captureId,
    UpdateNoteContextRequest request,
  ) async {
    try {
      await _dio.put(
        '/api/spaces/$spaceId/notes/$captureId',
        data: request.toJson(),
      );
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> unlinkNoteFromSpace(String spaceId, String captureId) async {
    try {
      await _dio.delete('/api/spaces/$spaceId/notes/$captureId');
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<NoteWithContext> getNoteContent(
    String spaceId,
    String captureId,
  ) async {
    try {
      final response = await _dio.get(
        '/api/spaces/$spaceId/notes/$captureId/content',
      );
      return NoteWithContext.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<SpaceDatabaseStats> getSpaceDatabaseStats(String spaceId) async {
    try {
      final response = await _dio.get('/api/spaces/$spaceId/database/stats');
      return SpaceDatabaseStats.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<TableQueryResult> getTableData(String spaceId, String tableName) async {
    try {
      final response = await _dio.get('/api/spaces/$spaceId/database/tables/$tableName');
      return TableQueryResult.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      throw _handleError(e);
    }
  }

  // Registry: Spaces

  Future<List<RegistrySpace>> getRegistrySpaces() async {
    try {
      final response = await _dio.get('/api/registry/spaces');
      final Map<String, dynamic> data = response.data as Map<String, dynamic>;
      final List<dynamic> spaces = data['spaces'] as List<dynamic>;
      return spaces
          .map((json) => RegistrySpace.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<RegistrySpace> getRegistrySpace(String id) async {
    try {
      final response = await _dio.get('/api/registry/spaces/$id');
      return RegistrySpace.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<RegistrySpace> addExternalSpace(AddSpaceParams params) async {
    try {
      final response = await _dio.post(
        '/api/registry/spaces/add',
        data: params.toJson(),
      );
      return RegistrySpace.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<RegistrySpace> createRegistrySpace(CreateSpaceParams params) async {
    try {
      final response = await _dio.post(
        '/api/registry/spaces/create',
        data: params.toJson(),
      );
      return RegistrySpace.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> removeRegistrySpace(String id) async {
    try {
      await _dio.delete('/api/registry/spaces/$id');
    } catch (e) {
      throw _handleError(e);
    }
  }

  // Registry: Captures

  Future<List<Capture>> getCaptures() async {
    try {
      final response = await _dio.get('/api/registry/captures');
      final Map<String, dynamic> data = response.data as Map<String, dynamic>;
      final List<dynamic> captures = data['captures'] as List<dynamic>;
      return captures
          .map((json) => Capture.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Capture> getCapture(String id) async {
    try {
      final response = await _dio.get('/api/registry/captures/$id');
      return Capture.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Capture> registerCapture(AddCaptureParams params) async {
    try {
      final response = await _dio.post(
        '/api/registry/captures',
        data: params.toJson(),
      );
      return Capture.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      throw _handleError(e);
    }
  }

  // Registry: Settings

  Future<Map<String, String>> getRegistrySettings() async {
    try {
      final response = await _dio.get('/api/registry/settings');
      final Map<String, dynamic> data = response.data as Map<String, dynamic>;
      return {
        'notes_folder': data['notes_folder'] as String,
        'spaces_folder': data['spaces_folder'] as String,
      };
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> updateRegistrySetting(String key, String value) async {
    try {
      await _dio.put(
        '/api/registry/settings/$key',
        data: {'value': value},
      );
    } catch (e) {
      throw _handleError(e);
    }
  }

  // Error handling

  Exception _handleError(dynamic error) {
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return Exception(
            'Connection timeout. Please check your internet connection.',
          );
        case DioExceptionType.badResponse:
          final statusCode = error.response?.statusCode;
          final data = error.response?.data;
          final message = data is Map
              ? (data['error'] ?? 'Unknown error')
              : (data?.toString() ?? 'Unknown error');
          return Exception('Server error ($statusCode): $message');
        case DioExceptionType.cancel:
          return Exception('Request cancelled');
        default:
          return Exception('Network error: ${error.message}');
      }
    }
    return Exception('Unexpected error: $error');
  }
}
