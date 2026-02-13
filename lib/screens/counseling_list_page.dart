import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/counseling_service.dart';

class CounselingListPage extends StatefulWidget {
  const CounselingListPage({super.key});

  @override
  State<CounselingListPage> createState() => _CounselingListPageState();
}

class _CounselingListPageState extends State<CounselingListPage> {
  final _service = CounselingService();
  bool _loading = true;
  List<Map<String, dynamic>> _statements = [];

  bool _isDarkMode = true; // for consistent styling

  @override
  void initState() {
    super.initState();
    fetchStatements();
    print(_statements);
  }

  Future<void> fetchStatements() async {
    setState(() => _loading = true);
    try {
      final data = await _service.getAllStatements();
      setState(() => _statements = data);
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  // ================== HELPER FUNCTIONS ==================
  String getSiteName(dynamic site) {
    if (site is Map && site.containsKey('name')) {
      return site['name'];
    } else if (site is int) {
      return 'Site ID: $site';
    }
    return 'No Site';
  }

  String getPersonName(dynamic person) {
    if (person is Map &&
        person.containsKey('firstName') &&
        person.containsKey('lastName')) {
      return "${person['firstName']} ${person['lastName']}";
    } else if (person is int) {
      return 'ID: $person';
    }
    return '-';
  }
  // =====================================================

  Color get _backgroundColor =>
      _isDarkMode ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
  Color get _cardColor =>
      _isDarkMode ? const Color(0xFF1E293B) : Colors.white;
  Color get _textColor =>
      _isDarkMode ? Colors.white : const Color(0xFF1E293B);
  Color get _secondaryTextColor =>
      _isDarkMode ? Colors.grey[400]! : Colors.grey[600]!;
  Color get _borderColor =>
      _isDarkMode ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

  void _showStatementDetails(Map<String, dynamic> statement) {
    final images = statement['mediaUrls'];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 50,
                  height: 5,
                  decoration: BoxDecoration(
                    color: _secondaryTextColor.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                statement['title'] ?? 'No Type',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: _textColor,
                ),
              ),
              const SizedBox(height: 12),
              _infoRow('Supervisor', getPersonName(statement['supervisor'])),
              _infoRow('Guard', getPersonName(statement['guard'])),
              _infoRow('Category', statement['category'] ?? '-'),
              _infoRow('Site', getSiteName(statement['site'])),
              _infoRow('Date', statement['createdAt'] ?? '-'),
              _infoRow('Status', statement['status'] ?? '-'),

              const SizedBox(height: 12),
              Text(
                'Description',
                style: TextStyle(fontWeight: FontWeight.bold, color: _textColor),
              ),
              const SizedBox(height: 8),
              Text(
                statement['description'] ?? 'No description available',
                style: TextStyle(color: _textColor),
              ),

              const SizedBox(height: 16),
              if (images != null && images is List && images.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Images',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: _textColor)),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 200,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: images.length,
                        itemBuilder: (context, index) {
                          final imgUrl = images[index];
                          return Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(15),
                              child: Image.network(
                                imgUrl,
                                width: 200,
                                height: 200,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                const Icon(Icons.broken_image, size: 50),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text("$label:", style: TextStyle(color: _secondaryTextColor)),
          ),
          Expanded(
            child: Text(
              value ?? '-',
              style: TextStyle(fontWeight: FontWeight.w500, color: _textColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatementCard(Map<String, dynamic> statement) {
    return GestureDetector(
      onTap: () => _showStatementDetails(statement),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _cardColor,
          borderRadius: BorderRadius.circular(25),
          border: Border.all(color: _borderColor),
        ),
        child: Row(
          children: [
            const Icon(Icons.description_outlined,
                size: 32, color: Color(0xFF4F46E5)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    statement['title'] ?? 'No Type',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: _textColor),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    getSiteName(statement['site']),
                    style: TextStyle(
                        fontWeight: FontWeight.w500, color: _secondaryTextColor),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 18, color: _secondaryTextColor),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,

      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _statements.length,
        itemBuilder: (context, i) => _buildStatementCard(_statements[i]),
      ),
    );
  }
}
