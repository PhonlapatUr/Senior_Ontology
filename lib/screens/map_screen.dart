// ========================= map_screen.dart =========================

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

// NEW
import '../models/route_request_item.dart';

// widgets
import '../widgets/search_box.dart';
import '../widgets/route_list.dart';
import '../widgets/detail_card.dart';
import '../widgets/preview_card.dart';
import '../widgets/nav_overlay.dart';

// models
import '../models/travel_time.dart';
import '../models/route_info.dart';
import '../models/safe_score.dart';
import '../models/route_indicators.dart';

// utils
import '../utils/helpers.dart';
import '../utils/debouncer.dart';

// services
import '../services/google_routes_service.dart';
import '../services/geocode_service.dart';
import '../services/backend_service.dart';

// CONFIG --------------------------------------------------------------

const String googleApiKey = "AIzaSyDg3Gv6FLg7KT19XyEuJEMrMYAVP8sjU6Y";

String backendBase() =>
    Platform.isAndroid ? "http://10.0.2.2:8000" : "http://127.0.0.1:8000";

enum FlowStep { choose, detail, preview, nav }

// SCREEN --------------------------------------------------------------

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  GoogleMapController? mapCtrl;

  final startCtrl = TextEditingController();
  final endCtrl = TextEditingController();
  final Debouncer debouncer = Debouncer(700);

  LatLng? origin;
  LatLng? dest;

  bool loading = false;
  FlowStep step = FlowStep.choose;

  String selectedMode = "DRIVE";

  List<RouteInfo> routes = [];
  int chosenRoute = 0;

  Map<String, TravelTime> travelTimes = {};
  Map<int, SafeScore> routeScores = {};
  Map<int, RouteIndicators> indicators = {};

  final Set<Polyline> polys = {};
  final Set<Marker> marks = {};

  static const LatLng initCenter = LatLng(13.7563, 100.5018);

  late final GoogleRoutesService gRoutes = GoogleRoutesService(googleApiKey);
  late final GeocodeService geocoder = GeocodeService(googleApiKey);
  late final BackendService backend = BackendService(backendBase());

  // INIT --------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    startCtrl.addListener(() => _handleLatLngText(true));
    endCtrl.addListener(() => _handleLatLngText(false));
  }

  @override
  void dispose() {
    startCtrl.dispose();
    endCtrl.dispose();
    super.dispose();
  }

  // INPUT HANDLING ----------------------------------------------------

  void _handleLatLngText(bool isOrigin) {
    final text = isOrigin ? startCtrl.text : endCtrl.text;

    if (text == "My Location") {
      debouncer.run(() => _onEndpointsUpdated());
      return;
    }

    final ll = parseLatLng(text);
    if (ll != null) {
      if (isOrigin) {
        origin = ll;
      } else {
        dest = ll;
      }

      debouncer.run(() => _onEndpointsUpdated());
      setState(() {});
    }
  }

  Future<LatLng?> _myLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) return null;

    LocationPermission p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    if (p == LocationPermission.deniedForever) return null;

    final pos = await Geolocator.getCurrentPosition();
    return LatLng(pos.latitude, pos.longitude);
  }

  // FETCH ROUTES & TRAVEL TIMES --------------------------------------

  Future<void> _onEndpointsUpdated() async {
    if (origin == null || dest == null) return;

    await _fetchTravelTimes();
    await _fetchRoutes();

    if (!mounted) return;
    setState(() => step = FlowStep.choose);
  }

  Future<void> _fetchTravelTimes() async {
    if (origin == null || dest == null) return;

    setState(() => loading = true);

    try {
      travelTimes = await gRoutes.getTravelTimes(origin!, dest!);
    } catch (_) {}

    if (mounted) setState(() => loading = false);
  }

  Future<void> _fetchRoutes() async {
    if (origin == null || dest == null) return;

    setState(() {
      loading = true;
      routes.clear();
      indicators.clear();
      routeScores.clear();
      polys.clear();
      marks.clear();
    });

    routes = await gRoutes.getRoutes(
      origin: origin!,
      dest: dest!,
      mode: selectedMode,
    );

    chosenRoute = 0;

    if (routes.isEmpty) {
      if (mounted) setState(() => loading = false);
      return;
    }

    _drawRoutesBasic();
    _fitMap();
    await _scoreAllRoutes();
  }

  // BACKEND SCORING ---------------------------------------------------

  Future<void> _scoreAllRoutes() async {
    if (routes.isEmpty) return;

    final routeItems = routes.asMap().entries.map((e) {
      final idx = e.key;
      final r = e.value;

      return RouteRequestItem(
        id: idx.toString(),
        encodedPolyline: r.encodedPolyline,
        distanceMeters: r.distanceMeters,
        durationSeconds: r.durationSec,
      );
    }).toList();

    final scores = await backend.scoreRoutes(
      routes: routeItems,
      sampleStride: 40,
    );

    routeScores = scores;

    _ensureScoreExists();
    _computeIndicators();
    _chooseBestRoute();
    _drawRoutesBasic();

    if (mounted) setState(() => loading = false);
  }

  void _ensureScoreExists() {
    for (int i = 0; i < routes.length; i++) {
      routeScores[i] ??= SafeScore(
        id: i.toString(),
        di: 1.0,
        dt: 1.0,
        dp: 0.0,
        dw: 0.5,
        riskScore: 0.50,
        avgHumidity: 60.0,
        pointsSampled: 0,
        pointsUsed: 0,
        note: "missing fallback",
      );
    }
  }

  void _computeIndicators() {
    if (routes.isEmpty) return;

    indicators.clear();

    for (int i = 0; i < routes.length; i++) {
      final s = routeScores[i]!;

      // Use backend values directly!
      final di = s.di.clamp(0.0, 1.0);
      final dt = s.dt.clamp(0.0, 1.0);
      final dp = s.dp.clamp(0.0, 1.0);
      final dw = s.dw.clamp(0.0, 1.0);

      final si = s.riskScore;

      indicators[i] = RouteIndicators(di: di, dt: dt, dp: dp, dw: dw, si: si);
    }

    // Sort by SI
    final combined = List.generate(
      routes.length,
      (i) => {
        "route": routes[i],
        "score": routeScores[i]!,
        "ind": indicators[i]!,
      },
    );

    combined.sort(
      (a, b) => (a["ind"] as RouteIndicators).si.compareTo(
        (b["ind"] as RouteIndicators).si,
      ),
    );

    routes = combined.map((e) => e["route"] as RouteInfo).toList();

    routeScores = {
      for (int i = 0; i < combined.length; i++)
        i: combined[i]["score"] as SafeScore,
    };

    indicators = {
      for (int i = 0; i < combined.length; i++)
        i: combined[i]["ind"] as RouteIndicators,
    };
  }

  // CHOOSE BEST ROUTE ------------------------------------------------

  void _chooseBestRoute() {
    if (indicators.isEmpty) return;

    double best = -1;
    int idx = 0;

    indicators.forEach((i, ind) {
      if (ind.si > best) {
        best = ind.si;
        idx = i;
      }
    });

    chosenRoute = idx.clamp(0, routes.length - 1);
  }

  // MAP RENDER --------------------------------------------------------

  void _drawRoutesBasic() {
    if (routes.isEmpty) return;

    polys.clear();
    marks.clear();

    final safeIndex = chosenRoute.clamp(0, routes.length - 1);

    for (int i = 0; i < routes.length; i++) {
      polys.add(
        Polyline(
          polylineId: PolylineId("route$i"),
          color: i == safeIndex ? Colors.blue : Colors.grey,
          width: i == safeIndex ? 6 : 4,
          points: routes[i].points,
        ),
      );
    }

    if (origin != null) {
      marks.add(Marker(markerId: const MarkerId("o"), position: origin!));
    }
    if (dest != null) {
      marks.add(Marker(markerId: const MarkerId("d"), position: dest!));
    }

    if (mounted) setState(() {});
  }

  void _fitMap() {
    if (!mounted || mapCtrl == null) return;
    if (routes.isEmpty || origin == null || dest == null) return;

    double minLat = 999, minLng = 999, maxLat = -999, maxLng = -999;

    void update(LatLng p) {
      minLat = p.latitude < minLat ? p.latitude : minLat;
      minLng = p.longitude < minLng ? p.longitude : minLng;
      maxLat = p.latitude > maxLat ? p.latitude : maxLat;
      maxLng = p.longitude > maxLng ? p.longitude : maxLng;
    }

    update(origin!);
    update(dest!);
    for (var r in routes) {
      for (var p in r.points) {
        update(p);
      }
    }

    Future.delayed(const Duration(milliseconds: 100), () {
      if (!mounted || mapCtrl == null) return;
      mapCtrl!.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(minLat, minLng),
            northeast: LatLng(maxLat, maxLng),
          ),
          60,
        ),
      );
    });
  }

  // MODE SELECTOR -----------------------------------------------------

  Widget _buildModeSelector() {
    return Row(
      children: [
        _modeChip(Icons.directions_car, "DRIVE"),
        const SizedBox(width: 8),
        _modeChip(Icons.directions_walk, "WALK"),
      ],
    );
  }

  Widget _modeChip(IconData icon, String mode) {
    final selected = selectedMode == mode;
    int sec;
    if (routes.isNotEmpty && selectedMode == mode) {
      sec = routes[chosenRoute].durationSec;
    } else {
      sec = travelTimes[mode]?.durationSec ?? 0;
    }

    return InkWell(
      onTap: () async {
        selectedMode = mode;
        chosenRoute = 0;

        if (origin != null && dest != null) await _fetchRoutes();
        if (mounted) setState(() {});
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.blue.shade100 : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 6),
            Text(
              formatDurationShort(sec), // NEW formatting
              style: const TextStyle(fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  // UI ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final safeIndex = routes.isEmpty
        ? 0
        : chosenRoute.clamp(0, routes.length - 1);

    return Scaffold(
      appBar: AppBar(title: const Text("Smart Route Finder")),
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: (c) => mapCtrl = c,
            initialCameraPosition: const CameraPosition(
              target: initCenter,
              zoom: 11,
            ),
            polylines: polys,
            markers: marks,
            zoomControlsEnabled: false,
          ),

          Positioned(
            top: 10,
            left: 10,
            right: 10,
            child: Card(
              elevation: 12,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  children: [
                    SearchBox(
                      controller: startCtrl,
                      hint: "Your Location",
                      isOrigin: true,
                      googleApiKey: googleApiKey,
                      onMyLocation: (loc) async {
                        origin = loc;
                        startCtrl.text = "My Location";
                        await _onEndpointsUpdated();
                      },
                      onPredictionSelected: (p) async {
                        final ll = await geocoder.geocode(p.description ?? "");
                        if (ll != null) {
                          origin = ll;
                          startCtrl.text = p.description ?? "";
                          debouncer.run(() => _onEndpointsUpdated());
                        }
                      },
                    ),

                    const SizedBox(height: 8),

                    SearchBox(
                      controller: endCtrl,
                      hint: "Destination",
                      isOrigin: false,
                      googleApiKey: googleApiKey,
                      onMyLocation: (loc) async {
                        dest = loc;
                        endCtrl.text = "My Location";
                        await _onEndpointsUpdated();
                      },
                      onPredictionSelected: (p) async {
                        final ll = await geocoder.geocode(p.description ?? "");
                        if (ll != null) {
                          dest = ll;
                          endCtrl.text = p.description ?? "";
                          debouncer.run(() => _onEndpointsUpdated());
                        }
                      },
                    ),

                    const SizedBox(height: 10),

                    if (step == FlowStep.choose && routes.isNotEmpty)
                      (indicators.length == routes.length)
                          ? Card(
                              elevation: 8,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                              margin: const EdgeInsets.only(top: 10),
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: RouteList(
                                  routes: routes,
                                  chosenRoute: safeIndex,
                                  indicators: indicators,
                                  onSelect: (i) {
                                    chosenRoute = i.clamp(0, routes.length - 1);
                                    step = FlowStep.detail;
                                    _drawRoutesBasic();
                                    setState(() {});
                                  },
                                  modeSelector: _buildModeSelector(),
                                ),
                              ),
                            )
                          : const Padding(
                              padding: EdgeInsets.all(8),
                              child: CircularProgressIndicator(),
                            ),

                    if (step == FlowStep.detail &&
                        routes.isNotEmpty &&
                        indicators.containsKey(safeIndex))
                      DetailCard(
                        route: routes[safeIndex],
                        ind: indicators[safeIndex]!,
                        score: routeScores[safeIndex],
                        modeSelector: _buildModeSelector(),
                        originLabel: startCtrl.text,
                        destinationLabel: endCtrl.text,
                        onBack: () => setState(() => step = FlowStep.choose),
                        onNext: () => setState(() => step = FlowStep.preview),
                      ),

                    if (step == FlowStep.preview)
                      PreviewCard(
                        onBack: () => setState(() => step = FlowStep.detail),
                        onNext: () async {
                          final live = await _myLocation();
                          if (live != null) {
                            origin = live;
                            startCtrl.text = "My Location";
                            await _onEndpointsUpdated();
                          }
                          setState(() => step = FlowStep.nav);
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),

          if (step == FlowStep.nav && routes.isNotEmpty)
            NavOverlay(
              route: routes[safeIndex],
              onExit: () => setState(() => step = FlowStep.choose),
            ),

          if (loading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
