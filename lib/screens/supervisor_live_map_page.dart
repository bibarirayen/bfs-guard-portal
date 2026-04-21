import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stomp_dart_client/stomp.dart';
import 'package:stomp_dart_client/stomp_config.dart';
import 'package:stomp_dart_client/stomp_frame.dart';
import '../config/ApiService.dart';

class SupervisorLiveMapPage extends StatefulWidget {
  const SupervisorLiveMapPage({super.key});

  @override
  State<SupervisorLiveMapPage> createState() =>
      _SupervisorLiveMapPageState();
}

class _SupervisorLiveMapPageState extends State<SupervisorLiveMapPage> {
  // ─── theme ────────────────────────────────────────────────────────────────
  Color get _bg => const Color(0xFF0F172A);
  Color get _card => const Color(0xFF1E293B);
  Color get _text => Colors.white;
  Color get _sub => Colors.grey[400]!;
  Color get _border => const Color(0xFF334155);
  Color get _primary => const Color(0xFF4F46E5);

  // ─── state ────────────────────────────────────────────────────────────────
  bool _loading = true;
  String? _error;
  String? _userId;
  Set<dynamic> _mySiteIds = {};
  List<Map<String, dynamic>> _mySites = [];

  // guard locations: guardId -> location data
  Map<String, Map<String, dynamic>> _guardLocations = {};

  StompClient? _stompClient;
  final MapController _mapController = MapController();
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _userId = prefs.getString('userId');
    await _loadSupervisorSites();
    await _loadInitialLocations();
    _connectStomp();
  }

  Future<void> _loadSupervisorSites() async {
    try {
      final api = ApiService();
      final res = await api.get('sites');
      if (res.statusCode == 200) {
        final List allSites = jsonDecode(res.body) as List;
        final mySites = allSites.where((s) {
          final ids = (s['supervisorIds'] as List?)?.cast<dynamic>() ?? [];
          return ids.any((id) => id.toString() == _userId.toString());
        }).map((s) => s as Map<String, dynamic>).toList();
        setState(() {
          _mySites = mySites;
          _mySiteIds = mySites.map((s) => s['id']).toSet();
        });
      }
    } catch (_) {}
  }

  Future<void> _loadInitialLocations() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ApiService();
      final res = await api.get('locations/all');
      if (res.statusCode == 200) {
        final List data = jsonDecode(res.body) as List;
        final Map<String, Map<String, dynamic>> locations = {};
        for (final loc in data) {
          final siteId = loc['siteId'];
          if (siteId != null && _mySiteIds.contains(siteId)) {
            final key = loc['id'].toString();
            locations[key] = loc as Map<String, dynamic>;
          }
        }
        setState(() {
          _guardLocations = locations;
          _loading = false;
        });

        // Center map on first guard or first site
        if (_mapReady) _fitMapBounds();
      } else {
        setState(() {
          _error = 'Failed to load locations.';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Could not connect to server.';
        _loading = false;
      });
    }
  }

  void _connectStomp() {
    _stompClient?.deactivate();
    _stompClient = StompClient(
      config: StompConfig(
        url: 'wss://api.blackfabricsecurity.com/ws',
        reconnectDelay: const Duration(seconds: 10),
        onConnect: (StompFrame frame) {
          _stompClient!.subscribe(
            destination: '/topic/guards',
            callback: (StompFrame frame) {
              if (frame.body == null) return;
              try {
                final data =
                    jsonDecode(frame.body!) as Map<String, dynamic>;
                final siteId = data['siteId'];
                if (siteId != null && _mySiteIds.contains(siteId)) {
                  final key = data['id'].toString();
                  if (mounted) {
                    setState(() {
                      _guardLocations[key] = data;
                    });
                  }
                }
              } catch (_) {}
            },
          );
        },
        onWebSocketError: (e) =>
            debugPrint('LiveMap WS error: $e'),
        onDisconnect: (_) =>
            debugPrint('LiveMap WS disconnected'),
      ),
    );
    _stompClient!.activate();
  }

  void _fitMapBounds() {
    final points = <LatLng>[];
    for (final loc in _guardLocations.values) {
      final lat = loc['latitude'];
      final lng = loc['longitude'];
      if (lat != null && lng != null) {
        points.add(LatLng((lat as num).toDouble(), (lng as num).toDouble()));
      }
    }
    for (final site in _mySites) {
      final lat = site['latitude'];
      final lng = site['longitude'];
      if (lat != null && lng != null) {
        points.add(LatLng((lat as num).toDouble(), (lng as num).toDouble()));
      }
    }
    if (points.isEmpty) return;
    if (points.length == 1) {
      _mapController.move(points.first, 14);
      return;
    }
    final lats = points.map((p) => p.latitude);
    final lngs = points.map((p) => p.longitude);
    final bounds = LatLngBounds(
      LatLng(lats.reduce((a, b) => a < b ? a : b),
          lngs.reduce((a, b) => a < b ? a : b)),
      LatLng(lats.reduce((a, b) => a > b ? a : b),
          lngs.reduce((a, b) => a > b ? a : b)),
    );
    _mapController.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(50)),
    );
  }

  @override
  void dispose() {
    _stompClient?.deactivate();
    super.dispose();
  }

  String _staleness(String? lastUpdate) {
    if (lastUpdate == null) return '';
    try {
      final dt = DateTime.parse(lastUpdate);
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 2) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      return '${diff.inHours}h ago';
    } catch (_) {
      return '';
    }
  }

  bool _isStale(String? lastUpdate) {
    if (lastUpdate == null) return true;
    try {
      final dt = DateTime.parse(lastUpdate);
      return DateTime.now().difference(dt).inMinutes > 5;
    } catch (_) {
      return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _card,
        foregroundColor: _text,
        title: Text('Live Map',
            style: TextStyle(color: _text, fontWeight: FontWeight.bold)),
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: _primary),
            onPressed: () async {
              await _loadSupervisorSites();
              await _loadInitialLocations();
            },
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
                        onPressed: () async {
                          await _loadSupervisorSites();
                          await _loadInitialLocations();
                        },
                        style: ElevatedButton.styleFrom(
                            backgroundColor: _primary),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Guard count bar
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      color: _card,
                      child: Row(
                        children: [
                          Icon(Icons.people, color: _primary, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            '${_guardLocations.length} guard(s) on duty',
                            style: TextStyle(color: _text, fontSize: 13),
                          ),
                          const Spacer(),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text('Live',
                              style:
                                  TextStyle(color: _sub, fontSize: 12)),
                        ],
                      ),
                    ),
                    // Map
                    Expanded(
                      child: FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: _guardLocations.isNotEmpty
                              ? LatLng(
                                  (_guardLocations.values.first[
                                              'latitude'] as num)
                                          .toDouble(),
                                  (_guardLocations.values.first[
                                              'longitude'] as num)
                                          .toDouble())
                              : _mySites.isNotEmpty
                                  ? LatLng(
                                      (_mySites.first['latitude'] as num)
                                          .toDouble(),
                                      (_mySites.first['longitude'] as num)
                                          .toDouble())
                                  : const LatLng(21.3069, -157.8583),
                          initialZoom: 13,
                          onMapReady: () {
                            _mapReady = true;
                            if (!_loading) _fitMapBounds();
                          },
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                            subdomains: const ['a', 'b', 'c'],
                            userAgentPackageName:
                                'com.blackfabricsecurity.app',
                          ),
                          // Site markers
                          MarkerLayer(
                            markers: _mySites.map((site) {
                              final lat = site['latitude'];
                              final lng = site['longitude'];
                              if (lat == null || lng == null) {
                                return Marker(
                                  point: const LatLng(0, 0),
                                  child: const SizedBox.shrink(),
                                );
                              }
                              return Marker(
                                point: LatLng((lat as num).toDouble(),
                                    (lng as num).toDouble()),
                                width: 44,
                                height: 44,
                                child: Tooltip(
                                  message: site['name'] ?? 'Site',
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: _primary.withOpacity(0.15),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: _primary, width: 2),
                                    ),
                                    child: Icon(Icons.location_city,
                                        color: _primary, size: 20),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          // Guard markers
                          MarkerLayer(
                            markers: _guardLocations.values.map((loc) {
                              final lat = loc['latitude'];
                              final lng = loc['longitude'];
                              if (lat == null || lng == null) {
                                return Marker(
                                  point: const LatLng(0, 0),
                                  child: const SizedBox.shrink(),
                                );
                              }
                              final stale = _isStale(loc['lastUpdate']);
                              final color =
                                  stale ? Colors.grey : Colors.green;
                              return Marker(
                                point: LatLng((lat as num).toDouble(),
                                    (lng as num).toDouble()),
                                width: 44,
                                height: 60,
                                child: GestureDetector(
                                  onTap: () =>
                                      _showGuardInfo(context, loc),
                                  child: Column(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color:
                                              color.withOpacity(0.2),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                              color: color, width: 2),
                                        ),
                                        child: Icon(
                                            Icons.security,
                                            color: color,
                                            size: 18),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 3, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: _card.withOpacity(0.9),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          (loc['name'] ?? '')
                                              .toString()
                                              .split(' ')
                                              .first,
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                    // Guard list panel
                    if (_guardLocations.isNotEmpty)
                      Container(
                        height: 130,
                        color: _card,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.all(12),
                          itemCount: _guardLocations.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 8),
                          itemBuilder: (_, i) {
                            final loc =
                                _guardLocations.values.elementAt(i);
                            final stale =
                                _isStale(loc['lastUpdate']);
                            return GestureDetector(
                              onTap: () {
                                final lat = loc['latitude'];
                                final lng = loc['longitude'];
                                if (lat != null && lng != null) {
                                  _mapController.move(
                                    LatLng(
                                        (lat as num).toDouble(),
                                        (lng as num).toDouble()),
                                    15,
                                  );
                                }
                              },
                              child: Container(
                                width: 130,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: _bg,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: stale
                                          ? Colors.grey.withOpacity(0.3)
                                          : Colors.green.withOpacity(0.3)),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            color: stale
                                                ? Colors.grey
                                                : Colors.green,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            loc['name'] ?? '',
                                            style: TextStyle(
                                                color: _text,
                                                fontWeight:
                                                    FontWeight.bold,
                                                fontSize: 12),
                                            overflow:
                                                TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      loc['site'] ?? '',
                                      style: TextStyle(
                                          color: _sub, fontSize: 11),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      loc['worktime'] ?? '',
                                      style: TextStyle(
                                          color: _primary, fontSize: 10),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _staleness(
                                          loc['lastUpdate']?.toString()),
                                      style: TextStyle(
                                          color: stale
                                              ? Colors.grey
                                              : Colors.green,
                                          fontSize: 10),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
    );
  }

  void _showGuardInfo(BuildContext ctx, Map<String, dynamic> loc) {
    showModalBottomSheet(
      context: ctx,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _primary.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.security, color: _primary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(loc['name'] ?? '',
                          style: TextStyle(
                              color: _text,
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                      Text(loc['site'] ?? '',
                          style: TextStyle(color: _sub, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _infoRow(Icons.access_time, 'Shift', loc['worktime'] ?? '--'),
            const SizedBox(height: 8),
            _infoRow(Icons.update, 'Last update',
                _staleness(loc['lastUpdate']?.toString())),
            const SizedBox(height: 8),
            _infoRow(Icons.location_on, 'Coordinates',
                '${(loc['latitude'] as num?)?.toStringAsFixed(5) ?? '--'}, ${(loc['longitude'] as num?)?.toStringAsFixed(5) ?? '--'}'),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: _sub, size: 16),
        const SizedBox(width: 8),
        Text('$label: ', style: TextStyle(color: _sub, fontSize: 13)),
        Expanded(
            child: Text(value,
                style: TextStyle(
                    color: _text,
                    fontSize: 13,
                    fontWeight: FontWeight.w500))),
      ],
    );
  }
}
