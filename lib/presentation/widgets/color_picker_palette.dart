import 'package:flutter/material.dart';

/// A simple color picker widget with a palette of predefined colors
class ColorPickerPalette extends StatelessWidget {
  const ColorPickerPalette({
    super.key,
    required this.selectedColor,
    required this.onColorSelected,
  });

  final Color selectedColor;
  final ValueChanged<Color> onColorSelected;

  // Predefined color palette
  static const List<Color> _colorPalette = [
    // Blues
    Color(0xFF2563EB), // Blue 600
    Color(0xFF3B82F6), // Blue 500
    Color(0xFF60A5FA), // Blue 400
    Color(0xFF1E40AF), // Blue 800
    Color(0xFF1E3A8A), // Blue 900
    
    // Purples
    Color(0xFF8B5CF6), // Violet 500
    Color(0xFF7C3AED), // Violet 600
    Color(0xFF6D28D9), // Violet 700
    Color(0xFF9333EA), // Fuchsia 600
    
    // Greens
    Color(0xFF10B981), // Emerald 500
    Color(0xFF059669), // Emerald 600
    Color(0xFF34D399), // Emerald 400
    Color(0xFF047857), // Emerald 700
    
    // Reds
    Color(0xFFEF4444), // Red 500
    Color(0xFFDC2626), // Red 600
    Color(0xFFF87171), // Red 400
    Color(0xFFB91C1C), // Red 700
    
    // Oranges
    Color(0xFFF97316), // Orange 500
    Color(0xFFEA580C), // Orange 600
    Color(0xFFFB923C), // Orange 400
    Color(0xFFC2410C), // Orange 700
    
    // Yellows
    Color(0xFFEAB308), // Yellow 500
    Color(0xFFCA8A04), // Yellow 600
    Color(0xFFFCD34D), // Yellow 300
    Color(0xFFA16207), // Yellow 700
    
    // Teals/Cyans
    Color(0xFF14B8A6), // Teal 500
    Color(0xFF0D9488), // Teal 600
    Color(0xFF00FFFF), // Cyan
    Color(0xFF0891B2), // Cyan 600
    
    // Pinks
    Color(0xFFEC4899), // Pink 500
    Color(0xFFDB2777), // Pink 600
    Color(0xFFF472B6), // Pink 400
    Color(0xFFBE185D), // Pink 700
    
    // Grays
    Color(0xFF6B7280), // Gray 500
    Color(0xFF4B5563), // Gray 600
    Color(0xFF374151), // Gray 700
    Color(0xFF1F2937), // Gray 800
    
    // Special colors
    Color(0xFF000000), // Black
    Color(0xFFFFFFFF), // White
  ];

  String _colorToHex(Color color) {
    return '#${color.value.toRadixString(16).substring(2).toUpperCase()}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Primary Color',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        // Current color display
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outline),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: selectedColor,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline,
                    width: 2,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _colorToHex(selectedColor),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.colorize),
                tooltip: 'Custom color',
                onPressed: () => _showCustomColorPicker(context),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Color palette grid
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _colorPalette.map((color) {
            final isSelected = color.value == selectedColor.value;
            return GestureDetector(
              onTap: () => onColorSelected(color),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outline,
                    width: isSelected ? 3 : 1,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
                child: isSelected
                    ? Icon(
                        Icons.check,
                        color: _getContrastColor(color),
                        size: 20,
                      )
                    : null,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Color _getContrastColor(Color color) {
    // Calculate relative luminance
    final luminance = color.computeLuminance();
    // Return white for dark colors, black for light colors
    return luminance > 0.5 ? Colors.black : Colors.white;
  }

  void _showCustomColorPicker(BuildContext context) {
    // Parse current hex to RGB
    final currentHex = _colorToHex(selectedColor);
    final r = int.parse(currentHex.substring(1, 3), radix: 16);
    final g = int.parse(currentHex.substring(3, 5), radix: 16);
    final b = int.parse(currentHex.substring(5, 7), radix: 16);

    final rController = TextEditingController(text: r.toString());
    final gController = TextEditingController(text: g.toString());
    final bController = TextEditingController(text: b.toString());
    final hexController = TextEditingController(text: currentHex);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Custom Color'),
        content: StatefulBuilder(
          builder: (context, setDialogState) {
            void updateColor() {
              try {
                final rVal = int.parse(rController.text).clamp(0, 255);
                final gVal = int.parse(gController.text).clamp(0, 255);
                final bVal = int.parse(bController.text).clamp(0, 255);
                final newColor = Color.fromRGBO(rVal, gVal, bVal, 1.0);
                hexController.text = _colorToHex(newColor);
                setDialogState(() {});
              } catch (_) {
                // Invalid input, ignore
              }
            }

            void updateFromHex() {
              try {
                final hex = hexController.text.replaceAll('#', '');
                if (hex.length == 6) {
                  final rVal = int.parse(hex.substring(0, 2), radix: 16);
                  final gVal = int.parse(hex.substring(2, 4), radix: 16);
                  final bVal = int.parse(hex.substring(4, 6), radix: 16);
                  rController.text = rVal.toString();
                  gController.text = gVal.toString();
                  bController.text = bVal.toString();
                  setDialogState(() {});
                }
              } catch (_) {
                // Invalid hex, ignore
              }
            }

            Color? previewColor;
            try {
              final rVal = int.tryParse(rController.text)?.clamp(0, 255) ?? 0;
              final gVal = int.tryParse(gController.text)?.clamp(0, 255) ?? 0;
              final bVal = int.tryParse(bController.text)?.clamp(0, 255) ?? 0;
              previewColor = Color.fromRGBO(rVal, gVal, bVal, 1.0);
            } catch (_) {
              previewColor = selectedColor;
            }

            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Color preview
                  Container(
                    width: double.infinity,
                    height: 60,
                    decoration: BoxDecoration(
                      color: previewColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        _colorToHex(previewColor),
                        style: TextStyle(
                          color: _getContrastColor(previewColor),
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // RGB inputs
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: rController,
                          decoration: const InputDecoration(
                            labelText: 'R',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (_) => updateColor(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: gController,
                          decoration: const InputDecoration(
                            labelText: 'G',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (_) => updateColor(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: bController,
                          decoration: const InputDecoration(
                            labelText: 'B',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (_) => updateColor(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Hex input
                  TextField(
                    controller: hexController,
                    decoration: const InputDecoration(
                      labelText: 'Hex',
                      border: OutlineInputBorder(),
                      prefixText: '#',
                    ),
                    onChanged: (_) => updateFromHex(),
                  ),
                ],
              ),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              try {
                final hex = hexController.text.replaceAll('#', '');
                if (hex.length == 6) {
                  final r = int.parse(hex.substring(0, 2), radix: 16);
                  final g = int.parse(hex.substring(2, 4), radix: 16);
                  final b = int.parse(hex.substring(4, 6), radix: 16);
                  onColorSelected(Color.fromRGBO(r, g, b, 1.0));
                }
              } catch (_) {
                // Invalid color, ignore
              }
              Navigator.of(context).pop();
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }
}
