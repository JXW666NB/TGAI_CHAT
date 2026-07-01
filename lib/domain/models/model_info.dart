enum ModelType { gguf, tgaiPtl }

class ModelInfo {
  final String id;
  final String name;
  final String path; // GGUF 路径 或 prefill.ptl 路径
  final ModelType type;
  final String? decodePath; // TGAI: decode.ptl 路径
  final String? tokenizerPath; // TGAI: tokenizer.json 路径
  final int? contextLength;
  final DateTime addedAt;

  ModelInfo({
    required this.id,
    required this.name,
    required this.path,
    this.type = ModelType.gguf,
    this.decodePath,
    this.tokenizerPath,
    this.contextLength,
    required this.addedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'path': path,
        'type': type.name,
        'decodePath': decodePath,
        'tokenizerPath': tokenizerPath,
        'contextLength': contextLength,
        'addedAt': addedAt.toIso8601String(),
      };

  factory ModelInfo.fromJson(Map<String, dynamic> json) => ModelInfo(
        id: json['id'] as String,
        name: json['name'] as String,
        path: json['path'] as String,
        type: ModelType.values.byName(json['type'] as String? ?? 'gguf'),
        decodePath: json['decodePath'] as String?,
        tokenizerPath: json['tokenizerPath'] as String?,
        contextLength: json['contextLength'] as int?,
        addedAt: DateTime.parse(json['addedAt'] as String),
      );
}
