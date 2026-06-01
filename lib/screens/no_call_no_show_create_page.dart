import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/no_call_no_show_service.dart';

class NoCallNoShowCreatePage extends StatefulWidget {
  const NoCallNoShowCreatePage({super.key});

  @override
  State<NoCallNoShowCreatePage> createState() => _NoCallNoShowCreatePageState();
}

class _NoCallNoShowCreatePageState extends State<NoCallNoShowCreatePage> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final NoCallNoShowService _service = NoCallNoShowService();

  bool _loadingOptions = true;
  bool _saving = false;

  int? _userId;
  DateTime _eventDate = DateTime.now();

  List<Map<String, dynamic>> _sites = [];
  List<Map<String, dynamic>> _guards = [];
  List<Map<String, dynamic>> _shifts = [];

  int? _selectedSiteId;
  int? _selectedGuardId;
  int? _selectedShiftId;

  @override
  void initState() {
    super.initState();
    _loadInitialOptions();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialOptions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _userId = prefs.getInt('userId');
      if (_userId == null) throw Exception('Missing user session');

      final sites = await _service.getSiteOptions(_userId!);
      if (!mounted) return;
      setState(() => _sites = sites);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load options: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _loadingOptions = false);
      }
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
      final guards = await _service.getGuardOptions(_userId!, siteId);
      final shifts = await _service.getShiftOptions(_userId!, siteId);
      if (!mounted) return;
      setState(() {
        _guards = guards;
        _shifts = shifts;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load guards/shifts: $e')),
      );
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _eventDate,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1),
    );
    if (picked != null) {
      setState(() => _eventDate = picked);
    }
  }

  String _dateIso(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_userId == null || _selectedSiteId == null || _selectedGuardId == null || _selectedShiftId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select site, guard, and shift.')),
      );
      return;
    }

    try {
      setState(() => _saving = true);

      final payload = {
        'supervisorId': _userId,
        'guardId': _selectedGuardId,
        'siteId': _selectedSiteId,
        'shiftId': _selectedShiftId,
        'eventDate': _dateIso(_eventDate),
        'description': _descriptionController.text.trim(),
      };

      await _service.create(payload);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No Call No Show report submitted.')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to submit report: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New No Call No Show')),
      body: _loadingOptions
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<int>(
                      value: _selectedSiteId,
                      decoration: const InputDecoration(labelText: 'Site *'),
                      items: _sites
                          .map((s) => DropdownMenuItem<int>(
                                value: s['id'] as int,
                                child: Text((s['name'] ?? '').toString()),
                              ))
                          .toList(),
                      onChanged: _saving ? null : _onSiteChanged,
                      validator: (value) => value == null ? 'Please select a site' : null,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      value: _selectedGuardId,
                      decoration: const InputDecoration(labelText: 'Guard *'),
                      items: _guards
                          .map((g) => DropdownMenuItem<int>(
                                value: g['id'] as int,
                                child: Text((g['name'] ?? '').toString()),
                              ))
                          .toList(),
                      onChanged: _saving ? null : (value) => setState(() => _selectedGuardId = value),
                      validator: (value) => value == null ? 'Please select a guard' : null,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      value: _selectedShiftId,
                      decoration: const InputDecoration(labelText: 'Shift *'),
                      items: _shifts
                          .map((s) => DropdownMenuItem<int>(
                                value: s['id'] as int,
                                child: Text((s['label'] ?? '').toString()),
                              ))
                          .toList(),
                      onChanged: _saving ? null : (value) => setState(() => _selectedShiftId = value),
                      validator: (value) => value == null ? 'Please select a shift' : null,
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: _saving ? null : _pickDate,
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Date *',
                          border: OutlineInputBorder(),
                        ),
                        child: Text(_dateIso(_eventDate)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _descriptionController,
                      minLines: 4,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        labelText: 'Description *',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Description is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _submit,
                        child: _saving
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Submit'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
