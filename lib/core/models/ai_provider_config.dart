/// Configuration model for an AI image generation provider.
///
/// Each provider has a unique [id], a display [name], a [signupUrl] where
/// users can create an account / obtain an API key, and optional hints for
/// the API key and endpoint fields shown in Settings.
class AiProviderConfig {
  final String id;
  final String name;
  final String signupUrl;
  final String apiKeyHint;
  final bool requiresEndpoint;
  final String endpointHint;
  final String apiKeyLabel;

  const AiProviderConfig({
    required this.id,
    required this.name,
    required this.signupUrl,
    this.apiKeyHint = 'Enter your API key',
    this.requiresEndpoint = false,
    this.endpointHint = '',
    this.apiKeyLabel = 'API Key',
  });

  /// Built-in providers.
  static const List<AiProviderConfig> builtIn = [
    AiProviderConfig(
      id: 'huggingface',
      name: 'HuggingFace (IDM-VTON)',
      signupUrl: 'https://huggingface.co/settings/tokens',
      apiKeyHint: 'Enter your HuggingFace API token (free)',
      apiKeyLabel: 'HuggingFace Token',
    ),
    AiProviderConfig(
      id: 'openai',
      name: 'OpenAI (ChatGPT / DALL-E 3)',
      signupUrl: 'https://platform.openai.com/api-keys',
      apiKeyHint: 'Enter your OpenAI API key (sk-...)',
      apiKeyLabel: 'OpenAI API Key',
    ),
    AiProviderConfig(
      id: 'fashn',
      name: 'Fashn.ai (Dedicated Try-On)',
      signupUrl: 'https://fashn.ai',
      apiKeyHint: 'Enter your Fashn.ai API key',
      apiKeyLabel: 'Fashn.ai API Key',
    ),
    AiProviderConfig(
      id: 'fal',
      name: 'Fal.ai (Fast Cloud VTON)',
      signupUrl: 'https://fal.ai/dashboard/api-keys',
      apiKeyHint: 'Enter your Fal.ai API key',
      apiKeyLabel: 'Fal.ai Key',
    ),
    AiProviderConfig(
      id: 'replicate',
      name: 'Replicate (IDM-VTON / Try-On)',
      signupUrl: 'https://replicate.com/account/api-tokens',
      apiKeyHint: 'Enter your Replicate API token',
      apiKeyLabel: 'Replicate Token',
    ),
    AiProviderConfig(
      id: 'segmind',
      name: 'Segmind (Try-On Diffusion)',
      signupUrl: 'https://www.segmind.com/api-keys',
      apiKeyHint: 'Enter your Segmind API key',
      apiKeyLabel: 'Segmind Key',
    ),
    AiProviderConfig(
      id: 'novita',
      name: 'Novita AI (IDM-VTON Cloud)',
      signupUrl: 'https://novita.ai',
      apiKeyHint: 'Enter your Novita AI API key',
      apiKeyLabel: 'Novita AI Key',
    ),
    AiProviderConfig(
      id: 'kling',
      name: 'Kling AI (Virtual Fitting)',
      signupUrl: 'https://klingai.com',
      apiKeyHint: 'Enter your Kling AI API key',
      apiKeyLabel: 'Kling AI Key',
    ),
    AiProviderConfig(
      id: 'custom',
      name: 'Custom API / Colab / RunPod',
      signupUrl: '',
      apiKeyHint: 'Enter your API key (if required)',
      requiresEndpoint: true,
      endpointHint: 'https://your-api-endpoint.com/generate',
      apiKeyLabel: 'Custom API Key',
    ),
  ];

  /// Look up a provider by [id].
  static AiProviderConfig? fromId(String id) {
    try {
      return builtIn.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiProviderConfig &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'AiProviderConfig($id, $name)';
}
