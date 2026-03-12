import 'package:flutter/material.dart';

class PollutionPanel extends StatelessWidget {
  final List<String> pollutants;
  final Set<String> selected;
  final Function(String p, bool selected) onChange;
  final VoidCallback onConfirm;
  final bool canConfirm;

  const PollutionPanel({
    super.key,
    required this.pollutants,
    required this.selected,
    required this.onChange,
    required this.onConfirm,
    required this.canConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Color(0xFFE0E0E0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Select pollutants you care about",
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFF212121),
            ),
          ),

          const SizedBox(height: 8),

          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: pollutants.map((p) {
              final isSelected = selected.contains(p);
              return FilterChip(
                selected: isSelected,
                label: Text(
                  p,
                  style: TextStyle(
                    color: isSelected ? Colors.white : const Color(0xFF424242),
                  ),
                ),
                selectedColor: const Color(0xFF8B5CF6), // purple accent
                backgroundColor: const Color(0xFFE0E0E0),
                onSelected: (v) => onChange(p, v),
              );
            }).toList(),
          ),

          const SizedBox(height: 12),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: canConfirm ? onConfirm : null,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                backgroundColor: const Color(0xFF8B5CF6),
                disabledBackgroundColor: const Color(0xFFCECECE),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                "CONFIRM",
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
