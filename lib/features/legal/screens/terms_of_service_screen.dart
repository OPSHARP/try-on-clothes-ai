import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';

/// Terms of Service screen — fully compliant with Google Play Store Policies
/// and international software regulations.
class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Terms of Service'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Terms of Service',
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
              title: '1. Acceptance of Terms',
              content:
                  'By downloading, installing, accessing, or using the Try On Clothes AI '
                  'application ("App", "Service", "we", "us", or "our"), you ("User" or "you") '
                  'agree to be legally bound by these Terms of Service. If you do not agree '
                  'to all terms and conditions set forth herein, you must immediately cease '
                  'using the App and uninstall it from your device.',
              isDark: isDark,
            ),
            const SizedBox(height: 20),
            _PolicySection(
              title: '2. License and Scope of Use',
              content:
                  'We grant you a personal, revocable, non-exclusive, non-transferable, and '
                  'limited license to install and use the App on supported Android devices '
                  'that you own or control, strictly for personal, non-commercial fashion '
                  'visualization.\n\n'
                  'You expressly agree NOT to:\n'
                  '• Decompile, reverse engineer, disassemble, or derive source code from the App\n'
                  '• Exploit, copy, duplicate, sell, or rent any portion of the App\n'
                  '• Circumvent rate limits, authentication keys, or security protocols\n'
                  '• Use the service to develop competing virtual try-on software or datasets',
              isDark: isDark,
            ),
            const SizedBox(height: 20),
            _PolicySection(
              title: '3. Acceptable Use and Content Policies',
              content:
                  'You retain complete responsibility for the images and data you upload.\n\n'
                  'Strictly Prohibited Submissions:\n'
                  '• Nudity, sexually suggestive, obscene, or pornographic content\n'
                  '• Photos of minors (individuals under 18 years of age)\n'
                  '• Photos of third parties uploaded without their verifiable informed consent\n'
                  '• Images intended to harass, defame, impersonate, or create malicious deepfakes\n'
                  '• Content that violates any third party\'s intellectual property, trademark, or copyright\n\n'
                  'Any violation of these guidelines will result in immediate termination of '
                  'access without prior notice.',
              isDark: isDark,
            ),
            const SizedBox(height: 20),
            _PolicySection(
              title: '4. AI Try-On Simulation Disclaimer',
              content:
                  'Try On Clothes AI leverages state-of-the-art neural diffusion networks and '
                  'virtual garment synthesis models (such as IDM-VTON, HuggingFace, Replicate, '
                  'Fashn AI, Segmind, and Kling AI).\n\n'
                  '• Experimental Nature: Results are computer-generated approximations intended '
                  'solely for aesthetic visualization and personal style exploration.\n'
                  '• Fit Variance: Generative simulations may not accurately reflect true fabric '
                  'drape, elasticity, seams, sizing, color saturation, or physical garment behavior.\n'
                  '• Purchasing Decisions: We are not responsible for physical clothing purchases, '
                  'tailoring outcomes, or e-commerce transactions made based on App simulations.',
              isDark: isDark,
            ),
            const SizedBox(height: 20),
            _PolicySection(
              title: '5. Subscriptions and Google Play Billing',
              content:
                  'Certain premium features (including ad-free generation) may be offered '
                  'via subscription or one-time in-app purchases.\n\n'
                  '• All financial transactions are managed and billed exclusively through '
                  'the Google Play Store billing platform.\n'
                  '• Subscriptions automatically renew at the specified interval unless canceled '
                  'at least 24 hours prior to the conclusion of the billing cycle.\n'
                  '• You can review, modify, or cancel your active subscription at any time by '
                  'navigating to Google Play Store > Payments & subscriptions > Subscriptions.\n'
                  '• Billing terms and subscription cancellations are governed by Google Play\'s '
                  'standard policies.',
              isDark: isDark,
            ),
            const SizedBox(height: 20),
            _PolicySection(
              title: '6. Intellectual Property and User Ownership',
              content:
                  '• User Photographs: You retain full copyright and ownership of the original '
                  'images you submit. You grant Try On Clothes AI only the temporary, royalty-free '
                  'license necessary to transmit and process your images through the selected AI engine.\n'
                  '• Software Assets: All visual interfaces, code, branding, logos, icons, and '
                  'proprietary shaders are our exclusive property protected by international copyright laws.',
              isDark: isDark,
            ),
            const SizedBox(height: 20),
            _PolicySection(
              title: '7. Limitation of Liability',
              content:
                  'To the maximum extent permitted by applicable law, Try On Clothes AI, its '
                  'developers, contributors, and service affiliates shall not be liable for any '
                  'indirect, punitive, incidental, special, consequential, or exemplary damages, '
                  'including loss of profits, data, goodwill, or device malfunction arising from '
                  'the use or inability to use the Service.',
              isDark: isDark,
            ),
            const SizedBox(height: 20),
            _PolicySection(
              title: '8. Disclaimer of Warranties',
              content:
                  'The App and its neural rendering outputs are provided strictly on an "AS IS" '
                  'and "AS AVAILABLE" basis without warranties of any kind, either express or '
                  'implied. We do not warrant that the service will be uninterrupted, error-free, '
                  'or secure at all times.',
              isDark: isDark,
            ),
            const SizedBox(height: 20),
            _PolicySection(
              title: '9. Termination of Service',
              content:
                  'We reserve the right to suspend or terminate your access to the App at our '
                  'sole discretion, without notice, if we determine that you have violated these '
                  'Terms of Service, applicable laws, or third-party rights.',
              isDark: isDark,
            ),
            const SizedBox(height: 20),
            _PolicySection(
              title: '10. Governing Law and Dispute Resolution',
              content:
                  'These Terms are governed by and construed in accordance with the laws of '
                  'India, without regard to conflict of law principles. Any dispute arising out '
                  'of or relating to these Terms shall be resolved through good-faith negotiation '
                  'or subject to the jurisdiction of competent courts in Mumbai, India.',
              isDark: isDark,
            ),
            const SizedBox(height: 20),
            _PolicySection(
              title: '11. Contact Information',
              content:
                  'For legal inquiries, copyright notices, or questions regarding these Terms:\n\n'
                  'Email: support@tryonclothesai.com\n'
                  'App Developer: Try On Clothes AI Team\n'
                  'Response Time: Within 2 to 3 business days',
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
