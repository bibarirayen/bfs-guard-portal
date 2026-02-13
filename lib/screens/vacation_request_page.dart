import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/ApiService.dart';

class VacationRequestPage extends StatefulWidget {
  const VacationRequestPage({super.key});

  @override
  State<VacationRequestPage> createState() => _VacationRequestPageState();
}

class _VacationRequestPageState extends State<VacationRequestPage> {
  // ---------- THEME ----------
  final bool _isDarkMode = true;

  Color get _backgroundColor => _isDarkMode ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
  Color get _cardColor => _isDarkMode ? const Color(0xFF1E293B) : Colors.white;
  Color get _borderColor => _isDarkMode ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
  Color get _textColor => _isDarkMode ? Colors.white : const Color(0xFF1E293B);
  Color get _secondaryTextColor => _isDarkMode ? Colors.grey[400]! : Colors.grey[600]!;
  Color get _primaryColor => const Color(0xFF4F46E5);

  final api = ApiService();

  List<dynamic> _vacations = [];
  bool _loading = true;

  // ---------- ADD REQUEST ----------
  DateTime? _dateFrom;
  DateTime? _dateTo;
  final TextEditingController _reasonController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchMyVacations();
  }

  // ================= FETCH =================
  Future<void> _fetchMyVacations() async {
    setState(() => _loading = true);

    final prefs = await SharedPreferences.getInstance();
    final guardId = prefs.getInt('userId');
    if (guardId == null) return;

    try {
      final res = await api.get("vacation-requests/by-guard/$guardId");

      if (res.statusCode == 200) {
        setState(() {
          _vacations = jsonDecode(res.body);
          _loading = false;
        });
      } else {
        throw Exception("Failed to load vacation requests");
      }
    } catch (e) {
      debugPrint("Vacation fetch error: $e");
      setState(() => _loading = false);
    }
  }

  // ================= SUBMIT =================
  Future<void> _submitVacationRequest() async {
    final prefs = await SharedPreferences.getInstance();
    final guardId = prefs.getInt('userId');

    if (_dateFrom == null || _dateTo == null || _reasonController.text.isEmpty) {
      return;
    }

    final payload = {
      "dateFrom": _dateFrom!.toIso8601String().split("T")[0],
      "dateTo": _dateTo!.toIso8601String().split("T")[0],
      "reason": _reasonController.text,
      "guard": {"id": guardId}
    };

    final res = await api.post("vacation-requests", payload);

    if (res.statusCode == 200 || res.statusCode == 201) {
      Navigator.pop(context);

      setState(() {
        _dateFrom = null;
        _dateTo = null;
        _reasonController.clear();
      });

      _fetchMyVacations();
    }
  }

  // ================= MODAL (FIXED) =================
  void _openAddModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _cardColor,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, modalSetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "New Vacation Request",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _textColor,
                    ),
                  ),
                  const SizedBox(height: 16),

                  _datePicker(
                    "From Date",
                    _dateFrom,
                        (d) => modalSetState(() => _dateFrom = d),
                  ),
                  const SizedBox(height: 12),

                  _datePicker(
                    "To Date",
                    _dateTo,
                        (d) => modalSetState(() => _dateTo = d),
                  ),
                  const SizedBox(height: 12),

                  TextField(
                    controller: _reasonController,
                    maxLines: 3,
                    style: TextStyle(color: _textColor),
                    decoration: _input("Reason"),
                  ),
                  const SizedBox(height: 20),

                  ElevatedButton(
                    onPressed: _submitVacationRequest,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryColor,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text("Submit"),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ================= UI HELPERS =================
  InputDecoration _input(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: _secondaryTextColor),
      filled: true,
      fillColor: _isDarkMode ? const Color(0xFF2D3748) : Colors.grey[100],
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    );
  }

  Widget _datePicker(String label, DateTime? value, Function(DateTime) onPick) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime.now(),
          lastDate: DateTime(2100),
        );
        if (picked != null) onPick(picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: _isDarkMode ? const Color(0xFF2D3748) : Colors.grey[100],
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _borderColor),
        ),
        child: Text(
          value == null
              ? label
              : "${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}",
          style: TextStyle(
            color: value == null ? _secondaryTextColor : _textColor,
          ),
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case "APPROVED":
        return Colors.green;
      case "REFUSED":
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  // ================= BUILD =================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      floatingActionButton: FloatingActionButton(
        backgroundColor: _primaryColor,
        onPressed: _openAddModal,
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [


              Expanded(
                child: ListView.builder(
                  itemCount: _vacations.length,
                  itemBuilder: (_, i) {
                    final v = _vacations[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _cardColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _borderColor),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "${v['dateFrom']} → ${v['dateTo']}",
                            style: TextStyle(
                              color: _textColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            v['reason'] ?? "",
                            style: TextStyle(color: _secondaryTextColor),
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Chip(
                              label: Text(v['status']),
                              backgroundColor:
                              _statusColor(v['status']).withOpacity(0.2),
                              labelStyle: TextStyle(
                                color: _statusColor(v['status']),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
