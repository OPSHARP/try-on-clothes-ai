import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/gradient_button.dart';

enum CompareMode { splitSlider, sideBySide, single }
/// compare modes, download, share, and 6-month Ad-Free pack promotion.
class ResultScreen extends ConsumerStatefulWidget {
  final String personImagePath;
  final String clothesImagePath;
  final String resultImagePath;

  const ResultScreen({
    super.key,
    required this.personImagePath,
    required this.clothesImagePath,
    required this.resultImagePath,
  });

  @override
  ConsumerState<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends ConsumerState<ResultScreen> {
  CompareMode _compareMode = CompareMode.splitSlider;
  double _splitPosition = 0.5;
  bool _isHoldingOriginal = false;
  bool _isDownloading = false;
  bool _isSaving = false;

  Future<void> _shareResult() async {
    try {
      final file = File(widget.resultImagePath);
      if (await file.exists()) {
        await Share.shareXFiles(
          [XFile(widget.resultImagePath)],
          text: 'Check out my AI virtual try-on created with Try On Clothes AI!',
        );
      } else {
        await Share.share(
          'Check out Try On Clothes AI - the best virtual fitting room app!',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not share image: $e')));
      }
    }
  }

  /// Save the result image to public Gallery / Pictures or prompt system share.
  Future<void> _downloadResult() async {
    if (_isDownloading) return;
    setState(() => _isDownloading = true);

    try {
      final sourceFile = File(widget.resultImagePath);
      if (!await sourceFile.exists()) {
        throw Exception('Result file not found');
      }

      bool savedToPublicFolder = false;
      String? savedLocation;

      // On Android, attempt writing to the public Pictures or Download collection
      if (Platform.isAndroid) {
        final picturesDir = Directory('/storage/emulated/0/Pictures/TryOnAI');
        final downloadsDir = Directory('/storage/emulated/0/Download/TryOnAI');

        Directory? targetDir;
        try {
          if (await picturesDir.exists() || await picturesDir.create(recursive: true).then((_) => true)) {
            targetDir = picturesDir;
          }
        } catch (_) {}

        if (targetDir == null) {
          try {
            if (await downloadsDir.exists() || await downloadsDir.create(recursive: true).then((_) => true)) {
              targetDir = downloadsDir;
            }
          } catch (_) {}
        }

        if (targetDir != null) {
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final destPath = '${targetDir.path}/tryon_$timestamp.png';
          await sourceFile.copy(destPath);
          savedToPublicFolder = true;
          savedLocation = 'Saved to Pictures/TryOnAI';
        }
      }

      if (!savedToPublicFolder) {
        // Fall back to opening the native system share/save sheet
        await Share.shareXFiles(
          [XFile(widget.resultImagePath)],
          text: 'Save or share your AI try-on image',
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(savedLocation ?? 'Image saved to Gallery!'),
            backgroundColor: Colors.green.shade600,
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'Share',
              textColor: Colors.white,
              onPressed: _shareResult,
            ),
          ),
        );

      }
    } catch (e) {
      try {
        await Share.shareXFiles([XFile(widget.resultImagePath)]);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Download failed: $e'),
              backgroundColor: Colors.red.shade600,
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  /// Save the result to app's persistent storage for history/offline viewing.
  Future<void> _saveResult() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final sourceFile = File(widget.resultImagePath);
      if (!await sourceFile.exists()) {
        throw Exception('Result file not found');
      }

      final appDir = await getApplicationDocumentsDirectory();
      final savedDir = Directory('${appDir.path}/saved');
      if (!await savedDir.exists()) {
        await savedDir.create(recursive: true);
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final destPath = '${savedDir.path}/tryon_$timestamp.png';
      await sourceFile.copy(destPath);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Saved to app favorites'),
            backgroundColor: Colors.green.shade600,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed: $e'),
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isAdFree = ref.watch(isAdFreeProvider);
    final activePath = _isHoldingOriginal
        ? widget.personImagePath
        : widget.resultImagePath;
    final activeLabel = _isHoldingOriginal
        ? 'Original (Before)'
        : 'AI Try-On (After)';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Try-On Result'),
        actions: [
          if (!isAdFree)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: TextButton.icon(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  context.push('/ads-remove');
                },
                icon: const Icon(
                  Icons.workspace_premium_rounded,
                  color: Color(0xFFFBBF24),
                  size: 16,
                ),
                label: const Text(
                  'No Ads',
                  style: TextStyle(
                    color: Color(0xFFFBBF24),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          IconButton(
            onPressed: _shareResult,
            icon: const Icon(Icons.share_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          // Hint banner for compare mode
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text(
              _compareMode == CompareMode.splitSlider
                  ? 'Drag slider left/right to compare Before vs After'
                  : _compareMode == CompareMode.single
                  ? 'Hold image to see original • Pinch to zoom'
                  : 'Side-by-side Before & After comparison',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: isDark
                    ? AppColors.darkTextTertiary
                    : AppColors.lightTextTertiary,
                fontSize: 12,
              ),
            ),
          ),

          // ── Image Preview with Split Slider / Compare / Zoom ──
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: _compareMode == CompareMode.splitSlider
                    ? _buildSplitSlider(context, isDark)
                    : _compareMode == CompareMode.sideBySide
                    ? Row(
                        children: [
                          Expanded(
                            child: _buildImage(
                              widget.personImagePath,
                              'Before',
                              isDark,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _buildImage(
                              widget.resultImagePath,
                              'After',
                              isDark,
                            ),
                          ),
                        ],
                      )
                    : GestureDetector(
                        onTapDown: (_) =>
                            setState(() => _isHoldingOriginal = true),
                        onTapUp: (_) =>
                            setState(() => _isHoldingOriginal = false),
                        onTapCancel: () =>
                            setState(() => _isHoldingOriginal = false),
                        child: _buildImage(activePath, activeLabel, isDark),
                      ),
              ),
            ),
          ),

          // ── Action Buttons ──
          Container(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
            child: Column(
              children: [
                // Compare mode selector & Download & Save
                Row(
                  children: [
                    Expanded(
                      child: _ActionChip(
                        icon: _compareMode == CompareMode.splitSlider
                            ? Icons.compare_arrows_rounded
                            : _compareMode == CompareMode.sideBySide
                            ? Icons.view_column_rounded
                            : Icons.crop_portrait_rounded,
                        label: _compareMode == CompareMode.splitSlider
                            ? 'Slider View'
                            : _compareMode == CompareMode.sideBySide
                            ? 'Side-by-Side'
                            : 'Single View',
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() {
                            if (_compareMode == CompareMode.splitSlider) {
                              _compareMode = CompareMode.sideBySide;
                            } else if (_compareMode == CompareMode.sideBySide) {
                              _compareMode = CompareMode.single;
                            } else {
                              _compareMode = CompareMode.splitSlider;
                            }
                          });
                        },
                        isDark: isDark,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ActionChip(
                        icon: Icons.download_rounded,
                        label: _isDownloading ? 'Saving...' : 'Download',
                        onTap: _downloadResult,
                        isDark: isDark,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ActionChip(
                        icon: Icons.bookmark_border_rounded,
                        label: _isSaving ? 'Saving...' : 'Save',
                        onTap: _saveResult,
                        isDark: isDark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // VIP 6-Month Ad-Free Pack offer strip (if ads active)
                if (!isAdFree) _buildAdFreeOffer(context, isDark),

                const SizedBox(height: 4),

                // Generate again
                GradientButton(
                  text: 'Try Another Outfit',
                  icon: Icons.auto_awesome,
                  onPressed: () => context.pop(),
                ),
                const SizedBox(height: 4),

                // Go home
                TextButton(
                  onPressed: () => context.go('/home'),
                  child: const Text('Back to Home'),
                ),
              ],
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 6),
        ],
      ),
    );
  }

  /// Interactive Before / After Split Slider
  Widget _buildSplitSlider(BuildContext context, bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final dividerX = (width * _splitPosition).clamp(0.0, width);

        return GestureDetector(
          onHorizontalDragUpdate: (details) {
            final newPos = (details.localPosition.dx / width).clamp(0.02, 0.98);
            setState(() => _splitPosition = newPos);
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Layer 1: Try-On Result (Right / After)
              Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.darkSurfaceVariant
                      : AppColors.lightSurfaceVariant,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: InteractiveViewer(
                    minScale: 1.0,
                    maxScale: 3.5,
                    child: Image.file(
                      File(widget.resultImagePath),
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),

              // Layer 2: Original (Left / Before) with ClipRect
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: ClipRect(
                  clipper: _SplitClipper(_splitPosition),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.darkSurfaceVariant
                          : AppColors.lightSurfaceVariant,
                    ),
                    child: Image.file(
                      File(widget.personImagePath),
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),

              // Divider Line
              Positioned(
                left: dividerX - 1.5,
                top: 0,
                bottom: 0,
                child: Container(
                  width: 3,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
              ),

              // Draggable Center Handle
              Positioned(
                left: dividerX - 18,
                top: height / 2 - 18,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.compare_arrows_rounded,
                      color: Color(0xFF6342E8),
                      size: 22,
                    ),
                  ),
                ),
              ),

              // Before Label
              Positioned(
                top: 10,
                left: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Before',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),

              // After Label
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6342E8).withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'After',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 6-Month Ad-Free Pack High-Converting Offer Card
  Widget _buildAdFreeOffer(BuildContext context, bool isDark) {
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        context.push('/ads-remove');
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF312E81), Color(0xFF4F46E5)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF4F46E5).withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.workspace_premium_rounded,
                color: Color(0xFFFBBF24),
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Remove All Ads for 1 Month',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'Instant Try-On • \$${AppConstants.subscriptionPriceUSD.toStringAsFixed(2)} / month',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Get Pass',
                style: TextStyle(
                  color: Color(0xFF4338CA),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImage(String path, String? label, bool isDark) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.darkSurfaceVariant
                : AppColors.lightSurfaceVariant,
            borderRadius: BorderRadius.circular(20),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: InteractiveViewer(
              minScale: 1.0,
              maxScale: 4.0,
              clipBehavior: Clip.none,
              child: Image.file(
                File(path),
                fit: BoxFit.contain,
                errorBuilder: (context, error, stack) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.image_rounded,
                          size: 48,
                          color: isDark
                              ? AppColors.darkTextTertiary
                              : AppColors.lightTextTertiary,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'AI Generated Result',
                          style: TextStyle(
                            color: isDark
                               ? AppColors.darkTextTertiary
                                : AppColors.lightTextTertiary,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        if (label != null)
          Positioned(
            top: 10,
            left: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDark;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.darkSurfaceVariant
              : AppColors.lightSurfaceVariant,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: (isDark ? AppColors.darkDivider : AppColors.lightDivider)
                .withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 22,
              color: isDark ? AppColors.darkIcon : AppColors.lightIcon,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

class _SplitClipper extends CustomClipper<Rect> {
  final double fraction;
  _SplitClipper(this.fraction);

  @override
  Rect getClip(Size size) {
    return Rect.fromLTWH(0, 0, size.width * fraction, size.height);
  }

  @override
  bool shouldReclip(covariant _SplitClipper oldClipper) =>
      oldClipper.fraction != fraction;
}

