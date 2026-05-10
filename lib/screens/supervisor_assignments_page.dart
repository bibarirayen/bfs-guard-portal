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
  int? _userId;

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
  // Extra sites to attach to the new assignment (mirrors website behaviour).
  final Set<int> _selectedAdditionalSiteIds = <int>{};

  // Days-of-week filter: all 7 selected by default = every day (same as old behavior)
  static const List<String> _allDayValues = [
    'MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY', 'SUNDAY'
  ];
  static const List<String> _dayLabels = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'
  ];
  List<String> _selectedDays = List.from(_allDayValues);

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
        return ids.any((id) => (id as num?)?.toInt() == _userId);
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

  /// Sites the current supervisor manages that share the given primary site's
  /// client and are NOT the primary site — those are eligible to be added as
  /// additional sites on an assignment (matches the website's picker logic).
  List<Map<String, dynamic>> _additionalSitesAvailableFor(
      Map<String, dynamic>? primarySite) {
    if (primarySite == null) return const [];
    final primaryId = primarySite['id'];
    final clientId = primarySite['client']?['id'] ??
        primarySite['clientId'];
    if (clientId == null) {
      // Fallback: just exclude the primary site.
      return _mySites.where((s) => s['id'] != primaryId).toList();
    }
    return _mySites.where((s) {
      final sClient = s['client']?['id'] ?? s['clientId'];
      return s['id'] != primaryId && sClient == clientId;
    }).toList();
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
      // Only send daysOfWeek when not all 7 days are selected
      if (_selectedDays.length < 7) {
        bodyMap['daysOfWeek'] = _selectedDays;
      }
      // Extra sites the guard will also patrol on this assignment.
      if (_selectedAdditionalSiteIds.isNotEmpty) {
        bodyMap['additionalSiteIds'] = _selectedAdditionalSiteIds.toList();
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
          _selectedDays = List.from(_allDayValues);
          _selectedAdditionalSiteIds.clear();
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
                _selectedDays = List.from(_allDayValues);
                _selectedAdditionalSiteIds.clear();
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
              // Reset extra sites whenever the primary site changes.
              _selectedAdditionalSiteIds.clear();
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

          // Days-of-week filter
          _label('Working Days (uncheck days off)'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(_allDayValues.length, (i) {
              final val = _allDayValues[i];
              final selected = _selectedDays.contains(val);
              return GestureDetector(
                onTap: () => setState(() {
                  if (selected) {
                    _selectedDays.remove(val);
                  } else {
                    _selectedDays.add(val);
                  }
                }),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: selected ? _primary : _bg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: selected ? _primary : _border),
                  ),
                  child: Text(
                    _dayLabels[i],
                    style: TextStyle(
                      color: selected ? Colors.white : _sub,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 16),

          // Additional sites — only show when there are eligible same-client sites.
          Builder(builder: (_) {
            final extras = _additionalSitesAvailableFor(_selectedSite);
            if (extras.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label('Additional Sites (same client)'),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: extras.map((s) {
                    final id = (s['id'] as num).toInt();
                    final selected = _selectedAdditionalSiteIds.contains(id);
                    return GestureDetector(
                      onTap: () => setState(() {
                        if (selected) {
                          _selectedAdditionalSiteIds.remove(id);
                        } else {
                          _selectedAdditionalSiteIds.add(id);
                        }
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: selected ? _primary : _bg,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: selected ? _primary : _border),
                        ),
                        child: Text(
                          s['name']?.toString() ?? '',
                          style: TextStyle(
                            color: selected ? Colors.white : _sub,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
              ],
            );
          }),

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
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
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

  // ─── assignment management sheet ──────────────────────────────────────────

  void _openAssignmentSheet(Map<String, dynamic> a) {
    // Deep-copy sessions so Stop updates are reflected inside the sheet
    final sheetA = Map<String, dynamic>.from(a);
    if (a['sessions'] != null) {
      sheetA['sessions'] = (a['sessions'] as List)
          .map((s) => Map<String, dynamic>.from(s as Map))
          .toList();
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, sc) => StatefulBuilder(
          builder: (_, setSheet) => Container(
            decoration: BoxDecoration(
              color: _card,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: _sub.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: sc,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    _buildSheetHeader(sheetA),
                    const SizedBox(height: 20),
                    _buildSheetSessions(sheetA, setSheet),
                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                    _buildSheetActions(sheetA, sheetCtx, setSheet),
                  ],
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildSheetHeader(Map<String, dynamic> a) {
    final guard = a['guard'];
    final shift = a['shift'];
    final site = shift?['site'];
    final client = shift?['client'];
    final isActive = a['active'] == true;
    final days = (a['daysOfWeek'] as List?)?.cast<String>() ?? [];
    const dayLabels = {
      'MONDAY': 'Mon', 'TUESDAY': 'Tue', 'WEDNESDAY': 'Wed',
      'THURSDAY': 'Thu', 'FRIDAY': 'Fri', 'SATURDAY': 'Sat', 'SUNDAY': 'Sun'
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: Text(
            guard != null
                ? '${guard['firstName'] ?? ''} ${guard['lastName'] ?? ''}'.trim()
                : 'Open Shift',
            style: TextStyle(
                color: _text, fontWeight: FontWeight.bold, fontSize: 18),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: (isActive ? Colors.green : Colors.grey).withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            isActive ? 'Active' : 'Inactive',
            style: TextStyle(
                color: isActive ? Colors.green : Colors.grey,
                fontWeight: FontWeight.w600,
                fontSize: 12),
          ),
        ),
      ]),
      const SizedBox(height: 6),
      if (client != null || site != null)
        Text(
          '${client?['name'] ?? ''} • ${site?['name'] ?? ''}',
          style: TextStyle(color: _sub, fontSize: 13),
        ),
      // Extra patrolling sites attached to this assignment.
      Builder(builder: (_) {
        final attached = (a['sites'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
        final primaryId = (site?['id'] as num?)?.toInt();
        final extras = attached.where((s) => (s['id'] as num?)?.toInt() != primaryId).toList();
        if (extras.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '+ ${extras.map((s) => s['name'] ?? '').join(' • ')}',
            style: TextStyle(color: _primary, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        );
      }),
      if (shift != null)
        Text(
          '${_formatTime(shift['startTime'])} – ${_formatTime(shift['endTime'])}',
          style: TextStyle(
              color: _primary, fontSize: 13, fontWeight: FontWeight.w600),
        ),
      const SizedBox(height: 4),
      Text(
        '${_formatDate(a['fromDate']?.toString())} → ${_formatDate(a['toDate']?.toString())}',
        style: TextStyle(color: _sub, fontSize: 12),
      ),
      if (days.isNotEmpty && days.length < 7)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '↺ ${days.map((d) => dayLabels[d] ?? d).join(', ')} only',
            style: TextStyle(
                color: _primary, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
    ]);
  }

  Widget _buildSheetSessions(Map<String, dynamic> a, StateSetter setSheet) {
    final sessions =
        (a['sessions'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (sessions.isEmpty) return const SizedBox.shrink();

    Color statusColor(String status) {
      switch (status) {
        case 'ACTIVE':    return Colors.green;
        case 'COMPLETED': return Colors.blue;
        case 'STOPPED':   return Colors.red;
        default:          return Colors.orange;
      }
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('Sessions',
            style: TextStyle(
                color: _text, fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
              color: _primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10)),
          child: Text('${sessions.length}',
              style: TextStyle(
                  color: _primary, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      ]),
      const SizedBox(height: 10),
      ...sessions.map((session) {
        final status = session['status']?.toString() ?? 'SCHEDULED';
        final isStoppable = status == 'SCHEDULED' || status == 'ACTIVE';
        final color = statusColor(status);
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _border),
          ),
          child: Row(children: [
            Expanded(
              child: Text(
                _formatDate(session['sessionDate']?.toString()),
                style: TextStyle(
                    color: _text, fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(status,
                  style: TextStyle(
                      color: color, fontSize: 10, fontWeight: FontWeight.w600)),
            ),
            if (isStoppable) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () =>
                    _stopSession(session['id'] as int, setSheet, a),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                  ),
                  child: const Text('Stop',
                      style: TextStyle(
                          color: Colors.red,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ]),
        );
      }),
    ]);
  }

  Widget _buildSheetActions(
      Map<String, dynamic> a, BuildContext sheetCtx, StateSetter setSheet) {
    final isActive = a['active'] == true;
    return Wrap(spacing: 10, runSpacing: 10, children: [
      _sheetActionBtn(Icons.edit_outlined, 'Edit', _primary, () {
        Navigator.pop(sheetCtx);
        _openEditSheet(a);
      }),
      if (isActive)
        _sheetActionBtn(Icons.nights_stay_outlined, 'End Tonight',
            Colors.orange,
            () => _endTonight(a['id'] as int, sheetCtx, setSheet)),
      if (isActive)
        _sheetActionBtn(Icons.block, 'Terminate', Colors.red,
            () => _terminateAssignment(a['id'] as int, sheetCtx)),
      _sheetActionBtn(Icons.delete_outline, 'Delete',
          const Color(0xFFEF4444), () {
        Navigator.pop(sheetCtx);
        _deleteAssignment(a['id'] as int);
      }),
    ]);
  }

  Widget _sheetActionBtn(
      IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w600, fontSize: 13)),
        ]),
      ),
    );
  }

  Future<void> _stopSession(
      int sessionId, StateSetter setSheet, Map<String, dynamic> a) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _card,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Stop this session?',
            style: TextStyle(
                color: _text, fontSize: 16, fontWeight: FontWeight.bold)),
        content: Text('This will stop only this one session.',
            style: TextStyle(color: _sub)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel', style: TextStyle(color: _sub))),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              child: const Text('Stop It',
                  style: TextStyle(color: Colors.white))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final res = await ApiService()
          .put('assignments/sessions/$sessionId/stop', {});
      if (res.statusCode == 200) {
        // Update status in the local copy so the sheet refreshes instantly
        final sessions =
            (a['sessions'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        for (final s in sessions) {
          if (s['id'] == sessionId) {
            s['status'] = 'STOPPED';
            break;
          }
        }
        setSheet(() {});
        _fetchData();
      } else {
        _showSheetError('Could not stop session. Please try again.');
      }
    } catch (_) {
      _showSheetError('Network error. Please check your connection.');
    }
  }

  Future<void> _endTonight(
      int assignmentId, BuildContext sheetCtx, StateSetter setSheet) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _card,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text("End Tonight's Session?",
            style: TextStyle(
                color: _text, fontSize: 16, fontWeight: FontWeight.bold)),
        content: Text(
          "This closes only tonight's session. The guard will still be scheduled for the remaining days.",
          style: TextStyle(color: _sub, height: 1.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel', style: TextStyle(color: _sub))),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              child: const Text('End Tonight',
                  style: TextStyle(color: Colors.white))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final res = await ApiService()
          .put('assignments/admin-end-tonight/$assignmentId', {});
      if (res.statusCode == 200) {
        Navigator.pop(sheetCtx);
        await _fetchData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text(
                "Tonight's session ended. Remaining sessions stay scheduled."),
            backgroundColor: Colors.green.shade700,
          ));
        }
      } else {
        _showSheetError("Could not end tonight's session. Please try again.");
      }
    } catch (_) {
      _showSheetError('Network error. Please check your connection.');
    }
  }

  Future<void> _terminateAssignment(
      int assignmentId, BuildContext sheetCtx) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _card,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Terminate Assignment?',
            style: TextStyle(
                color: _text, fontSize: 16, fontWeight: FontWeight.bold)),
        content: Text(
          'This permanently ends the assignment and closes any open session. The guard will not return to this post.',
          style: TextStyle(color: _sub, height: 1.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel', style: TextStyle(color: _sub))),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              child: const Text('Yes, Terminate',
                  style: TextStyle(color: Colors.white))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final res = await ApiService()
          .put('assignments/admin-terminate/$assignmentId', {});
      if (res.statusCode == 200) {
        Navigator.pop(sheetCtx);
        await _fetchData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('Assignment terminated.'),
            backgroundColor: Colors.green.shade700,
          ));
        }
      } else {
        _showSheetError('Could not terminate assignment. Please try again.');
      }
    } catch (_) {
      _showSheetError('Network error. Please check your connection.');
    }
  }

  void _openEditSheet(Map<String, dynamic> a) {
    Map<String, dynamic>? editGuard = a['guard'] != null
        ? Map<String, dynamic>.from(a['guard'] as Map)
        : null;
    DateTime? editFrom = a['fromDate'] != null
        ? DateTime.parse(a['fromDate'].toString())
        : null;
    DateTime? editTo =
        a['toDate'] != null ? DateTime.parse(a['toDate'].toString()) : null;
    final rawDays = (a['daysOfWeek'] as List?)?.cast<String>() ?? [];
    List<String> editDays =
        rawDays.isEmpty ? List.from(_allDayValues) : List.from(rawDays);
    bool editSubmitting = false;

    // Pre-load any additional sites already attached to this assignment.
    // Backend returns the full `sites` list (primary + extras) on each
    // assignment. Strip the primary (shift.site) to get just the extras.
    final primarySite = a['shift']?['site'] as Map<String, dynamic>?;
    final primarySiteId = (primarySite?['id'] as num?)?.toInt();
    final attachedSites =
        (a['sites'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final Set<int> editAdditionalSiteIds = attachedSites
        .where((s) => (s['id'] as num?)?.toInt() != primarySiteId)
        .map((s) => (s['id'] as num).toInt())
        .toSet();
    final extraSitesAvailable = _additionalSitesAvailableFor(primarySite);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (editCtx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, sc) => StatefulBuilder(
          builder: (_, setEdit) => Container(
            decoration: BoxDecoration(
              color: _card,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: _sub.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: sc,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    Text('Edit Assignment',
                        style: TextStyle(
                            color: _text,
                            fontWeight: FontWeight.bold,
                            fontSize: 18)),
                    Text(
                      '${a['shift']?['client']?['name'] ?? ''} • ${a['shift']?['site']?['name'] ?? ''}',
                      style: TextStyle(color: _sub, fontSize: 13),
                    ),
                    const SizedBox(height: 20),

                    // Guard picker
                    _label('Guard (leave empty for open shift)'),
                    _dropdown(
                      value: editGuard,
                      hint: 'Select guard',
                      items: [
                        {
                          'id': null,
                          'firstName': 'None',
                          'lastName': '(Open Shift)'
                        },
                        ..._guards
                      ],
                      labelKey: '__guardLabel',
                      customLabel: (g) =>
                          '${g['firstName'] ?? ''} ${g['lastName'] ?? ''}'
                              .trim(),
                      onChanged: (v) => setEdit(() =>
                          editGuard =
                              (v != null && v['id'] == null) ? null : v),
                    ),
                    const SizedBox(height: 16),

                    // Date pickers row
                    Row(children: [
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _label('From Date *'),
                              _dateTile(
                                editFrom != null
                                    ? '${editFrom!.month}/${editFrom!.day}/${editFrom!.year}'
                                    : 'Pick date',
                                () async {
                                  final now = DateTime.now();
                                  final p = await showDatePicker(
                                    context: context,
                                    initialDate: editFrom ?? now,
                                    firstDate: DateTime(now.year - 1),
                                    lastDate: DateTime(now.year + 2),
                                    builder: (c, child) => Theme(
                                        data: ThemeData.dark().copyWith(
                                            colorScheme: ColorScheme.dark(
                                                primary: _primary)),
                                        child: child!),
                                  );
                                  if (p != null) setEdit(() => editFrom = p);
                                },
                              ),
                            ]),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _label('To Date *'),
                              _dateTile(
                                editTo != null
                                    ? '${editTo!.month}/${editTo!.day}/${editTo!.year}'
                                    : 'Pick date',
                                () async {
                                  final now = DateTime.now();
                                  final p = await showDatePicker(
                                    context: context,
                                    initialDate: editTo ?? now,
                                    firstDate: DateTime(now.year - 1),
                                    lastDate: DateTime(now.year + 2),
                                    builder: (c, child) => Theme(
                                        data: ThemeData.dark().copyWith(
                                            colorScheme: ColorScheme.dark(
                                                primary: _primary)),
                                        child: child!),
                                  );
                                  if (p != null) setEdit(() => editTo = p);
                                },
                              ),
                            ]),
                      ),
                    ]),
                    const SizedBox(height: 16),

                    // Days chips
                    _label('Working Days (uncheck days off)'),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: List.generate(_allDayValues.length, (i) {
                        final val = _allDayValues[i];
                        final selected = editDays.contains(val);
                        return GestureDetector(
                          onTap: () => setEdit(() {
                            if (selected) {
                              editDays.remove(val);
                            } else {
                              editDays.add(val);
                            }
                          }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: selected ? _primary : _bg,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: selected ? _primary : _border),
                            ),
                            child: Text(
                              _dayLabels[i],
                              style: TextStyle(
                                color: selected ? Colors.white : _sub,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 24),

                    // Additional sites — only show when there are eligible options.
                    if (extraSitesAvailable.isNotEmpty) ...[
                      _label('Additional Sites (same client)'),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: extraSitesAvailable.map((s) {
                          final id = (s['id'] as num).toInt();
                          final selected = editAdditionalSiteIds.contains(id);
                          return GestureDetector(
                            onTap: () => setEdit(() {
                              if (selected) {
                                editAdditionalSiteIds.remove(id);
                              } else {
                                editAdditionalSiteIds.add(id);
                              }
                            }),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 7),
                              decoration: BoxDecoration(
                                color: selected ? _primary : _bg,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: selected ? _primary : _border),
                              ),
                              child: Text(
                                s['name']?.toString() ?? '',
                                style: TextStyle(
                                  color: selected ? Colors.white : _sub,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 24),
                    ],

                    // Save button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: editSubmitting
                            ? null
                            : () async {
                                if (editFrom == null || editTo == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                    content: const Text(
                                        'Please select both dates.'),
                                    backgroundColor: Colors.red.shade700,
                                  ));
                                  return;
                                }
                                setEdit(() => editSubmitting = true);
                                try {
                                  final body = <String, dynamic>{
                                    'shiftId': a['shift']?['id'],
                                    'fromDate': editFrom!
                                        .toIso8601String()
                                        .split('T')
                                        .first,
                                    'toDate': editTo!
                                        .toIso8601String()
                                        .split('T')
                                        .first,
                                    'openShift': editGuard == null,
                                  };
                                  if (editGuard != null) {
                                    body['guardId'] = editGuard!['id'];
                                  }
                                  if (editDays.length < 7) {
                                    body['daysOfWeek'] = editDays;
                                  }
                                  if (editAdditionalSiteIds.isNotEmpty) {
                                    body['additionalSiteIds'] =
                                        editAdditionalSiteIds.toList();
                                  } else {
                                    // Explicit null clears any previously
                                    // attached extras on the backend.
                                    body['additionalSiteIds'] = null;
                                  }
                                  final res = await ApiService()
                                      .put('assignments/${a['id']}', body);
                                  if (res.statusCode == 200) {
                                    Navigator.pop(editCtx);
                                    await _fetchData();
                                    if (mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(SnackBar(
                                        content:
                                            const Text('Assignment updated!'),
                                        backgroundColor:
                                            Colors.green.shade700,
                                      ));
                                    }
                                  } else {
                                    String msg =
                                        'Could not update assignment.';
                                    try {
                                      final d = jsonDecode(res.body);
                                      msg =
                                          (d is Map ? d['error'] : d)
                                                  ?.toString() ??
                                              msg;
                                    } catch (_) {}
                                    setEdit(() => editSubmitting = false);
                                    _showSheetError(msg);
                                  }
                                } catch (_) {
                                  setEdit(() => editSubmitting = false);
                                  _showSheetError(
                                      'Network error. Please check your connection.');
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primary,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: editSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Text('Save Changes',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  void _showSheetError(String msg) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _card,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 22),
          const SizedBox(width: 8),
          Text('Something went wrong',
              style: TextStyle(
                  color: _text, fontSize: 15, fontWeight: FontWeight.bold)),
        ]),
        content: Text(msg, style: TextStyle(color: _sub, height: 1.5)),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            child:
                const Text('OK', style: TextStyle(color: Colors.white)),
          ),
        ],
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

    return GestureDetector(
      onTap: () => _openAssignmentSheet(a),
      child: Container(
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
                              ? '${guard['firstName'] ?? ''} ${guard['lastName'] ?? ''}'
                                  .trim()
                              : 'Open Shift',
                          style: TextStyle(
                              color: _text,
                              fontWeight: FontWeight.bold,
                              fontSize: 14),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
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
                  // Extra sites listed inline beneath the primary site.
                  Builder(builder: (_) {
                    final attached = (a['sites'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
                    final primaryId = (site?['id'] as num?)?.toInt();
                    final extras = attached.where((s) => (s['id'] as num?)?.toInt() != primaryId).toList();
                    if (extras.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '+ ${extras.map((s) => s['name'] ?? '').join(', ')}',
                        style: TextStyle(color: _primary, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    );
                  }),
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
                  Builder(builder: (_) {
                    final days =
                        (a['daysOfWeek'] as List?)?.cast<String>() ?? [];
                    if (days.isEmpty || days.length == 7) {
                      return const SizedBox.shrink();
                    }
                    const labels = {
                      'MONDAY': 'Mon', 'TUESDAY': 'Tue', 'WEDNESDAY': 'Wed',
                      'THURSDAY': 'Thu', 'FRIDAY': 'Fri', 'SATURDAY': 'Sat',
                      'SUNDAY': 'Sun'
                    };
                    final readable =
                        days.map((d) => labels[d] ?? d).join(', ');
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '↺ $readable only',
                        style: TextStyle(
                            color: _primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600),
                      ),
                    );
                  }),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                color: Color(0xFF64748B), size: 18),
          ],
        ),
      ),
    );
  }
}
