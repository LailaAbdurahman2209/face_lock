class WorkSite {
  final int id;
  final String name;

  WorkSite({required this.id, required this.name});

  factory WorkSite.fromJson(Map<String, dynamic> json) {
    return WorkSite(
      id: json['id'],
      name: json['name'],
    );
  }
}