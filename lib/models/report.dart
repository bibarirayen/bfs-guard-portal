class Report {
  final int id;
  final String type;
  final String? client;
  final String? site;
  final String? officer;
  final String? dateEntered;
  final List<String> images;

  /// contains ALL backend fields dynamically
  final Map<String, dynamic> raw;

  Report({
    required this.id,
    required this.type,
    this.client,
    this.site,
    this.officer,
    this.dateEntered,
    required this.images,
    required this.raw,
  });

  factory Report.fromJson(Map<String, dynamic> json) {
    return Report(
      id: json['id'],
      type: json['type'] ?? 'Unknown',
      client: json['client'],
      site: json['site'],
      officer: json['officer'],
      dateEntered: json['dateEntered'],
      images: List<String>.from(json['images'] ?? []),
      raw: json,
    );
  }
}
