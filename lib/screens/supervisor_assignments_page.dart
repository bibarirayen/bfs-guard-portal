import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/ApiService.dart';

class SupervisorAssignmentsPage extends StatefulWidget {
  const SupervisorAssignmentsPage({super.key});

  @override
  State<SupervisorAssignmentsPage> createState() =>
      _SupervisorAssignmentsPageState();
}

class _SupervisorAssignmentsPageState
    extends State<SupervisorAssignmentsPage> {
  // ─── theme ────────────────────────────────────────────────────────────────
  Color get _bg => const Color(0xFF0F172A);
  Color get _card => const Color(0xFF1E293B);
  Color get _text => Colors.white;
  Color get _sub => Colors.grey[400]!;
  Color get _border => const Color(0xFF334155);
  Color get _primary => const Color(0xFF4F46E5);

  // ─── state ────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _assignments = [];
  List<Map<String, dynamic>> _mySites = [];
  bool _loading = true;
  String? _error;
  String? _userId;

  // ─── add form state ────────────────────────────────────────────────────────
  bool _showAddForm = false;

  List<Map<String, dynamic>> _allShifts = [];
  List<Map<String, dynamic>> _guards = [];

  Map<String, dynamic>? _selectedSite;
  Map<String, dynamic>? _selectedShift;
  Map<String, dynamic>? _selectedGuard;
  DateTime? _fromDate;
  DateTime? _toDate;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _userId = prefs.getString('userId');
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
      final assignRes = await api.get('assignments');
      final shiftsRes = await api.get('shift');
      final guardsRes = await api.get('shift/guards');

      if (sitesRes.statusCode != 200 ||
          assignRes.statusCode != 200 ||
          shiftsRes.statusCode != 200 ||
          guardsRes.statusCode != 200) {
        setState(() {
          _error = 'Failed to load data.';
          _loading = false;
        });
        return;
      }

      final List allSites =
          jsonDecode(sitesRes.body) as List;
      final List allAssignments =
          jsonDecode(assignRes.body) as List;
      final List allShifts =
          jsonDecode(shiftsRes.body) as List;
      final List allGuards =
          jsonDecode(guardsRes.body) as List;

      // Filter sites where this user is a supervisor
      final mySitesList = allSites.where((s) {
        final ids = (s['supervisorIds'] as List?)?.cast<dynamic>() ?? [];
        return ids.any((id) => id.toString() == _userId.toString());
      }).map((s) => s as Map<String, dynamic>).toList();

      final mySiteIds = mySitesList.map((s) => s['id']).toSet();

      // Filter assignments to only those at my sites
      final myAssignments = allAssignments.where((a) {
        final siteId = a['shift']?['site']?['id'];
        return siteId != null && mySiteIds.contains(siteId);
      }).map((a) => a as Map<String, dynamic>).toList();

      // Only shifts at my sites
      final myShifts = allShifts.where((sh) {
        final siteId = sh['site']?['id'];
        return siteId != null && mySiteIds.contains(siteId);
      }).map((sh) => sh as Map<String, dynamic>).toList();

      setState(() {
        _mySites = mySitesList;
        _assignments = myAssignments;
        _allShifts = myShifts;
        _guards = allGuards.map((g) => g as Map<String, dynamic>).toList();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not connect to server.';
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _shiftsForSelectedSite {
    if (_selectedSite == null) return [];
    final siteId = _selectedSite!['id'];
    return _allShifts
        .where((sh) => sh['site']?['id'] == siteId)
        .toList();
  }

  Future<void> _pickDate(bool isFrom) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: ColorScheme.dark(primary: _primary),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _fromDate = picked;
        } else {
          _toDate = picked;
        }
      });
    }
  }

  Future<void> _submitAssignment() async {
    if (_selectedShift == null || _fromDate == null || _toDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: const Text('Please fill all required fields.'),
            backgroundColor: _card),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final api = ApiService();
      final bodyMap = <String, dynamic>{
        'shiftId': _selectedShift!['id'],
        'fromDate': _fromDate!.toIso8601String().split('T').first,
        'toDate': _toDate!.toIso8601String().split('T').first,
        'openShift': _selectedGuard == null,
      };
      if (_selectedGuard != null) {
        bodyMap['guardId'] = _selectedGuard!['id'];
      }
      final res = await api.post('assignments', bodyMap);
      if (res.statusCode == 200 || res.statusCode == 201) {
        setState(() {
          _showAddForm = false;
          _selectedSite = null;
          _selectedShift = null;
          _selectedGuard = null;
          _fromDate = null;
          _toDate = null;
          _submitting = false;
        });
        await _fetchData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: const Text('Assignment created!'),
                backgroundColor: Colors.green.shade700),
          );
        }
      } else {
        String msg = 'Failed to create assignment.';
        try {
          final decoded = jsonDecode(res.body);
          if (decoded is Map && decoded['error'] != null) {
            msg = decoded['error'];
          } else if (decoded is String) {
            msg = decoded;
          }
        } catch (_) {}
        setState(() => _submitting = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg), backgroundColor: Colors.red.shade700),
          );
        }
      }
    } catch (e) {
      setState(() => _submitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Network error.'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteAssignment(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _card,
        title: Text('Delete Assignment?', style: TextStyle(color: _text)),
        content: Text('This cannot be undone.', style: TextStyle(color: _sub)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel', style: TextStyle(color: _sub))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete',
                  style: TextStyle(color: Color(0xFFEF4444)))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final api = ApiService();
      final res = await api.delete('assignments/$id');
      if (res.statusCode == 200 || res.statusCode == 204) {
        await _fetchData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: const Text('Assignment deleted.'),
                backgroundColor: Colors.green.shade700),
          );
        }
      }
    } catch (_) {}
  }

  String _formatDate(String? d) {
    if (d == null) return '--';
    try {
      final parts = d.split('-');
      if (parts.length == 3) return '${parts[1]}/${parts[2]}/${parts[0]}';
    } catch (_) {}
    return d;
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
        title: Text('Assignments', style: TextStyle(color: _text, fontWeight: FontWeight.bold)),
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(_showAddForm ? Icons.close : Icons.add, color: _primary),
            onPressed: () => setState(() {
              _showAddForm = !_showAddForm;
              if (!_showAddForm) {
                _selectedSite = null;
                _selectedShift = null;
                _selectedGuard = null;
                _fromDate = null;
                _toDate = null;
              }
            }),
          ),
        ],
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
                          style: ElevatedButton.styleFrom(backgroundColor: _primary),
                          child: const Text('Retry')),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _fetchData,
                  color: _primary,
                  backgroundColor: _card,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (_showAddForm) _buildAddForm(),
                      if (_showAddForm) const SizedBox(height: 16),
                      if (_assignments.isEmpty && !_showAddForm)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 60),
                            child: Column(
                              children: [
                                Icon(Icons.assignment_outlined,
                                    color: _sub, size: 56),
                                const SizedBox(height: 12),
                                Text('No assignments found.',
                                    style: TextStyle(color: _sub, fontSize: 15)),
                              ],
                            ),
                          ),
                        )
                      else
                        ..._assignments.map((a) => _buildAssignmentCard(a)),
                    ],
                  ),
                ),
    );
  }

  Widget _buildAddForm() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _primary.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('New Assignment',
              style: TextStyle(
                  color: _text, fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 14),

          // Site picker
          _label('Site *'),
          _dropdown(
            value: _selectedSite,
            hint: 'Select site',
            items: _mySites,
            labelKey: 'name',
            onChanged: (v) => setState(() {
              _selectedSite = v;
              _selectedShift = null;
            }),
          ),
          const SizedBox(height: 12),

          // Shift picker (filtered by site)
          _label('Shift *'),
          _dropdown(
            value: _selectedShift,
            hint: _selectedSite == null ? 'Select site first' : 'Select shift',
            items: _shiftsForSelectedSite,
            labelKey: '__shiftLabel',
            customLabel: (sh) {
              final site = sh['site']?['name'] ?? '';
              final start = _formatTime(sh['startTime']);
              final end = _formatTime(sh['endTime']);
              return '$site · $start – $end';
            },
            onChanged: _selectedSite == null
                ? null
                : (v) => setState(() => _selectedShift = v),
          ),
          const SizedBox(height: 12),

          // Guard picker (optional — leave null for open shift)
          _label('Guard (optional — leave empty for open shift)'),
          _dropdown(
            value: _selectedGuard,
            hint: 'Select guard',
            items: [{'id': null, 'firstName': 'None', 'lastName': '(Open Shift)'}, ..._guards],
            labelKey: '__guardLabel',
            customLabel: (g) =>
                '${g['firstName'] ?? ''} ${g['lastName'] ?? ''}'.trim(),
            onChanged: (v) => setState(() =>
                _selectedGuard = (v != null && v['id'] == null) ? null : v),
          ),
          const SizedBox(height: 12),

          // Dates row
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('From Date *'),
                    _dateTile(
                      _fromDate != null
                          ? '${_fromDate!.month}/${_fromDate!.day}/${_fromDate!.year}'
                          : 'Pick date',
                      () => _pickDate(true),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('To Date *'),
                    _dateTile(
                      _toDate != null
                          ? '${_toDate!.month}/${_toDate!.day}/${_toDate!.year}'
                          : 'Pick date',
                      () => _pickDate(false),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submitAssignment,
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child:
                          CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Create Assignment',
                      style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(t, style: TextStyle(color: _sub, fontSize: 12)),
      );

  Widget _dropdown({
    required Map<String, dynamic>? value,
    required String hint,
    required List<Map<String, dynamic>> items,
    required String labelKey,
    String Function(Map<String, dynamic>)? customLabel,
    void Function(Map<String, dynamic>?)? onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _border),
      ),
      child: DropdownButton<Map<String, dynamic>>(
        value: value,
        hint: Text(hint, style: TextStyle(color: _sub, fontSize: 13)),
        isExpanded: true,
        underline: const SizedBox(),
        dropdownColor: _card,
        style: TextStyle(color: _text, fontSize: 13),
        onChanged: onChanged,
        items: items.map((item) {
          final label = customLabel != null
              ? customLabel(item)
              : (item[labelKey]?.toString() ?? '');
          return DropdownMenuItem(
            value: item,
            child: Text(label, style: TextStyle(color: _text)),
          );
        }).toList(),
      ),
    );
  }

  Widget _dateTile(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _border),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today, color: _sub, size: 14),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: _text, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildAssignmentCard(Map<String, dynamic> a) {
    final guard = a['guard'];
    final shift = a['shift'];
    final site = shift?['site'];
    final client = shift?['client'];
    final isActive = a['active'] == true;
    final isOpen = a['openShift'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: (isActive ? _primary : Colors.grey).withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isOpen ? Icons.work_outline : Icons.person,
              color: isActive ? _primary : Colors.grey,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        guard != null
                            ? '${guard['firstName'] ?? ''} ${guard['lastName'] ?? ''}'.trim()
                            : 'Open Shift',
                        style: TextStyle(
                            color: _text,
                            fontWeight: FontWeight.bold,
                            fontSize: 14),
                      ),
                    ),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isActive
                            ? Colors.green.withOpacity(0.15)
                            : Colors.grey.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        isActive ? 'Active' : 'Inactive',
                        style: TextStyle(
                            color: isActive ? Colors.green : Colors.grey,
                            fontSize: 11,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (site != null)
                  Text(site['name'] ?? '',
                      style: TextStyle(color: _sub, fontSize: 12)),
                if (client != null)
                  Text(client['name'] ?? '',
                      style: TextStyle(color: _sub, fontSize: 12)),
                if (shift != null)
                  Text(
                      '${_formatTime(shift['startTime'])} – ${_formatTime(shift['endTime'])}',
                      style: TextStyle(color: _primary, fontSize: 12)),
                const SizedBox(height: 4),
                Text(
                  '${_formatDate(a['fromDate']?.toString())} → ${_formatDate(a['toDate']?.toString())}',
                  style: TextStyle(color: _sub, fontSize: 11),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444), size: 20),
            onPressed: () => _deleteAssignment(a['id'] as int),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}
