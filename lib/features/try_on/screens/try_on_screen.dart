import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/config/ad_config.dart';
import '../../../core/services/ad_service.dart';
import '../../../data/models/generation_model.dart';

/// AI Try-On screen: upload person photo, upload clothes, set options, generate.
class TryOnScreen extends ConsumerStatefulWidget {
  const TryOnScreen({super.key});

  @override
  ConsumerState<TryOnScreen> createState() => _TryOnScreenState();
}

class _TryOnScreenState extends ConsumerState<TryOnScreen> {
  final _imagePicker = ImagePicker();
  final _garmentDescController = TextEditingController();
  String? _personImagePath;
  String? _clothesImagePath;
  bool _isGenerating = false;
  String _pipelineStage = 'Preparing AI Image Generation Pipeline...';
  double _pipelineProgress = 0.1;

  // Advanced options
  String _category = 'upper_body'; // 'upper_body', 'lower_body', 'dresses'
  String _gender = 'auto';
  String _bodySize = 'auto';
  String _style = 'realistic';
  String _quality = 'standard';
  bool _showAdvanced = false;

  // Currently selected provider for generation
  late String _selectedProviderId;

  @override
  void initState() {
    super.initState();
    _selectedProviderId = ref.read(storageServiceProvider).selectedProviderId;
    _preloadAds();
  }

  @override
  void dispose() {
    _garmentDescController.dispose();
    super.dispose();
  }

  void _preloadAds() {
    final showAd = AdConfig.shouldShowAds(ref.read(isAdFreeProvider));
    if (showAd) {
      AdService.instance.preloadAllAds();
    }
  }

  /// Allowed image file extensions for upload validation.
  static const _validImageExtensions = [
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.bmp',
  ];

  Future<void> _pickImage({required bool isPerson}) async {
    final source = await _showImageSourceDialog();
    if (source == null) return;

    // 1024x1365 follows the 3:4 portrait ratio standard for IDM-VTON models,
    // avoiding distorted proportions and reducing upload payload latency.
    final picked = await _imagePicker.pickImage(
      source: source,
      maxWidth: 1024,
      maxHeight: 1365,
      imageQuality: 92,
    );

    if (picked != null) {
      // Validate the picked file is a supported image format
      final ext = picked.path.toLowerCase();
      final isValid = _validImageExtensions.any((e) => ext.endsWith(e));
      if (!isValid) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Unsupported image format. Please use JPG, PNG, or WebP.',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      setState(() {
        if (isPerson) {
          _personImagePath = picked.path;
        } else {
          _clothesImagePath = picked.path;
        }
      });
    }
  }

  Future<ImageSource?> _showImageSourceDialog() async {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottomPadding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color:
                        (isDark
                                ? AppColors.darkTextTertiary
                                : Colors.grey.shade300)
                            .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Choose Image Source',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _SourceOption(
                        icon: Icons.camera_alt_rounded,
                        label: 'Camera',
                        onTap: () => Navigator.pop(context, ImageSource.camera),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _SourceOption(
                        icon: Icons.photo_library_rounded,
                        label: 'Gallery',
                        onTap: () =>
                            Navigator.pop(context, ImageSource.gallery),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Callback when the user selects a different AI provider.
  void _onProviderChanged(String providerId) {
    if (providerId == _selectedProviderId) return;
    ref.read(selectedProviderIdProvider.notifier).setProvider(providerId);
    setState(() => _selectedProviderId = providerId);
  }

  Future<void> _generate() async {
    if (_personImagePath == null || _clothesImagePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please upload both images')),
      );
      return;
    }

    // Check if AI pipeline service is available
    final pipelineService = ref.read(aiImagePipelineServiceProvider);
    if (pipelineService == null) {
      _showNoApiKeyDialog();
      return;
    }

    final bool showAd = AdConfig.shouldShowAds(ref.read(isAdFreeProvider));
    final bool isSecondResult = AdService.shouldTriggerForNextGeneration();

    // Start generation immediately with stage updates
    setState(() {
      _isGenerating = true;
      _pipelineStage = 'Preparing AI Image Generation Pipeline...';
      _pipelineProgress = 0.1;
    });

    try {
      // Read image files
      final personBytes = await File(_personImagePath!).readAsBytes();
      final clothesBytes = await File(_clothesImagePath!).readAsBytes();

      // Generate a detailed garment description for better model guidance
      final garmentDescription = _buildGarmentDescription();

      // ── Asynchronous Background Generation Task ──
      // Execute full Multi-Skill Generation & Enhancement Pipeline in background
      final generationFuture = pipelineService.executePipeline(
        personImage: personBytes,
        clothesImage: clothesBytes,
        userGarmentDescription: garmentDescription,
        category: _category,
        style: _style,
        quality: _quality,
        onProgress: (stage, progress) {
          if (mounted) {
            setState(() {
              _pipelineStage = stage;
              _pipelineProgress = progress;
            });
          }
        },
      );

      // ── Concurrent Interstitial Ad on Every 2nd Generation ──
      // While AI generation is calculating in the background, play 1 interstitial ad
      if (showAd && isSecondResult) {
        try {
          if (AdService.instance.isInterstitialReady) {
            await AdService.instance.showInterstitial(ignoreCooldown: true);
          } else {
            final loaded = await AdService.instance.loadInterstitial();
            if (loaded) {
              await AdService.instance.showInterstitial(ignoreCooldown: true);
            }
          }
        } catch (adError) {
          debugPrint('Ad presentation error during background generation: $adError');
        }
      }

      // Await background generation completion
      final result = await generationFuture;

      // Save result image to a temporary file
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final resultPath = '${tempDir.path}/tryon_result_$timestamp.png';
      await File(resultPath).writeAsBytes(result.imageBytes);

      // Save generation to permanent history
      await _saveToHistory(resultPath);

      // Record generation completion count and preload next ad
      AdService.recordGenerationCompleted();
      _preloadAds();

      if (!mounted) return;
      setState(() => _isGenerating = false);

      if (mounted) {
        context.push(
          '/result',
          extra: {
            'personImage': _personImagePath,
            'clothesImage': _clothesImagePath,
            'resultImage': resultPath,
          },
        );
      }

    } catch (e) {
      setState(() => _isGenerating = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Generation failed: ${_getUserFriendlyError(e)}'),
            backgroundColor: Colors.red.shade600,
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () => _generate(),
            ),
          ),
        );
      }
    }
  }

  /// Build a concise garment description for the VTON model.
  ///
  /// SDXL text encoders perform best with clean, natural apparel labels
  /// (e.g. "short sleeve crewneck t-shirt", "casual button-down shirt")
  /// rather than abstract phrases.
  String _buildGarmentDescription() {
    final customDesc = _garmentDescController.text.trim();
    if (customDesc.isNotEmpty) {
      return customDesc;
    }

    final categoryHint = _category == 'upper_body'
        ? 't-shirt, shirt, top'
        : _category == 'lower_body'
        ? 'jeans, pants, trousers'
        : 'dress, full outfit';

    final genderHint = _gender == 'male'
        ? 'men\'s'
        : _gender == 'female'
        ? 'women\'s'
        : '';

    final styleHint = _style == 'vintage' ? 'vintage' : '';

    final parts = [
      if (genderHint.isNotEmpty) genderHint,
      if (styleHint.isNotEmpty) styleHint,
      categoryHint,
    ];

    return parts.join(' ').trim();
  }

  /// Save the completed generation to permanent local history.
  Future<void> _saveToHistory(String tempResultPath) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final historyDir = Directory('${appDir.path}/history');
      if (!await historyDir.exists()) {
        await historyDir.create(recursive: true);
      }

      final id = const Uuid().v4();
      final permResultPath = '${historyDir.path}/${id}_result.png';
      final permPersonPath = '${historyDir.path}/${id}_person.png';
      final permClothesPath = '${historyDir.path}/${id}_clothes.png';

      await File(tempResultPath).copy(permResultPath);
      if (_personImagePath != null && File(_personImagePath!).existsSync()) {
        await File(_personImagePath!).copy(permPersonPath);
      }
      if (_clothesImagePath != null && File(_clothesImagePath!).existsSync()) {
        await File(_clothesImagePath!).copy(permClothesPath);
      }

      final historyService = ref.read(historyServiceProvider);
      final generation = GenerationModel(
        id: id,
        userId: 'local',
        personImageUrl: File(permPersonPath).existsSync() ? permPersonPath : (_personImagePath ?? ''),
        clothesImageUrl: File(permClothesPath).existsSync() ? permClothesPath : (_clothesImagePath ?? ''),
        resultImageUrl: permResultPath,
        creditsUsed: 1,
        createdAt: DateTime.now(),
        status: GenerationStatus.completed,
        gender: _gender,
        bodySize: _bodySize,
        style: _style,
        quality: _quality,
        category: _category,
      );
      await historyService.addGeneration(generation);
      ref.invalidate(historyListProvider);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to save generation to history: $e');
      }
    }
  }

  /// Convert technical errors to user-friendly messages.
  String _getUserFriendlyError(Object error) {
    final msg = error.toString();

    // HTTP 400 - Invalid request (most common cause of generation failure)
    if (msg.contains('HTTP 400') ||
        msg.contains('statusCode: 400') ||
        msg.contains('invalid-argument')) {
      return 'Request format error. The images may be too large or in an unsupported format.';
    }

    // HTTP 401 / 403 - Auth errors (incorrect API key)
    if (msg.contains('HTTP 401') ||
        msg.contains('HTTP 403') ||
        msg.contains('unauthenticated') ||
        msg.contains('permission-denied')) {
      return 'Invalid API key. Please check your API key in Settings.';
    }

    // HTTP 429 - Rate limit / ZeroGPU quota
    if (msg.contains('HTTP 429') ||
        msg.contains('Rate limit') ||
        msg.contains('rate_limit') ||
        msg.contains('resource-exhausted') ||
        msg.contains('ZeroGPU') ||
        msg.contains('quota')) {
      return 'AI GPU servers are in high demand. Please wait a moment and try again.';
    }

    // VTON model error
    if (msg.contains('VTON model error')) {
      return 'Garment alignment error. Please ensure person and cloth photos are clear.';
    }

    // HTTP 502 / 503 - Server errors / model loading
    if (msg.contains('HTTP 502') ||
        msg.contains('HTTP 503') ||
        msg.contains('internal') ||
        msg.contains('unavailable') ||
        msg.contains('loading') ||
        msg.contains('overloaded') ||
        msg.contains('GENERATION_FAILED') ||
        msg.contains('DOWNLOAD_FAILED')) {
      return 'AI model is temporarily unavailable. Please try again.';
    }

    // Server configuration errors
    if (msg.contains('SERVER_CONFIG') || msg.contains('not configured')) {
      return 'Service not fully configured. Please check your API settings.';
    }

    // Timeouts
    if (msg.contains('timeout') ||
        msg.contains('Timeout') ||
        msg.contains('deadline-exceeded')) {
      return 'Request timed out. The server may be busy. Please try again.';
    }

    // Network errors
    if (msg.contains('SocketException') ||
        msg.contains('Connection') ||
        msg.contains('Failed host lookup')) {
      return 'Network error. Check your internet connection.';
    }

    // Generic AiServiceException - show the real message
    if (msg.startsWith('AiServiceException:')) {
      final endIdx = msg.indexOf(' (HTTP');
      final endIdx2 = endIdx == -1 ? msg.indexOf(' [model:') : endIdx;
      final end = endIdx2 == -1 ? msg.length : endIdx2;
      final cleanMsg = msg.substring('AiServiceException: '.length, end);
      return cleanMsg.isNotEmpty
          ? cleanMsg
          : 'Something went wrong. Please try again.';
    }

    return 'Something went wrong. Please try again.';
  }

  /// Show dialog when no AI service is available / API key not configured.
  void _showNoApiKeyDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          backgroundColor: isDark
              ? AppColors.darkSurface
              : AppColors.lightSurface,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.vpn_key_rounded,
                  color: AppColors.warning,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Text('API Key Required'),
            ],
          ),
          content: const Text(
            'To use AI generation, you need to configure an API key.\n\n'
            'Please go to Settings, select your preferred AI provider, '
            'and enter your API key.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary,
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  context.push('/profile');
                },
                child: const Text(
                  'Open Settings',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final configuredProviders = ref.watch(configuredProvidersProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('AI Try On'),
      ),
      body: _isGenerating
          ? _GeneratingView(
              isDark: isDark,
              stageMessage: _pipelineStage,
              progress: _pipelineProgress,
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Step 1: Upload Person
                  Text(
                    'Step 1: Upload Your Photo',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Take a photo or choose from gallery',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isDark
                          ? AppColors.darkTextTertiary
                          : AppColors.lightTextTertiary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _ImageUploadCard(
                    imagePath: _personImagePath,
                    icon: Icons.person_rounded,
                    label: 'Choose Your Photo',
                    onTap: () => _pickImage(isPerson: true),
                    onRemove: () => setState(() => _personImagePath = null),
                    isDark: isDark,
                  ),
                  const SizedBox(height: 24),

                  // Step 2: Upload Clothes
                  Text(
                    'Step 2: Upload Clothing',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'PNG, JPG, or transparent PNG supported',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isDark
                          ? AppColors.darkTextTertiary
                          : AppColors.lightTextTertiary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _ImageUploadCard(
                    imagePath: _clothesImagePath,
                    icon: Icons.checkroom_rounded,
                    label: 'Choose Cloth Photo',
                    onTap: () => _pickImage(isPerson: false),
                    onRemove: () => setState(() => _clothesImagePath = null),
                    isDark: isDark,
                  ),
                  const SizedBox(height: 12),
                  // Optional Garment Details field to maximize AI model accuracy
                  TextField(
                    controller: _garmentDescController,
                    decoration: InputDecoration(
                      hintText: 'e.g. Navy blue polo, black leather jacket, white cotton t-shirt',
                      labelText: 'Garment Details (Boosts AI accuracy significantly)',
                      prefixIcon: const Icon(Icons.edit_note_rounded),
                      filled: true,
                      fillColor: isDark
                          ? AppColors.darkSurfaceVariant.withValues(alpha: 0.5)
                          : AppColors.lightSurfaceVariant.withValues(alpha: 0.5),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      'T-Shirt',
                      'Casual Shirt',
                      'Hoodie',
                      'Jacket',
                      'Sweater',
                      'Polo Shirt',
                      'Jeans',
                      'Dress',
                    ].map((tag) {
                      return ActionChip(
                        label: Text(tag, style: const TextStyle(fontSize: 11)),
                        onPressed: () {
                          _garmentDescController.text = tag;
                          setState(() {});
                        },
                        visualDensity: VisualDensity.compact,
                        backgroundColor: isDark
                            ? AppColors.darkSurfaceVariant.withValues(alpha: 0.5)
                            : AppColors.lightSurfaceVariant.withValues(alpha: 0.5),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),

                  // Step 3: Garment Category
                  Text(
                    'Step 3: Garment Category',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Choose the type of clothing for best AI fit and accuracy',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isDark
                          ? AppColors.darkTextTertiary
                          : AppColors.lightTextTertiary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _CategoryCard(
                        icon: Icons.checkroom_rounded,
                        label: 'Upper Body',
                        subtitle: 'Tops, Shirts, Jackets',
                        isSelected: _category == 'upper_body',
                        onTap: () => setState(() => _category = 'upper_body'),
                        isDark: isDark,
                      ),
                      const SizedBox(width: 8),
                      _CategoryCard(
                        icon: Icons.dry_cleaning_rounded,
                        label: 'Lower Body',
                        subtitle: 'Pants, Jeans, Skirts',
                        isSelected: _category == 'lower_body',
                        onTap: () => setState(() => _category = 'lower_body'),
                        isDark: isDark,
                      ),
                      const SizedBox(width: 8),
                      _CategoryCard(
                        icon: Icons.accessibility_new_rounded,
                        label: 'Dress / Suit',
                        subtitle: 'Full Outfits, Gowns',
                        isSelected: _category == 'dresses',
                        onTap: () => setState(() => _category = 'dresses'),
                        isDark: isDark,
                      ),
                    ],
                  ),
                  if (_selectedProviderId == 'huggingface' && _category != 'upper_body') ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded, color: Colors.amber, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'HuggingFace IDM-VTON specializes in Upper Body. For lower body or dresses, consider using Fal.ai or Replicate in Settings.',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? Colors.amber.shade200 : Colors.amber.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),

                  // Advanced Options Toggle
                  GestureDetector(
                    onTap: () => setState(() => _showAdvanced = !_showAdvanced),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: isDark
                              ? [
                                  AppColors.darkSurfaceVariant.withValues(
                                    alpha: 0.9,
                                  ),
                                  AppColors.darkSurfaceVariant.withValues(
                                    alpha: 0.6,
                                  ),
                                ]
                              : [
                                  AppColors.lightSurfaceVariant.withValues(
                                    alpha: 0.9,
                                  ),
                                  AppColors.lightSurfaceVariant.withValues(
                                    alpha: 0.6,
                                  ),
                                ],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _showAdvanced
                              ? AppColors.primary.withValues(alpha: 0.4)
                              : AppColors.primary.withValues(alpha: 0.1),
                        ),
                        boxShadow: [
                          if (_showAdvanced)
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.08),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: _showAdvanced
                                  ? AppColors.primary.withValues(alpha: 0.15)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.tune_rounded,
                              color: _showAdvanced
                                  ? AppColors.primary
                                  : (isDark
                                        ? AppColors.darkTextSecondary
                                        : AppColors.lightTextSecondary),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Advanced Options',
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: _showAdvanced
                                        ? (isDark
                                              ? AppColors.darkText
                                              : AppColors.lightText)
                                        : (isDark
                                              ? AppColors.darkTextSecondary
                                              : AppColors.lightTextSecondary),
                                  ),
                            ),
                          ),
                          AnimatedRotation(
                            duration: const Duration(milliseconds: 250),
                            turns: _showAdvanced ? 0.5 : 0,
                            child: Icon(
                              Icons.expand_more_rounded,
                              color: _showAdvanced
                                  ? AppColors.primary
                                  : (isDark
                                        ? AppColors.darkTextSecondary
                                        : AppColors.lightTextSecondary),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  if (_showAdvanced) ...[
                    const SizedBox(height: 16),
                    _buildOptionSection(
                      context,
                      'Gender',
                      ['Auto Detect', 'Male', 'Female'],
                      ['auto', 'male', 'female'],
                      _gender,
                      (v) => setState(() => _gender = v),
                      isDark,
                    ),
                    const SizedBox(height: 16),
                    _buildOptionSection(
                      context,
                      'Body Size',
                      ['Auto', 'Slim', 'Regular', 'Plus'],
                      ['auto', 'slim', 'regular', 'plus'],
                      _bodySize,
                      (v) => setState(() => _bodySize = v),
                      isDark,
                    ),
                    const SizedBox(height: 16),
                    _buildOptionSection(
                      context,
                      'Style',
                      ['Realistic', 'Artistic', 'Vintage'],
                      ['realistic', 'artistic', 'vintage'],
                      _style,
                      (v) => setState(() => _style = v),
                      isDark,
                    ),
                    const SizedBox(height: 16),
                    _buildOptionSection(
                      context,
                      'Quality',
                      ['Standard', 'High', 'Ultra'],
                      ['standard', 'high', 'ultra'],
                      _quality,
                      (v) => setState(() => _quality = v),
                      isDark,
                    ),
                  ],

                  // AI Provider Selector
                  if (configuredProviders.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _buildOptionSection(
                      context,
                      'AI Provider',
                      configuredProviders.map((p) => p.name).toList(),
                      configuredProviders.map((p) => p.id).toList(),
                      _selectedProviderId,
                      _onProviderChanged,
                      isDark,
                    ),
                  ],
                  const SizedBox(height: 24),

                  // Generate Button
                  GradientButton(
                    text: 'Generate',
                    icon: Icons.auto_awesome,
                    onPressed:
                        (_personImagePath != null && _clothesImagePath != null)
                        ? _generate
                        : null,
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color:
                            (isDark
                                    ? AppColors.darkSurfaceVariant
                                    : AppColors.lightSurfaceVariant)
                                .withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.1),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.timer_outlined,
                            size: 16,
                            color: isDark
                                ? AppColors.darkTextTertiary
                                : AppColors.lightTextTertiary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Generation typically takes 10-30 seconds',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: isDark
                                      ? AppColors.darkTextTertiary
                                      : AppColors.lightTextTertiary,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  Widget _buildOptionSection(
    BuildContext context,
    String title,
    List<String> labels,
    List<String> values,
    String selected,
    ValueChanged<String> onChanged,
    bool isDark,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 3,
              height: 16,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: isDark ? AppColors.darkText : AppColors.lightText,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: List.generate(labels.length, (index) {
            final isSelected = values[index] == selected;
            return ChoiceChip(
              label: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(labels[index]),
              ),
              selected: isSelected,
              onSelected: (_) => onChanged(values[index]),
              selectedColor: AppColors.primary.withValues(alpha: 0.15),
              backgroundColor: isDark
                  ? AppColors.darkSurfaceVariant.withValues(alpha: 0.5)
                  : AppColors.lightSurfaceVariant.withValues(alpha: 0.5),
              labelStyle: TextStyle(
                color: isSelected
                    ? AppColors.primary
                    : (isDark
                          ? AppColors.darkTextSecondary
                          : AppColors.lightTextSecondary),
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                fontSize: 13,
              ),
              side: BorderSide(
                color: isSelected
                    ? AppColors.primary
                    : (isDark ? AppColors.darkDivider : AppColors.lightDivider)
                          .withValues(alpha: 0.5),
                width: isSelected ? 1.5 : 1.0,
              ),
              visualDensity: VisualDensity.compact,
              elevation: isSelected ? 2 : 0,
              pressElevation: 3,
              shadowColor: AppColors.primary.withValues(alpha: 0.2),
            );
          }),
        ),
      ],
    );
  }
}

class _ImageUploadCard extends StatefulWidget {
  final String? imagePath;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  final bool isDark;

  const _ImageUploadCard({
    this.imagePath,
    required this.icon,
    required this.label,
    required this.onTap,
    required this.onRemove,
    required this.isDark,
  });

  @override
  State<_ImageUploadCard> createState() => _ImageUploadCardState();
}

class _ImageUploadCardState extends State<_ImageUploadCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.imagePath != null) {
      return GestureDetector(
        onTap: widget.onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              // Image preview
              Container(
                width: double.infinity,
                height: 200,
                decoration: BoxDecoration(
                  image: DecorationImage(
                    image: FileImage(File(widget.imagePath!)),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              // Gradient overlay at bottom
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  height: 60,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.7),
                      ],
                    ),
                  ),
                ),
              ),
              // Remove button
              Positioned(
                top: 8,
                right: 8,
                child: Material(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: const CircleBorder(),
                  child: InkWell(
                    onTap: widget.onRemove,
                    customBorder: const CircleBorder(),
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
              // Tap to change badge
              Positioned(
                bottom: 12,
                left: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.touch_app_rounded,
                        color: Colors.white,
                        size: 14,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Tap to change',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Empty state with glassmorphism
    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (context, child) {
        return Transform.scale(
          scale: _isPressed ? 0.97 : _pulseAnim.value,
          child: GestureDetector(
            onTap: widget.onTap,
            onTapDown: (_) => setState(() => _isPressed = true),
            onTapUp: (_) => setState(() => _isPressed = false),
            onTapCancel: () => setState(() => _isPressed = false),
            child: Container(
              width: double.infinity,
              height: 170,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: widget.isDark
                      ? [
                          AppColors.darkSurfaceVariant.withValues(alpha: 0.9),
                          AppColors.darkSurfaceVariant.withValues(alpha: 0.6),
                        ]
                      : [
                          AppColors.lightSurfaceVariant.withValues(alpha: 0.9),
                          AppColors.lightSurfaceVariant.withValues(alpha: 0.6),
                        ],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primary.withValues(alpha: 0.15),
                          AppColors.secondary.withValues(alpha: 0.15),
                        ],
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.3),
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      widget.icon,
                      color: AppColors.primary,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    widget.label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Tap to upload',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SourceOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SourceOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [
                    AppColors.darkSurfaceVariant.withValues(alpha: 0.9),
                    AppColors.darkSurfaceVariant.withValues(alpha: 0.6),
                  ]
                : [
                    AppColors.lightSurfaceVariant.withValues(alpha: 0.9),
                    AppColors.lightSurfaceVariant.withValues(alpha: 0.6),
                  ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.2),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primary.withValues(alpha: 0.15),
                    AppColors.secondary.withValues(alpha: 0.15),
                  ],
                ),
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
              child: Icon(icon, size: 24, color: AppColors.primary),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: isDark ? AppColors.darkText : AppColors.lightText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GeneratingView extends StatefulWidget {
  final bool isDark;
  final String stageMessage;
  final double progress;

  const _GeneratingView({
    required this.isDark,
    required this.stageMessage,
    required this.progress,
  });

  @override
  State<_GeneratingView> createState() => _GeneratingViewState();
}

class _GeneratingViewState extends State<_GeneratingView>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pulseAnimation;
  late AnimationController _rotateController;
  late Animation<double> _rotateAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(
      begin: 0.85,
      end: 1.15,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _rotateController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();
    _rotateAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _rotateController, curve: Curves.linear));
  }

  @override
  void dispose() {
    _controller.dispose();
    _rotateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: Listenable.merge([_pulseAnimation, _rotateAnimation]),
            builder: (context, child) {
              return Transform.scale(
                scale: _pulseAnimation.value,
                child: Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.primary, AppColors.secondary],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(
                          alpha: 0.4 * _pulseAnimation.value,
                        ),
                        blurRadius: 40,
                        spreadRadius: 8,
                      ),
                    ],
                  ),
                  child: Transform.rotate(
                    angle: _rotateAnimation.value * 2 * 3.14159,
                    child: const Icon(
                      Icons.auto_awesome,
                      color: Colors.white,
                      size: 44,
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 36),
          ShaderMask(
            shaderCallback: (bounds) =>
                AppColors.primaryGradient.createShader(bounds),
            child: Text(
              'AI Studio Pipeline',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                widget.stageMessage,
                key: ValueKey(widget.stageMessage),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: widget.isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: 250,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: widget.progress.clamp(0.05, 1.0),
                minHeight: 6,
                backgroundColor:
                    (widget.isDark
                            ? AppColors.darkDivider
                            : AppColors.lightDivider)
                        .withValues(alpha: 0.5),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  AppColors.primary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${(widget.progress * 100).toInt()}% • Multi-Skill Enhancement Active',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Category selection card for Upper Body, Lower Body, or Dress/Suit.
class _CategoryCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isDark;

  const _CategoryCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primary.withValues(alpha: 0.12)
                : (isDark
                    ? AppColors.darkSurfaceVariant.withValues(alpha: 0.6)
                    : AppColors.lightSurfaceVariant.withValues(alpha: 0.6)),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? AppColors.primary
                  : (isDark ? AppColors.darkDivider : AppColors.lightDivider)
                      .withValues(alpha: 0.4),
              width: isSelected ? 2 : 1,
            ),
            boxShadow: [
              if (isSelected)
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 26,
                color: isSelected
                    ? AppColors.primary
                    : (isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? AppColors.primary
                      : (isDark ? AppColors.darkText : AppColors.lightText),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9,
                  color: isDark
                      ? AppColors.darkTextTertiary
                      : AppColors.lightTextTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

