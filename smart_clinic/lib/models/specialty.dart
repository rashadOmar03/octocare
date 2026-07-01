class Specialty {
  final int? id;
  final String? name;
  final String? description;
  final int? doctorCount;

  Specialty({
    this.id,
    this.name,
    this.description,
    this.doctorCount,
  });

  factory Specialty.fromJson(Map<String, dynamic> json) {
    return Specialty(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      doctorCount: json['doctor_count'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
    };
  }
}
