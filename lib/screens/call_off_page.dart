import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/call_off_service.dart';

class CallOffPage extends StatefulWidget {
  const CallOffPage({super.key});

  @override
  State<CallOffPage> createState() => _CallOffPageState();
}

class _CallOffPageState extends State<CallOffPage>
    with SingleTickerProviderStateMixin {
  // ── theme ──────────────────────────────────────────────────────────────────
  static const _accent = Color(0xFF6366F1); // indigo — distinct from NCNS orange
  Color get _bg       => const Color(0xFF0F172A);
  Color get _card     => const Color(0xFF1E293B);
  Color get _border   => const Color(0xFF334155);
  Color get _text     => Colors.white;
  Color get _sub      => Colors.grey[400]!;
  Color get _inputFill => const Color(0xFF2D3748);

  static const _tabHeight = 44.0;
  late final TabController _tabController;

  // ── shared ─────────────────────────────────────────────────────────────────
  int? _userId;
  final CallOffService _service = CallOffService();

  // ── history state ──────────────────────────────────────────────────────────
  bool _listLoading = true;
  List<Map<String, dynamic>> _reports = [];

  // ── form state ─────────────────────────────────────────────────────────────
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();

  bool _loadingOptions = true;
  bool _loadingShifts  = false;
  bool _saving         = false;

  DateTime _callOffDate = DateTime.now();

  List<Map<String, dynamic>> _sites  = [];
  List<Map<String, dynamic>> _guards = [];
  List<Map<String, dynamic>> _shifts = [];

  int? _selectedSiteId;
  int? _selectedGuardId;
  int? _selectedShiftId;

  // ── lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _init();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _userId = prefs.getInt('userId');
    await Future.wait([_loadReports(), _loadSites(), _loadAllGuards()]);
  }

  // ── data loaders ───────────────────────────────────────────────────────────
  Future<void> _loadReports() async {
    if (_userId == null) return;
    try {
      setState(() => _listLoading = true);
      final data = await _service.getSupervisorReports(_userId!);
      if (!mounted) return;
      setState(() => _reports = data);
    } catch (e) {
      if (!mounted) return;
      _snack('Failed to load reports: $e');
    } finally {
      if (mounted) setState(() => _listLoading = false);
    }
  }

  Future<void> _loadSites() async {
    if (_userId == null) return;
    try {
      final sites = await _service.getSiteOptions(_userId!);
      if (!mounted) return;
      setState(() => _sites = sites);
    } catch (e) {
      if (!mounted) return;
      _snack('Failed to load sites: $e');
    } finally {
      if (mounted) setState(() => _loadingOptions = false);
    }
  }

  Future<void> _loadAllGuards() async {
    try {
      final guards = await _service.getAllGuards();
      if (!mounted) return;
      guards.sort((a, b) {
        final aName = '${a['firstName'] ?? ''} ${a['lastName'] ?? ''}'.trim();
        final bName = '${b['firstName'] ?? ''} ${b['lastName'] ?? ''}'.trim();
        return aName.compareTo(bName);
      });
      setState(() => _guards = guards);
    } catch (e) {
      if (!mounted) return;
      _snack('Failed to load guards: $e');
    }
  }

  Future<void> _onSiteChanged(int? siteId) async {
    setState(() {
      _selectedSiteId  = siteId;
      _selectedShiftId = null;
      _shifts = [];
    });
    if (siteId == null || _userId == null) return;
    try {
      setState(() => _loadingShifts = true);
      final shifts = await _service.getShiftOptions(_userId!, siteId);
      if (!mounted) return;
      setState(() => _shifts = shifts);
    } catch (e) {
      if (!mounted) return;
      _snack('Failed to load shifts: $e');
    } finally {
      if (mounted) setState(() => _loadingShifts = false);
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _callOffDate,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: _accent,
            onPrimary: Colors.white,
            surface: Color(0xFF1E293B),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _callOffDate = picked);
  }

  String _isoDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _displayDate(String? raw) {
    if (raw == null || raw.isEmpty) return '–';
    try {
      final p = raw.split('-');
      return '${p[1]}/${p[2]}/${p[0]}';
    } catch (_) {
      return raw;
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedSiteId == null || _selectedGuardId == null || _selectedShiftId == null) {
      _snack('Please select site, guard, and shift.');
      return;
    }
    final payload = {
      'supervisorId': _userId,
      'guardId':      _selectedGuardId,
      'siteId':       _selectedSiteId,
      'shiftId':      _selectedShiftId,
      'callOffDate':  _isoDate(_callOffDate),
      'reason':       _reasonController.text.trim(),
    };
    dev.log('[CallOff Page] submit payload=$payload', name: 'CallOff');
    try {
      setState(() => _saving = true);
      await _service.create(payload);
      if (!mounted) return;
      _snack('Call-off report submitted.');
      _resetForm();
      _tabController.animateTo(0);
      _loadReports();
    } catch (e) {
      if (!mounted) return;
      _snack('$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _resetForm() {
    _reasonController.clear();
    setState(() {
      _selectedSiteId  = null;
      _selectedGuardId = null;
      _selectedShiftId = null;
      _shifts      = [];
      _callOffDate = DateTime.now();
    });
    _formKey.currentState?.reset();
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: _card),
    );
  }

  int _toInt(dynamic v) => (v as num).toInt();

  // ── build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Column(
        children: [
          Container(
            color: _card,
            child: TabBar(
              controller: _tabController,
              indicatorColor: _accent,
              labelColor: _accent,
              unselectedLabelColor: Colors.grey[400],
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              tabs: const [
                Tab(
                  height: _tabHeight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.history_rounded, size: 16),
                      SizedBox(width: 6),
                      Text('History'),
                    ],
                  ),
                ),
                Tab(
                  height: _tabHeight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_circle_outline_rounded, size: 16),
                      SizedBox(width: 6),
                      Text('New Report'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [_buildHistoryTab(), _buildFormTab()],
            ),
          ),
        ],
      ),
    );
  }

  // ── HISTORY TAB ────────────────────────────────────────────────────────────
  Widget _buildHistoryTab() {
    if (_listLoading) {
      return Center(child: CircularProgressIndicator(color: _accent));
    }
    return RefreshIndicator(
      onRefresh: _loadReports,
      color: _accent,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _buildSummaryBanner(),
          const SizedBox(height: 16),
          if (_reports.isEmpty)
            _buildEmptyState()
          else
            ...(_reports.map(_buildReportCard)),
        ],
      ),
    );
  }

  Widget _buildSummaryBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_accent, Color(0xFF4F46E5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: _accent.withOpacity(0.25),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _statItem(_reports.length.toString(), 'Total Call-Offs'),
        ],
      ),
    );
  }

  Widget _statItem(String value, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(value,
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(width: 6),
      Text(label, style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13)),
    ],
  );

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        children: [
          Icon(Icons.phone_missed_rounded, size: 64, color: _sub),
          const SizedBox(height: 16),
          Text('No call-off reports yet.',
              style: TextStyle(color: _text, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('Tap "New Report" to file one.',
              style: TextStyle(color: _sub, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildReportCard(Map<String, dynamic> r) {
    final guardName  = r['guard']?['name'] ?? 'Unknown Guard';
    final siteName   = r['site']?['name'] ?? 'Unknown Site';
    final shiftLabel = r['shift']?['label'] ?? '--:-- – --:--';
    final date       = _displayDate(r['callOffDate']?.toString());
    final reason     = r['reason']?.toString() ?? '';

    return GestureDetector(
      onTap: () => _showDetail(r),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _border),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 2)),
          ],
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: _accent.withOpacity(0.15),
                    child: Text(
                      guardName.isNotEmpty ? guardName[0].toUpperCase() : '?',
                      style: const TextStyle(color: _accent, fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(guardName,
                            style: TextStyle(color: _text, fontWeight: FontWeight.bold, fontSize: 15),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(siteName, style: TextStyle(color: _sub, fontSize: 12)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _accent.withOpacity(0.35)),
                    ),
                    child: Text('CALL OFF',
                        style: TextStyle(color: _accent, fontWeight: FontWeight.bold, fontSize: 11)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Divider(color: _border, height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: Column(
                children: [
                  _detailRow(Icons.calendar_today_rounded, 'Date', date),
                  const SizedBox(height: 6),
                  _detailRow(Icons.access_time_rounded, 'Shift', shiftLabel),
                  if (reason.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _detailRow(Icons.notes_rounded, 'Reason',
                        reason.length > 80 ? '${reason.substring(0, 80)}…' : reason),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 14, color: _sub),
      const SizedBox(width: 6),
      Text('$label: ', style: TextStyle(color: _sub, fontSize: 12)),
      Expanded(
        child: Text(value,
            style: TextStyle(color: _text, fontSize: 13, fontWeight: FontWeight.w500)),
      ),
    ],
  );

  void _showDetail(Map<String, dynamic> r) {
    final guardName  = r['guard']?['name'] ?? 'Unknown Guard';
    final siteName   = r['site']?['name'] ?? 'Unknown Site';
    final shiftLabel = r['shift']?['label'] ?? '--';
    final date       = _displayDate(r['callOffDate']?.toString());
    final reason     = r['reason']?.toString() ?? '';
    final supervisor = r['supervisor']?['name'] ?? '–';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (_, controller) => SingleChildScrollView(
          controller: controller,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: _sub, borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: _accent.withOpacity(0.15),
                    child: Text(
                      guardName.isNotEmpty ? guardName[0].toUpperCase() : '?',
                      style: const TextStyle(color: _accent, fontWeight: FontWeight.bold, fontSize: 22),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(guardName,
                            style: TextStyle(color: _text, fontWeight: FontWeight.bold, fontSize: 18)),
                        Text(siteName, style: TextStyle(color: _sub, fontSize: 13)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _accent.withOpacity(0.35)),
                    ),
                    child: Text('CALL OFF',
                        style: TextStyle(color: _accent, fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Divider(color: _border),
              const SizedBox(height: 12),
              _sheetRow(Icons.calendar_today_rounded, 'Date', date),
              const SizedBox(height: 10),
              _sheetRow(Icons.access_time_rounded, 'Shift', shiftLabel),
              const SizedBox(height: 10),
              _sheetRow(Icons.person_outlined, 'Submitted By', supervisor),
              if (reason.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Reason',
                    style: TextStyle(color: _sub, fontSize: 12,
                        fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _bg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _border),
                  ),
                  child: Text(reason,
                      style: TextStyle(color: _text, fontSize: 14, height: 1.5)),
                ),
              ],
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetRow(IconData icon, String label, String value) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 16, color: _sub),
      const SizedBox(width: 8),
      Text('$label: ', style: TextStyle(color: _sub, fontSize: 13)),
      Expanded(
        child: Text(value,
            style: TextStyle(color: _text, fontSize: 13, fontWeight: FontWeight.w600)),
      ),
    ],
  );

  // ── FORM TAB ───────────────────────────────────────────────────────────────
  Widget _buildFormTab() {
    if (_loadingOptions) {
      return Center(child: CircularProgressIndicator(color: _accent));
    }
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.translucent,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionHeader('Call-Off Details'),
              const SizedBox(height: 16),

              _label('Site'),
              const SizedBox(height: 6),
              _dropdown<int>(
                hint: _sites.isEmpty ? 'No sites available' : 'Select site…',
                value: _selectedSiteId,
                items: _sites.map((s) => DropdownMenuItem<int>(
                  value: _toInt(s['id']),
                  child: Text((s['name'] ?? '').toString(), style: TextStyle(color: _text)),
                )).toList(),
                onChanged: _saving ? null : _onSiteChanged,
                validator: (v) => v == null ? 'Please select a site' : null,
              ),
              const SizedBox(height: 16),

              _label('Guard'),
              const SizedBox(height: 6),
              _dropdown<int>(
                hint: _guards.isEmpty ? 'Loading guards…' : 'Select guard…',
                value: _selectedGuardId,
                items: _guards.map((g) {
                  final name = '${g['firstName'] ?? ''} ${g['lastName'] ?? ''}'.trim();
                  return DropdownMenuItem<int>(
                    value: _toInt(g['id']),
                    child: Text(name, style: TextStyle(color: _text)),
                  );
                }).toList(),
                onChanged: _saving ? null : (v) => setState(() => _selectedGuardId = v),
                validator: (v) => v == null ? 'Please select a guard' : null,
              ),
              const SizedBox(height: 16),

              _label('Shift Called Off'),
              const SizedBox(height: 6),
              _loadingShifts
                  ? _loadingIndicator('Loading shifts…')
                  : _dropdown<int>(
                      hint: _selectedSiteId == null
                          ? 'Select a site first'
                          : _shifts.isEmpty
                              ? 'No shifts for this site'
                              : 'Select shift…',
                      value: _selectedShiftId,
                      items: _shifts.map((s) => DropdownMenuItem<int>(
                        value: _toInt(s['id']),
                        child: Text((s['label'] ?? '').toString(), style: TextStyle(color: _text)),
                      )).toList(),
                      onChanged: _saving || _selectedSiteId == null
                          ? null
                          : (v) => setState(() => _selectedShiftId = v),
                      validator: (v) => v == null ? 'Please select a shift' : null,
                    ),
              const SizedBox(height: 16),

              _label('Date of Call-Off'),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: _saving ? null : _pickDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: _inputFill,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _border),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today_rounded, size: 18, color: _sub),
                      const SizedBox(width: 10),
                      Text(_displayDate(_isoDate(_callOffDate)),
                          style: TextStyle(color: _text, fontSize: 15)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              _label('Reason for Call-Off'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _reasonController,
                minLines: 4,
                maxLines: 6,
                enabled: !_saving,
                style: TextStyle(color: _text),
                decoration: InputDecoration(
                  hintText: 'Describe the reason for calling off…',
                  hintStyle: TextStyle(color: _sub),
                  filled: true,
                  fillColor: _inputFill,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: _border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: _border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: _accent, width: 1.5),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Colors.redAccent),
                  ),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Reason is required' : null,
              ),
              const SizedBox(height: 28),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _saving ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: _accent.withOpacity(0.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: _saving
                      ? const SizedBox(
                          height: 20, width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Submit Call-Off',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  // ── form helpers ───────────────────────────────────────────────────────────
  Widget _sectionHeader(String title) => Text(title,
      style: TextStyle(color: _text, fontSize: 17, fontWeight: FontWeight.bold));

  Widget _label(String text) => Text(text,
      style: TextStyle(color: _sub, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5));

  Widget _loadingIndicator(String msg) => Container(
    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
    decoration: BoxDecoration(
      color: _inputFill,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _border),
    ),
    child: Row(
      children: [
        SizedBox(
          width: 16, height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: _accent),
        ),
        const SizedBox(width: 10),
        Text(msg, style: TextStyle(color: _sub, fontSize: 14)),
      ],
    ),
  );

  Widget _dropdown<T>({
    required String hint,
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required void Function(T?)? onChanged,
    String? Function(T?)? validator,
  }) {
    return DropdownButtonFormField<T>(
      value: value,
      items: items,
      onChanged: onChanged,
      validator: validator,
      dropdownColor: _card,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: _sub),
        filled: true,
        fillColor: _inputFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      style: TextStyle(color: _text),
      iconEnabledColor: _sub,
      iconDisabledColor: _sub.withOpacity(0.4),
    );
  }
}
