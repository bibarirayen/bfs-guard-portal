// lib/screens/conversations_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/chat_service.dart';
import 'chat_screen.dart';

class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key});

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  final _chat = ChatService();

  int?   _myUserId;
  String _myName = '';

  List<Conversation>         _conversations = [];
  List<Map<String, dynamic>> _allUsers      = [];
  bool _loadingConvs = true;
  bool _loadingUsers = false;

  StreamSubscription<ChatMessage>? _msgSub;

  // ── Theme ─────────────────────────────────────────────────────────────────
  Color get _bg      => const Color(0xFF0F172A);
  Color get _card    => const Color(0xFF1E293B);
  Color get _border  => const Color(0xFF334155);
  Color get _text    => Colors.white;
  Color get _sub     => Colors.grey[400]!;
  Color get _primary => const Color(0xFF4F46E5);

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _myUserId = prefs.getInt('userId');
    _myName   = prefs.getString('guardName') ?? '';

    if (_myUserId == null) return;

    _chat.connect(_myUserId!);

    _msgSub = _chat.messageStream.listen((_) {
      if (mounted) _loadConversations();
    });

    _loadConversations();
  }

  Future<void> _loadConversations() async {
    setState(() => _loadingConvs = true);
    final convs = await _chat.getConversations();
    if (mounted) setState(() { _conversations = convs; _loadingConvs = false; });
  }

  Future<void> _openNewChatSheet() async {
    setState(() => _loadingUsers = true);
    final users = await _chat.getChatUsers();
    if (mounted) setState(() { _allUsers = users; _loadingUsers = false; });

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: _card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _NewChatSheet(
        users: _allUsers,
        myUserId: _myUserId ?? 0,
        loading: _loadingUsers,
        card: _card, border: _border, text: _text, sub: _sub, primary: _primary,
        onSelect: (u) {
          Navigator.pop(context);
          _openChat(u);
        },
      ),
    );
  }

  void _openChat(Map<String, dynamic> user) {
    final name = '${user['firstName']} ${user['lastName']}';
    final role = (user['roles'] as List?)?.isNotEmpty == true
        ? user['roles'][0] as String
        : 'Guard';
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          otherUserId:   user['id'],
          otherUserName: name,
          otherUserRole: role,
        ),
      ),
    ).then((_) => _loadConversations());
  }

  void _openChatFromConversation(Conversation conv) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          otherUserId:   conv.userId,
          otherUserName: conv.userName,
          otherUserRole: conv.userRole,
        ),
      ),
    ).then((_) => _loadConversations());
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ── AppBar removed — title is already shown by HomeScreen's CustomAppBar ──
    return Scaffold(
      backgroundColor: _bg,
      body: _loadingConvs
          ? Center(child: CircularProgressIndicator(color: _primary))
          : _conversations.isEmpty
          ? _emptyState()
          : RefreshIndicator(
        color: _primary,
        onRefresh: _loadConversations,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: _conversations.length,
          separatorBuilder: (_, __) =>
              Divider(height: 1, color: _border, indent: 76),
          itemBuilder: (_, i) => _tile(_conversations[i]),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: _primary,
        onPressed: _openNewChatSheet,
        child: const Icon(Icons.chat_bubble_outline, color: Colors.white),
      ),
    );
  }

  Widget _emptyState() => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.chat_bubble_outline, size: 64, color: _sub),
      const SizedBox(height: 16),
      Text('No conversations yet',
          style: TextStyle(color: _text, fontSize: 18, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Text('Tap the button below to start a chat',
          style: TextStyle(color: _sub, fontSize: 14)),
      const SizedBox(height: 24),
      ElevatedButton.icon(
        onPressed: _openNewChatSheet,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('New Message',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(
          backgroundColor: _primary,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    ]),
  );

  Widget _tile(Conversation conv) {
    final hasUnread = conv.unreadCount > 0;
    final roleColor = _roleColor(conv.userRole);

    return ListTile(
      onTap: () => _openChatFromConversation(conv),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Stack(children: [
        CircleAvatar(
          radius: 26,
          backgroundColor: roleColor.withOpacity(0.15),
          child: Text(
            conv.userName.isNotEmpty ? conv.userName[0].toUpperCase() : '?',
            style: TextStyle(
                color: roleColor, fontSize: 18, fontWeight: FontWeight.w700),
          ),
        ),
        if (hasUnread)
          Positioned(
            right: 0, top: 0,
            child: Container(
              width: 16, height: 16,
              decoration: BoxDecoration(
                  color: _primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: _card, width: 2)),
              child: Center(
                child: Text(
                  conv.unreadCount > 9 ? '9+' : '${conv.unreadCount}',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 8, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
      ]),
      title: Row(children: [
        Expanded(child: Text(conv.userName,
            style: TextStyle(
                color: _text,
                fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w500,
                fontSize: 15))),
        if (conv.lastMessageTime != null)
          Text(_formatTime(conv.lastMessageTime!),
              style: TextStyle(
                  color: hasUnread ? _primary : _sub, fontSize: 11)),
      ]),
      subtitle: Row(children: [
        Expanded(child: Text(
          conv.lastMessage ?? 'No messages yet',
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(
              color: hasUnread ? _text : _sub,
              fontWeight: hasUnread ? FontWeight.w500 : FontWeight.normal,
              fontSize: 13),
        )),
        const SizedBox(width: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
              color: roleColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8)),
          child: Text(conv.userRole,
              style: TextStyle(
                  color: roleColor, fontSize: 10, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }

  Color _roleColor(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
      case 'full admin': return Colors.redAccent;
      case 'supervisor':  return Colors.orange;
      default:            return _primary;
    }
  }

  String _formatTime(DateTime dt) {
    // Compare against Hawaii "now" since all times are stored/parsed as Hawaii time
    final hawaiiNow = DateTime.now().toUtc().subtract(const Duration(hours: 10));
    final diff = hawaiiNow.difference(dt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inHours < 1)   return '\${diff.inMinutes}m';
    if (diff.inDays < 1)    return '\${diff.inHours}h';
    if (diff.inDays < 7)    return '\${diff.inDays}d';
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    return '\$h:\$m \$period';
  }
}

// ─── New Chat Bottom Sheet ────────────────────────────────────────────────────
class _NewChatSheet extends StatefulWidget {
  final List<Map<String, dynamic>> users;
  final int myUserId;
  final bool loading;
  final Color card, border, text, sub, primary;
  final void Function(Map<String, dynamic>) onSelect;

  const _NewChatSheet({
    required this.users, required this.myUserId, required this.loading,
    required this.card, required this.border, required this.text,
    required this.sub, required this.primary, required this.onSelect,
  });

  @override
  State<_NewChatSheet> createState() => _NewChatSheetState();
}

class _NewChatSheetState extends State<_NewChatSheet> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.users
        .where((u) => u['id'] != widget.myUserId)
        .where((u) {
      final name =
      '${u['firstName'] ?? ''} ${u['lastName'] ?? ''}'.toLowerCase();
      return name.contains(_search.toLowerCase());
    })
        .toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      builder: (_, ctrl) => Column(children: [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 10),
          width: 36, height: 4,
          decoration: BoxDecoration(
              color: widget.border, borderRadius: BorderRadius.circular(2)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('New Message',
              style: TextStyle(
                  color: widget.text, fontSize: 17, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            style: TextStyle(color: widget.text),
            decoration: InputDecoration(
              hintText: 'Search by name...',
              hintStyle: TextStyle(color: widget.sub),
              prefixIcon: Icon(Icons.search, color: widget.sub),
              filled: true,
              fillColor: widget.border.withOpacity(0.3),
              contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none),
            ),
            onChanged: (v) => setState(() => _search = v),
          ),
        ),
        const SizedBox(height: 8),
        Divider(color: widget.border),
        Expanded(
          child: widget.loading
              ? Center(child: CircularProgressIndicator(color: widget.primary))
              : filtered.isEmpty
              ? Center(
              child: Text('No users found',
                  style: TextStyle(color: widget.sub)))
              : ListView.builder(
            controller: ctrl,
            itemCount: filtered.length,
            itemBuilder: (_, i) {
              final u = filtered[i];
              final name =
                  '${u['firstName'] ?? ''} ${u['lastName'] ?? ''}';
              final roles = u['roles'] as List?;
              final role = roles?.isNotEmpty == true
                  ? roles![0] as String
                  : 'Guard';
              return ListTile(
                onTap: () => widget.onSelect(u),
                leading: CircleAvatar(
                  backgroundColor:
                  widget.primary.withOpacity(0.15),
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: TextStyle(
                        color: widget.primary,
                        fontWeight: FontWeight.w700),
                  ),
                ),
                title: Text(name,
                    style: TextStyle(
                        color: widget.text,
                        fontWeight: FontWeight.w500)),
                subtitle: Text(role,
                    style: TextStyle(
                        color: widget.sub, fontSize: 12)),
                trailing:
                Icon(Icons.chevron_right, color: widget.sub),
              );
            },
          ),
        ),
      ]),
    );
  }
}