/// Generation data model for AI try-on history.
class GenerationModel {
  final String id;
  final String userId;
  final String personImageUrl;
  final String clothesImageUrl;
  final String? resultImageUrl;
  final int creditsUsed;
  final DateTime createdAt;
  final GenerationStatus status;
  final String? gender;
  final String? bodySize;
  final String? style;
  final String? quality;
  final String? category;

  const GenerationModel({
    required this.id,
    required this.userId,
    required this.personImageUrl,
    required this.clothesImageUrl,
    this.resultImageUrl,
    this.creditsUsed = 1,
    required this.createdAt,
    this.status = GenerationStatus.pending,
    this.gender,
    this.bodySize,
    this.style,
    this.quality,
    this.category,
  });

  GenerationModel copyWith({
    String? id,
    String? userId,
    String? personImageUrl,
    String? clothesImageUrl,
    String? resultImageUrl,
    int? creditsUsed,
    DateTime? createdAt,
    GenerationStatus? status,
    String? gender,
    String? bodySize,
    String? style,
    String? quality,
    String? category,
  }) {
    return GenerationModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      personImageUrl: personImageUrl ?? this.personImageUrl,
      clothesImageUrl: clothesImageUrl ?? this.clothesImageUrl,
      resultImageUrl: resultImageUrl ?? this.resultImageUrl,
      creditsUsed: creditsUsed ?? this.creditsUsed,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      gender: gender ?? this.gender,
      bodySize: bodySize ?? this.bodySize,
      style: style ?? this.style,
      quality: quality ?? this.quality,
      category: category ?? this.category,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'personImageUrl': personImageUrl,
      'clothesImageUrl': clothesImageUrl,
      'resultImageUrl': resultImageUrl,
      'creditsUsed': creditsUsed,
      'createdAt': createdAt.toIso8601String(),
      'status': status.name,
      'gender': gender,
      'bodySize': bodySize,
      'style': style,
      'quality': quality,
      'category': category,
    };
  }

  factory GenerationModel.fromMap(Map<String, dynamic> map) {
    return GenerationModel(
      id: map['id'] ?? '',
      userId: map['userId'] ?? '',
      personImageUrl: map['personImageUrl'] ?? '',
      clothesImageUrl: map['clothesImageUrl'] ?? '',
      resultImageUrl: map['resultImageUrl'],
      creditsUsed: map['creditsUsed'] ?? 1,
      createdAt: DateTime.tryParse(map['createdAt'] ?? '') ?? DateTime.now(),
      status: GenerationStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => GenerationStatus.pending,
      ),
      gender: map['gender'],
      bodySize: map['bodySize'],
      style: map['style'],
      quality: map['quality'],
      category: map['category'],
    );
  }
}

enum GenerationStatus {
  pending,
  processing,
  completed,
  failed,
}
