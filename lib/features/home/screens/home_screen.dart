import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/config/ad_config.dart';
import '../../../core/services/ad_service.dart';
import '../../../data/models/generation_model.dart';
import '../widgets/api_setup_guide_sheet.dart';

/// The main Virtual Try-On Studio screen.
/// Directly presents the core AI Try-On features:
/// 1. Apni Photo Upload (Your Photo / Model)
/// 2. Kisi Bhi Cloth Ki Photo Upload (Garment Photo)
/// 3. Category Selector (Upper Body, Lower Body, Dresses & Suits)
/// 4. Fine-Tune Fit & Style Options (Optional Prompt & Settings)
/// 5. Vibrant Gradient "TRY ON CLOTHES" Generation Button
///
/// Implemented with the exact visual aesthetics of the reference design:
/// soft neumorphic pastel canvas (#EFF1FA), sunset violet-to-coral gradient hero card,
/// clean category pills, soft neumorphic cards, and buttery 120 FPS performance.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with TickerProviderStateMixin {
  final _imagePicker = ImagePicker();
  final _garmentDescController = TextEditingController();

  // Core try-on states
  int _currentStep =
      1; // 1 = Your Photo (Start With Your Photo), 2 = Cloth / Garment Photo
  String? _personImagePath;
  String? _clothesImagePath;
  final String _category = 'upper_body';
  String _style = 'realistic'; // 'realistic', 'artistic', 'vintage'
  String _quality = 'standard';
  bool _showFineTune = false;
  bool _isGenerating = false;
  String _pipelineStage = 'AI Stylist analyzing fabric, color & lighting...';
  double _pipelineProgress = 0.20;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _shimmerController;

  static const _validImageExtensions = [
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.bmp',
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulseAnimation = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    );

    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();

    _preloadAds();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkFirstLaunchApiGuide();
    });
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    _pulseController.dispose();
    _garmentDescController.dispose();
    super.dispose();
  }

  void _preloadAds() {
    final showAd = AdConfig.shouldShowAds(ref.read(isAdFreeProvider));
    if (showAd) {
      AdService.instance.preloadAllAds();
    }
  }

  void _checkFirstLaunchApiGuide() {
    final hasSeen = ref.read(hasSeenApiSetupGuideProvider);
    final hasApiKey = ref.read(hasApiKeyForProviderProvider);
    if (!hasSeen && !hasApiKey && mounted) {
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) {
          ApiSetupGuideSheet.show(context);
        }
      });
    }
  }

  Future<void> _pickImage({required bool isPerson}) async {
    final source = await _showImageSourceDialog(isPerson: isPerson);
    if (source == null) return;

    // 1024x1365 follows standard 3:4 portrait ratio for IDM-VTON
    final picked = await _imagePicker.pickImage(
      source: source,
      maxWidth: 1024,
      maxHeight: 1365,
      imageQuality: 92,
    );

    if (picked != null) {
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

  Future<ImageSource?> _showImageSourceDialog({required bool isPerson}) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final title = isPerson ? 'Choose Your Photo' : 'Choose Cloth Photo';

    return showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      backgroundColor: isDark ? const Color(0xFF1B202E) : Colors.white,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: (isDark ? Colors.white30 : Colors.black12),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF1E2432),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  isPerson
                      ? 'Choose a well-lit photo of yourself'
                      : 'Choose a clear photo of the garment',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF8B98AF),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: _SourceOptionTile(
                        icon: Icons.camera_alt_rounded,
                        label: 'Take Photo',
                        isDark: isDark,
                        onTap: () => Navigator.pop(context, ImageSource.camera),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _SourceOptionTile(
                        icon: Icons.photo_library_rounded,
                        label: 'From Gallery',
                        isDark: isDark,
                        onTap: () =>
                            Navigator.pop(context, ImageSource.gallery),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _generate() async {
    HapticFeedback.mediumImpact();

    if (_personImagePath == null && _clothesImagePath == null) {
      _showFriendlySnackBar('Please upload your photo and cloth photo.');
      return;
    }
    if (_personImagePath == null) {
      _showFriendlySnackBar('Please upload your photo (Model Photo).');
      return;
    }
    if (_clothesImagePath == null) {
      _showFriendlySnackBar('Please upload the cloth photo (Garment).');
      return;
    }

    final aiService = ref.read(aiServiceProvider);
    if (aiService == null || !aiService.isAvailable) {
      ApiSetupGuideSheet.show(context);
      return;
    }
    final bool showAd = AdConfig.shouldShowAds(ref.read(isAdFreeProvider));
    final bool isSecondResult = AdService.shouldTriggerForNextGeneration();

    setState(() {
      _isGenerating = true;
      _pipelineStage = 'AI Stylist analyzing fabric, color & lighting...';
      _pipelineProgress = 0.20;
    });

    try {
      final personBytes = await File(_personImagePath!).readAsBytes();
      final clothesBytes = await File(_clothesImagePath!).readAsBytes();

      final garmentDescription = _buildGarmentDescription();

      final pipeline = ref.read(aiImagePipelineServiceProvider);

      // ── Asynchronous Background Generation Task ──
      // The generation starts calculating immediately in the background
      final generationFuture = (pipeline != null
          ? pipeline.executePipeline(
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
            )
          : aiService.generateTryOn(
              personImage: personBytes,
              clothesImage: clothesBytes,
              options: {
                'category': _category,
                'style': _style,
                'quality': _quality,
                'description': garmentDescription,
                'auto_mask': 'true',
                'crop': 'false',
              },
            ));

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

      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final resultPath = '${tempDir.path}/tryon_result_$timestamp.png';
      await File(resultPath).writeAsBytes(result.imageBytes);

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
      if (!mounted) return;
      setState(() => _isGenerating = false);
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

  void _showFriendlySnackBar(String message) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF6342E8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  String _buildGarmentDescription() {
    final customDesc = _garmentDescController.text.trim();
    if (customDesc.isNotEmpty) {
      return customDesc;
    }

    final categoryHint = _category == 'upper_body'
        ? 't-shirt, shirt, top'
        : _category == 'lower_body'
        ? 'pants, jeans, trousers'
        : 'dress, full outfit';

    return categoryHint;
  }

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
        personImageUrl: File(permPersonPath).existsSync()
            ? permPersonPath
            : (_personImagePath ?? ''),
        clothesImageUrl: File(permClothesPath).existsSync()
            ? permClothesPath
            : (_clothesImagePath ?? ''),
        resultImageUrl: permResultPath,
        creditsUsed: 1,
        createdAt: DateTime.now(),
        status: GenerationStatus.completed,
        gender: 'auto',
        bodySize: 'auto',
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

  String _getUserFriendlyError(Object error) {
    final msg = error.toString();
    if (msg.contains('HTTP 400') || msg.contains('invalid-argument')) {
      return 'Image format issue. Please use clear standard JPG/PNG photos.';
    }
    if (msg.contains('HTTP 401') || msg.contains('HTTP 403') || msg.contains('unauthenticated')) {
      return 'API key error. Please check your HuggingFace key in Profile.';
    }
    if (msg.contains('ZeroGPU') || msg.contains('quota')) {
      return 'AI GPU servers are currently at capacity. Please try again in a few moments.';
    }
    if (msg.contains('VTON model error')) {
      return 'Garment alignment error. Please ensure person and cloth photos are clear.';
    }
    if (msg.contains('HTTP 429') || msg.contains('Rate limit') || msg.contains('rate_limit')) {
      return 'Busy queue. Please wait a few seconds and tap Retry.';
    }
    if (msg.contains('SocketException') || msg.contains('Connection') || msg.contains('timeout')) {
      return 'Network connection error. Check your internet connection.';
    }
    return 'Server busy. Please tap Retry to generate.';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF0F121C)
          : const Color(0xFFF4F6FC),
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                children: [
                  // 1. Top Headline Header
                  _buildTopHeader(isDark),

                  const SizedBox(height: 18),

                  // 2. Step Progress Indicator Tabs (1. Your Photo -> 2. Cloth Photo)
                  _buildStepIndicator(isDark),

                  const SizedBox(height: 16),

                  // 3. Current Step Card (Step 1: Your Photo / Step 2: Cloth Photo)
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    child: _currentStep == 1
                        ? _buildStep1View(context, isDark)
                        : _buildStep2View(context, isDark),
                  ),

                  const SizedBox(height: 20),

                  // 4. Guarantee Badges
                  _buildProGuaranteeStrip(isDark),

                  const SizedBox(height: 24),
                ],
              ),
            ),

            // Generating Progress Overlay (120 FPS Buttery Animation)
            if (_isGenerating) _buildGeneratingOverlay(isDark),
          ],
        ),
      ),
    );
  }

  /// Top Headline Header (Clean Justified Margins)
  Widget _buildTopHeader(bool isDark) {
    return Column(
      children: [
        // Big Bold Headline
        Text(
          _currentStep == 1 ? 'Start With' : 'Now Choose',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.8,
            height: 1.05,
            color: isDark ? Colors.white : const Color(0xFF1E1B4B),
          ),
        ),
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => LinearGradient(
            colors: _currentStep == 1
                ? const [Color(0xFF8B5CF6), Color(0xFF6342E8)]
                : const [Color(0xFF6342E8), Color(0xFFF97352)],
          ).createShader(bounds),
          child: Text(
            _currentStep == 1 ? 'Your Photo' : 'Cloth Photo',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.8,
              height: 1.1,
            ),
          ),
        ),
        const SizedBox(height: 6),

        // Subtitle
        Text(
          _currentStep == 1
              ? 'Upload a photo to begin your try-on.'
              : 'Upload any garment or cloth photo to try on.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF6B7280),
          ),
        ),
      ],
    );
  }

  /// Step Navigation Indicator (1. Your Photo <-> 2. Cloth Photo)
  Widget _buildStepIndicator(bool isDark) {
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: () {
              HapticFeedback.lightImpact();
              setState(() => _currentStep = 1);
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                color: _currentStep == 1
                    ? const Color(0xFF6342E8).withValues(alpha: 0.12)
                    : (isDark
                          ? Colors.white.withValues(alpha: 0.05)
                          : Colors.white),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _currentStep == 1
                      ? const Color(0xFF6342E8)
                      : (isDark ? Colors.white12 : Colors.black12),
                  width: _currentStep == 1 ? 1.5 : 1,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _personImagePath != null
                        ? Icons.check_circle_rounded
                        : Icons.person_rounded,
                    size: 16,
                    color: _personImagePath != null
                        ? const Color(0xFF10B981)
                        : (_currentStep == 1
                              ? const Color(0xFF6342E8)
                              : Colors.grey),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Step 1: Your Photo',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _currentStep == 1
                          ? const Color(0xFF6342E8)
                          : (isDark ? Colors.white70 : Colors.black54),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: InkWell(
            onTap: () {
              HapticFeedback.lightImpact();
              setState(() => _currentStep = 2);
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                color: _currentStep == 2
                    ? const Color(0xFFF97352).withValues(alpha: 0.12)
                    : (isDark
                          ? Colors.white.withValues(alpha: 0.05)
                          : Colors.white),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _currentStep == 2
                      ? const Color(0xFFF97352)
                      : (isDark ? Colors.white12 : Colors.black12),
                  width: _currentStep == 2 ? 1.5 : 1,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _clothesImagePath != null
                        ? Icons.check_circle_rounded
                        : Icons.checkroom_rounded,
                    size: 16,
                    color: _clothesImagePath != null
                        ? const Color(0xFF10B981)
                        : (_currentStep == 2
                              ? const Color(0xFFF97352)
                              : Colors.grey),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Step 2: Cloth Photo',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _currentStep == 2
                          ? const Color(0xFFF97352)
                          : (isDark ? Colors.white70 : Colors.black54),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Step 1: Start With Your Photo (Mirrors the reference image)
  Widget _buildStep1View(BuildContext context, bool isDark) {
    final hasPhoto = _personImagePath != null;

    return Container(
      key: const ValueKey('step_1_view'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1B202E) : Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.06),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // Step 1 Header: Choose Your Photo
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Choose Your Photo',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  color: isDark ? Colors.white : const Color(0xFF1E1B4B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Big Hero Photo Card (3:4 Ratio, rounded 22)
          GestureDetector(
            onTap: () => _pickImage(isPerson: true),
            child: Container(
              width: double.infinity,
              height: 380,
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF131722)
                    : const Color(0xFFF1F3F9),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: hasPhoto
                      ? const Color(0xFF6342E8).withValues(alpha: 0.5)
                      : (isDark
                            ? Colors.white10
                            : Colors.black.withValues(alpha: 0.04)),
                  width: hasPhoto ? 2 : 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (hasPhoto) ...[
                      Image.file(File(_personImagePath!), fit: BoxFit.cover),
                      Positioned(
                        bottom: 14,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 7,
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
                                  size: 14,
                                  color: Colors.white,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'Tap photo to change',
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
                      ),
                    ] else
                      // Clean Empty State for Choose Your Photo
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 76,
                            height: 76,
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF6342E8,
                              ).withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.person_outline_rounded,
                              color: Color(0xFF6342E8),
                              size: 40,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Choose Your Photo',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF1E2432),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Tap to upload half-body or full-body photo',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: isDark
                                  ? const Color(0xFF94A3B8)
                                  : const Color(0xFF8B98AF),
                            ),
                          ),
                        ],
                      ),

                    // Top-right delete button if photo chosen
                    if (hasPhoto)
                      Positioned(
                        top: 12,
                        right: 12,
                        child: GestureDetector(
                          onTap: () => setState(() => _personImagePath = null),
                          child: Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close_rounded,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // Big Vibrant "Choose Your Photo" Gradient Button (Only when no photo chosen)
          if (!hasPhoto) ...[
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF8B5CF6), Color(0xFF6342E8)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6342E8).withValues(alpha: 0.38),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ElevatedButton(
                  onPressed: () => _pickImage(isPerson: true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.file_upload_outlined,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Choose Your Photo',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Subtext: "Choose a clear, well-lit photo"
            Text(
              'Choose a clear, well-lit photo',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF6B7280),
              ),
            ),
            const SizedBox(height: 14),
          ] else ...[
            const SizedBox(height: 18),
          ],

          // Status Pill Badge: "✓ Photo selected" (from reference image)
          if (hasPhoto) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF2E1065)
                    : const Color(0xFFEDE9FE),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: Color(0xFF6342E8),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check,
                      size: 12,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Photo selected',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? const Color(0xFFC4B5FD)
                          : const Color(0xFF6342E8),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Continue to Step 2 Button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  setState(() => _currentStep = 2);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E1B4B),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 2,
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Next: Choose Garment / Cloth',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                    SizedBox(width: 8),
                    Icon(Icons.arrow_forward_rounded, size: 18),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Step 2: Now Choose Cloth Photo (Upload garment photo)
  Widget _buildStep2View(BuildContext context, bool isDark) {
    final hasCloth = _clothesImagePath != null;

    return Container(
      key: const ValueKey('step_2_view'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1B202E) : Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.06),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // Step 2 Header with Back Button to return to Step 1
          Row(
            children: [
              IconButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  setState(() => _currentStep = 1);
                },
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 16),
                style: IconButton.styleFrom(
                  backgroundColor: isDark
                      ? Colors.white10
                      : const Color(0xFFF1F5F9),
                  padding: const EdgeInsets.all(8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              const Expanded(
                child: Text(
                  'Choose Cloth Photo',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              const SizedBox(width: 32),
            ],
          ),
          const SizedBox(height: 14),

          // Big Hero Cloth Photo Card (3:4 Ratio, rounded 22)
          GestureDetector(
            onTap: () => _pickImage(isPerson: false),
            child: Container(
              width: double.infinity,
              height: 360,
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF131722)
                    : const Color(0xFFF1F3F9),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: hasCloth
                      ? const Color(0xFFF97352).withValues(alpha: 0.5)
                      : (isDark
                            ? Colors.white10
                            : Colors.black.withValues(alpha: 0.04)),
                  width: hasCloth ? 2 : 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (hasCloth) ...[
                      Image.file(File(_clothesImagePath!), fit: BoxFit.contain),
                      Positioned(
                        bottom: 14,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 7,
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
                                  size: 14,
                                  color: Colors.white,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'Tap cloth to change',
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
                      ),
                    ] else
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 68,
                            height: 68,
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFFF97352,
                              ).withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.checkroom_rounded,
                              color: Color(0xFFF97352),
                              size: 34,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Choose Cloth Photo',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF1E2432),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Shirt, T-Shirt, Jacket, Pants, or Dress',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? const Color(0xFF94A3B8)
                                  : const Color(0xFF8B98AF),
                            ),
                          ),
                        ],
                      ),

                    if (hasCloth)
                      Positioned(
                        top: 12,
                        right: 12,
                        child: GestureDetector(
                          onTap: () => setState(() => _clothesImagePath = null),
                          child: Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close_rounded,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // Big "Choose Cloth Photo" Button (Only when no cloth chosen)
          if (!hasCloth) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6342E8), Color(0xFFF97352)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFF97352).withValues(alpha: 0.35),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ElevatedButton(
                  onPressed: () => _pickImage(isPerson: false),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.file_upload_outlined,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Choose Cloth Photo',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Subtext
            Text(
              'Choose a clear photo of the garment',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF6B7280),
              ),
            ),
            const SizedBox(height: 14),
          ] else ...[
            const SizedBox(height: 16),
          ],

          // Status Pill Badge: "✓ Garment selected"
          if (hasCloth) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF431407)
                    : const Color(0xFFFFEDD5),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF97352),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check,
                      size: 12,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Garment selected',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? const Color(0xFFFDBA74)
                          : const Color(0xFFC2410C),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Fine-Tune section
          _buildFineTuneSection(isDark),
          const SizedBox(height: 16),

          // Grand TRY ON CLOTHES Button
          _buildBottomActionButton(context),
        ],
      ),
    );
  }

  /// Pro Guarantee Strip
  Widget _buildProGuaranteeStrip(bool isDark) {
    final guarantees = [
      {'icon': Icons.verified_user_rounded, 'title': '99.4% Anatomy Fit'},
      {'icon': Icons.bolt_rounded, 'title': 'Fast GPU Warp'},
      {'icon': Icons.lock_rounded, 'title': '100% Private'},
    ];

    return Row(
      children: guarantees.map((g) {
        return Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.04)
                  : Colors.black.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  g['icon'] as IconData,
                  size: 14,
                  color: const Color(0xFF6342E8),
                ),
                const SizedBox(width: 5),
                Text(
                  g['title'] as String,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  /// Fine-Tune Fit & Style Options (Optional Text Prompt + Presets)
  Widget _buildFineTuneSection(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1B202E) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: AppColors.neumorphic(isDark),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () {
              HapticFeedback.lightImpact();
              setState(() => _showFineTune = !_showFineTune);
            },
            borderRadius: BorderRadius.circular(22),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFF6342E8).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.tune_rounded,
                      size: 18,
                      color: Color(0xFF6342E8),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Fine-Tune Fit & Style',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF1E2432),
                          ),
                        ),
                        Text(
                          'Style presets, fabric prompts & quality',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF8B98AF),
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    duration: const Duration(milliseconds: 200),
                    turns: _showFineTune ? 0.5 : 0.0,
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF8B98AF),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_showFineTune) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 1),
                  const SizedBox(height: 14),

                  // Optional Garment Prompt
                  TextField(
                    controller: _garmentDescController,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white : const Color(0xFF1E2432),
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText:
                          'e.g. Navy blue cotton shirt, black leather jacket',
                      hintStyle: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? const Color(0xFF64748B)
                            : const Color(0xFF94A3B8),
                      ),
                      labelText: 'Garment Details (Optional)',
                      labelStyle: const TextStyle(fontSize: 13),
                      prefixIcon: const Icon(Icons.edit_note_rounded, size: 20),
                      filled: true,
                      fillColor: isDark
                          ? const Color(0xFF131722)
                          : const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: isDark ? Colors.white12 : Colors.black12,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: isDark ? Colors.white12 : Colors.black12,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Style Selector Chips
                  Row(
                    children: [
                      Text(
                        'Style: ',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildMiniChip('Realistic', _style == 'realistic', () {
                        setState(() => _style = 'realistic');
                      }, isDark),
                      const SizedBox(width: 6),
                      _buildMiniChip('Artistic', _style == 'artistic', () {
                        setState(() => _style = 'artistic');
                      }, isDark),
                      const SizedBox(width: 6),
                      _buildMiniChip('Vintage', _style == 'vintage', () {
                        setState(() => _style = 'vintage');
                      }, isDark),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Quality Selector Chips
                  Row(
                    children: [
                      Text(
                        'Quality: ',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildMiniChip('Standard', _quality == 'standard', () {
                        setState(() => _quality = 'standard');
                      }, isDark),
                      const SizedBox(width: 6),
                      _buildMiniChip('Ultra HD', _quality == 'ultra', () {
                        setState(() => _quality = 'ultra');
                      }, isDark),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMiniChip(
    String label,
    bool isSelected,
    VoidCallback onTap,
    bool isDark,
  ) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF6342E8)
              : (isDark ? const Color(0xFF131722) : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected
                ? Colors.white
                : (isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569)),
          ),
        ),
      ),
    );
  }

  /// Big Vibrant Pill Button ("TRY ON CLOTHES" in reference gradient)
  Widget _buildBottomActionButton(BuildContext context) {
    final isReady = _personImagePath != null && _clothesImagePath != null;

    return SizedBox(
      width: double.infinity,
      height: 56,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          gradient: isReady
              ? const LinearGradient(
                  colors: [
                    Color(0xFF6342E8),
                    Color(0xFF8B5CF6),
                    Color(0xFFF97352),
                  ],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                )
              : AppColors.buttonGradient,
          boxShadow: [
            BoxShadow(
              color: isReady
                  ? const Color(0xFF6342E8).withValues(alpha: 0.6)
                  : const Color(0xFF6342E8).withValues(alpha: 0.35),
              blurRadius: isReady ? 24 : 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: _generate,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isReady ? Icons.auto_awesome_rounded : Icons.checkroom_rounded,
                size: 20,
                color: Colors.white,
              ),
              const SizedBox(width: 10),
              Text(
                isReady ? '✨ GENERATE VIRTUAL FIT' : 'TRY ON CLOTHES',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Full-screen 120 FPS generation overlay with rotating aura and progress
  Widget _buildGeneratingOverlay(bool isDark) {
    return Container(
      color: (isDark ? Colors.black : Colors.white).withValues(alpha: 0.88),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Container(
                    width: 86,
                    height: 86,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: AppColors.buttonGradient,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6342E8).withValues(
                            alpha: 0.4 + (_pulseAnimation.value * 0.3),
                          ),
                          blurRadius: 36,
                          spreadRadius: 6 * _pulseAnimation.value,
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.auto_awesome_rounded,
                        color: Colors.white,
                        size: 40,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 28),
              ShaderMask(
                shaderCallback: (bounds) =>
                    AppColors.buttonGradient.createShader(bounds),
                child: const Text(
                  'AI Stylist at Work...',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Text(
                  _pipelineStage,
                  key: ValueKey(_pipelineStage),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? const Color(0xFFC4B5FD)
                        : const Color(0xFF6342E8),
                  ),
                ),
              ),
              const SizedBox(height: 26),
              SizedBox(
                width: 220,
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value: _pipelineProgress,
                        minHeight: 7,
                        backgroundColor: const Color(0x336342E8),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF6342E8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${(_pipelineProgress * 100).toInt()}% • Multi-Skill Pipeline',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Image source selection button in bottom sheet
class _SourceOptionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;
  final VoidCallback onTap;

  const _SourceOptionTile({
    required this.icon,
    required this.label,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF131722) : const Color(0xFFEFF1FA),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark
                ? Colors.white12
                : Colors.black.withValues(alpha: 0.05),
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 28, color: const Color(0xFF6342E8)),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF1E2432),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
