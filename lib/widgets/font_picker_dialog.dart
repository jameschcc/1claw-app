import 'package:flutter/material.dart';
import 'package:posh_flutter_components/font/posh_font_service.dart';

/// Dialog for selecting a UI font from the system's available fonts.
/// Design follows 1Shell's font selector pattern with search + preview.
class FontPickerDialog extends StatefulWidget {
  final String currentFont;

  const FontPickerDialog({super.key, required this.currentFont});

  @override
  State<FontPickerDialog> createState() => _FontPickerDialogState();
}

class _FontPickerDialogState extends State<FontPickerDialog> {
  String _searchQuery = '';
  String _selectedFont = '';
  final TextEditingController _searchController = TextEditingController();
  List<String> _availableFonts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _selectedFont = widget.currentFont;
    _loadFonts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFonts() async {
    try {
      final list = await PoshFontService.getAvailableFonts();
      // Ensure 'System' is always listed first as default
      if (!list.contains('System')) {
        list.insert(0, 'System');
      }
      setState(() {
        _availableFonts = list;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _availableFonts = ['System'];
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isLoading) {
      return AlertDialog(
        content: const SizedBox(
          height: 80,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final filteredFonts = _searchQuery.isEmpty
        ? _availableFonts
        : _availableFonts
            .where((f) => f.toLowerCase().contains(_searchQuery.toLowerCase()))
            .toList();

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Row(
        children: [
          Icon(
            Icons.text_fields,
            size: 20,
            color: isDark ? Colors.white70 : Colors.black87,
          ),
          const SizedBox(width: 8),
          const Expanded(child: Text('Choose UI Font')),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          children: [
            // Search field
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search fonts...',
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                border: const OutlineInputBorder(),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
            const SizedBox(height: 8),
            // Count
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${filteredFonts.length} font${filteredFonts.length != 1 ? 's' : ''} available',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Font list
            Expanded(
              child: ListView.separated(
                itemCount: filteredFonts.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final font = filteredFonts[index];
                  final isSelected = font == _selectedFont;
                  return RadioListTile<String>(
                    title: Text(
                      font,
                      style: TextStyle(
                        fontFamily: font == 'System' ? null : font,
                        fontSize: 14,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    secondary: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white12 : Colors.grey[100],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Aa 1',
                        style: TextStyle(
                          fontFamily: font == 'System' ? null : font,
                          fontSize: 12,
                          color: isDark ? Colors.white60 : Colors.grey[700],
                        ),
                      ),
                    ),
                    value: font,
                    groupValue: _selectedFont,
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _selectedFont = value);
                      }
                    },
                    dense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_selectedFont),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
