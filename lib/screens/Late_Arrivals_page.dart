import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config/ApiService.dart';

/// Displayed when a supervisor taps the "Late Arrivals" notification or
/// the dashboard button.  Fetches all attendance records where lateBy > 0.
class LateArrivalsPage extends StatefulWidget {
  const LateArrivalsPage({super.key});

  @override
  State<LateArrivalsPage> createState() => _LateArrivalsPageState();
}

class _LateArrivalsPageState extends State<LateArrivalsPage> {
  // ─── theme ───────────────────────────────────────────────────────────────
  final bool _isDarkMode = true;
  Color get _bg      => const Color(0xFF0F172A);
  Color get _card    => const Color(0xFF1E293B);
  Color get _text    => Colors.white;
  Color get _sub     => Colors.grey[400]!;
  Color get _border  => const Color(0xFF334155);

  // ─── state ───────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _records = [];
  bool _loading = true;
  String? _error;

  // ─── filter / sort ───────────────────────────────────────────────────────
  String _searchQuery = '';
  String _sortBy = 'date_desc'; // date_desc | date_asc | late_desc | name_asc

  @override
  void initState() {
    super.initState();
    _fetchLateArrivals();
  }

  // ─── data ─────────────────────────────────────────────────────────────────
  Future<void> _fetchLateArrivals() async {
    setState(() {
      _loading = true;
      _error   = null;
    });
    try {
      final api      = ApiService();
      final response = await api.get('attendance/late');

      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        setState(() {
          _records = data.cast<Map<String, dynamic>>();
          _loading = false;
        });
      } else {
        setState(() {
          _error   = 'Server error ${response.statusCode}';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error   = 'Could not connect to server.';
        _loading = false;
      });
    }
  }

  // ─── helpers ─────────────────────────────────────────────────────────────
  String _formatTime(String? raw) {
    if (raw == null || raw.isEmpty) return '--:--';
    try {
      final parts = raw.split(':');
      int hour = int.parse(parts[0]);
      final int minute = int.parse(parts[1]);
      final String period = hour >= 12 ? 'PM' : 'AM';
      hour = hour % 12;
      if (hour == 0) hour = 12;
      return '${hour}:${minute.toString().padLeft(2, '0')} $period';
    } catch (_) {
      return raw;
    }
  }

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '–';
    try {
      final d = DateTime.parse(raw);
      return DateFormat('MMM d, yyyy').format(d);
    } catch (_) {
      return raw;
    }
  }

  String _lateLabel(int? mins) {
    if (mins == null) return '';
    if (mins < 60) return '$mins min late';
    final h = mins ~/ 60;
    final m = mins % 60;
    return m == 0 ? '${h}h late' : '${h}h ${m}m late';
  }

  Color _lateColor(int? mins) {
    if (mins == null || mins == 0) return Colors.grey;
    if (mins <= 15) return const Color(0xFFF59E0B);   // amber  – slightly late
    if (mins <= 60) return const Color(0xFFEF4444);   // red    – late
    return const Color(0xFF7C3AED);                    // purple – very late
  }

  List<Map<String, dynamic>> get _filtered {
    var list = _records.where((r) {
      final name = (r['guardName'] ?? '').toString().toLowerCase();
      final site = (r['siteName'] ?? '').toString().toLowerCase();
      final q    = _searchQuery.toLowerCase();
      return name.contains(q) || site.contains(q);
    }).toList();

    switch (_sortBy) {
      case 'date_asc':
        list.sort((a, b) => (a['date'] ?? '').compareTo(b['date'] ?? ''));
        break;
      case 'date_desc':
        list.sort((a, b) => (b['date'] ?? '').compareTo(a['date'] ?? ''));
        break;
      case 'late_desc':
        list.sort((a, b) =>
            ((b['lateBy'] ?? 0) as int).compareTo((a['lateBy'] ?? 0) as int));
        break;
      case 'name_asc':
        list.sort((a, b) =>
            (a['guardName'] ?? '').compareTo(b['guardName'] ?? ''));
        break;
    }
    return list;
  }

  // ─── build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _card,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.warning_amber_rounded,
                  color: Color(0xFFEF4444), size: 20),
            ),
            const SizedBox(width: 10),
            const Text('Late Arrivals',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: _fetchLateArrivals,
            tooltip: 'Refresh',
          ),
        ],
        elevation: 0,
      ),
      body: Column(
        children: [
          _buildSearchAndSort(),
          if (!_loading && _error == null)
            _buildSummaryBanner(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  // ─── search + sort bar ───────────────────────────────────────────────────
  Widget _buildSearchAndSort() {
    return Container(
      color: _card,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        children: [
          // search field
          TextField(
            style: TextStyle(color: _text),
            decoration: InputDecoration(
              hintText: 'Search by guard or site…',
              hintStyle: TextStyle(color: _sub),
              prefixIcon: Icon(Icons.search, color: _sub),
              filled: true,
              fillColor: _bg,
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
          const SizedBox(height: 10),
          // sort chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _sortChip('Most Recent',   'date_desc'),
                _sortChip('Oldest First',  'date_asc'),
                _sortChip('Most Late',     'late_desc'),
                _sortChip('Name A–Z',      'name_asc'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sortChip(String label, String value) {
    final selected = _sortBy == value;
    return GestureDetector(
      onTap: () => setState(() => _sortBy = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFFEF4444)
              : _bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? const Color(0xFFEF4444) : _border),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected ? Colors.white : _sub,
                fontSize: 12,
                fontWeight:
                selected ? FontWeight.bold : FontWeight.normal)),
      ),
    );
  }

  // ─── summary banner ───────────────────────────────────────────────────────
  Widget _buildSummaryBanner() {
    final total     = _filtered.length;
    final avgLate   = total == 0
        ? 0
        : (_filtered
        .map((r) => (r['lateBy'] ?? 0) as int)
        .reduce((a, b) => a + b)) ~/
        total;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFEF4444), Color(0xFFB91C1C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFFEF4444).withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _statItem(total.toString(), 'Late Guards'),
          Container(width: 1, height: 40, color: Colors.white30),
          _statItem('$avgLate min', 'Avg Delay'),
        ],
      ),
    );
  }

  Widget _statItem(String value, String label) => Column(
    children: [
      Text(value,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold)),
      const SizedBox(height: 2),
      Text(label,
          style: TextStyle(
              color: Colors.white.withOpacity(0.8), fontSize: 12)),
    ],
  );

  // ─── body ─────────────────────────────────────────────────────────────────
  Widget _buildBody() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFFEF4444)));
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off_rounded,
                color: Colors.redAccent, size: 48),
            const SizedBox(height: 12),
            Text(_error!,
                style: TextStyle(color: _sub, fontSize: 15)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _fetchLateArrivals,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEF4444)),
            ),
          ],
        ),
      );
    }
    if (_filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline_rounded,
                color: const Color(0xFF10B981), size: 64),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isEmpty
                  ? 'No late arrivals recorded.'
                  : 'No results for "$_searchQuery".',
              style: TextStyle(color: _sub, fontSize: 15),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchLateArrivals,
      color: const Color(0xFFEF4444),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        itemCount: _filtered.length,
        itemBuilder: (ctx, i) => _buildCard(_filtered[i]),
      ),
    );
  }

  // ─── card ─────────────────────────────────────────────────────────────────
  Widget _buildCard(Map<String, dynamic> r) {
    final lateBy    = r['lateBy'] as int?;
    final lateColor = _lateColor(lateBy);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          // ── header row ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                // avatar
                CircleAvatar(
                  radius: 22,
                  backgroundColor: lateColor.withOpacity(0.15),
                  child: Text(
                    (r['guardName'] ?? '?')[0].toUpperCase(),
                    style: TextStyle(
                        color: lateColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 18),
                  ),
                ),
                const SizedBox(width: 12),
                // name + employee id
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r['guardName'] ?? '–',
                          style: TextStyle(
                              color: _text,
                              fontWeight: FontWeight.bold,
                              fontSize: 15)),
                      Text(
                        'ID: ${r['guardEmployeeId'] ?? '–'}',
                        style: TextStyle(color: _sub, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                // late badge
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: lateColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: lateColor.withOpacity(0.4)),
                  ),
                  child: Text(
                    _lateLabel(lateBy),
                    style: TextStyle(
                        color: lateColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),
          Divider(color: _border, height: 1),

          // ── detail rows ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: Column(
              children: [
                _detailRow(Icons.business_rounded,  'Client', r['clientName']),
                const SizedBox(height: 6),
                _detailRow(Icons.location_on_rounded, 'Site',  r['siteName']),
                const SizedBox(height: 6),
                _detailRow(Icons.calendar_today_rounded, 'Date',
                    _formatDate(r['date'])),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: _detailRow(
                          Icons.login_rounded, 'Time In', _formatTime(r['timeIn'])),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _detailRow(
                          Icons.logout_rounded, 'Time Out',
                          _formatTime(r['timeOut'])),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String? value) {
    return Row(
      children: [
        Icon(icon, size: 14, color: _sub),
        const SizedBox(width: 6),
        Text('$label: ',
            style: TextStyle(color: _sub, fontSize: 12)),
        Text(value ?? '–',
            style: TextStyle(
                color: _text,
                fontSize: 13,
                fontWeight: FontWeight.w500)),
      ],
    );
  }
}