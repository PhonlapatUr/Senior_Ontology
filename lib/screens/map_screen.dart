// ========================= map_screen.dart =========================

import 'dart:async';

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
import 'welcome_screen.dart';

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
import '../config/backend_config.dart';
import '../utils/debug_log.dart';

// CONFIG --------------------------------------------------------------

const String googleApiKey = "AIzaSyDg3Gv6FLg7KT19XyEuJEMrMYAVP8sjU6Y";
const Color _kMainTeal = Color(0xFF26A69A);

/// Default pollutant list for "Your concern about pollution" when ontology is not yet loaded.
const List<String> _defaultPollutantList = [
  'CO',
  'NO2',
  'NOx',
  'O3',
  'PM10',
  'PM2.5',
  'SO2',
  'VOCs',
];

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
  final focusOrigin = FocusNode();
  final focusDest = FocusNode();
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

  // In-app navigation: live position and stream
  StreamSubscription<Position>? _positionSubscription;
  LatLng? _navCurrentLocation;
  static const double _navZoom = 17.0;
  /// If user is farther than this (meters) from the route, trigger recalc.
  static const double _offRouteThresholdMeters = 80.0;
  bool _isRecalculatingRoute = false;
  DateTime? _lastRecalcRouteAt;
  static const Duration _recalcCooldown = Duration(seconds: 15);
  int _lastNavClosestIndex = 0;

  /// Route info panel: true = maximized (default), false = minimized to see map
  bool _routePanelExpanded = true;

  late final GoogleRoutesService gRoutes = GoogleRoutesService(googleApiKey);
  late final GeocodeService geocoder = GeocodeService(googleApiKey);
  late final BackendService backend = BackendService(backendBase);
  final AuthService _authService = AuthService();

  // INIT --------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    startCtrl.addListener(() => _handleLatLngText(true));
    endCtrl.addListener(() => _handleLatLngText(false));
    focusOrigin.addListener(() {
      // #region agent log
      if (focusOrigin.hasFocus) {
        debugLog('map_screen.dart:focusOrigin', 'Origin gained focus',
            hypothesisId: 'H3', data: {'hasFocus': true});
      }
      // #endregion
    });
    focusDest.addListener(() {
      // #region agent log
      debugLog('map_screen.dart:focusDest', 'Dest focus changed',
          hypothesisId: 'H3', data: {'hasFocus': focusDest.hasFocus});
      // #endregion
    });
    _loadPollutants();
  }

  Future<void> _loadPollutants() async {
    availablePollutants = await OntologyService.getPollutantsFromOntology();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _stopPositionStream();
    focusOrigin.dispose();
    focusDest.dispose();
    startCtrl.dispose();
    endCtrl.dispose();
    super.dispose();
  }

  void _startPositionStream() {
    _stopPositionStream();
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position position) {
      if (!mounted) return;
      final latLng = LatLng(position.latitude, position.longitude);
      setState(() => _navCurrentLocation = latLng);
      if (step == FlowStep.nav && routes.isNotEmpty) {
        _drawRoutesBasic();
      }
      // #region agent log
      if (step == FlowStep.nav && routes.isNotEmpty) {
        final navPoints = routes[chosenRoute.clamp(0, routes.length - 1)].points;
        final idx = _closestRoutePointIndex(latLng, navPoints);
        debugLog(
          'map_screen.dart:_startPositionStream',
          'position update',
          runId: 'initial',
          hypothesisId: 'H5',
          data: {
            'lat': position.latitude,
            'lng': position.longitude,
            'closestIdx': idx,
            'routePoints': navPoints.length,
          },
        );
      }
      // #endregion
      mapCtrl?.animateCamera(
        CameraUpdate.newLatLngZoom(latLng, _navZoom),
      );
      // Off-route: recalculate from current location to destination
      if (step == FlowStep.nav &&
          routes.isNotEmpty &&
          dest != null &&
          !_isRecalculatingRoute) {
        final routePoints = routes[chosenRoute.clamp(0, routes.length - 1)].points;
        final distToRoute = distanceToRoute(latLng, routePoints);
        final cooldownPassed = _lastRecalcRouteAt == null ||
            DateTime.now().difference(_lastRecalcRouteAt!) > _recalcCooldown;
        // #region agent log
        debugLog(
          'map_screen.dart:_startPositionStream',
          'off-route check',
          runId: 'initial',
          hypothesisId: 'H6',
          data: {
            'distToRouteMeters': distToRoute,
            'thresholdMeters': _offRouteThresholdMeters,
            'cooldownPassed': cooldownPassed,
            'isRecalculating': _isRecalculatingRoute,
          },
        );
        // #endregion
        if (distToRoute > _offRouteThresholdMeters && cooldownPassed) {
          // #region agent log
          debugLog(
            'map_screen.dart:_startPositionStream',
            'trigger auto-reroute',
            runId: 'initial',
            hypothesisId: 'H6',
            data: {
              'distToRouteMeters': distToRoute,
            },
          );
          // #endregion
          _recalculateRouteFromCurrentLocation();
        }
      }
    });
  }

  void _stopPositionStream() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _navCurrentLocation = null;
  }

  /// Recalculate route from current location to destination (e.g. when user goes off-route).
  Future<void> _recalculateRouteFromCurrentLocation() async {
    if (_isRecalculatingRoute || !mounted || dest == null || _navCurrentLocation == null) return;
    _isRecalculatingRoute = true;
    // #region agent log
    debugLog(
      'map_screen.dart:_recalculateRouteFromCurrentLocation',
      'reroute started',
      runId: 'initial',
      hypothesisId: 'H7',
      data: {
        'hasPollutionConcern': hasPollutionConcern,
        'selectedPollutants': selectedPollutants.toList(),
        'mode': selectedMode,
      },
    );
    // #endregion
    if (mounted) setState(() => loading = true);
    try {
      final newRoutes = await gRoutes.getRoutes(
        origin: _navCurrentLocation!,
        dest: dest!,
        mode: selectedMode,
      );
      if (!mounted || newRoutes.isEmpty) return;
      setState(() {
        routes = newRoutes;
        chosenRoute = 0;
        origin = _navCurrentLocation;
      });
      // #region agent log
      debugLog(
        'map_screen.dart:_recalculateRouteFromCurrentLocation',
        'reroute fetched routes',
        runId: 'initial',
        hypothesisId: 'H7',
        data: {
          'newRouteCount': newRoutes.length,
        },
      );
      // #endregion
      await _scoreAllRoutes();
      _lastRecalcRouteAt = DateTime.now();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Route recalculated from your current location."),
            backgroundColor: _kMainTeal,
          ),
        );
        mapCtrl?.animateCamera(
          CameraUpdate.newLatLngZoom(_navCurrentLocation!, _navZoom),
        );
      }
    } catch (e) {
      // #region agent log
      debugLog(
        'map_screen.dart:_recalculateRouteFromCurrentLocation',
        'reroute failed',
        runId: 'initial',
        hypothesisId: 'H7',
        data: {'error': e.toString()},
      );
      // #endregion
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Could not recalculate route: $e"),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } finally {
      _isRecalculatingRoute = false;
      if (mounted) setState(() => loading = false);
    }
  }

  /// Start in-app navigation for the route the user selected. Only allowed when start location is "My Location".
  Future<void> _startNavigation() async {
    if (startCtrl.text != "My Location") {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Route couldn't be started. Please set start location to My Location.",
            ),
          ),
        );
      }
      return;
    }
    final live = await _myLocation();
    if (live == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Location unavailable. Enable location and try again."),
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() => step = FlowStep.nav);
    _drawRoutesBasic();
    // #region agent log
    debugLog(
      'map_screen.dart:_startNavigation',
      'navigation started',
      runId: 'initial',
      hypothesisId: 'H4',
      data: {
        'originIsMyLocation': startCtrl.text == "My Location",
        'chosenRoute': chosenRoute,
        'routeCount': routes.length,
      },
    );
    // #endregion
    mapCtrl?.animateCamera(
      CameraUpdate.newLatLngZoom(live, _navZoom),
    );
    _startPositionStream();
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
      // #region agent log
      debugLog('map_screen.dart:_onEndpointsUpdated', 'setState showPollutionDialog',
          hypothesisId: 'H2', data: {'hasPollutionConcern': null});
      // #endregion
      setState(() => showPollutionDialog = true);
      return;
    }

    // If user selected pollutants, don't fetch here (will be fetched in _handlePollutantSelectionComplete)
    // Only fetch if user clicked "No" (no concern)
    if (hasPollutionConcern == false) {
      // #region agent log
      debugLog('map_screen.dart:_onEndpointsUpdated', 'setState loading=true',
          hypothesisId: 'H2', data: {'loading': true});
      // #endregion
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
          // #region agent log
          debugLog('map_screen.dart:_onEndpointsUpdated', 'setState loading=false',
              hypothesisId: 'H2', data: {'loading': false});
          // #endregion
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

    await _recalculateRoutesWithCurrentPollutants();
  }

  /// Re-fetch and re-score routes using current selectedPollutants (e.g. after adding a concern).
  Future<void> _recalculateRoutesWithCurrentPollutants() async {
    try {
      await _fetchTravelTimes();
      await _fetchRoutes();
    } catch (e) {
      print("Error in _recalculateRoutesWithCurrentPollutants: $e");
    } finally {
      if (mounted && loading) {
        setState(() => loading = false);
      }
    }
  }

  void _showAddPollutionConcernDialog() {
    // Dismiss keyboard and unfocus location fields so only the dialog shows (no search/autocomplete)
    FocusScope.of(context).unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
    // #region agent log
    debugLog('map_screen.dart:_showAddPollutionConcernDialog', 'entry',
        hypothesisId: 'H1', data: {'mounted': mounted});
    // #endregion
    final listToShow = availablePollutants.isEmpty
        ? _defaultPollutantList
        : availablePollutants;
    final selectedInDialog = Set<String>.from(selectedPollutants);
    // #region agent log
    debugLog('map_screen.dart:_showAddPollutionConcernDialog', 'before showDialog',
        hypothesisId: 'H2', data: {'listLength': listToShow.length});
    // #endregion
    try {
      showDialog<void>(
        context: context,
        useRootNavigator: true,
        builder: (ctx) {
          // #region agent log
          debugLog('map_screen.dart:_showAddPollutionConcernDialog', 'builder called',
              hypothesisId: 'H3', data: {});
          // #endregion
          return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    icon: const Icon(Icons.arrow_back),
                    tooltip: 'Back',
                  ),
                  const SizedBox(width: 8),
                  const Flexible(
                    child: Text(
                      "Your concern about pollution",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 280, minHeight: 320),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        "Select pollutants to add as concerns (they will receive heavy weight).",
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: listToShow.map((pollutant) {
                          final isSelected = selectedInDialog.contains(pollutant);
                          return SizedBox(
                            width: 80,
                            height: 40,
                            child: InkWell(
                              onTap: () {
                                setDialogState(() {
                                  if (isSelected) {
                                    selectedInDialog.remove(pollutant);
                                  } else {
                                    selectedInDialog.add(pollutant);
                                  }
                                });
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? _kMainTeal.withOpacity(0.25)
                                      : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isSelected
                                        ? _kMainTeal
                                        : Colors.grey.shade300,
                                    width: isSelected ? 2 : 1,
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  pollutant,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight:
                                        isSelected ? FontWeight.bold : FontWeight.normal,
                                    color: isSelected
                                        ? _kMainTeal
                                        : Colors.grey.shade700,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                if (selectedInDialog.isNotEmpty)
                  TextButton(
                    onPressed: () {
                      setDialogState(() {
                        selectedInDialog.clear();
                      });
                    },
                    child: Text(
                      "Remove all",
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text("Cancel"),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _kMainTeal,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: selectedInDialog.isEmpty
                      ? null
                      : () async {
                          Navigator.of(ctx).pop();
                          setState(() {
                            selectedPollutants.clear();
                            selectedPollutants.addAll(selectedInDialog);
                            for (final p in selectedInDialog) {
                              if (!availablePollutants.contains(p)) {
                                availablePollutants.add(p);
                              }
                            }
                            hasPollutionConcern = true;
                            loading = true;
                          });
                          await _recalculateRoutesWithCurrentPollutants();
                        },
                  child: const Text("Add & Recalculate"),
                ),
              ],
            );
          },
        );
      },
    );
    } catch (e, st) {
      // #region agent log
      debugLog('map_screen.dart:_showAddPollutionConcernDialog', 'exception',
          hypothesisId: 'H5', data: {'error': e.toString(), 'stack': st.toString().split('\n').take(3).join(' ')});
      // #endregion
      rethrow;
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
        useOntology =
            true; // Enable ontology-based adjustments for better scoring
      }
      // #region agent log
      debugLog(
        'map_screen.dart:_scoreAllRoutes',
        'score parameters',
        runId: 'initial',
        hypothesisId: 'H8',
        data: {
          'routeCount': routeItems.length,
          'hasPollutionConcern': hasPollutionConcern,
          'selectedPollutants': selectedPollutants.toList(),
          'focusPollutants': focusPollutants ?? <String>[],
          'useOntology': useOntology,
        },
      );
      // #endregion

      // Call backend API to calculate DSS scores with selected pollutants
      print("Connecting to: $backendBase");
      final scores = await backend.scoreRoutes(
        routes: routeItems,
        sampleStride: 40,
        focusPollutants: focusPollutants,
        useOntology: useOntology,
      );

      routeScores = scores;
      // #region agent log
      debugLog(
        'map_screen.dart:_scoreAllRoutes',
        'score success',
        runId: 'initial',
        hypothesisId: 'H8',
        data: {
          'scoreCount': scores.length,
        },
      );
      // #endregion

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
        weatherValid: false,
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

  int _closestRoutePointIndex(LatLng location, List<LatLng> routePoints) {
    if (routePoints.isEmpty) return 0;
    double minDist = double.infinity;
    int closestIdx = 0;
    for (int i = 0; i < routePoints.length; i++) {
      final d = Geolocator.distanceBetween(
        location.latitude,
        location.longitude,
        routePoints[i].latitude,
        routePoints[i].longitude,
      );
      if (d < minDist) {
        minDist = d;
        closestIdx = i;
      }
    }
    return closestIdx;
  }

  void _drawRoutesBasic() {
    if (routes.isEmpty) return;

    polys.clear();
    marks.clear();

    final safeIndex = chosenRoute.clamp(0, routes.length - 1);

    // Non-selected routes underneath (zIndex 0), selected route on top (zIndex 1)
    for (int i = 0; i < routes.length; i++) {
      if (i == safeIndex) continue;
      final routeIndex = i;
      polys.add(
        Polyline(
          polylineId: PolylineId("route$i"),
          color: Colors.grey,
          width: 4,
          points: routes[i].points,
          zIndex: 0,
          consumeTapEvents: true,
          onTap: () {
            if (step != FlowStep.choose || routes.isEmpty) return;
            if (routeIndex >= 0 && routeIndex < routes.length) {
              chosenRoute = routeIndex;
              _drawRoutesBasic();
            }
          },
        ),
      );
    }
    // Thinner green route during navigation when user is moving
    final selectedPoints = routes[safeIndex].points;
    final routeWidth = step == FlowStep.nav ? 8 : 6;
    if (step == FlowStep.nav && _navCurrentLocation != null && selectedPoints.length >= 2) {
      final closestIdx = _closestRoutePointIndex(_navCurrentLocation!, selectedPoints);
      _lastNavClosestIndex = closestIdx;
      final traveledPoints = selectedPoints.sublist(0, (closestIdx + 1).clamp(1, selectedPoints.length));
      final remainingPoints = selectedPoints.sublist(closestIdx.clamp(0, selectedPoints.length - 1));
      polys.add(
        Polyline(
          polylineId: PolylineId("route${safeIndex}_traveled"),
          color: _kMainTeal.withOpacity(0.28),
          width: routeWidth,
          points: traveledPoints,
          zIndex: 1,
        ),
      );
      polys.add(
        Polyline(
          polylineId: PolylineId("route${safeIndex}_remaining"),
          color: _kMainTeal,
          width: routeWidth,
          points: remainingPoints,
          zIndex: 2,
        ),
      );
      // #region agent log
      debugLog(
        'map_screen.dart:_drawRoutesBasic',
        'nav polyline split',
        runId: 'initial',
        hypothesisId: 'H1',
        data: {
          'closestIdx': closestIdx,
          'totalPoints': selectedPoints.length,
          'traveledPoints': traveledPoints.length,
          'remainingPoints': remainingPoints.length,
        },
      );
      // #endregion
    } else {
      polys.add(
        Polyline(
          polylineId: PolylineId("route$safeIndex"),
          color: _kMainTeal,
          width: routeWidth,
          points: selectedPoints,
          zIndex: 1,
          consumeTapEvents: true,
          onTap: () {
            if (step != FlowStep.choose || routes.isEmpty) return;
            chosenRoute = safeIndex;
            _drawRoutesBasic();
          },
        ),
      );
    }

    // During nav/reroute don't show origin pin (avoids red pin); destination only
    if (origin != null && step != FlowStep.nav) {
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
              child: const Text(
                "Sign Out",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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

      // Navigate to welcome (sign-in / sign-up) page
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const WelcomeScreen()),
          (route) => false, // Remove all previous routes
        );
      }
    } catch (e) {
      print('Error signing out: $e');
      // Still navigate to welcome page even if there's an error
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const WelcomeScreen()),
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
          color: selected ? _kMainTeal.withOpacity(0.25) : Colors.grey.shade200,
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
            myLocationEnabled: step == FlowStep.nav,
            myLocationButtonEnabled: false,
          ),

          if (step != FlowStep.nav)
            Positioned(
              top: 10,
              left: 10,
              right: 10,
              child: Card(
                elevation: 12,
                child: _routePanelExpanded
                    ? Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Minimize button row
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text(
                                  "Route info",
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey.shade700,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.keyboard_arrow_down),
                                  tooltip: "Minimize",
                                  onPressed: () => setState(() => _routePanelExpanded = false),
                                  color: _kMainTeal,
                                ),
                              ],
                            ),
                            SearchBox(
                      key: const ValueKey<String>('origin'),
                      controller: startCtrl,
                      hint: "Your Location",
                      isOrigin: true,
                      focusNode: focusOrigin,
                      googleApiKey: googleApiKey,
                      onClear: () {
                        setState(() {
                          startCtrl.clear();
                          origin = null;
                          hasPollutionConcern = null;
                          selectedPollutants.clear();
                          routes.clear();
                          indicators.clear();
                          routeScores.clear();
                          polys.clear();
                          marks.clear();
                        });
                      },
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
                      key: const ValueKey<String>('destination'),
                      controller: endCtrl,
                      hint: "Destination",
                      isOrigin: false,
                      focusNode: focusDest,
                      googleApiKey: googleApiKey,
                      onClear: () {
                        setState(() {
                          endCtrl.clear();
                          dest = null;
                          hasPollutionConcern = null;
                          selectedPollutants.clear();
                          routes.clear();
                          indicators.clear();
                          routeScores.clear();
                          polys.clear();
                          marks.clear();
                        });
                      },
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
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: loading
                                        ? null
                                        : _showAddPollutionConcernDialog,
                                    icon: const Icon(Icons.add_circle_outline, size: 20),
                                    label: const Text("Add pollution concern"),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.orange.shade700,
                                      side: BorderSide(color: Colors.orange.shade300),
                                    ),
                                  ),
                                  if (selectedPollutants.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    OutlinedButton.icon(
                                      onPressed: loading
                                          ? null
                                          : () async {
                                              setState(() {
                                                selectedPollutants.clear();
                                                hasPollutionConcern = false;
                                                loading = true;
                                              });
                                              await _recalculateRoutesWithCurrentPollutants();
                                            },
                                      icon: const Icon(Icons.remove_circle_outline, size: 20),
                                      label: const Text("Remove pollution concern"),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.red.shade700,
                                        side: BorderSide(color: Colors.red.shade300),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 12),
                                  ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxHeight: MediaQuery.of(context).size.height * 0.45,
                                    ),
                                    child: SingleChildScrollView(
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
                                    ),
                                  ),
                                ],
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
                        onNext: () =>
                            setState(() => step = FlowStep.dssCalculation),
                        onStartRoute: () => _startNavigation(),
                        onAddPollutionConcern: _showAddPollutionConcernDialog,
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
                          onAddPollutionConcern: _showAddPollutionConcernDialog,
                        ),
                      ),

                    if (step == FlowStep.preview)
                      PreviewCard(
                        onBack: () =>
                            setState(() => step = FlowStep.dssCalculation),
                        onNext: () => _startNavigation(),
                      ),
                          ],
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    "${startCtrl.text} → ${endCtrl.text}",
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey.shade800,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.keyboard_arrow_up),
                                  tooltip: "Maximize",
                                  onPressed: () => setState(() => _routePanelExpanded = true),
                                  color: _kMainTeal,
                                ),
                              ],
                            ),
                            if (step == FlowStep.choose && routes.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  "${formatDurationShort(routes[chosenRoute.clamp(0, routes.length - 1)].durationSec)} • ${prettyKm(routes[chosenRoute.clamp(0, routes.length - 1)].distanceMeters)}",
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: _kMainTeal,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
              ),
            ),

          if (step == FlowStep.nav && routes.isNotEmpty)
            NavOverlay(
              route: routes[safeIndex],
              currentLocation: _navCurrentLocation ?? origin,
              destination: dest,
              onRecenter: () {
                final center = _navCurrentLocation ?? origin;
                if (center != null && mapCtrl != null) {
                  mapCtrl!.animateCamera(
                    CameraUpdate.newLatLngZoom(center, 17),
                  );
                }
              },
              onZoomIn: () => mapCtrl?.animateCamera(CameraUpdate.zoomIn()),
              onZoomOut: () => mapCtrl?.animateCamera(CameraUpdate.zoomOut()),
              onCompassTap: () {
                final center = _navCurrentLocation ?? origin;
                if (center != null && mapCtrl != null) {
                  mapCtrl!.animateCamera(
                    CameraUpdate.newLatLngZoom(center, _navZoom),
                  );
                }
              },
              onRouteOptionsTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Route options – recalculating from current location."),
                  ),
                );
                _recalculateRouteFromCurrentLocation();
              },
              onExit: () {
                // #region agent log
                debugLog(
                  'map_screen.dart:NavOverlay.onExit',
                  'user tapped exit in nav overlay',
                  runId: 'initial',
                  hypothesisId: 'H4',
                  data: {
                    'stepBefore': step.name,
                    'originText': startCtrl.text,
                    'destText': endCtrl.text,
                    'hasOrigin': origin != null,
                    'hasDest': dest != null,
                  },
                );
                // #endregion
                _stopPositionStream();
                FocusScope.of(context).unfocus();
                FocusManager.instance.primaryFocus?.unfocus();
                setState(() => step = FlowStep.choose);
              },
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
                                  backgroundColor: _kMainTeal,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
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
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
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
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 40,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              onPressed: () {
                                setState(() {
                                  showPollutantSelection = false;
                                  showPollutionDialog = true;
                                });
                              },
                              icon: const Icon(Icons.arrow_back),
                              tooltip: 'Back',
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                "Your concern about pollution",
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(width: 48),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Flexible(
                          child: GridView.builder(
                            shrinkWrap: true,
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                  childAspectRatio: 2.5,
                                ),
                            itemCount: (availablePollutants.isEmpty
                                    ? _defaultPollutantList
                                    : availablePollutants)
                                .length,
                            itemBuilder: (context, index) {
                              final listToShow = availablePollutants.isEmpty
                                  ? _defaultPollutantList
                                  : availablePollutants;
                              final pollutant = listToShow[index];
                              final isSelected = selectedPollutants.contains(
                                pollutant,
                              );

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
                                        ? _kMainTeal.withOpacity(0.25)
                                        : Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isSelected
                                            ? _kMainTeal
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
                                            ? _kMainTeal
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
                              backgroundColor: _kMainTeal,
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
