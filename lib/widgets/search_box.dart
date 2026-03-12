import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_places_flutter/google_places_flutter.dart';
import 'package:google_places_flutter/model/prediction.dart';
import 'package:geolocator/geolocator.dart';

class SearchBox extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool isOrigin;
  final String googleApiKey;
  final Future<void> Function(LatLng loc) onMyLocation;
  final Function(Prediction p) onPredictionSelected;

  const SearchBox({
    super.key,
    required this.controller,
    required this.hint,
    required this.isOrigin,
    required this.googleApiKey,
    required this.onMyLocation,
    required this.onPredictionSelected,
  });

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

    await onMyLocation(loc);
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
        googleAPIKey: googleApiKey,
        textEditingController: controller,
        debounceTime: 600,
        textStyle: const TextStyle(fontSize: 14, color: Color(0xFF212121)),
        inputDecoration: InputDecoration(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 10,
          ),
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFF616161)),
          prefixIcon: Icon(
            isOrigin ? Icons.my_location : Icons.place,
            color: const Color(0xFF8B5CF6), // purple accent
          ),
          suffixIcon: IconButton(
            icon: const Icon(Icons.my_location, color: Color(0xFF8B5CF6)),
            onPressed: () {
              controller.text = "My Location";
              _handleMyLocation();
            },
          ),
          filled: true,
          fillColor: const Color(0xFFF5F5F5),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
        isLatLngRequired: true,
        getPlaceDetailWithLatLng: (Prediction p) => onPredictionSelected(p),
        itemClick: (Prediction p) {
          controller.text = p.description ?? "";
          controller.selection = TextSelection.fromPosition(
            TextPosition(offset: controller.text.length),
          );
        },
        countries: const ["th"],
      ),
    );
  }
}
