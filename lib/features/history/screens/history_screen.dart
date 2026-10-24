import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/providers/app_providers.dart';
import '../../../data/models/generation_model.dart';

/// History screen showing past AI generations with search and filters.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  final _searchController = TextEditingController();
  String _filter = 'all';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<GenerationModel> _filterHistory(List<GenerationModel> history) {
    var result = history;

    // Apply status filter
    if (_filter != 'all') {
      result = result.where((g) {
        switch (_filter) {
          case 'completed':
            return g.status == GenerationStatus.completed;
          case 'processing':
            return g.status == GenerationStatus.processing;
          case 'failed':
            return g.status == GenerationStatus.failed;
          default:
            return true;
        }
      }).toList();
    }

    // Apply search filter
    final query = _searchController.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      result = result.where((g) {
        return (g.gender?.toLowerCase().contains(query) ?? false) ||
            (g.style?.toLowerCase().contains(query) ?? false) ||
            (g.quality?.toLowerCase().contains(query) ?? false) ||
            (g.bodySize?.toLowerCase().contains(query) ?? false) ||
            (g.category?.toLowerCase().contains(query) ?? false) ||
            g.id.toLowerCase().contains(query);
      }).toList();
    }

    return result;
  }

  Future<void> _deleteGeneration(String id) async {
    try {
      final historyService = ref.read(historyServiceProvider);
      await historyService.deleteGeneration(id);
      ref.invalidate(historyListProvider);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Generation deleted')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete: $e'),
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
    }
  }

  Future<void> _clearAllHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Clear All History'),
        content: const Text(
          'This will permanently delete all generation history. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text(
              'Clear All',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final historyService = ref.read(historyServiceProvider);
        await historyService.clearHistory();
        ref.invalidate(historyListProvider);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('History cleared')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to clear history: $e'),
              backgroundColor: Colors.red.shade600,
            ),
          );
        }
      }
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';

    return '${date.day}/${date.month}/${date.year}';
  }

  IconData _statusIcon(GenerationStatus status) {
    switch (status) {
      case GenerationStatus.completed:
        return Icons.check_circle_rounded;
      case GenerationStatus.processing:
        return Icons.hourglass_top_rounded;
      case GenerationStatus.failed:
        return Icons.error_rounded;
      case GenerationStatus.pending:
        return Icons.schedule_rounded;
    }
  }

  Color _statusColor(GenerationStatus status) {
    switch (status) {
      case GenerationStatus.completed:
        return Colors.green;
      case GenerationStatus.processing:
        return Colors.orange;
      case GenerationStatus.failed:
        return Colors.red;
      case GenerationStatus.pending:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final historyList = ref.watch(historyListProvider);
    final filteredList = _filterHistory(historyList);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),

              // Title row with clear all button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'History',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (historyList.isNotEmpty)
                    IconButton(
                      onPressed: _clearAllHistory,
                      icon: Icon(
                        Icons.delete_sweep_rounded,
                        color: isDark
                            ? AppColors.darkTextTertiary
                            : AppColors.lightTextTertiary,
                      ),
                      tooltip: 'Clear all history',
                    ),
                ],
              ),
              const SizedBox(height: 16),

              // Search bar
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search generations...',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                        )
                      : null,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),

              // Filters
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _FilterChip(
                      label: 'All',
                      count: historyList.length,
                      isSelected: _filter == 'all',
                      onTap: () => setState(() => _filter = 'all'),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: 'Completed',
                      count: historyList
                          .where((g) => g.status == GenerationStatus.completed)
                          .length,
                      isSelected: _filter == 'completed',
                      onTap: () => setState(() => _filter = 'completed'),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: 'Processing',
                      count: historyList
                          .where((g) => g.status == GenerationStatus.processing)
                          .length,
                      isSelected: _filter == 'processing',
                      onTap: () => setState(() => _filter = 'processing'),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: 'Failed',
                      count: historyList
                          .where((g) => g.status == GenerationStatus.failed)
                          .length,
                      isSelected: _filter == 'failed',
                      onTap: () => setState(() => _filter = 'failed'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // History list or empty state
              Expanded(
                child: filteredList.isEmpty
                    ? _buildEmptyState(isDark, historyList.isEmpty)
                    : ListView.separated(
                        itemCount: filteredList.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final generation = filteredList[index];
                          return _HistoryCard(
                            generation: generation,
                            formattedDate: _formatDate(generation.createdAt),
                            isDark: isDark,
                            statusIcon: _statusIcon(generation.status),
                            statusColor: _statusColor(generation.status),
                            onDelete: () => _deleteGeneration(generation.id),
                            onTap: () => _openGenerationDetail(generation),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark, bool isTotalEmpty) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.darkSurfaceVariant
                  : AppColors.lightSurfaceVariant,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isTotalEmpty ? Icons.history_rounded : Icons.search_off_rounded,
              size: 36,
              color: isDark
                  ? AppColors.darkTextTertiary
                  : AppColors.lightTextTertiary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            isTotalEmpty ? 'No Generations Yet' : 'No Matches Found',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            isTotalEmpty
                ? 'Your AI try-on results will appear here'
                : 'Try adjusting your search or filter',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.lightTextSecondary,
            ),
          ),
          if (!isTotalEmpty) ...[
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                _searchController.clear();
                setState(() => _filter = 'all');
              },
              child: const Text('Clear Filters'),
            ),
          ],
        ],
      ),
    );
  }

  void _openGenerationDetail(GenerationModel generation) {
    showDialog(
      context: context,
      builder: (ctx) => _GenerationDetailDialog(
        generation: generation,
        isDark: Theme.of(context).brightness == Brightness.dark,
        onDelete: () {
          Navigator.pop(ctx);
          _deleteGeneration(generation.id);
        },
      ),
    );
  }
}

/// A card widget that displays a single generation history entry.
class _HistoryCard extends StatelessWidget {
  final GenerationModel generation;
  final String formattedDate;
  final bool isDark;
  final IconData statusIcon;
  final Color statusColor;
  final VoidCallback onDelete;
  final VoidCallback onTap;

  const _HistoryCard({
    required this.generation,
    required this.formattedDate,
    required this.isDark,
    required this.statusIcon,
    required this.statusColor,
    required this.onDelete,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Determine the best image to show as thumbnail
    final thumbnailPath =
        generation.resultImageUrl ?? generation.personImageUrl;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.darkSurfaceVariant
              : AppColors.lightSurfaceVariant,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: (isDark ? AppColors.darkDivider : AppColors.lightDivider)
                .withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 64,
                height: 64,
                child: _buildThumbnail(thumbnailPath),
              ),
            ),
            const SizedBox(width: 12),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(statusIcon, size: 16, color: statusColor),
                      const SizedBox(width: 4),
                      Text(
                        generation.status.name.toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: statusColor,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        formattedDate,
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark
                              ? AppColors.darkTextTertiary
                              : AppColors.lightTextTertiary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _buildOptionsLabel(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (generation.style != null || generation.quality != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        [
                          if (generation.style != null)
                            generation.style!.toUpperCase(),
                          if (generation.quality != null)
                            generation.quality!.toUpperCase(),
                        ].join(' · '),
                        style: TextStyle(
                          fontSize: 10,
                          color: isDark
                              ? AppColors.darkTextTertiary
                              : AppColors.lightTextTertiary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),

            // Delete button
            IconButton(
              onPressed: onDelete,
              icon: Icon(
                Icons.delete_outline_rounded,
                size: 20,
                color: isDark
                    ? AppColors.darkTextTertiary
                    : AppColors.lightTextTertiary,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnail(String path) {
    final file = File(path);
    if (file.existsSync()) {
      return Image.file(
        file,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _placeholderIcon(),
      );
    }
    return _placeholderIcon();
  }

  Widget _placeholderIcon() {
    return Container(
      color: isDark
          ? AppColors.darkDivider.withValues(alpha: 0.3)
          : AppColors.lightDivider.withValues(alpha: 0.3),
      child: Icon(
        Icons.image_rounded,
        color: isDark
            ? AppColors.darkTextTertiary
            : AppColors.lightTextTertiary,
      ),
    );
  }

  String _buildOptionsLabel() {
    final parts = <String>[
      if (generation.category != null)
        _formatCategory(generation.category!),
      if (generation.gender != null && generation.gender != 'auto')
        generation.gender!.toUpperCase(),
      if (generation.bodySize != null && generation.bodySize != 'auto')
        generation.bodySize!.toUpperCase(),
    ];
    if (parts.isEmpty) return 'Generation ${generation.id.substring(0, 8)}';
    return parts.join(' · ');
  }

  static String _formatCategory(String cat) {
    switch (cat) {
      case 'upper_body':
        return 'TOP';
      case 'lower_body':
        return 'BOTTOM';
      case 'dresses':
        return 'DRESS';
      default:
        return cat.replaceAll('_', ' ').toUpperCase();
    }
  }
}

/// Filter chip widget with count badge.
class _FilterChip extends StatelessWidget {
  final String label;
  final int count;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.count,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? AppColors.primary
                : (Theme.of(context).brightness == Brightness.dark
                          ? AppColors.darkDivider
                          : AppColors.lightDivider)
                      .withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? AppColors.primary
                    : (Theme.of(context).brightness == Brightness.dark
                          ? AppColors.darkTextSecondary
                          : AppColors.lightTextSecondary),
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                fontSize: 13,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary
                      : (Theme.of(context).brightness == Brightness.dark
                                ? AppColors.darkDivider
                                : AppColors.lightDivider)
                            .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? Colors.white
                        : (Theme.of(context).brightness == Brightness.dark
                              ? AppColors.darkTextSecondary
                              : AppColors.lightTextSecondary),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Full-screen dialog showing detailed view of a generation.
class _GenerationDetailDialog extends StatelessWidget {
  final GenerationModel generation;
  final bool isDark;
  final VoidCallback onDelete;

  const _GenerationDetailDialog({
    required this.generation,
    required this.isDark,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with status
              Row(
                children: [
                  _statusBadge(),
                  const Spacer(),
                  Text(
                    _formatDate(generation.createdAt),
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? AppColors.darkTextTertiary
                          : AppColors.lightTextTertiary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Images row
              Row(
                children: [
                  Expanded(
                    child: _buildPreview(
                      generation.personImageUrl,
                      'Person',
                      context,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildPreview(
                      generation.clothesImageUrl,
                      'Clothes',
                      context,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildPreview(
                      generation.resultImageUrl ?? '',
                      'Result',
                      context,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Details
              if (generation.category != null) ...[
                _detailRow(
                  Icons.checkroom_rounded,
                  'Category',
                  _HistoryCard._formatCategory(generation.category!),
                ),
                const SizedBox(height: 4),
              ],
              if (generation.gender != null || generation.bodySize != null) ...[
                _detailRow(
                  Icons.person_rounded,
                  'Gender',
                  generation.gender ?? 'Auto',
                ),
                const SizedBox(height: 4),
                _detailRow(
                  Icons.straighten_rounded,
                  'Body Size',
                  generation.bodySize ?? 'Auto',
                ),
              ],
              if (generation.style != null || generation.quality != null) ...[
                const SizedBox(height: 4),
                _detailRow(
                  Icons.brush_rounded,
                  'Style',
                  generation.style ?? '-',
                ),
                const SizedBox(height: 4),
                _detailRow(
                  Icons.high_quality_rounded,
                  'Quality',
                  generation.quality ?? '-',
                ),
              ],
              const SizedBox(height: 4),
              _detailRow(
                Icons.credit_card_rounded,
                'Credits',
                '${generation.creditsUsed}',
              ),
              const SizedBox(height: 4),
              _detailRow(
                Icons.tag_rounded,
                'ID',
                generation.id.substring(0, 12),
              ),

              const SizedBox(height: 20),

              // Actions
              Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                      label: const Text('Close'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('Delete'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusBadge() {
    String statusText;
    Color statusColor;
    IconData icon;

    switch (generation.status) {
      case GenerationStatus.completed:
        statusText = 'Completed';
        statusColor = Colors.green;
        icon = Icons.check_circle_rounded;
        break;
      case GenerationStatus.processing:
        statusText = 'Processing';
        statusColor = Colors.orange;
        icon = Icons.hourglass_top_rounded;
        break;
      case GenerationStatus.failed:
        statusText = 'Failed';
        statusColor = Colors.red;
        icon = Icons.error_rounded;
        break;
      case GenerationStatus.pending:
        statusText = 'Pending';
        statusColor = Colors.grey;
        icon = Icons.schedule_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: statusColor),
          const SizedBox(width: 4),
          Text(
            statusText,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: statusColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview(String path, String label, BuildContext context) {
    final file = File(path);
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: double.infinity,
            height: 100,
            color: isDark
                ? AppColors.darkSurfaceVariant
                : AppColors.lightSurfaceVariant,
            child: file.existsSync()
                ? Image.file(file, fit: BoxFit.cover)
                : Center(
                    child: Icon(
                      Icons.broken_image_rounded,
                      color: isDark
                          ? AppColors.darkTextTertiary
                          : AppColors.lightTextTertiary,
                      size: 28,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: isDark
                ? AppColors.darkTextTertiary
                : AppColors.lightTextTertiary,
          ),
        ),
      ],
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: isDark
              ? AppColors.darkTextTertiary
              : AppColors.lightTextTertiary,
        ),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 13,
            color: isDark
                ? AppColors.darkTextSecondary
                : AppColors.lightTextSecondary,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: isDark ? AppColors.darkText : AppColors.lightText,
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
