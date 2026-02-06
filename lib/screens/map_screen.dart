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
import '../widgets/dss_calculation_screen.dart';
import '../widgets/preview_card.dart';
import '../widgets/nav_overlay.dart';

// screens
import 'login_screen.dart';

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
import '../services/ontology_service.dart';
import '../services/auth_service.dart';

// CONFIG --------------------------------------------------------------

const String googleApiKey = "AIzaSyDg3Gv6FLg7KT19XyEuJEMrMYAVP8sjU6Y";

String backendBase() =>
    Platform.isAndroid ? "http://10.0.2.2:8000" : "http://127.0.0.1:8000";

enum FlowStep { choose, detail, dssCalculation, preview, nav }

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
  bool? hasPollutionConcern; // null = not asked yet, true = yes, false = no
  bool showPollutionDialog = false;
  bool showPollutantSelection = false;
  List<String> availablePollutants = [];
  Set<String> selectedPollutants = {};

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
  final AuthService _authService = AuthService();

  // INIT --------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    startCtrl.addListener(() => _handleLatLngText(true));
    endCtrl.addListener(() => _handleLatLngText(false));
    _loadPollutants();
  }

  Future<void> _loadPollutants() async {
    availablePollutants = await OntologyService.getPollutantsFromOntology();
    if (mounted) setState(() {});
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
        // Reset pollution concern if origin changes
        if (origin != ll) {
          hasPollutionConcern = null;
          selectedPollutants.clear();
        }
        origin = ll;
      } else {
        // Reset pollution concern if destination changes
        if (dest != ll) {
          hasPollutionConcern = null;
          selectedPollutants.clear();
        }
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

    // Show pollution concern dialog if not asked yet
    if (hasPollutionConcern == null) {
      setState(() => showPollutionDialog = true);
      return;
    }

    // If user selected pollutants, don't fetch here (will be fetched in _handlePollutantSelectionComplete)
    // Only fetch if user clicked "No" (no concern)
    if (hasPollutionConcern == false) {
      setState(() {
        loading = true;
        step = FlowStep.choose;
      });
      try {
        await _fetchTravelTimes();
        await _fetchRoutes();
      } catch (e) {
        print("Error in _onEndpointsUpdated: $e");
      } finally {
        if (mounted) {
          setState(() => loading = false);
        }
      }
    }
  }

  void _handlePollutionConcern(bool concern) {
    if (concern) {
      // Show pollutant selection dialog
      setState(() {
        showPollutionDialog = false;
        showPollutantSelection = true;
        selectedPollutants.clear();
      });
    } else {
      // No concern, proceed directly
      setState(() {
        hasPollutionConcern = false;
        showPollutionDialog = false;
        selectedPollutants.clear();
      });
      _onEndpointsUpdated();
    }
  }

  void _handlePollutantSelectionComplete() async {
    setState(() {
      hasPollutionConcern = selectedPollutants.isNotEmpty;
      showPollutantSelection = false;
      loading = true; // Show loading while fetching routes and calculating DSS
      step = FlowStep.choose;
    });
    
    try {
      // Step 1: Fetch travel times from Google API
      await _fetchTravelTimes();
      
      // Step 2: Fetch routes from Google API
      await _fetchRoutes();
      // Note: _fetchRoutes() will call _scoreAllRoutes() which uses selectedPollutants
      // to calculate DSS with focus_pollutants and ontology adjustments
    } catch (e) {
      print("Error in _handlePollutantSelectionComplete: $e");
    } finally {
      // loading will be set to false in _scoreAllRoutes() or _fetchRoutes() after completion
      if (mounted && loading) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> _fetchTravelTimes() async {
    if (origin == null || dest == null) return;

    try {
      travelTimes = await gRoutes.getTravelTimes(origin!, dest!);
    } catch (_) {}
  }

  Future<void> _fetchRoutes() async {
    if (origin == null || dest == null) {
      if (mounted) setState(() => loading = false);
      return;
    }

    try {
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
    } catch (e) {
      // Handle errors (network issues, API errors, etc.)
      print("Error fetching routes: $e");
      if (mounted) {
        setState(() {
          loading = false;
          routes = [];
        });
      }
    }
  }

  // BACKEND SCORING ---------------------------------------------------
  // This function is called after routes are fetched from Google API
  // It sends routes to backend DSS for scoring with selected pollutants

  Future<void> _scoreAllRoutes() async {
    if (routes.isEmpty) {
      if (mounted) setState(() => loading = false);
      return;
    }

    try {
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

      // Prepare DSS parameters based on user's pollution concern
      List<String>? focusPollutants;
      bool useOntology = false;
      
      if (hasPollutionConcern == true && selectedPollutants.isNotEmpty) {
        // Convert ontology pollutant names to backend format (e.g., "PM2.5" -> "pm2.5")
        focusPollutants = selectedPollutants
            .map((p) => OntologyService.toBackendFormat(p))
            .toList();
        useOntology = true; // Enable ontology-based adjustments for better scoring
      }

      // Call backend API to calculate DSS scores with selected pollutants
      final scores = await backend.scoreRoutes(
        routes: routeItems,
        sampleStride: 40,
        focusPollutants: focusPollutants,
        useOntology: useOntology,
      );

      routeScores = scores;

      _ensureScoreExists();
      _computeIndicators();
      _chooseBestRoute();
      _drawRoutesBasic();
    } catch (e) {
      // Handle errors (network timeout, backend error, etc.)
      print("Error scoring routes: $e");
      // Still ensure scores exist even if backend call failed
      _ensureScoreExists();
      _computeIndicators();
      _chooseBestRoute();
      _drawRoutesBasic();
    } finally {
      // Always stop loading, even if there was an error
      if (mounted) setState(() => loading = false);
    }
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

  // SIGN OUT ---------------------------------------------------------

  // Show sign out confirmation dialog
  void _showSignOutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Row(
            children: [
              Icon(Icons.logout, color: Colors.red, size: 28),
              SizedBox(width: 12),
              Text(
                "Sign Out?",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
            ],
          ),
          content: const Text(
            "Are you sure you want to sign out?",
            style: TextStyle(fontSize: 16),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text(
                "Cancel",
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await _handleSignOut(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text(
                "Sign Out",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // Handle sign out
  Future<void> _handleSignOut(BuildContext context) async {
    try {
      print('👋 User signed out');
      
      // Navigate to login page
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false, // Remove all previous routes
        );
      }
    } catch (e) {
      print('Error signing out: $e');
      // Still navigate to login even if there's an error
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
      }
    }
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
      appBar: AppBar(
        title: const Text("Smart Route Finder"),
        automaticallyImplyLeading: false, // Remove back arrow icon
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign Out',
            onPressed: () => _showSignOutDialog(context),
          ),
        ],
      ),
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
                        if (origin != loc) {
                          hasPollutionConcern = null;
                          selectedPollutants.clear();
                        }
                        origin = loc;
                        startCtrl.text = "My Location";
                        await _onEndpointsUpdated();
                      },
                      onPredictionSelected: (p) async {
                        final ll = await geocoder.geocode(p.description ?? "");
                        if (ll != null) {
                          if (origin != ll) {
                            hasPollutionConcern = null;
                            selectedPollutants.clear();
                          }
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
                        if (dest != loc) {
                          hasPollutionConcern = null;
                          selectedPollutants.clear();
                        }
                        dest = loc;
                        endCtrl.text = "My Location";
                        await _onEndpointsUpdated();
                      },
                      onPredictionSelected: (p) async {
                        final ll = await geocoder.geocode(p.description ?? "");
                        if (ll != null) {
                          if (dest != ll) {
                            hasPollutionConcern = null;
                            selectedPollutants.clear();
                          }
                          dest = ll;
                          endCtrl.text = p.description ?? "";
                          debouncer.run(() => _onEndpointsUpdated());
                        }
                      },
                    ),

                    const SizedBox(height: 10),

                    if (step == FlowStep.choose && routes.isNotEmpty)
                      (indicators.length == routes.length)
                          ? Container(
                              margin: const EdgeInsets.only(top: 10),
                              child: RouteList(
                                routes: routes,
                                chosenRoute: safeIndex,
                                indicators: indicators,
                                selectedPollutants: selectedPollutants,
                                onSelect: (i) {
                                  // "View more details" -> Detail page
                                  chosenRoute = i.clamp(0, routes.length - 1);
                                  step = FlowStep.detail;
                                  _drawRoutesBasic();
                                  setState(() {});
                                },
                                onPreview: (i) {
                                  // Chevron arrow -> Preview page
                                  chosenRoute = i.clamp(0, routes.length - 1);
                                  step = FlowStep.preview;
                                  _drawRoutesBasic();
                                  setState(() {});
                                },
                                modeSelector: _buildModeSelector(),
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
                        selectedPollutants: selectedPollutants,
                        onBack: () => setState(() => step = FlowStep.choose),
                        onNext: () => setState(() => step = FlowStep.dssCalculation),
                        onStartRoute: () async {
                          final live = await _myLocation();
                          if (live != null) {
                            origin = live;
                            startCtrl.text = "My Location";
                            await _onEndpointsUpdated();
                          }
                          setState(() => step = FlowStep.nav);
                        },
                      ),

                    if (step == FlowStep.dssCalculation &&
                        routes.isNotEmpty &&
                        routeScores.containsKey(safeIndex))
                      Positioned.fill(
                        child: DSSCalculationScreen(
                          route: routes[safeIndex],
                          score: routeScores[safeIndex],
                          originLabel: startCtrl.text,
                          destinationLabel: endCtrl.text,
                          selectedPollutants: selectedPollutants,
                          modeSelector: _buildModeSelector(),
                          onBack: () => setState(() => step = FlowStep.detail),
                          onNext: () => setState(() => step = FlowStep.preview),
                        ),
                      ),

                    if (step == FlowStep.preview)
                      PreviewCard(
                        onBack: () => setState(() => step = FlowStep.dssCalculation),
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

          // Pollution Concern Dialog
          if (showPollutionDialog)
            Container(
              color: Colors.black54,
              child: Center(
                child: Card(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          "Do you have concern about pollution?",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () => _handlePollutionConcern(true),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: const Text(
                                  "Yes",
                                  style: TextStyle(fontSize: 16),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => _handlePollutionConcern(false),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.grey[700],
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  side: BorderSide(color: Colors.grey[300]!),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: const Text(
                                  "No",
                                  style: TextStyle(fontSize: 16),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // Pollutant Selection Dialog
          if (showPollutantSelection)
            Container(
              color: Colors.black54,
              child: Center(
                child: Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          "Your concern about pollution",
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        Flexible(
                          child: GridView.builder(
                            shrinkWrap: true,
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              childAspectRatio: 2.5,
                            ),
                            itemCount: availablePollutants.length,
                            itemBuilder: (context, index) {
                              final pollutant = availablePollutants[index];
                              final isSelected = selectedPollutants.contains(pollutant);
                              
                              return InkWell(
                                onTap: () {
                                  setState(() {
                                    if (isSelected) {
                                      selectedPollutants.remove(pollutant);
                                    } else {
                                      selectedPollutants.add(pollutant);
                                    }
                                  });
                                },
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: isSelected 
                                        ? Colors.blue.shade100 
                                        : Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isSelected 
                                          ? Colors.blue 
                                          : Colors.grey.shade300,
                                      width: isSelected ? 2 : 1,
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      pollutant,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: isSelected 
                                            ? FontWeight.bold 
                                            : FontWeight.normal,
                                        color: isSelected 
                                            ? Colors.blue.shade900 
                                            : Colors.grey.shade700,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: selectedPollutants.isNotEmpty
                                ? _handlePollutantSelectionComplete
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              disabledBackgroundColor: Colors.grey.shade300,
                            ),
                            child: const Text(
                              "Continue",
                              style: TextStyle(fontSize: 16),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
