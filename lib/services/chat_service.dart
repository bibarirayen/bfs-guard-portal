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

  ChatMessage copyWith({bool? isRead}) => ChatMessage(
    id: id, senderId: senderId, senderName: senderName,
    receiverId: receiverId, content: content, sentAt: sentAt,
    isRead: isRead ?? this.isRead,
  );

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
    id:         j['id'] ?? -1,
    senderId:   j['senderId'] ?? 0,
    senderName: j['senderName'] ?? '',
    receiverId: j['receiverId'] ?? 0,
    content:    j['content'] ?? '',
    sentAt:     j['sentAt'] != null
        ? (DateTime.tryParse(j['sentAt']) ?? DateTime.now()).toLocal()
        : DateTime.now(),
    isRead:     j['isRead'] ?? false,
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'senderId': senderId, 'senderName': senderName,
    'receiverId': receiverId, 'content': content,
    'sentAt': sentAt.toIso8601String(), 'isRead': isRead,
  };
}

// Read receipt pushed by the backend when the receiver opens the chat
class ReadReceipt {
  final int readBy;    // the user who read the messages
  final int readFrom;  // whose messages were read

  ReadReceipt({required this.readBy, required this.readFrom});

  factory ReadReceipt.fromJson(Map<String, dynamic> j) => ReadReceipt(
    readBy:   j['readBy']   ?? 0,
    readFrom: j['readFrom'] ?? 0,
  );
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
        ? DateTime.tryParse(j['lastMessageTime'])?.toLocal()
        : null,
    unreadCount:     j['unreadCount'] ?? 0,
  );
}

// ─── Service ──────────────────────────────────────────────────────────────────

class ChatService {
  static final ChatService _instance = ChatService._internal();
  factory ChatService() => _instance;
  ChatService._internal();

  final _api = ApiService();

  StompClient? _stompClient;
  int?         _myUserId;

  // Stream for incoming chat messages
  final _messageStreamController = StreamController<ChatMessage>.broadcast();
  Stream<ChatMessage> get messageStream => _messageStreamController.stream;

  // Stream for read receipts — tells the sender their messages were seen
  final _readReceiptController = StreamController<ReadReceipt>.broadcast();
  Stream<ReadReceipt> get readReceiptStream => _readReceiptController.stream;

  bool get isConnected => _stompClient?.connected ?? false;

  // ─── Connect ──────────────────────────────────────────────────────────────
  void connect(int userId) {
    if (_stompClient?.connected == true && _myUserId == userId) return;

    _myUserId = userId;
    _stompClient?.deactivate();

    _stompClient = StompClient(
      config: StompConfig(
        url: 'wss://api.blackfabricsecurity.com/ws',
        reconnectDelay: const Duration(seconds: 5),
        onConnect: (StompFrame frame) {
          _stompClient!.subscribe(
            destination: '/topic/chat.$userId',
            callback: (StompFrame frame) {
              if (frame.body == null) return;
              try {
                final payload = jsonDecode(frame.body!) as Map<String, dynamic>;
                // Route to the correct stream based on payload type
                if (payload['type'] == 'READ_RECEIPT') {
                  _readReceiptController.add(ReadReceipt.fromJson(payload));
                } else {
                  _messageStreamController.add(ChatMessage.fromJson(payload));
                }
              } catch (e) {
                print('Chat parse error: $e');
              }
            },
          );
        },
        onWebSocketError: (e) => print('Chat WS error: $e'),
        onDisconnect:     (_) => print('Chat WS disconnected'),
      ),
    );
    _stompClient!.activate();
  }

  // ─── Send ─────────────────────────────────────────────────────────────────
  void sendMessage(int toUserId, String content) {
    if (_stompClient == null || !_stompClient!.connected) return;
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
    } catch (e) { print('Chat history error: $e'); }
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
    } catch (e) { print('Conversations error: $e'); }
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
    } catch (e) { print('Chat users error: $e'); }
    return [];
  }

  Future<void> markRead(int fromUserId) async {
    if (_myUserId == null) return;
    try {
      await _api.post('chat/mark-read', {
        'userId':     _myUserId,
        'fromUserId': fromUserId,
      });
    } catch (e) { print('Mark read error: $e'); }
  }

  // ─── Disconnect ───────────────────────────────────────────────────────────
  void disconnect() {
    _stompClient?.deactivate();
    _stompClient = null;
  }
}