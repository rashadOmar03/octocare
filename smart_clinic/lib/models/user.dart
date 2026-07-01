class User {
  final String? id;
  final String? email;
  final String? phone;
  final String? firstName;
  final String? middleName;
  final String? lastName;
  final String? role;
  final bool? isActive;
  final String? profilePhoto;
  final Profile? profile;

  User({
    this.id,
    this.email,
    this.phone,
    this.firstName,
    this.middleName,
    this.lastName,
    this.role,
    this.isActive,
    this.profilePhoto,
    this.profile,
  });

  String get fullName {
    final parts = <String>[];
    if (firstName != null && firstName!.isNotEmpty) parts.add(firstName!);
    if (middleName != null && middleName!.isNotEmpty) parts.add(middleName!);
    if (lastName != null && lastName!.isNotEmpty) parts.add(lastName!);
    return parts.join(' ');
  }

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id']?.toString(),
      email: json['email'],
      phone: json['phone'],
      firstName: json['first_name'],
      middleName: json['middle_name'],
      lastName: json['last_name'],
      role: json['role'],
      isActive: json['is_active'],
      profilePhoto: json['profile_photo'],
      profile: json['profile'] != null ? Profile.fromJson(json['profile']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'phone': phone,
      'first_name': firstName,
      'middle_name': middleName,
      'last_name': lastName,
      'role': role,
      'is_active': isActive,
      'profile_photo': profilePhoto,
      'profile': profile?.toJson(),
    };
  }
}

class Profile {
  final String? id;
  final String? dateOfBirth;
  final String? gender;
  final String? address;
  final String? bloodType;
  final String? allergies;
  final String? chronicDiseases;
  final String? existingConditions;
  final String? emergencyContactName;
  final String? emergencyContactPhone;
  final String? specialty;
  final String? qualifications;
  final String? bio;

  Profile({
    this.id,
    this.dateOfBirth,
    this.gender,
    this.address,
    this.bloodType,
    this.allergies,
    this.chronicDiseases,
    this.existingConditions,
    this.emergencyContactName,
    this.emergencyContactPhone,
    this.specialty,
    this.qualifications,
    this.bio,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id']?.toString(),
      dateOfBirth: json['date_of_birth'],
      gender: json['gender'],
      address: json['address'],
      bloodType: json['blood_type'],
      allergies: json['allergies'],
      chronicDiseases: json['chronic_diseases'],
      existingConditions: json['existing_conditions'],
      emergencyContactName: json['emergency_contact_name'],
      emergencyContactPhone: json['emergency_contact_phone'],
      specialty: json['specialty'],
      qualifications: json['qualifications'],
      bio: json['bio'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'date_of_birth': dateOfBirth,
      'gender': gender,
      'address': address,
      'blood_type': bloodType,
      'allergies': allergies,
      'chronic_diseases': chronicDiseases,
      'existing_conditions': existingConditions,
      'emergency_contact_name': emergencyContactName,
      'emergency_contact_phone': emergencyContactPhone,
      'specialty': specialty,
      'qualifications': qualifications,
      'bio': bio,
    };
  }
}
