class Doctor {
  final String? id;
  final String? name;
  final String? email;
  final String? phone;
  final String? specialty;
  final String? specialtyId;
  final String? qualifications;
  final String? bio;
  final String? profilePhoto;
  final bool? isAvailable;
  final double? averageRating;
  final int? reviewCount;

  Doctor({
    this.id,
    this.name,
    this.email,
    this.phone,
    this.specialty,
    this.specialtyId,
    this.qualifications,
    this.bio,
    this.profilePhoto,
    this.isAvailable,
    this.averageRating,
    this.reviewCount,
  });

  factory Doctor.fromJson(Map<String, dynamic> json) {
    return Doctor(
      id: json['id']?.toString(),
      name: json['name'] ?? '${json['first_name'] ?? ''} ${json['last_name'] ?? ''}'.trim(),
      email: json['email'],
      phone: json['phone'],
      specialty: json['specialty_name'] ?? json['specialty'],
      specialtyId: json['specialty_id']?.toString(),
      qualifications: json['qualifications'],
      bio: json['bio'],
      profilePhoto: json['profile_photo'],
      isAvailable: json['is_available'],
      averageRating: json['average_rating'] == null ? null : (json['average_rating'] as num).toDouble(),
      reviewCount: json['review_count'] is int ? json['review_count'] : int.tryParse(json['review_count']?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'phone': phone,
      'specialty_id': specialtyId,
      'specialty_name': specialty,
      'qualifications': qualifications,
      'bio': bio,
    };
  }
}
