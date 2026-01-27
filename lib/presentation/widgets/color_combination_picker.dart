import 'package:flutter/material.dart';

/// A color combination represents a cohesive set of colors for UI design
class ColorCombination {
  const ColorCombination({
    required this.name,
    required this.description,
    required this.primaryHex,
    required this.secondaryHex,
    required this.textHex,
    this.category = 'Modern',
  });

  final String name;
  final String description;
  final String primaryHex;
  final String secondaryHex;
  final String textHex;
  final String category;

  Color get primaryColor => _hexToColor(primaryHex);
  Color get secondaryColor => _hexToColor(secondaryHex);
  Color get textColor => _hexToColor(textHex);

  Color _hexToColor(String hex) {
    try {
      final hexColor = hex.replaceAll('#', '');
      if (hexColor.length == 6) {
        return Color(int.parse('FF$hexColor', radix: 16));
      }
    } catch (_) {
      // Invalid color
    }
    return const Color(0xFF000000);
  }
}

/// Widget for selecting color combinations with creative presets
class ColorCombinationPicker extends StatefulWidget {
  const ColorCombinationPicker({
    super.key,
    required this.selectedPrimaryHex,
    required this.onCombinationSelected,
  });

  final String selectedPrimaryHex;
  final ValueChanged<ColorCombination> onCombinationSelected;

  @override
  State<ColorCombinationPicker> createState() => _ColorCombinationPickerState();
}

class _ColorCombinationPickerState extends State<ColorCombinationPicker> {
  bool _isDropdownOpen = false;

  static const List<ColorCombination> _combinations = [
    // Ocean & Sky
    ColorCombination(
      name: 'Ocean Breeze',
      description: 'Calm blue tones',
      primaryHex: '#0EA5E9',
      secondaryHex: '#7DD3FC',
      textHex: '#0C4A6E',
      category: 'Ocean & Sky',
    ),
    ColorCombination(
      name: 'Deep Ocean',
      description: 'Rich navy blues',
      primaryHex: '#1E40AF',
      secondaryHex: '#3B82F6',
      textHex: '#1E3A8A',
      category: 'Ocean & Sky',
    ),
    ColorCombination(
      name: 'Sky Blue',
      description: 'Light and airy',
      primaryHex: '#38BDF8',
      secondaryHex: '#BAE6FD',
      textHex: '#075985',
      category: 'Ocean & Sky',
    ),

    // Nature & Earth
    ColorCombination(
      name: 'Forest Green',
      description: 'Natural and fresh',
      primaryHex: '#059669',
      secondaryHex: '#34D399',
      textHex: '#064E3B',
      category: 'Nature & Earth',
    ),
    ColorCombination(
      name: 'Emerald',
      description: 'Vibrant green',
      primaryHex: '#10B981',
      secondaryHex: '#6EE7B7',
      textHex: '#065F46',
      category: 'Nature & Earth',
    ),
    ColorCombination(
      name: 'Sage',
      description: 'Muted earth tones',
      primaryHex: '#84CC16',
      secondaryHex: '#BEF264',
      textHex: '#365314',
      category: 'Nature & Earth',
    ),

    // Sunset & Warmth
    ColorCombination(
      name: 'Sunset Orange',
      description: 'Warm and inviting',
      primaryHex: '#F97316',
      secondaryHex: '#FDBA74',
      textHex: '#9A3412',
      category: 'Sunset & Warmth',
    ),
    ColorCombination(
      name: 'Amber Glow',
      description: 'Golden warmth',
      primaryHex: '#F59E0B',
      secondaryHex: '#FCD34D',
      textHex: '#78350F',
      category: 'Sunset & Warmth',
    ),
    ColorCombination(
      name: 'Coral',
      description: 'Soft and friendly',
      primaryHex: '#EF4444',
      secondaryHex: '#FCA5A5',
      textHex: '#991B1B',
      category: 'Sunset & Warmth',
    ),

    // Purple & Royal
    ColorCombination(
      name: 'Royal Purple',
      description: 'Bold and elegant',
      primaryHex: '#7C3AED',
      secondaryHex: '#A78BFA',
      textHex: '#5B21B6',
      category: 'Purple & Royal',
    ),
    ColorCombination(
      name: 'Violet Dream',
      description: 'Soft purple tones',
      primaryHex: '#8B5CF6',
      secondaryHex: '#C4B5FD',
      textHex: '#6D28D9',
      category: 'Purple & Royal',
    ),
    ColorCombination(
      name: 'Fuchsia',
      description: 'Vibrant and modern',
      primaryHex: '#D946EF',
      secondaryHex: '#F0ABFC',
      textHex: '#A21CAF',
      category: 'Purple & Royal',
    ),

    // Pink & Rose
    ColorCombination(
      name: 'Rose Gold',
      description: 'Elegant and soft',
      primaryHex: '#EC4899',
      secondaryHex: '#F9A8D4',
      textHex: '#BE185D',
      category: 'Pink & Rose',
    ),
    ColorCombination(
      name: 'Blush',
      description: 'Delicate pink',
      primaryHex: '#F472B6',
      secondaryHex: '#FBCFE8',
      textHex: '#9F1239',
      category: 'Pink & Rose',
    ),

    // Teal & Cyan
    ColorCombination(
      name: 'Teal Wave',
      description: 'Fresh and modern',
      primaryHex: '#14B8A6',
      secondaryHex: '#5EEAD4',
      textHex: '#134E4A',
      category: 'Teal & Cyan',
    ),
    ColorCombination(
      name: 'Cyan',
      description: 'Bright and energetic',
      primaryHex: '#06B6D4',
      secondaryHex: '#67E8F9',
      textHex: '#164E63',
      category: 'Teal & Cyan',
    ),

    // Monochrome & Professional
    ColorCombination(
      name: 'Midnight',
      description: 'Dark and professional',
      primaryHex: '#2563EB',
      secondaryHex: '#60A5FA',
      textHex: '#1E293B',
      category: 'Monochrome & Professional',
    ),
    ColorCombination(
      name: 'Charcoal',
      description: 'Sophisticated gray',
      primaryHex: '#475569',
      secondaryHex: '#94A3B8',
      textHex: '#0F172A',
      category: 'Monochrome & Professional',
    ),
    ColorCombination(
      name: 'Slate',
      description: 'Modern gray tones',
      primaryHex: '#64748B',
      secondaryHex: '#CBD5E1',
      textHex: '#1E293B',
      category: 'Monochrome & Professional',
    ),

    // Bold & Vibrant
    ColorCombination(
      name: 'Electric Blue',
      description: 'High energy',
      primaryHex: '#3B82F6',
      secondaryHex: '#93C5FD',
      textHex: '#1E3A8A',
      category: 'Bold & Vibrant',
    ),
    ColorCombination(
      name: 'Neon Green',
      description: 'Eye-catching',
      primaryHex: '#22C55E',
      secondaryHex: '#86EFAC',
      textHex: '#14532D',
      category: 'Bold & Vibrant',
    ),
    ColorCombination(
      name: 'Fire Red',
      description: 'Bold and urgent',
      primaryHex: '#DC2626',
      secondaryHex: '#FCA5A5',
      textHex: '#7F1D1D',
      category: 'Bold & Vibrant',
    ),
  ];

  Color _parseColor(String hex) {
    try {
      final hexColor = hex.replaceAll('#', '');
      if (hexColor.length == 6) {
        return Color(int.parse('FF$hexColor', radix: 16));
      }
    } catch (_) {
      // Invalid color
    }
    return const Color(0xFF2563EB);
  }

  ColorCombination? _findCurrentCombination() {
    final currentColor = _parseColor(widget.selectedPrimaryHex);
    return ColorCombinationPicker._combinations.firstWhere(
      (c) => c.primaryColor.value == currentColor.value,
      orElse: () => ColorCombinationPicker._combinations.first,
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = _findCurrentCombination();
    final grouped = <String, List<ColorCombination>>{};
    for (final combo in _combinations) {
      grouped.putIfAbsent(combo.category, () => []).add(combo);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Color Scheme',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<ColorCombination>(
          value: current,
          decoration: const InputDecoration(
            labelText: 'Select color combination',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.palette_outlined),
          ),
          isExpanded: true,
          items: grouped.entries.map((entry) {
            return [
              // Category header
              DropdownMenuItem<ColorCombination>(
                enabled: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    entry.key,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  ),
                ),
              ),
              // Items in category
              ...entry.value.map((combo) {
                final isSelected = combo.primaryHex == selectedPrimaryHex;
                return DropdownMenuItem<ColorCombination>(
                  value: combo,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        // Color swatches
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: combo.primaryColor,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Theme.of(context).colorScheme.outline,
                                  width: 1.5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                color: combo.secondaryColor,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Theme.of(context).colorScheme.outline,
                                  width: 1,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: combo.textColor,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Theme.of(context).colorScheme.outline,
                                  width: 1,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                combo.name,
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    ),
                              ),
                              Text(
                                combo.description,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      fontSize: 11,
                                    ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        if (isSelected)
                          Icon(
                            Icons.check_circle,
                            size: 20,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                      ],
                    ),
                  ),
                );
              }),
            ];
          }).expand((x) => x).toList(),
          onChanged: (combo) {
            if (combo != null) {
              onCombinationSelected(combo);
            }
          },
        ),
        if (current != null) ...[
          const SizedBox(height: 12),
          // Show color preview
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).colorScheme.outline),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Primary',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: current.primaryColor,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Theme.of(context).colorScheme.outline,
                                width: 2,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            current.primaryHex,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  fontFamily: 'monospace',
                                ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Secondary',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: current.secondaryColor,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Theme.of(context).colorScheme.outline,
                                width: 2,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            current.secondaryHex,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  fontFamily: 'monospace',
                                ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Text',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: current.textColor,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Theme.of(context).colorScheme.outline,
                                width: 2,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            current.textHex,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  fontFamily: 'monospace',
                                ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),