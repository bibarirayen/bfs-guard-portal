import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/no_call_no_show_service.dart';
import 'no_call_no_show_create_page.dart';

class NoCallNoShowListPage extends StatefulWidget {
  const NoCallNoShowListPage({super.key});

  @override
  State<NoCallNoShowListPage> createState() => _NoCallNoShowListPageState();
}

class _NoCallNoShowListPageState extends State<NoCallNoShowListPage> {
  final NoCallNoShowService _service = NoCallNoShowService();
  bool _loading = true;
  List<Map<String, dynamic>> _reports = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      setState(() => _loading = true);
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('userId');
      if (userId == null) throw Exception('Missing user session');
      final data = await _service.getSupervisorReports(userId);
      if (!mounted) return;
      setState(() => _reports = data);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load reports: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('No Call No Show List'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => const NoCallNoShowCreatePage()),
          );
          if (created == true) {
            _load();
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('New'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _reports.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 120),
                        Center(child: Text('No reports yet.')),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: _reports.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final report = _reports[i];
                        final guardName = report['guard']?['name'] ?? 'Guard';
                        final siteName = report['site']?['name'] ?? 'Site';
                        final shiftLabel = report['shift']?['label'] ?? '--:-- - --:--';
                        final date = report['eventDate']?.toString() ?? '';
                        final status = report['status']?.toString() ?? 'OPEN';
                        final desc = report['description']?.toString() ?? '';

                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '$guardName - $siteName',
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    Chip(
                                      label: Text(status),
                                      backgroundColor: status == 'SOLVED'
                                          ? Colors.green.shade100
                                          : Colors.orange.shade100,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text('Date: $date'),
                                Text('Shift: $shiftLabel'),
                                const SizedBox(height: 8),
                                Text(
                                  desc,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
