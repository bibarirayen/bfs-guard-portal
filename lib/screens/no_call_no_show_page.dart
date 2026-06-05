import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/no_call_no_show_service.dart';

class NoCallNoShowPage extends StatefulWidget {
  const NoCallNoShowPage({super.key});

  @override
  State<NoCallNoShowPage> createState() => _NoCallNoShowPageState();
}

class _NoCallNoShowPageState extends State<NoCallNoShowPage>
    with SingleTickerProviderStateMixin {
  // ── theme ─────────────────────────────────────────────────────────────────
  static const _accent = Color(0xFFF97316);
  Color get _bg => const Color(0xFF0F172A);
  Color get _card => const Color(0xFF1E293B);
  Color get _border => const Color(0xFF334155);
  Color get _text => Colors.white;
  Color get _sub => Colors.grey[400]!;
  Color get _inputFill => const Color(0xFF2D3748);

  // ── tabs ──────────────────────────────────────────────────────────────────
  late final TabController _tabController;

  // ── shared ────────────────────────────────────────────────────────────────
  int? _userId;

  // ── history state ─────────────────────────────────────────────────────────
  final NoCallNoShowService _service = NoCallNoShowService();
  bool _listLoading = true;
  List<Map<String, dynamic>> _reports = [];

  // ── form state ────────────────────────────────────────────────────────────
  final _formKey = GlobalKey<FormState>();
  final _descController = TextEditingController();

  bool _loadingOptions = true;
  bool _loadingGuardsShifts = false;
  bool _saving = false;

  DateTime _eventDate = DateTime.now();

  List<Map<String, dynamic>> _sites = [];
  List<Map<String, dynamic>> _guards = [];
  List<Map<String, dynamic>> _shifts = [];

  int? _selectedSiteId;
  int? _selectedGuardId;
  int? _selectedShiftId;

  // ── lifecycle ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _init();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _userId = prefs.getInt('userId');
    await Future.wait([_loadReports(), _loadSites()]);
  }

  // ── history data ──────────────────────────────────────────────────────────
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

  // ── form data ─────────────────────────────────────────────────────────────
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

  Future<void> _onSiteChanged(int? siteId) async {
    setState(() {
      _selectedSiteId = siteId;
      _selectedGuardId = null;
      _selectedShiftId = null;
      _guards = [];
      _shifts = [];
    });
    if (siteId == null || _userId == null) return;

    try {
      setState(() => _loadingGuardsShifts = true);
      final guards = await _service.getGuardOptions(_userId!, siteId);
      final shifts = await _service.getShiftOptions(_userId!, siteId);
      if (!mounted) return;
      setState(() {
        _guards = guards;
        _shifts = shifts;
      });
    } catch (e) {
      if (!mounted) return;
      _snack('Failed to load guards/shifts: $e');
    } finally {
      if (mounted) setState(() => _loadingGuardsShifts = false);
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _eventDate,
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
    if (picked != null) setState(() => _eventDate = picked);
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

    try {
      setState(() => _saving = true);
      await _service.create({
        'supervisorId': _userId,
        'guardId': _selectedGuardId,
        'siteId': _selectedSiteId,
        'shiftId': _selectedShiftId,
        'eventDate': _isoDate(_eventDate),
        'description': _descController.text.trim(),
      });
      if (!mounted) return;
      _snack('Report submitted successfully.');
      _resetForm();
      _tabController.animateTo(0);
      _loadReports();
    } catch (e) {
      if (!mounted) return;
      _snack('Failed to submit report: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _resetForm() {
    _descController.clear();
    setState(() {
      _selectedSiteId = null;
      _selectedGuardId = null;
      _selectedShiftId = null;
      _guards = [];
      _shifts = [];
      _eventDate = DateTime.now();
    });
    _formKey.currentState?.reset();
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: _card),
    );
  }

  // ── helpers ───────────────────────────────────────────────────────────────
  int _toInt(dynamic v) => (v as num).toInt();

  // ── build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _card,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _accent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.event_busy_rounded, color: _accent, size: 20),
            ),
            const SizedBox(width: 10),
            const Text(
              'No Call No Show',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: _accent,
          labelColor: _accent,
          unselectedLabelColor: Colors.grey[400],
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          tabs: const [
            Tab(text: 'History', icon: Icon(Icons.history_rounded, size: 18)),
            Tab(text: 'New Report', icon: Icon(Icons.add_circle_outline_rounded, size: 18)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildHistoryTab(),
          _buildFormTab(),
        ],
      ),
    );
  }

  // ── HISTORY TAB ───────────────────────────────────────────────────────────
  Widget _buildHistoryTab() {
    if (_listLoading) {
      return Center(child: CircularProgressIndicator(color: _accent));
    }

    final open = _reports.where((r) => r['status'] == 'OPEN').length;
    final solved = _reports.where((r) => r['status'] == 'SOLVED').length;

    return RefreshIndicator(
      onRefresh: _loadReports,
      color: _accent,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _buildSummaryBanner(open, solved),
          const SizedBox(height: 16),
          if (_reports.isEmpty)
            _buildEmptyState()
          else
            ...(_reports.map(_buildReportCard)),
        ],
      ),
    );
  }

  Widget _buildSummaryBanner(int open, int solved) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_accent, const Color(0xFFEA580C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _accent.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _statItem(_reports.length.toString(), 'Total'),
          Container(width: 1, height: 40, color: Colors.white30),
          _statItem(open.toString(), 'Open'),
          Container(width: 1, height: 40, color: Colors.white30),
          _statItem(solved.toString(), 'Solved'),
        ],
      ),
    );
  }

  Widget _statItem(String value, String label) => Column(
    children: [
      Text(value,
          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
      const SizedBox(height: 2),
      Text(label, style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12)),
    ],
  );

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        children: [
          Icon(Icons.event_available_rounded, size: 64, color: _sub),
          const SizedBox(height: 16),
          Text('No reports yet.',
              style: TextStyle(color: _text, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('Tap "New Report" to file one.',
              style: TextStyle(color: _sub, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildReportCard(Map<String, dynamic> r) {
    final guardName = r['guard']?['name'] ?? 'Unknown Guard';
    final siteName = r['site']?['name'] ?? 'Unknown Site';
    final shiftLabel = r['shift']?['label'] ?? '--:-- – --:--';
    final date = _displayDate(r['eventDate']?.toString());
    final status = r['status']?.toString() ?? 'OPEN';
    final desc = r['description']?.toString() ?? '';
    final isOpen = status == 'OPEN';

    final statusColor = isOpen ? const Color(0xFFF59E0B) : const Color(0xFF10B981);

    return GestureDetector(
      onTap: () => _showReportDetail(r),
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
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        Text(siteName, style: TextStyle(color: _sub, fontSize: 12)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: statusColor.withOpacity(0.4)),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
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
                  if (desc.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _detailRow(Icons.notes_rounded, 'Note',
                        desc.length > 80 ? '${desc.substring(0, 80)}…' : desc),
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

  void _showReportDetail(Map<String, dynamic> r) {
    final guardName = r['guard']?['name'] ?? 'Unknown Guard';
    final siteName = r['site']?['name'] ?? 'Unknown Site';
    final shiftLabel = r['shift']?['label'] ?? '--';
    final date = _displayDate(r['eventDate']?.toString());
    final status = r['status']?.toString() ?? 'OPEN';
    final desc = r['description']?.toString() ?? '';
    final supervisor = r['supervisor']?['name'] ?? '–';
    final isOpen = status == 'OPEN';
    final statusColor = isOpen ? const Color(0xFFF59E0B) : const Color(0xFF10B981);

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
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _sub,
                    borderRadius: BorderRadius.circular(10),
                  ),
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
                      style: const TextStyle(
                          color: _accent, fontWeight: FontWeight.bold, fontSize: 22),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(guardName,
                            style: TextStyle(
                                color: _text, fontWeight: FontWeight.bold, fontSize: 18)),
                        Text(siteName, style: TextStyle(color: _sub, fontSize: 13)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: statusColor.withOpacity(0.4)),
                    ),
                    child: Text(status,
                        style: TextStyle(
                            color: statusColor, fontWeight: FontWeight.bold, fontSize: 13)),
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
              _sheetRow(Icons.person_outlined, 'Reported By', supervisor),
              if (desc.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Description',
                    style: TextStyle(
                        color: _sub, fontSize: 12, fontWeight: FontWeight.w600,
                        letterSpacing: 0.5)),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _bg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _border),
                  ),
                  child: Text(desc, style: TextStyle(color: _text, fontSize: 14, height: 1.5)),
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
              style: TextStyle(color: _text, fontSize: 13, fontWeight: FontWeight.w600))),
    ],
  );

  // ── FORM TAB ──────────────────────────────────────────────────────────────
  Widget _buildFormTab() {
    if (_loadingOptions) {
      return Center(child: CircularProgressIndicator(color: _accent));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader('Report Details'),
            const SizedBox(height: 16),

            // ── Site ──────────────────────────────────────────────────────
            _label('Site'),
            const SizedBox(height: 6),
            _dropdown<int>(
              hint: _sites.isEmpty ? 'No sites available' : 'Select site…',
              value: _selectedSiteId,
              items: _sites.map((s) => DropdownMenuItem<int>(
                value: _toInt(s['id']),
                child: Text((s['name'] ?? '').toString(),
                    style: TextStyle(color: _text)),
              )).toList(),
              onChanged: _saving ? null : _onSiteChanged,
              validator: (v) => v == null ? 'Please select a site' : null,
            ),

            const SizedBox(height: 16),

            // ── Guard ─────────────────────────────────────────────────────
            _label('Guard'),
            const SizedBox(height: 6),
            _loadingGuardsShifts
                ? _loadingIndicator('Loading guards…')
                : _dropdown<int>(
                    hint: _selectedSiteId == null
                        ? 'Select a site first'
                        : _guards.isEmpty
                            ? 'No guards assigned to this site'
                            : 'Select guard…',
                    value: _selectedGuardId,
                    items: _guards.map((g) => DropdownMenuItem<int>(
                      value: _toInt(g['id']),
                      child: Text(
                        _guards.any((x) => x['employeeId'] != null)
                            ? '${g['name'] ?? ''} (${g['employeeId'] ?? ''})'
                            : (g['name'] ?? '').toString(),
                        style: TextStyle(color: _text),
                      ),
                    )).toList(),
                    onChanged: _saving || _selectedSiteId == null
                        ? null
                        : (v) => setState(() => _selectedGuardId = v),
                    validator: (v) => v == null ? 'Please select a guard' : null,
                  ),

            const SizedBox(height: 16),

            // ── Shift ─────────────────────────────────────────────────────
            _label('Shift'),
            const SizedBox(height: 6),
            _loadingGuardsShifts
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
                      child: Text((s['label'] ?? '').toString(),
                          style: TextStyle(color: _text)),
                    )).toList(),
                    onChanged: _saving || _selectedSiteId == null
                        ? null
                        : (v) => setState(() => _selectedShiftId = v),
                    validator: (v) => v == null ? 'Please select a shift' : null,
                  ),

            const SizedBox(height: 16),

            // ── Date ──────────────────────────────────────────────────────
            _label('Incident Date'),
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
                    Text(
                      _displayDate(_isoDate(_eventDate)),
                      style: TextStyle(color: _text, fontSize: 15),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Description ───────────────────────────────────────────────
            _label('Description'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _descController,
              minLines: 4,
              maxLines: 6,
              enabled: !_saving,
              style: TextStyle(color: _text),
              decoration: InputDecoration(
                hintText: 'Describe the no call no show incident…',
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
                  v == null || v.trim().isEmpty ? 'Description is required' : null,
            ),

            const SizedBox(height: 28),

            // ── Submit ────────────────────────────────────────────────────
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
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text(
                        'Submit Report',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // ── form UI helpers ───────────────────────────────────────────────────────
  Widget _sectionHeader(String title) => Text(
    title,
    style: TextStyle(
        color: _text, fontSize: 17, fontWeight: FontWeight.bold),
  );

  Widget _label(String text) => Text(
    text,
    style: TextStyle(color: _sub, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5),
  );

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
          width: 16,
          height: 16,
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
