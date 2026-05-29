// lib/widgets/common/engineer_route_map.dart
//
// Customer-facing live map: shows the assigned engineer's live position
// (streamed from ticket_engineer_locations) and a route line to the
// customer's own current location, with distance + rough ETA.
// Uses flutter_map (OpenStreetMap tiles) — no API key required.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../config/brand_colors.dart';
import '../../config/supabase_config.dart';
import '../../services/chat_attachment_service.dart';

class EngineerRouteMap extends StatefulWidget {
  final String ticketId;
  final double height;
  const EngineerRouteMap({super.key, required this.ticketId, this.height = 260});

  @override
  State<EngineerRouteMap> createState() => _EngineerRouteMapState();
}

class _EngineerRouteMapState extends State<EngineerRouteMap> {
  final MapController _map = MapController();
  StreamSubscription? _sub;
  LatLng? _engineer;
  LatLng? _me;
  DateTime? _updatedAt;
  bool _loading = true;
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // Customer's own location (best-effort) = the destination.
    final pos = await ChatAttachmentService.currentLocation();
    if (mounted && pos != null) {
      setState(() => _me = LatLng(pos.latitude, pos.longitude));
    }
    // Live engineer position.
    _sub = SupabaseConfig.client
        .from('ticket_engineer_locations')
        .stream(primaryKey: ['ticket_id'])
        .eq('ticket_id', widget.ticketId)
        .listen((rows) {
      if (!mounted) return;
      if (rows.isNotEmpty) {
        final r = rows.first;
        final lat = (r['lat'] as num?)?.toDouble();
        final lng = (r['lng'] as num?)?.toDouble();
        setState(() {
          if (lat != null && lng != null) _engineer = LatLng(lat, lng);
          _updatedAt =
              DateTime.tryParse(r['updated_at']?.toString() ?? '')?.toLocal();
          _loading = false;
        });
        _fit();
      } else {
        setState(() => _loading = false);
      }
    }, onError: (_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  void _fit() {
    if (!_mapReady || _engineer == null) return;
    final pts = <LatLng>[_engineer!, if (_me != null) _me!];
    if (pts.length < 2) {
      _map.move(_engineer!, 14);
    } else {
      _map.fitCamera(CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(pts),
        padding: const EdgeInsets.all(44),
      ));
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_loading) {
      return _shell(isDark,
          child: const Center(child: CircularProgressIndicator()));
    }
    if (_engineer == null) {
      return _shell(isDark,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Waiting for your engineer to share their location…',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Brand.darkTextSecondary : Brand.subtleLight),
              ),
            ),
          ));
    }

    final center = _me == null
        ? _engineer!
        : LatLng((_engineer!.latitude + _me!.latitude) / 2,
            (_engineer!.longitude + _me!.longitude) / 2);

    String? info;
    if (_me != null) {
      final km = const Distance()
          .as(LengthUnit.Kilometer, _engineer!, _me!);
      final etaMin = (km / 30 * 60).ceil(); // assume ~30 km/h
      info = '${km.toStringAsFixed(1)} km away · ~$etaMin min';
    }

    return _shell(
      isDark,
      child: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: center,
              initialZoom: 13,
              onMapReady: () {
                _mapReady = true;
                _fit();
              },
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.ifrontiers.iconnect',
              ),
              if (_me != null)
                PolylineLayer(polylines: [
                  Polyline(
                    points: [_engineer!, _me!],
                    strokeWidth: 4,
                    color: Brand.royalBlue.withAlpha(180),
                  ),
                ]),
              MarkerLayer(markers: [
                Marker(
                  point: _engineer!,
                  width: 44,
                  height: 44,
                  child: _pin(Icons.engineering_rounded, Brand.royalBlue),
                ),
                if (_me != null)
                  Marker(
                    point: _me!,
                    width: 40,
                    height: 40,
                    child: _pin(Icons.home_rounded, const Color(0xFF16A34A)),
                  ),
              ]),
            ],
          ),
          if (info != null)
            Positioned(
              left: 12,
              bottom: 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: (isDark ? Brand.darkCard : Colors.white).withAlpha(235),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withAlpha(30),
                        blurRadius: 8,
                        offset: const Offset(0, 2)),
                  ],
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.directions_car_rounded,
                      size: 15, color: Brand.royalBlue),
                  const SizedBox(width: 6),
                  Text(info,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? Brand.darkTextPrimary
                              : Brand.royalBlueDark)),
                ]),
              ),
            ),
          if (_updatedAt != null)
            Positioned(
              right: 12,
              top: 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF16A34A).withAlpha(230),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.circle, size: 8, color: Colors.white),
                  SizedBox(width: 5),
                  Text('LIVE',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.5)),
                ]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _pin(IconData icon, Color color) => Container(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.5),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withAlpha(60),
                blurRadius: 6,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      );

  Widget _shell(bool isDark, {required Widget child}) => ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: widget.height,
          color: isDark ? Brand.darkCard : const Color(0xFFE2E8F0),
          child: child,
        ),
      );
}
