import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/ApiService.dart';

class GuardSchedulePage extends StatefulWidget {
  const GuardSchedulePage({super.key});

  @override
  State<GuardSchedulePage> createState() => _GuardSchedulePageState();
}

class _GuardSchedulePageState extends State<GuardSchedulePage> {
  bool _loading = true;
  String _guardName = '';
  String? _error;
  List<Map<String, dynamic>> _assignments = [];
  DateTime? _selectedDate;

  Color get _bg => const Color(0xFF0F172A);
  Color get _card => const Color(0xFF1E293B);
  Color get _text => Colors.white;
  Color get _muted => const Color(0xFF94A3B8);
  Color get _line => const Color(0xFF334155);
  Color get _accent => const Color(0xFF38BDF8);

  @override
  void initState() {
    super.initState();
    _loadSchedule();
  }

  Future<void> _loadSchedule() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final guardId = prefs.getInt('userId');
      if (guardId == null) {
        throw Exception('User not found in session');
      }

      final api = ApiService();
      final res = await api.get('assignments/guard-schedule/$guardId');
      if (res.statusCode != 200) {
        throw Exception('Failed to load schedule (${res.statusCode})');
      }

      final Map<String, dynamic> body = jsonDecode(res.body);
      final List<dynamic> rows = body['assignments'] ?? [];
      final assignments = rows.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      setState(() {
        _guardName = (body['guardName'] ?? '').toString();
        _assignments = assignments;
        _selectedDate = _pickInitialDate(assignments);
      });
    } catch (e) {
      setState(() {
        _error = ApiService.friendlyError(e);
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  String _toAmPm(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return '-';
    final parts = timeStr.split(':');
    if (parts.length < 2) return timeStr;
    int hour = int.tryParse(parts[0]) ?? 0;
    final minute = int.tryParse(parts[1]) ?? 0;
    final period = hour >= 12 ? 'PM' : 'AM';
    int displayHour = hour % 12;
    if (displayHour == 0) displayHour = 12;
    return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
  }

  String _fmtDate(String? yyyyMmDd) {
    if (yyyyMmDd == null || yyyyMmDd.isEmpty) return '-';
    try {
      final d = DateTime.parse(yyyyMmDd);
      return '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}/${d.year}';
    } catch (_) {
      return yyyyMmDd;
    }
  }

  String _compactDays(List<dynamic> days) {
    if (days.isEmpty || days.length == 7) return 'Every day';
    const map = {
      'MONDAY': 'Mon',
      'TUESDAY': 'Tue',
      'WEDNESDAY': 'Wed',
      'THURSDAY': 'Thu',
      'FRIDAY': 'Fri',
      'SATURDAY': 'Sat',
      'SUNDAY': 'Sun',
    };
    return days.map((d) => map[d.toString()] ?? d.toString()).join(' • ');
  }

  DateTime? _parseDate(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      return DateTime.parse(value);
    } catch (_) {
      return null;
    }
  }

  bool _sameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  DateTime? _pickInitialDate(List<Map<String, dynamic>> assignments) {
    final dates = assignments
        .map((item) => _parseDate(item['fromDate']?.toString()))
        .whereType<DateTime>()
        .toList()
      ..sort();

    if (dates.isEmpty) return null;

    final today = DateTime.now();
    for (final date in dates) {
      if (!date.isBefore(DateTime(today.year, today.month, today.day))) {
        return date;
      }
    }
    return dates.first;
  }

  List<DateTime> get _scheduleDates {
    final seen = <String>{};
    final dates = <DateTime>[];
    for (final item in _assignments) {
      final date = _parseDate(item['fromDate']?.toString());
      if (date == null) continue;
      final key = '${date.year}-${date.month}-${date.day}';
      if (seen.add(key)) dates.add(date);
    }
    dates.sort();
    return dates;
  }

  List<Map<String, dynamic>> get _visibleAssignments {
    if (_selectedDate == null) return _assignments;
    return _assignments.where((item) {
      final date = _parseDate(item['fromDate']?.toString());
      return date != null && _sameDate(date, _selectedDate!);
    }).toList();
  }

  String _weekdayShort(DateTime date) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[date.weekday - 1];
  }

  String _monthTitle(DateTime? date) {
    if (date == null) return 'Schedule';
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${months[date.month - 1]} ${date.year}';
  }

  String _selectedDateLabel() {
    if (_selectedDate == null) return 'All assignments';
    final today = DateTime.now();
    if (_sameDate(_selectedDate!, DateTime(today.year, today.month, today.day))) {
      return 'Today';
    }
    return '${_weekdayShort(_selectedDate!)} ${_fmtDate(_selectedDate!.toIso8601String())}';
  }

  Future<void> _openMap(double? lat, double? lng) async {
    if (lat == null || lng == null) return;
    final Uri url = Platform.isIOS
        ? Uri.parse('https://maps.apple.com/?q=$lat,$lng&ll=$lat,$lng&z=15')
        : Uri.parse('https://maps.google.com/maps?q=$lat,$lng');
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Future<void> _openDialer(String? phone) async {
    if (phone == null || phone.trim().isEmpty) return;
    final clean = phone.replaceAll(' ', '');
    await launchUrl(Uri.parse('tel:$clean'));
  }

  Future<void> _openEmail(String? email) async {
    if (email == null || email.trim().isEmpty) return;
    await launchUrl(Uri.parse('mailto:$email'));
  }

  void _showDetails(Map<String, dynamic> item) {
    final shift = Map<String, dynamic>.from(item['shift'] ?? {});
    final site = Map<String, dynamic>.from(item['site'] ?? {});
    final days = List<dynamic>.from(item['daysOfWeek'] ?? []);

    final supervisorName = (site['supervisorName'] ?? '').toString();
    final supervisorPhone = (site['supervisorPhone'] ?? '').toString();
    final supervisorEmail = (site['supervisorEmail'] ?? '').toString();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.72,
        minChildSize: 0.45,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, controller) => Container(
          decoration: BoxDecoration(
            color: _card,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
            children: [
              Center(
                child: Container(
                  width: 52,
                  height: 5,
                  decoration: BoxDecoration(
                    color: _muted.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                (site['name'] ?? 'Assignment details').toString(),
                style: TextStyle(color: _text, fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              _detailTile(Icons.event, 'Date', '${_fmtDate(item['fromDate']?.toString())}  →  ${_fmtDate(item['toDate']?.toString())}'),
              _detailTile(Icons.schedule, 'Time', '${_toAmPm(shift['startTime']?.toString())}  -  ${_toAmPm(shift['endTime']?.toString())}'),
              _detailTile(Icons.repeat, 'Pattern', _compactDays(days)),
              if ((shift['specialInstructions'] ?? '').toString().trim().isNotEmpty)
                _detailTile(Icons.info_outline, 'Instructions', shift['specialInstructions'].toString()),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _line),
                  color: const Color(0xFF0B1220),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Supervisor Contact', style: TextStyle(color: _text, fontWeight: FontWeight.w700, fontSize: 14)),
                    const SizedBox(height: 10),
                    Text(supervisorName.isEmpty ? 'Not assigned' : supervisorName, style: TextStyle(color: _text, fontSize: 14)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _actionChip(icon: Icons.map_outlined, label: 'Open Map', onTap: () => _openMap((site['latitude'] as num?)?.toDouble(), (site['longitude'] as num?)?.toDouble())),
                        _actionChip(icon: Icons.call_outlined, label: 'Call', onTap: supervisorPhone.isEmpty ? null : () => _openDialer(supervisorPhone)),
                        _actionChip(icon: Icons.email_outlined, label: 'Email', onTap: supervisorEmail.isEmpty ? null : () => _openEmail(supervisorEmail)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailTile(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: const Color(0xFF60A5FA)),
          const SizedBox(width: 10),
          SizedBox(
            width: 92,
            child: Text(label, style: TextStyle(color: _muted, fontSize: 13)),
          ),
          Expanded(
            child: Text(value, style: TextStyle(color: _text, fontSize: 14, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _actionChip({required IconData icon, required String label, VoidCallback? onTap}) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: enabled ? const Color(0xFF1D4ED8).withValues(alpha: 0.15) : const Color(0xFF334155).withValues(alpha: 0.4),
          border: Border.all(color: enabled ? const Color(0xFF2563EB).withValues(alpha: 0.35) : _line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: enabled ? const Color(0xFF93C5FD) : _muted),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: enabled ? _text : _muted, fontWeight: FontWeight.w600, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildDateChip(DateTime date) {
    final selected = _selectedDate != null && _sameDate(_selectedDate!, date);
    return GestureDetector(
      onTap: () => setState(() => _selectedDate = date),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 68,
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? _accent : _line),
          gradient: selected
              ? const LinearGradient(
                  colors: [Color(0xFF0EA5E9), Color(0xFF2563EB)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: selected ? null : _card,
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: const Color(0xFF0EA5E9).withValues(alpha: 0.25),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  )
                ]
              : null,
        ),
        child: Column(
          children: [
            Text(
              _weekdayShort(date),
              style: TextStyle(
                color: selected ? Colors.white : _muted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${date.day}',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAgendaCard(Map<String, dynamic> item) {
    final shift = Map<String, dynamic>.from(item['shift'] ?? {});
    final site = Map<String, dynamic>.from(item['site'] ?? {});
    final active = item['active'] == true;
    final days = List<dynamic>.from(item['daysOfWeek'] ?? []);
    final supervisor = (site['supervisorName'] ?? '').toString();

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        onTap: () => _showDetails(item),
        borderRadius: BorderRadius.circular(22),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: active ? const Color(0xFF10B981) : _line),
            gradient: const LinearGradient(
              colors: [Color(0xFF172033), Color(0xFF111827)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: active ? const Color(0xFF10B981) : _accent,
                        boxShadow: [
                          BoxShadow(
                            color: (active ? const Color(0xFF10B981) : _accent).withValues(alpha: 0.4),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 2,
                      height: 84,
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      color: _line,
                    ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${_toAmPm(shift['startTime']?.toString())} - ${_toAmPm(shift['endTime']?.toString())}',
                                  style: const TextStyle(
                                    color: Color(0xFF7DD3FC),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  (site['name'] ?? 'Unknown Site').toString(),
                                  style: TextStyle(
                                    color: _text,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 17,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: active ? const Color(0xFF10B981).withValues(alpha: 0.18) : const Color(0xFF0EA5E9).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              active ? 'ON DUTY' : 'UPCOMING',
                              style: TextStyle(
                                color: active ? const Color(0xFF86EFAC) : const Color(0xFF7DD3FC),
                                fontWeight: FontWeight.w800,
                                fontSize: 10,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _metaPill(Icons.event_outlined, '${_fmtDate(item['fromDate']?.toString())} → ${_fmtDate(item['toDate']?.toString())}'),
                          _metaPill(Icons.repeat, _compactDays(days)),
                          if (supervisor.isNotEmpty) _metaPill(Icons.support_agent, supervisor),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          TextButton.icon(
                            onPressed: () => _openMap((site['latitude'] as num?)?.toDouble(), (site['longitude'] as num?)?.toDouble()),
                            icon: const Icon(Icons.location_on_outlined, size: 18),
                            label: const Text('Location'),
                            style: TextButton.styleFrom(foregroundColor: _accent),
                          ),
                          const SizedBox(width: 6),
                          TextButton.icon(
                            onPressed: () => _showDetails(item),
                            icon: const Icon(Icons.read_more_outlined, size: 18),
                            label: const Text('Details'),
                            style: TextButton.styleFrom(foregroundColor: Colors.white),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _metaPill(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: _muted),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(color: _muted, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('My Schedule'),
        backgroundColor: _card,
        foregroundColor: _text,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF3B82F6)))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, color: Color(0xFFF87171), size: 34),
                        const SizedBox(height: 8),
                        Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: _muted)),
                        const SizedBox(height: 14),
                        ElevatedButton(onPressed: _loadSchedule, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadSchedule,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: _line),
                          gradient: const LinearGradient(
                            colors: [Color(0xFF132238), Color(0xFF0F172A), Color(0xFF111827)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _monthTitle(_selectedDate),
                              style: TextStyle(color: _muted, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1.1),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _guardName.isEmpty ? 'Guard Schedule' : _guardName,
                              style: TextStyle(color: _text, fontWeight: FontWeight.w800, fontSize: 22),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${_assignments.length} assignment(s) planned • ${_selectedDateLabel()}',
                              style: TextStyle(color: _muted, fontSize: 13),
                            ),
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.04),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: _line),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Selected Day', style: TextStyle(color: _muted, fontSize: 11)),
                                        const SizedBox(height: 4),
                                        Text(_selectedDateLabel(), style: TextStyle(color: _text, fontWeight: FontWeight.w700)),
                                      ],
                                    ),
                                  ),
                                  Container(width: 1, height: 34, color: _line),
                                  const SizedBox(width: 14),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Agenda', style: TextStyle(color: _muted, fontSize: 11)),
                                      const SizedBox(height: 4),
                                      Text('${_visibleAssignments.length} item(s)', style: TextStyle(color: _accent, fontWeight: FontWeight.w800)),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (_scheduleDates.isNotEmpty) ...[
                        Text('Calendar', style: TextStyle(color: _text, fontWeight: FontWeight.w700, fontSize: 16)),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 96,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: _scheduleDates.map(_buildDateChip).toList(),
                          ),
                        ),
                        const SizedBox(height: 18),
                      ],
                      Row(
                        children: [
                          Text('Agenda', style: TextStyle(color: _text, fontWeight: FontWeight.w800, fontSize: 18)),
                          const Spacer(),
                          Text(_selectedDateLabel(), style: TextStyle(color: _muted, fontSize: 12, fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_assignments.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            color: _card,
                            border: Border.all(color: _line),
                          ),
                          child: Text('No assignments found.', style: TextStyle(color: _muted)),
                        ),
                      if (_assignments.isNotEmpty && _visibleAssignments.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            color: _card,
                            border: Border.all(color: _line),
                          ),
                          child: Text('No assignments on this day.', style: TextStyle(color: _muted)),
                        ),
                      ..._visibleAssignments.map(_buildAgendaCard),
                    ],
                  ),
                ),
    );
  }
}
