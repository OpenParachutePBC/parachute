import 'package:dio/dio.dart';
import '../constants/api_constants.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../models/file_info.dart';
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
