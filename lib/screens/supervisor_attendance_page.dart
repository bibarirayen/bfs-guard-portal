import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/ApiService.dart';

class SupervisorAttendancePage extends StatefulWidget {
  const SupervisorAttendancePage({super.key});

  @override
  State<SupervisorAttendancePage> createState() =>
      _SupervisorAttendancePageState();
}

class _SupervisorAttendancePageState
    extends State<SupervisorAttendancePage> {
  // ─── theme ────────────────────────────────────────────────────────────────
  Color get _bg => const Color(0xFF0F172A);
  Color get _card => const Color(0xFF1E293B);
  Color get _text => Colors.white;
  Color get _sub => Colors.grey[400]!;
  Color get _border => const Color(0xFF334155);
  Color get _primary => const Color(0xFF4F46E5);

  // ─── state ────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _records = [];
  bool _loading = true;
  String? _error;
  int? _userId;
  Set<dynamic> _mySiteIds = {};
  List<String> _siteNames = [];

  // ─── filters ──────────────────────────────────────────────────────────────
  String _searchQuery = '';
  String? _selectedSiteFilter;
  String _sortBy = 'date_desc'; // date_desc | date_asc | late_desc

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _userId = prefs.getInt('userId');
    await _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ApiService();
      final sitesRes = await api.get('sites');
      final attendanceRes = await api.get('attendance');

      if (sitesRes.statusCode != 200 || attendanceRes.statusCode != 200) {
        setState(() {
          _error = 'Failed to load data.';
          _loading = false;
        });
        return;
      }

      final List allSites = jsonDecode(sitesRes.body) as List;
      final List allRecords = jsonDecode(attendanceRes.body) as List;

      final mySites = allSites.where((s) {
        final ids = (s['supervisorIds'] as List?)?.cast<dynamic>() ?? [];
        return ids.any((id) => (id as num?)?.toInt() == _userId);
      }).toList();

      final mySiteIds =
          mySites.map((s) => s['id']).toSet();
      final mySiteNames = mySites
          .map((s) => s['name']?.toString() ?? '')
          .where((n) => n.isNotEmpty)
          .toSet()
          .toList()
        ..sort();

      final filtered = allRecords.where((r) {
        final siteId = r['siteId'];
        return siteId != null && mySiteIds.contains(siteId);
      }).map((r) => r as Map<String, dynamic>).toList();

      setState(() {
        _mySiteIds = mySiteIds;
        _siteNames = mySiteNames.cast<String>();
        _records = filtered;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not connect to server.';
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredAndSorted {
    var list = _records.where((r) {
      final matchSearch = _searchQuery.isEmpty ||
          (r['guardName'] ?? '')
              .toString()
              .toLowerCase()
              .contains(_searchQuery.toLowerCase()) ||
          (r['siteName'] ?? '')
              .toString()
              .toLowerCase()
              .contains(_searchQuery.toLowerCase()) ||
          (r['clientName'] ?? '')
              .toString()
              .toLowerCase()
              .contains(_searchQuery.toLowerCase());
      final matchSite = _selectedSiteFilter == null ||
          (r['siteName'] ?? '') == _selectedSiteFilter;
      return matchSearch && matchSite;
    }).toList();

    list.sort((a, b) {
      switch (_sortBy) {
        case 'date_asc':
          return (a['date'] ?? '').compareTo(b['date'] ?? '');
        case 'late_desc':
          final la = (a['lateBy'] as num?)?.toInt() ?? 0;
          final lb = (b['lateBy'] as num?)?.toInt() ?? 0;
          return lb.compareTo(la);
        case 'date_desc':
        default:
          return (b['date'] ?? '').compareTo(a['date'] ?? '');
      }
    });

    return list;
  }

  String _formatDate(String? d) {
    if (d == null || d.isEmpty) return '--';
    try {
      final dt = DateTime.parse(d);
      return '${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}/${dt.year}';
    } catch (_) {
      return d;
    }
  }

  String _formatTime(String? raw) {
    if (raw == null || raw.isEmpty) return '--:--';
    try {
      final parts = raw.split(':');
      int hour = int.parse(parts[0]);
      final int minute = int.parse(parts[1]);
      final String period = hour >= 12 ? 'PM' : 'AM';
      hour = hour % 12;
      if (hour == 0) hour = 12;
      return '$hour:${minute.toString().padLeft(2, '0')} $period';
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _card,
        foregroundColor: _text,
        title: Text('Attendance',
            style: TextStyle(color: _text, fontWeight: FontWeight.bold)),
        elevation: 0,
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: _primary))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, color: Colors.red, size: 48),
                      const SizedBox(height: 12),
                      Text(_error!, style: TextStyle(color: _sub)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                          onPressed: _fetchData,
                          style: ElevatedButton.styleFrom(
                              backgroundColor: _primary),
                          child: const Text('Retry')),
                    ],
                  ),
                )
              : Column(
                  children: [
                    _buildFilters(),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _fetchData,
                        color: _primary,
                        backgroundColor: _card,
                        child: _filteredAndSorted.isEmpty
                            ? ListView(
                                children: [
                                  const SizedBox(height: 80),
                                  Center(
                                    child: Column(
                                      children: [
                                        Icon(Icons.history,
                                            color: _sub, size: 56),
                                        const SizedBox(height: 12),
                                        Text(
                                          'No attendance records found.',
                                          style: TextStyle(
                                              color: _sub, fontSize: 15),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.all(16),
                                itemCount: _filteredAndSorted.length,
                                itemBuilder: (_, i) => _buildCard(
                                    _filteredAndSorted[i]),
                              ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      color: _card,
      child: Column(
        children: [
          // Search bar
          TextField(
            style: TextStyle(color: _text, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Search guard, site, client...',
              hintStyle: TextStyle(color: _sub, fontSize: 13),
              prefixIcon: Icon(Icons.search, color: _sub, size: 18),
              filled: true,
              fillColor: _bg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: _border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: _border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: _primary),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              // Site filter
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: _bg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _border),
                  ),
                  child: DropdownButton<String?>(
                    value: _selectedSiteFilter,
                    hint: Text('All sites',
                        style: TextStyle(color: _sub, fontSize: 12)),
                    isExpanded: true,
                    underline: const SizedBox(),
                    dropdownColor: _card,
                    style: TextStyle(color: _text, fontSize: 12),
                    items: [
                      DropdownMenuItem<String?>(
                          value: null,
                          child: Text('All sites',
                              style: TextStyle(color: _text))),
                      ..._siteNames.map((s) => DropdownMenuItem<String?>(
                          value: s,
                          child:
                              Text(s, style: TextStyle(color: _text)))),
                    ],
                    onChanged: (v) =>
                        setState(() => _selectedSiteFilter = v),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Sort
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: _bg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _border),
                ),
                child: DropdownButton<String>(
                  value: _sortBy,
                  underline: const SizedBox(),
                  dropdownColor: _card,
                  style: TextStyle(color: _text, fontSize: 12),
                  items: const [
                    DropdownMenuItem(
                        value: 'date_desc',
                        child: Text('Newest first')),
                    DropdownMenuItem(
                        value: 'date_asc', child: Text('Oldest first')),
                    DropdownMenuItem(
                        value: 'late_desc',
                        child: Text('Most late first')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _sortBy = v);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${_filteredAndSorted.length} record(s)',
              style: TextStyle(color: _sub, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> r) {
    final lateBy = (r['lateBy'] as num?)?.toInt() ?? 0;
    final isLate = lateBy > 0;
    final totalHours = (r['totalHours'] as num?)?.toStringAsFixed(1) ?? '--';
    final timeOut = r['timeOut'];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isLate
              ? const Color(0xFFEF4444).withOpacity(0.4)
              : _border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r['guardName'] ?? '--',
                      style: TextStyle(
                          color: _text,
                          fontWeight: FontWeight.bold,
                          fontSize: 14),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${r['siteName'] ?? '--'} · ${r['clientName'] ?? ''}',
                      style: TextStyle(color: _sub, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (isLate)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Late ${lateBy}m',
                    style: const TextStyle(
                        color: Color(0xFFEF4444),
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _pill(Icons.calendar_today,
                  _formatDate(r['date']?.toString()), _primary),
              const SizedBox(width: 8),
              _pill(Icons.login, _formatTime(r['timeIn']?.toString()),
                  Colors.green),
              const SizedBox(width: 8),
              _pill(
                  Icons.logout,
                  timeOut != null && timeOut.toString().isNotEmpty
                      ? _formatTime(timeOut.toString())
                      : 'On duty',
                  timeOut != null ? Colors.orange : Colors.blueGrey),
              const Spacer(),
              if (timeOut != null)
                Text(
                  '${totalHours}h',
                  style: TextStyle(
                      color: _primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 13),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pill(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 12),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(color: color, fontSize: 11)),
      ],
    );
  }
}
