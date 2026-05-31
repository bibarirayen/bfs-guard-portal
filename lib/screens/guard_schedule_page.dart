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

  Color get _bg => const Color(0xFF0F172A);
  Color get _card => const Color(0xFF1E293B);
  Color get _text => Colors.white;
  Color get _muted => const Color(0xFF94A3B8);
  Color get _line => const Color(0xFF334155);

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
      setState(() {
        _guardName = (body['guardName'] ?? '').toString();
        _assignments = rows.map((e) => Map<String, dynamic>.from(e as Map)).toList();
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
                    color: _muted.withOpacity(0.4),
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
          color: enabled ? const Color(0xFF1D4ED8).withOpacity(0.15) : const Color(0xFF334155).withOpacity(0.4),
          border: Border.all(color: enabled ? const Color(0xFF2563EB).withOpacity(0.35) : _line),
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
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: _line),
                          gradient: const LinearGradient(
                            colors: [Color(0xFF1E293B), Color(0xFF111827)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: const Color(0xFF3B82F6).withOpacity(0.18),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(Icons.calendar_month, color: Color(0xFF93C5FD)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_guardName.isEmpty ? 'Guard Schedule' : _guardName, style: TextStyle(color: _text, fontWeight: FontWeight.w700, fontSize: 16)),
                                  const SizedBox(height: 3),
                                  Text('${_assignments.length} assignment(s)', style: TextStyle(color: _muted, fontSize: 13)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
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
                      ..._assignments.map((item) {
                        final shift = Map<String, dynamic>.from(item['shift'] ?? {});
                        final site = Map<String, dynamic>.from(item['site'] ?? {});
                        final active = (item['active'] == true);
                        final days = List<dynamic>.from(item['daysOfWeek'] ?? []);

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: InkWell(
                            onTap: () => _showDetails(item),
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: _card,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: active ? const Color(0xFF10B981) : _line, width: active ? 1.2 : 1),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          (site['name'] ?? 'Unknown Site').toString(),
                                          style: TextStyle(color: _text, fontWeight: FontWeight.w700, fontSize: 15),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                                        decoration: BoxDecoration(
                                          color: active ? const Color(0xFF10B981).withOpacity(0.2) : const Color(0xFF334155),
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        child: Text(active ? 'ACTIVE' : 'SCHEDULED', style: TextStyle(color: active ? const Color(0xFF86EFAC) : _muted, fontWeight: FontWeight.w700, fontSize: 11)),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '${_fmtDate(item['fromDate']?.toString())}  →  ${_fmtDate(item['toDate']?.toString())}',
                                    style: TextStyle(color: _muted, fontSize: 13),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${_toAmPm(shift['startTime']?.toString())} - ${_toAmPm(shift['endTime']?.toString())}',
                                    style: const TextStyle(color: Color(0xFF93C5FD), fontWeight: FontWeight.w600, fontSize: 13),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(_compactDays(days), style: TextStyle(color: _muted, fontSize: 12)),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
    );
  }
}
