import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
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

class _SupervisorLiveMapPageState extends State<SupervisorLiveMapPage>
    with TickerProviderStateMixin {
  // ─── theme ───────────────────────────────────────────────────────────────
  static const _bg      = Color(0xFF0F172A);
  static const _card    = Color(0xFF1E293B);
  static const _cardBdr = Color(0xFF334155);
  static const _primary = Color(0xFF6366F1);
  static const _green   = Color(0xFF10B981);
  static const _amber   = Color(0xFFF59E0B);

  Color get _text => Colors.white;
  Color get _sub  => Colors.grey[400]!;

  // ─── state ───────────────────────────────────────────────────────────────
  bool    _loading = true;
  String? _error;
  int?    _userId;

  List<Map<String, dynamic>>        _mySites        = [];
  Set<dynamic>                      _mySiteIds      = {};
  Map<String, Map<String, dynamic>> _guardLocations = {};

  String? _selectedSiteFilter;
  String? _selectedGuardKey;
  int     _sheetTab = 0; // 0 = guards, 1 = sites

  StompClient? _stompClient;
  GoogleMapController? _googleMapController;
  final Set<Marker>   _gMarkers = {};
  bool _mapReady = false;

  late AnimationController _pulseCtrl;
  late Animation<double>   _pulseAnim;
  bool _panelExpanded = false;
  final ScrollController _guardListCtrl = ScrollController();
  final ScrollController _siteListCtrl  = ScrollController();

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.75, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _init();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _guardListCtrl.dispose();
    _siteListCtrl.dispose();
    _stompClient?.deactivate();
    super.dispose();
  }

  // ─── init ────────────────────────────────────────────────────────────────
  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _userId = prefs.getInt('userId');
    await _loadSupervisorSites();
    await _loadInitialLocations();
    _connectStomp();
  }

  Future<void> _loadSupervisorSites() async {
    try {
      final res = await ApiService().get('sites');
      if (res.statusCode == 200) {
        final List all = jsonDecode(res.body) as List;
        final my = all.where((s) {
          final ids = (s['supervisorIds'] as List?)?.cast<dynamic>() ?? [];
          return ids.any((id) => (id as num?)?.toInt() == _userId);
        }).map((s) => s as Map<String, dynamic>).toList();
        setState(() {
          _mySites   = my;
          _mySiteIds = my.map((s) => s['id']).toSet();
        });
      }
    } catch (_) {}
  }

  Future<void> _loadInitialLocations() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiService().get('locations/all');
      if (res.statusCode == 200) {
        final List data = jsonDecode(res.body) as List;
        final Map<String, Map<String, dynamic>> locs = {};
        for (final loc in data) {
          final siteId = loc['siteId'];
          if (siteId != null && _mySiteIds.contains(siteId)) {
            locs[loc['id'].toString()] = loc as Map<String, dynamic>;
          }
        }
        setState(() { _guardLocations = locs; _loading = false; });
        _rebuildMarkers();
        if (_mapReady) _fitAll();
      } else {
        setState(() { _error = 'Server error (${res.statusCode})'; _loading = false; });
      }
    } catch (_) {
      setState(() { _error = 'Could not connect to server.'; _loading = false; });
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
                final data = jsonDecode(frame.body!) as Map<String, dynamic>;
                final siteId = data['siteId'];
                if (siteId != null && _mySiteIds.contains(siteId)) {
                  final key = data['id'].toString();
                  if (mounted) {
                  setState(() => _guardLocations[key] = data);
                  _rebuildMarkers();
                }
                }
              } catch (_) {}
            },
          );
        },
        onWebSocketError: (e) => debugPrint('LiveMap WS error: $e'),
      ),
    );
    _stompClient!.activate();
  }

  // ─── custom marker bitmaps ──────────────────────────────────────────────
  BitmapDescriptor? _iconOnline;
  BitmapDescriptor? _iconOffline;
  BitmapDescriptor? _iconSite;

  /// Draw a circle pin with an emoji label inside.
  /// [bgColor] is the fill; [emoji] is rendered in the centre.
  Future<BitmapDescriptor> _buildEmojiPin(
      Color bgColor, Color borderColor, String emoji) async {
    const double size = 96;
    const double radius = 40;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(const Offset(size / 2, size / 2 + 2), radius, shadowPaint);

    // Background circle
    final bgPaint = Paint()..color = bgColor;
    canvas.drawCircle(const Offset(size / 2, size / 2), radius, bgPaint);

    // Border
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawCircle(const Offset(size / 2, size / 2), radius, borderPaint);

    // Emoji text
    final paragraphBuilder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        textAlign: TextAlign.center,
        fontSize: 36,
      ),
    )
      ..addText(emoji);
    final paragraph = paragraphBuilder.build()
      ..layout(const ui.ParagraphConstraints(width: size));
    canvas.drawParagraph(paragraph, Offset(0, (size - paragraph.height) / 2 - 2));

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(byteData!.buffer.asUint8List());
  }

  Future<void> _ensureIcons() async {
    _iconOnline ??= await _buildEmojiPin(
        const Color(0xFF064E3B), const Color(0xFF10B981), '🟢');
    _iconOffline ??= await _buildEmojiPin(
        const Color(0xFF1F2937), const Color(0xFF6B7280), '⚫');
    _iconSite ??= await _buildEmojiPin(
        const Color(0xFF1E1B4B), const Color(0xFF6366F1), '🏠');
  }

  // ─── helpers ─────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> get _filteredGuards =>
      _guardLocations.values.where((loc) {
        if (_selectedSiteFilter == null) return true;
        return loc['site']?.toString() == _selectedSiteFilter;
      }).toList();

  bool _isStale(String? ts) {
    if (ts == null) return true;
    try {
      return DateTime.now().difference(DateTime.parse(ts)).inMinutes > 5;
    } catch (_) { return true; }
  }

  String _staleness(String? ts) {
    if (ts == null) return 'Unknown';
    try {
      final diff = DateTime.now().difference(DateTime.parse(ts));
      if (diff.inSeconds < 60) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      return '${diff.inHours}h ago';
    } catch (_) { return 'Unknown'; }
  }

  void _fitAll() {
    if (_googleMapController == null) return;
    final lats = <double>[];
    final lngs = <double>[];
    for (final loc in _guardLocations.values) {
      final lat = loc['latitude']; final lng = loc['longitude'];
      if (lat != null && lng != null) {
        lats.add((lat as num).toDouble()); lngs.add((lng as num).toDouble());
      }
    }
    for (final s in _mySites) {
      final lat = s['latitude']; final lng = s['longitude'];
      if (lat != null && lng != null) {
        lats.add((lat as num).toDouble()); lngs.add((lng as num).toDouble());
      }
    }
    if (lats.isEmpty) return;
    if (lats.length == 1) {
      _googleMapController!.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(lats.first, lngs.first), 15));
      return;
    }
    _googleMapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(lats.reduce(min), lngs.reduce(min)),
          northeast: LatLng(lats.reduce(max), lngs.reduce(max)),
        ),
        70,
      ),
    );
  }

  void _rebuildMarkers() async {
    await _ensureIcons();
    final markers = <Marker>{};
    for (final loc in _filteredGuards) {
      final lat = loc['latitude']; final lng = loc['longitude'];
      if (lat == null || lng == null) continue;
      final stale = _isStale(loc['lastUpdate']?.toString());
      final key   = loc['id']?.toString() ?? '';
      markers.add(Marker(
        markerId: MarkerId(key),
        position: LatLng((lat as num).toDouble(), (lng as num).toDouble()),
        infoWindow: InfoWindow(
          title: loc['name']?.toString() ?? 'Guard',
          snippet: loc['site']?.toString(),
        ),
        icon: stale ? _iconOffline! : _iconOnline!,
        onTap: () => _showGuardSheet(context, loc),
      ));
    }
    for (final s in _mySites) {
      final lat = s['latitude']; final lng = s['longitude'];
      if (lat == null || lng == null) continue;
      if (_selectedSiteFilter != null && s['name']?.toString() != _selectedSiteFilter) continue;
      markers.add(Marker(
        markerId: MarkerId('site_${s['id']}'),
        position: LatLng((lat as num).toDouble(), (lng as num).toDouble()),
        infoWindow: InfoWindow(title: s['name']?.toString() ?? 'Site'),
        icon: _iconSite!,
      ));
    }
    if (mounted) setState(() => _gMarkers
      ..clear()
      ..addAll(markers));
  }

  void _flyToGuard(Map<String, dynamic> loc) {
    final lat = loc['latitude']; final lng = loc['longitude'];
    if (lat == null || lng == null) return;
    _googleMapController?.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng((lat as num).toDouble(), (lng as num).toDouble()), 16));
    setState(() {
      _selectedGuardKey = loc['id']?.toString();
      _panelExpanded = true;
    });
  }

  // ─── build ───────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text('Live Map',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: _primary),
            tooltip: 'Refresh',
            onPressed: () async {
              await _loadSupervisorSites();
              await _loadInitialLocations();
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _primary))
          : _error != null
              ? _buildError()
              : Column(
                  children: [
                    Expanded(
                      child: Stack(
                        children: [
                          _buildMap(),
                          _buildTopStatsBar(),
                          _buildMapControls(),
                          _buildSiteFilterChips(),
                        ],
                      ),
                    ),
                    _buildBottomPanel(),
                  ],
                ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.wifi_off_rounded, color: Colors.redAccent, size: 52),
          const SizedBox(height: 14),
          Text(_error!, style: TextStyle(color: _sub)),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            onPressed: () async {
              await _loadSupervisorSites();
              await _loadInitialLocations();
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(backgroundColor: _primary),
          ),
        ],
      ),
    );
  }

  // ─── Map (Google Maps) ────────────────────────────────────────────────────
  Widget _buildMap() {
    // Pick a sensible initial camera position.
    LatLng center = const LatLng(21.3069, -157.8583); // Hawaii fallback
    if (_guardLocations.isNotEmpty) {
      final first = _guardLocations.values.first;
      center = LatLng((first['latitude'] as num).toDouble(),
          (first['longitude'] as num).toDouble());
    } else if (_mySites.isNotEmpty) {
      final s = _mySites.first;
      if (s['latitude'] != null && s['longitude'] != null)
        center = LatLng((s['latitude'] as num).toDouble(),
            (s['longitude'] as num).toDouble());
    }

    return GoogleMap(
      initialCameraPosition: CameraPosition(target: center, zoom: 13),
      markers: _gMarkers,
      myLocationEnabled: true,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      compassEnabled: true,
      mapType: MapType.normal,
      onMapCreated: (ctrl) {
        _googleMapController = ctrl;
        _mapReady = true;
        _rebuildMarkers();
        if (!_loading) _fitAll();
      },
    );
  }

  // ─── Top stats bar ────────────────────────────────────────────────────────
  Widget _buildTopStatsBar() {
    final total  = _filteredGuards.length;
    final active = _filteredGuards
        .where((l) => !_isStale(l['lastUpdate']?.toString()))
        .length;
    final sites = _mySites.length;

    return Positioned(
      top: kToolbarHeight + MediaQuery.of(context).padding.top + 8,
      left: 12,
      right: 12,
      child: Row(
        children: [
          _statChip(Icons.people_alt_rounded, '$total', 'Guards', _primary),
          const SizedBox(width: 8),
          _statChip(Icons.circle, '$active', 'Active', _green),
          const SizedBox(width: 8),
          _statChip(Icons.location_city_rounded, '$sites', 'Sites', _amber),
        ],
      ),
    );
  }

  Widget _statChip(IconData icon, String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A).withOpacity(0.88),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.35)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 6,
                offset: const Offset(0, 2))
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 13),
            const SizedBox(width: 5),
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13)),
            const SizedBox(width: 3),
            Text(label, style: TextStyle(color: _sub, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  // ─── Map control buttons ──────────────────────────────────────────────────
  Widget _buildMapControls() {
    return Positioned(
      right: 12,
      bottom: 66,
      child: Column(
        children: [
          _mapBtn(Icons.add_rounded, 'Zoom in',
              () => _googleMapController?.animateCamera(CameraUpdate.zoomIn())),
          const SizedBox(height: 6),
          _mapBtn(Icons.remove_rounded, 'Zoom out',
              () => _googleMapController?.animateCamera(CameraUpdate.zoomOut())),
          const SizedBox(height: 14),
          _mapBtn(Icons.fit_screen_rounded, 'Fit all', _fitAll,
              color: _primary),
        ],
      ),
    );
  }

  Widget _mapBtn(IconData icon, String tooltip, VoidCallback onTap,
      {Color color = Colors.white}) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B).withOpacity(0.96),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF334155)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 3))
            ],
          ),
          child: Icon(icon, color: color, size: 22),
        ),
      ),
    );
  }

  // ─── Site filter chips ────────────────────────────────────────────────────
  Widget _buildSiteFilterChips() {
    if (_mySites.isEmpty) return const SizedBox.shrink();
    return Positioned(
      left: 0,
      right: 0,
      bottom: 8,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            _siteChip('All Sites', null),
            ..._mySites.map(
                (s) => _siteChip(s['name']?.toString() ?? 'Site',
                    s['name']?.toString())),
          ],
        ),
      ),
    );
  }

  Widget _siteChip(String label, String? value) {
    final selected = _selectedSiteFilter == value;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedSiteFilter = value);
        _rebuildMarkers();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? _primary
              : const Color(0xFF0F172A).withOpacity(0.88),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? _primary : const Color(0xFF334155)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.25),
                blurRadius: 6,
                offset: const Offset(0, 2))
          ],
        ),
        child: Text(label,
            style: TextStyle(
                color: selected ? Colors.white : _sub,
                fontWeight: FontWeight.w600,
                fontSize: 12)),
      ),
    );
  }

  // ─── Bottom panel (no gesture overlap with map) ───────────────────────────
  Widget _buildBottomPanel() {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragUpdate: (d) {
        if (d.delta.dy < -4 && !_panelExpanded)
          setState(() => _panelExpanded = true);
        if (d.delta.dy > 4 && _panelExpanded)
          setState(() => _panelExpanded = false);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
        // 124 collapsed (handle + tabs visible), 50% expanded for the list.
        height: _panelExpanded
            ? MediaQuery.of(context).size.height * 0.50
            : 124,
        decoration: BoxDecoration(
          color: _card,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(22)),
          border: Border.all(color: _cardBdr.withOpacity(0.6)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 20,
                offset: const Offset(0, -4))
          ],
        ),
        child: ClipRRect(
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(22)),
          child: Column(
            children: [
              // Drag handle — tap or swipe to expand/collapse
              GestureDetector(
                onTap: () =>
                    setState(() => _panelExpanded = !_panelExpanded),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  width: double.infinity,
                  alignment: Alignment.center,
                  color: Colors.transparent,
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: _cardBdr,
                        borderRadius: BorderRadius.circular(2)),
                  ),
                ),
              ),
              // Tabs
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Row(
                  children: [
                    _sheetTabBtn(
                        0, Icons.people_alt_rounded, 'Guards',
                        _filteredGuards.length),
                    const SizedBox(width: 8),
                    _sheetTabBtn(
                        1, Icons.location_city_rounded, 'Sites',
                        _mySites.length),
                    const Spacer(),
                    Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                            color: _green, shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    Text('Live',
                        style: TextStyle(color: _sub, fontSize: 11)),
                  ],
                ),
              ),
              // List — only rendered (and sized) when expanded
              if (_panelExpanded)
                Expanded(
                  child: _sheetTab == 0
                      ? _buildGuardList(_guardListCtrl)
                      : _buildSiteList(_siteListCtrl),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetTabBtn(int index, IconData icon, String label, int count) {
    final active = _sheetTab == index;
    return GestureDetector(
      onTap: () => setState(() => _sheetTab = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active ? _primary : _bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: active ? _primary : _cardBdr.withOpacity(0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: active ? Colors.white : _sub, size: 13),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    color: active ? Colors.white : _sub,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: active
                    ? Colors.white.withOpacity(0.2)
                    : _cardBdr.withOpacity(0.4),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('$count',
                  style: TextStyle(
                      color: active ? Colors.white : _sub,
                      fontSize: 10,
                      fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Guard list ───────────────────────────────────────────────────────────
  Widget _buildGuardList(ScrollController scrollCtrl) {
    if (_filteredGuards.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.location_off_rounded, color: _sub, size: 36),
            const SizedBox(height: 8),
            Text('No guards on duty', style: TextStyle(color: _sub)),
          ],
        ),
      );
    }
    return ListView.builder(
      controller: scrollCtrl,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      itemCount: _filteredGuards.length,
      itemBuilder: (_, i) => _buildGuardCard(_filteredGuards[i]),
    );
  }

  Widget _buildGuardCard(Map<String, dynamic> loc) {
    final key        = loc['id']?.toString() ?? '';
    final stale      = _isStale(loc['lastUpdate']?.toString());
    final color      = stale ? Colors.grey : _green;
    final isSelected = _selectedGuardKey == key;

    return GestureDetector(
      onTap: () => _flyToGuard(loc),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? _primary.withOpacity(0.1) : _bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: isSelected
                  ? _primary.withOpacity(0.6)
                  : _cardBdr.withOpacity(0.5)),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                      color: _primary.withOpacity(0.15),
                      blurRadius: 10,
                      offset: const Offset(0, 2))
                ]
              : [],
        ),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: color, width: 1.5),
                  ),
                  child: Icon(Icons.security_rounded, color: color, size: 20),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(color: _card, width: 1.5),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(loc['name'] ?? '--',
                      style: TextStyle(
                          color: _text,
                          fontWeight: FontWeight.bold,
                          fontSize: 13),
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Row(children: [
                    Icon(Icons.location_city_rounded, color: _sub, size: 11),
                    const SizedBox(width: 3),
                    Expanded(
                        child: Text(loc['site'] ?? '--',
                            style: TextStyle(color: _sub, fontSize: 11),
                            overflow: TextOverflow.ellipsis)),
                  ]),
                  const SizedBox(height: 2),
                  Row(children: [
                    Icon(Icons.access_time_rounded, color: _sub, size: 11),
                    const SizedBox(width: 3),
                    Text(loc['worktime'] ?? '--',
                        style: TextStyle(color: _sub, fontSize: 11)),
                  ]),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _staleness(loc['lastUpdate']?.toString()),
                    style: TextStyle(
                        color: color,
                        fontSize: 10,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 6),
                Icon(Icons.my_location_rounded,
                    color: isSelected ? _primary : _sub, size: 16),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── Site list ────────────────────────────────────────────────────────────
  Widget _buildSiteList(ScrollController scrollCtrl) {
    final sites = _selectedSiteFilter == null
        ? _mySites
        : _mySites
            .where((s) => s['name']?.toString() == _selectedSiteFilter)
            .toList();

    if (sites.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.location_city_rounded, color: _sub, size: 36),
            const SizedBox(height: 8),
            Text('No sites assigned', style: TextStyle(color: _sub)),
          ],
        ),
      );
    }
    return ListView.builder(
      controller: scrollCtrl,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      itemCount: sites.length,
      itemBuilder: (_, i) => _buildSiteCard(sites[i]),
    );
  }

  Widget _buildSiteCard(Map<String, dynamic> site) {
    final lat        = site['latitude'];
    final lng        = site['longitude'];
    final hasCoords  = lat != null && lng != null;
    final isFiltered = _selectedSiteFilter == site['name']?.toString();

    final guardCount = _guardLocations.values
        .where((l) => l['site']?.toString() == site['name']?.toString())
        .length;
    final activeCount = _guardLocations.values
        .where((l) =>
            l['site']?.toString() == site['name']?.toString() &&
            !_isStale(l['lastUpdate']?.toString()))
        .length;

    return GestureDetector(
      onTap: () {
        if (hasCoords) {
          _googleMapController?.animateCamera(CameraUpdate.newLatLngZoom(
              LatLng((lat as num).toDouble(), (lng as num).toDouble()), 15));
        }
        setState(() {
          _selectedSiteFilter =
              isFiltered ? null : site['name']?.toString();
        });
        _rebuildMarkers();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isFiltered ? _primary.withOpacity(0.1) : _bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: isFiltered
                  ? _primary.withOpacity(0.55)
                  : _cardBdr.withOpacity(0.5)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _primary.withOpacity(0.12),
                shape: BoxShape.circle,
                border:
                    Border.all(color: _primary.withOpacity(0.4), width: 1.5),
              ),
              child: const Icon(Icons.location_city_rounded,
                  color: _primary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(site['name']?.toString() ?? '--',
                      style: TextStyle(
                          color: _text,
                          fontWeight: FontWeight.bold,
                          fontSize: 13),
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Row(children: [
                    Icon(Icons.domain_rounded, color: _sub, size: 11),
                    const SizedBox(width: 3),
                    Expanded(
                        child: Text(
                            site['clientName']?.toString() ??
                                site['client']?.toString() ??
                                '--',
                            style: TextStyle(color: _sub, fontSize: 11),
                            overflow: TextOverflow.ellipsis)),
                  ]),
                  if (site['description'] != null &&
                      site['description'].toString().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Row(children: [
                      Icon(Icons.info_outline_rounded,
                          color: _sub, size: 11),
                      const SizedBox(width: 3),
                      Expanded(
                          child: Text(site['description'].toString(),
                              style: TextStyle(color: _sub, fontSize: 11),
                              overflow: TextOverflow.ellipsis)),
                    ]),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: activeCount > 0
                        ? _green.withOpacity(0.12)
                        : _cardBdr.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: activeCount > 0
                            ? _green.withOpacity(0.4)
                            : Colors.transparent),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.security_rounded,
                          color: activeCount > 0 ? _green : _sub, size: 11),
                      const SizedBox(width: 4),
                      Text('$activeCount/$guardCount',
                          style: TextStyle(
                              color: activeCount > 0 ? _green : _sub,
                              fontSize: 11,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Icon(
                  isFiltered
                      ? Icons.filter_alt_rounded
                      : Icons.my_location_rounded,
                  color: isFiltered ? _primary : _sub,
                  size: 15,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── Guard detail bottom sheet (tap marker) ───────────────────────────────
  void _showGuardSheet(BuildContext ctx, Map<String, dynamic> loc) {
    setState(() => _selectedGuardKey = loc['id']?.toString());
    final stale = _isStale(loc['lastUpdate']?.toString());
    final color = stale ? Colors.grey : _green;

    showModalBottomSheet(
      context: ctx,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: _cardBdr,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: color, width: 2),
                  ),
                  child: Icon(Icons.security_rounded, color: color, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(loc['name'] ?? '--',
                          style: TextStyle(
                              color: _text,
                              fontSize: 17,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Row(children: [
                        Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                                color: color, shape: BoxShape.circle)),
                        const SizedBox(width: 5),
                        Text(stale ? 'Inactive' : 'Active',
                            style: TextStyle(color: color, fontSize: 12)),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _infoTile(Icons.location_city_rounded, 'Site', loc['site']),
            const SizedBox(height: 8),
            _infoTile(Icons.access_time_rounded, 'Shift', loc['worktime']),
            const SizedBox(height: 8),
            _infoTile(Icons.update_rounded, 'Last update',
                _staleness(loc['lastUpdate']?.toString())),
            const SizedBox(height: 8),
            _infoTile(
              Icons.gps_fixed_rounded,
              'Coordinates',
              '${(loc['latitude'] as num?)?.toStringAsFixed(5) ?? '--'}, '
                  '${(loc['longitude'] as num?)?.toStringAsFixed(5) ?? '--'}',
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoTile(IconData icon, String label, String? value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _cardBdr.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          Icon(icon, color: _sub, size: 15),
          const SizedBox(width: 10),
          Text('$label  ', style: TextStyle(color: _sub, fontSize: 13)),
          Expanded(
            child: Text(
              value ?? '--',
              style: TextStyle(
                  color: _text, fontSize: 13, fontWeight: FontWeight.w600),
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
