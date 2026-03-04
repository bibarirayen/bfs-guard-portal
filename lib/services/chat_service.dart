// lib/services/chat_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stomp_dart_client/stomp.dart';
import 'package:stomp_dart_client/stomp_config.dart';
import 'package:stomp_dart_client/stomp_frame.dart';
import '../config/ApiService.dart';

// ─── Models ───────────────────────────────────────────────────────────────────

class ChatMessage {
  final int    id;
  final int    senderId;
  final String senderName;
  final int    receiverId;
  final String content;
  final DateTime sentAt;
  final bool   isRead;

  ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.receiverId,
    required this.content,
    required this.sentAt,
    required this.isRead,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
    id:         j['id'] ?? -1,
    senderId:   j['senderId'] ?? 0,
    senderName: j['senderName'] ?? '',
    receiverId: j['receiverId'] ?? 0,
    content:    j['content'] ?? '',
    sentAt:     j['sentAt'] != null
        ? DateTime.tryParse(j['sentAt']) ?? DateTime.now()
        : DateTime.now(),
    isRead:     j['isRead'] ?? false,
  );

  Map<String, dynamic> toJson() => {
    'id':         id,
    'senderId':   senderId,
    'senderName': senderName,
    'receiverId': receiverId,
    'content':    content,
    'sentAt':     sentAt.toIso8601String(),
    'isRead':     isRead,
  };
}

class Conversation {
  final int    userId;
  final String userName;
  final String userRole;
  final String? lastMessage;
  final DateTime? lastMessageTime;
  final int    unreadCount;

  Conversation({
    required this.userId,
    required this.userName,
    required this.userRole,
    this.lastMessage,
    this.lastMessageTime,
    this.unreadCount = 0,
  });

  factory Conversation.fromJson(Map<String, dynamic> j) => Conversation(
    userId:          j['userId'] ?? 0,
    userName:        j['userName'] ?? '',
    userRole:        j['userRole'] ?? 'Guard',
    lastMessage:     j['lastMessage'],
    lastMessageTime: j['lastMessageTime'] != null
        ? DateTime.tryParse(j['lastMessageTime'])
        : null,
    unreadCount:     j['unreadCount'] ?? 0,
  );
}

// ─── Service ──────────────────────────────────────────────────────────────────

class ChatService {
  // Singleton — same pattern as LiveLocationService
  static final ChatService _instance = ChatService._internal();
  factory ChatService() => _instance;
  ChatService._internal();

  final _api = ApiService();

  StompClient? _stompClient;
  int?         _myUserId;

  // Stream that any screen can listen to for incoming messages
  final _messageStreamController = StreamController<ChatMessage>.broadcast();
  Stream<ChatMessage> get messageStream => _messageStreamController.stream;

  bool get isConnected => _stompClient?.connected ?? false;

  // ─── Connect ──────────────────────────────────────────────────────────────
  // Call once when the app starts or when entering the chat tab.
  // Safe to call multiple times — checks isConnected first.
  void connect(int userId) {
    if (_stompClient?.connected == true && _myUserId == userId) return;

    _myUserId = userId;
    _stompClient?.deactivate();

    _stompClient = StompClient(
      config: StompConfig(
        // Same WS URL as LiveLocationService
        url: 'wss://api.blackfabricsecurity.com/ws',
        reconnectDelay: const Duration(seconds: 5),
        onConnect: (StompFrame frame) {
          print('✅ Chat WebSocket connected for user $userId');
          // Subscribe to personal topic — backend sends here when a message arrives
          // /topic/chat.{myUserId}
          _stompClient!.subscribe(
            destination: '/topic/chat.$userId',
            callback: (StompFrame frame) {
              if (frame.body == null) return;
              try {
                final msg = ChatMessage.fromJson(jsonDecode(frame.body!));
                _messageStreamController.add(msg);
                print('💬 Received: ${msg.senderName} → "${msg.content}"');
              } catch (e) {
                print('❌ Chat parse error: $e');
              }
            },
          );
        },
        onWebSocketError: (e) => print('❌ Chat WS error: $e'),
        onDisconnect: (_) => print('⚠️ Chat WS disconnected'),
      ),
    );
    _stompClient!.activate();
  }

  // ─── Send ─────────────────────────────────────────────────────────────────
  // Sends over STOMP to /app/chat.send — backend handles routing + persistence
  void sendMessage(int toUserId, String content) {
    if (_stompClient == null || !_stompClient!.connected) {
      print('⚠️ Chat WS not connected, cannot send');
      return;
    }

    _stompClient!.send(
      destination: '/app/chat.send',
      body: jsonEncode({
        'senderId':   _myUserId,
        'receiverId': toUserId,
        'content':    content.trim(),
      }),
    );
  }

  // ─── REST calls ───────────────────────────────────────────────────────────

  Future<List<ChatMessage>> getHistory(int otherUserId) async {
    if (_myUserId == null) return [];
    try {
      final res = await _api.get('chat/messages/$_myUserId/$otherUserId');
      if (res.statusCode == 200) {
        final List data = jsonDecode(res.body);
        return data.map((e) => ChatMessage.fromJson(e)).toList();
      }
    } catch (e) {
      print('❌ Chat history error: $e');
    }
    return [];
  }

  Future<List<Conversation>> getConversations() async {
    if (_myUserId == null) return [];
    try {
      final res = await _api.get('chat/conversations/$_myUserId');
      if (res.statusCode == 200) {
        final List data = jsonDecode(res.body);
        return data.map((e) => Conversation.fromJson(e)).toList();
      }
    } catch (e) {
      print('❌ Conversations error: $e');
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> getChatUsers() async {
    if (_myUserId == null) return [];
    try {
      final res = await _api.get('chat/users/$_myUserId');
      if (res.statusCode == 200) {
        final List data = jsonDecode(res.body);
        return data.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      print('❌ Chat users error: $e');
    }
    return [];
  }

  Future<void> markRead(int fromUserId) async {
    if (_myUserId == null) return;
    try {
      await _api.post('chat/mark-read', {
        'userId':     _myUserId,
        'fromUserId': fromUserId,
      });
    } catch (e) {
      print('❌ Mark read error: $e');
    }
  }

  // ─── Disconnect ───────────────────────────────────────────────────────────
  void disconnect() {
    _stompClient?.deactivate();
    _stompClient = null;
    print('🛑 Chat WebSocket disconnected');
  }
}