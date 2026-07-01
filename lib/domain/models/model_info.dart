class ModelInfo {
  final String id;
  final String name;
  final String path; // prefill.ptl 路径
  final String decodePath; // decode.ptl 路径
  final String tokenizerPath; // tokenizer.json 路径
  final int? contextLength;
  final DateTime addedAt;

  ModelInfo({
    required this.id,
    required this.name,
    required this.path,
    required this.decodePath,
    required this.tokenizerPath,
    this.contextLength,
    required this.addedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'path': path,
        'decodePath': decodePath,
        'tokenizerPath': tokenizerPath,
        'contextLength': contextLength,
        'addedAt': addedAt.toIso8601String(),
      };

  factory ModelInfo.fromJson(Map<String, dynamic> json) => ModelInfo(
        id: json['id'] as String,
        name: json['name'] as String,
        path: json['path'] as String,
        decodePath: json['decodePath'] as String,
        tokenizerPath: json['tokenizerPath'] as String,
        contextLength: json['contextLength'] as int?,
        addedAt: DateTime.parse(json['addedAt'] as String),
      );
}
