// lib/screens/chat_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/chat_service.dart';

class ChatScreen extends StatefulWidget {
  final int    otherUserId;
  final String otherUserName;
  final String otherUserRole;

  const ChatScreen({
    super.key,
    required this.otherUserId,
    required this.otherUserName,
    required this.otherUserRole,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _chat       = ChatService();
  final _inputCtrl  = TextEditingController();
  final _scrollCtrl = ScrollController();

  int? _myUserId;

  List<ChatMessage> _messages = [];
  bool _loading = true;

  // ── FIX: explicit generic type so the compiler resolves _sub correctly ──
  StreamSubscription<ChatMessage>? _sub;

  // ── Theme ─────────────────────────────────────────────────────────────────
  Color get _bg        => const Color(0xFF0F172A);
  Color get _card      => const Color(0xFF1E293B);
  Color get _border    => const Color(0xFF334155);
  Color get _text      => Colors.white;
  Color get _sub_color => Colors.grey[400]!;   // renamed from _sub to avoid clash
  Color get _primary   => const Color(0xFF4F46E5);
  Color get _inputFill => const Color(0xFF2D3748);

  Color get _roleColor {
    switch (widget.otherUserRole.toLowerCase()) {
      case 'admin':
      case 'full admin': return Colors.redAccent;
      case 'supervisor':  return Colors.orange;
      default:            return _primary;
    }
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _myUserId   = prefs.getInt('userId');
    if (_myUserId == null) return;

    // Make sure WS is connected
    _chat.connect(_myUserId!);

    // Listen for incoming messages on this conversation
    _sub = _chat.messageStream.listen((ChatMessage msg) {
      final relevant =
          (msg.senderId == widget.otherUserId && msg.receiverId == _myUserId) ||
              (msg.senderId == _myUserId           && msg.receiverId == widget.otherUserId);
      if (!relevant || !mounted) return;

      // Avoid duplicates: skip if we already have this message by id
      final exists = _messages.any((m) => m.id == msg.id && msg.id != -1);
      if (exists) return;

      setState(() {
        // Replace optimistic message (id == -1) with confirmed one
        final optIdx = _messages.indexWhere(
              (m) => m.id == -1 && m.senderId == msg.senderId && m.content == msg.content,
        );
        if (optIdx != -1) {
          _messages[optIdx] = msg;
        } else {
          _messages.add(msg);
        }
      });
      _scrollToBottom();
    });

    // Load history
    final history = await _chat.getHistory(widget.otherUserId);
    if (mounted) {
      setState(() {
        _messages = history;
        _loading  = false;
      });
      _scrollToBottom(delay: true);
    }

    // Mark received messages as read
    await _chat.markRead(widget.otherUserId);
  }

  void _scrollToBottom({bool delay = false}) {
    Future.delayed(Duration(milliseconds: delay ? 200 : 50), () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage() {
    final content = _inputCtrl.text.trim();
    if (content.isEmpty) return;

    _inputCtrl.clear();

    // Optimistic bubble
    final optimistic = ChatMessage(
      id:         -1,
      senderId:   _myUserId!,
      senderName: 'Me',
      receiverId: widget.otherUserId,
      content:    content,
      sentAt:     DateTime.now(),
      isRead:     false,
    );
    setState(() => _messages.add(optimistic));
    _scrollToBottom();

    // Send over STOMP — backend persists + pushes confirmed message back
    _chat.sendMessage(widget.otherUserId, content);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: _appBar(),
      body: Column(children: [
        Expanded(
          child: _loading
              ? Center(child: CircularProgressIndicator(color: _primary))
              : _messageList(),
        ),
        _inputBar(),
      ]),
    );
  }

  PreferredSizeWidget _appBar() => AppBar(
    backgroundColor: _card,
    elevation: 0,
    leading: IconButton(
      icon: Icon(Icons.arrow_back_ios_new, color: _text, size: 20),
      onPressed: () => Navigator.pop(context),
    ),
    titleSpacing: 0,
    title: Row(children: [
      CircleAvatar(
        radius: 18,
        backgroundColor: _roleColor.withOpacity(0.15),
        child: Text(
          widget.otherUserName.isNotEmpty
              ? widget.otherUserName[0].toUpperCase()
              : '?',
          style: TextStyle(
            color: _roleColor,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ),
      const SizedBox(width: 10),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          widget.otherUserName,
          style: TextStyle(
            color: _text,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
        Text(
          widget.otherUserRole,
          style: TextStyle(
            color: _roleColor,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ]),
    ]),
    bottom: PreferredSize(
      preferredSize: const Size.fromHeight(1),
      child: Container(height: 1, color: _border),
    ),
  );

  Widget _messageList() {
    if (_messages.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.chat_bubble_outline, size: 48, color: _sub_color),
          const SizedBox(height: 12),
          Text('No messages yet',
              style: TextStyle(color: _sub_color, fontSize: 14)),
          const SizedBox(height: 4),
          Text(
            'Say hello to ${widget.otherUserName}!',
            style: TextStyle(color: _sub_color.withOpacity(0.6), fontSize: 12),
          ),
        ]),
      );
    }

    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: _messages.length,
      itemBuilder: (_, i) {
        final msg      = _messages[i];
        final isMe     = msg.senderId == _myUserId;
        final showDate = i == 0 ||
            !_sameDay(_messages[i - 1].sentAt, msg.sentAt);
        final showAvatar = !isMe &&
            (i == _messages.length - 1 ||
                _messages[i + 1].senderId == _myUserId);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showDate) _dateDivider(msg.sentAt),
            _bubble(msg, isMe, showAvatar),
          ],
        );
      },
    );
  }

  Widget _dateDivider(DateTime dt) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(children: [
      Expanded(child: Divider(color: _border)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(
          _formatDate(dt),
          style: TextStyle(color: _sub_color, fontSize: 11),
        ),
      ),
      Expanded(child: Divider(color: _border)),
    ]),
  );

  Widget _bubble(ChatMessage msg, bool isMe, bool showAvatar) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment:
        isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            showAvatar
                ? CircleAvatar(
              radius: 14,
              backgroundColor: _roleColor.withOpacity(0.15),
              child: Text(
                widget.otherUserName[0].toUpperCase(),
                style: TextStyle(
                  color: _roleColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
                : const SizedBox(width: 28),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.72,
              ),
              padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isMe ? _primary : _card,
                borderRadius: BorderRadius.only(
                  topLeft:     const Radius.circular(18),
                  topRight:    const Radius.circular(18),
                  bottomLeft:  Radius.circular(isMe ? 18 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 18),
                ),
                border: isMe ? null : Border.all(color: _border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    msg.content,
                    style: TextStyle(
                      color: isMe ? Colors.white : _text,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(
                      _formatTime(msg.sentAt),
                      style: TextStyle(
                        color: isMe
                            ? Colors.white.withOpacity(0.6)
                            : _sub_color,
                        fontSize: 10,
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 4),
                      Icon(
                        msg.id == -1
                            ? Icons.access_time
                            : (msg.isRead ? Icons.done_all : Icons.done),
                        size: 12,
                        color: msg.isRead
                            ? Colors.lightBlueAccent
                            : Colors.white.withOpacity(0.6),
                      ),
                    ],
                  ]),
                ],
              ),
            ),
          ),
          if (isMe) const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _inputBar() => Container(
    padding: EdgeInsets.fromLTRB(
      12,
      8,
      12,
      MediaQuery.of(context).viewInsets.bottom + 12,
    ),
    decoration: BoxDecoration(
      color: _card,
      border: Border(top: BorderSide(color: _border)),
    ),
    child: Row(children: [
      Expanded(
        child: Container(
          decoration: BoxDecoration(
            color: _inputFill,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _border),
          ),
          child: TextField(
            controller: _inputCtrl,
            style: TextStyle(color: _text, fontSize: 14),
            maxLines: 4,
            minLines: 1,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'Message ${widget.otherUserName}...',
              hintStyle: TextStyle(color: _sub_color, fontSize: 14),
              border: InputBorder.none,
              contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            onSubmitted: (_) => _sendMessage(),
          ),
        ),
      ),
      const SizedBox(width: 8),
      GestureDetector(
        onTap: _sendMessage,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _primary,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: _primary.withOpacity(0.4),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
        ),
      ),
    ]),
  );

  // ── Helpers ───────────────────────────────────────────────────────────────
  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _formatTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';

  String _formatDate(DateTime dt) {
    final diff = DateTime.now().difference(dt).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}