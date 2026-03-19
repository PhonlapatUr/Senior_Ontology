import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_places_flutter/google_places_flutter.dart';
import 'package:google_places_flutter/model/prediction.dart';
import 'package:geolocator/geolocator.dart';
import '../utils/debug_log.dart';

class SearchBox extends StatefulWidget {
  final TextEditingController controller;
  final String hint;
  final bool isOrigin;
  final FocusNode? focusNode;
  final String googleApiKey;
  final Future<void> Function(LatLng loc) onMyLocation;
  final Function(Prediction p) onPredictionSelected;
  final VoidCallback? onClear;

  const SearchBox({
    super.key,
    required this.controller,
    required this.hint,
    required this.isOrigin,
    this.focusNode,
    required this.googleApiKey,
    required this.onMyLocation,
    required this.onPredictionSelected,
    this.onClear,
  });

  @override
  State<SearchBox> createState() => _SearchBoxState();
}

class _SearchBoxState extends State<SearchBox> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _handleMyLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) return;

    final pos = await Geolocator.getCurrentPosition();
    final loc = LatLng(pos.latitude, pos.longitude);

    await widget.onMyLocation(loc);
  }

  Widget? _buildSuffixIcon() {
    final hasText = widget.controller.text.trim().isNotEmpty;
    final clearButton = (widget.onClear != null && hasText)
        ? IconButton(
            icon: const Icon(Icons.close, size: 20, color: Colors.grey),
            onPressed: widget.onClear,
            tooltip: 'Clear',
          )
        : null;

    if (widget.isOrigin) {
      final myLocationButton = IconButton(
        icon: const Icon(Icons.my_location, color: Color(0xFF26A69A)),
        onPressed: () {
          // #region agent log
          debugLog('search_box.dart:MyLocation', 'My Location pressed',
              hypothesisId: 'H1', data: {'isOrigin': true});
          // #endregion
          // Unfocus first so the patched google_places_flutter removes the suggestions overlay
          // on focus loss; then set "My Location" and resolve location.
          widget.focusNode?.unfocus();
          FocusScope.of(context).unfocus();
          FocusManager.instance.primaryFocus?.unfocus();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            widget.controller.text = "My Location";
            widget.controller.selection = TextSelection.fromPosition(
              TextPosition(offset: widget.controller.text.length),
            );
            _handleMyLocation();
          });
        },
      );
      if (clearButton != null) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [clearButton, myLocationButton],
        );
      }
      return myLocationButton;
    }
    return clearButton;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5), // light grey primary
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: GooglePlaceAutoCompleteTextField(
        googleAPIKey: widget.googleApiKey,
        textEditingController: widget.controller,
        focusNode: widget.focusNode,
        debounceTime: 600,
        isCrossBtnShown: false,
        textStyle: const TextStyle(fontSize: 14, color: Color(0xFF212121)),
        inputDecoration: InputDecoration(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 10,
          ),
          hintText: widget.hint,
          hintStyle: const TextStyle(color: Color(0xFF616161)),
          prefixIcon: Icon(
            widget.isOrigin ? Icons.my_location : Icons.place,
            color: const Color(0xFF26A69A), // main teal
          ),
          suffixIcon: _buildSuffixIcon(),
          filled: true,
          fillColor: const Color(0xFFF5F5F5),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
        isLatLngRequired: true,
        getPlaceDetailWithLatLng: (Prediction p) => widget.onPredictionSelected(p),
        itemClick: (Prediction p) {
          widget.controller.text = p.description ?? "";
          widget.controller.selection = TextSelection.fromPosition(
            TextPosition(offset: widget.controller.text.length),
          );
        },
        countries: const ["th"],
      ),
    );
  }
}
