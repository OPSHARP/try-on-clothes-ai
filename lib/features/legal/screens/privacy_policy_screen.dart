import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';

/// Privacy Policy screen — compliant with GDPR, CCPA/CPRA, and Google Play Store AI Policies.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Privacy Policy'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Privacy Policy',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Last Updated: October 2026',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: isDark
                    ? AppColors.darkTextTertiary
                    : AppColors.lightTextTertiary,
              ),
            ),
            const SizedBox(height: 28),
            _PolicySection(
              title: '1. Introduction and Commitment',
              content:
                  'Try On Clothes AI ("we", "us", or "our") is dedicated to safeguarding '
                  'your personal privacy. This Privacy Policy details the exact types of '
                  'information we collect, how your photos and data are handled, how they '
                  'are transmitted to AI generative backends, and the stringent security '
                  'protocols in place to protect your rights.',
              isDark: isDark,
            ),
            const SizedBox(height: 20),
            _PolicySection(
              title: '2. Information We Collect',
              content:
                  '• Photos Provided by You: When you choose to use the virtual try-on feature, '
                  'you provide a photo of a person/model and a photo of a garment. These photos '
                  'are selected by you from your camera or local gallery.\n'
                  '• Technical & Diagnostic Data: To ensure maximum app performance, we may collect '
                  'anonymized device technical data such as operating system version, screen refresh '
                  'rate, crash logs, and hardware model.\n'
                  '• Advertising Identifiers: For users on the free tier, Google AdMob may collect '
                  'resettable advertising identifiers in accordance with Google Play policies.\n'
                  '• Local Settings: Your preferred language, theme choice, and optional user-entered '
                  'API keys are stored exclusively locally on your device in secure app preferences.',
              isDark: isDark,
            ),
            const SizedBox(height: 20),
            _PolicySection(
              title: '3. AI Image Processing & Biometric Privacy',
              content:
                  'Your privacy during AI inference is our top priority:\n\n'
                  '• Ephemeral Processing: Images you submit for try-on are transferred over secure '
                  'encrypted HTTPS/TLS channels to the AI service provider (e.g., IDM-VTON, HuggingFace, '
                  'Replicate, Fashn AI, Segmind, or Kling AI) solely to generate the virtual try-on result.\n'
                  '• No Biometric Profiling: We DO NOT extract facial geometry, create biometric '
                  'signatures, or collect facial recognition templates. Image segmentation algorithms '
                  'operate purely to align garment polygons to body posture.\n'
                  '• Zero Model Training: Your uploaded personal photos are NEVER used to train, '
                  'fine-tune, or improve public or private AI models.\n'
                  '• Immediate Discarding: Third-party AI processing providers process the images in '
                  'ephemeral volatile memory (RAM) and do not retain your raw photos after the generation '
                  'task is concluded.',
              isDark: isDark,
            ),
            const SizedBox(height: 20),
            _PolicySection(
              title: '4. Local Storage and User Control',
              content:
                  '• History & Saved Try-Ons: Completed try-on results are saved locally within '
                  'your device\'s sandboxed application storage.\n'
                  '• Full Deletion Control: You can delete any saved generation from your History '
                  'tab at any time, or clear all app data in your Android device settings.',
              isDark: isDark,
            ),
            const SizedBox(height: 20),
            _PolicySection(
              title: '5. Third-Party Service Providers',
              content:
                  'We partner exclusively with reputable, compliant industry infrastructure:\n\n'
                  '• Google Play Store: Manages in-app subscriptions and app distribution securely.\n'
                  '• Google Mobile Ads (AdMob): Serves contextual and personalized ads (which can be '
                  'removed permanently via subscription).\n'
                  '• Google Play In-App Updates: Delivers flexible background software updates directly '
                  'through Play Core without disrupting your workflow.\n'
                  '• AI Service Providers: HuggingFace, Replicate, Fashn AI, Segmind, Kling AI.',
              isDark: isDark,
            ),
            const SizedBox(height: 20),
            _PolicySection(
              title: '6. User Rights (GDPR, CCPA & Global Protections)',
              content:
                  'Regardless of your geographic location, you enjoy the following rights:\n\n'
                  '• Right of Access: You can inspect all data stored locally in your history.\n'
                  '• Right to Erasure: You have the unconditional right to erase all photos and history.\n'
                  '• Right to Opt-Out: You can opt out of personalized advertisements via your Android '
                  'device\'s Google Settings > Ads.\n'
                  '• Right to Non-Discrimination: Exercising your privacy rights will never result in '
                  'diminished service quality.',
              isDark: isDark,
            ),
            const SizedBox(height: 20),
            _PolicySection(
              title: '7. Children\'s Privacy Protection (COPPA)',
              content:
                  'Try On Clothes AI is strictly designed for users aged 13 and older (or 16 in the '
                  'European Economic Area). We do not knowingly solicit or collect photographs or '
                  'personal data from children under 13. If you become aware that a child has provided '
                  'us with photos, please notify us immediately for expedited data purge.',
              isDark: isDark,
            ),
            const SizedBox(height: 20),
            _PolicySection(
              title: '8. Security Architecture',
              content:
                  'We employ rigorous administrative, organizational, and technical safeguards. '
                  'All API communication uses 256-bit TLS encryption in transit. Local preferences '
                  'and keys remain securely scoped within the Android operating system\'s private sandbox.',
              isDark: isDark,
            ),
            const SizedBox(height: 20),
            _PolicySection(
              title: '9. Updates to This Privacy Policy',
              content:
                  'We may update this Privacy Policy to reflect software improvements or legal updates. '
                  'When updates occur, the "Last Updated" timestamp will be revised, and significant changes '
                  'will be highlighted in-app.',
              isDark: isDark,
            ),
            const SizedBox(height: 20),
            _PolicySection(
              title: '10. Contact and Grievance Officer',
              content:
                  'If you have questions, privacy requests, or wish to exercise data rights, '
                  'please reach out directly:\n\n'
                  'Email: privacy@tryonclothesai.com\n'
                  'Support: support@tryonclothesai.com\n'
                  'Expected Response Window: 48 business hours',
              isDark: isDark,
            ),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }
}

class _PolicySection extends StatelessWidget {
  final String title;
  final String content;
  final bool isDark;

  const _PolicySection({
    required this.title,
    required this.content,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          content,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.lightTextSecondary,
                height: 1.6,
              ),
        ),
      ],
    );
  }
}
