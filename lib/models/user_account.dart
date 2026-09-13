class UserAccount {
  const UserAccount({
    required this.userId,
    required this.displayName,
    required this.mobile,
    required this.status,
    required this.role,
    required this.createdAtJalali,
    this.email,
    this.createdAtUtc,
    this.lastLoginAtUtc,
    this.lastLoginAtJalali,
    this.lastActivityAtUtc,
    this.lastActivityAtJalali,
  });

  final String userId;
  final String displayName;
  final String mobile;
  final String? email;
  final String status;
  final String role;
  final String createdAtJalali;
  final String? createdAtUtc;
  final String? lastLoginAtUtc;
  final String? lastLoginAtJalali;
  final String? lastActivityAtUtc;
  final String? lastActivityAtJalali;

  bool get isAdmin => role == 'admin' || role == 'owner';
  bool get isOwner => role == 'owner';

  factory UserAccount.fromMap(Map<String, Object?> map) => UserAccount(
        userId: (map['user_id'] ?? map['id'] ?? '').toString(),
        displayName: (map['display_name'] ?? map['name'] ?? '').toString(),
        mobile: (map['mobile'] ?? map['username'] ?? '').toString(),
        email: map['email']?.toString(),
        status: (map['status'] ?? 'active').toString(),
        role: (map['role'] ?? 'user').toString(),
        createdAtUtc: map['created_at_utc']?.toString(),
        createdAtJalali: (map['created_at_jalali'] ?? '').toString(),
        lastLoginAtUtc: map['last_login_at_utc']?.toString(),
        lastLoginAtJalali: map['last_login_at_jalali']?.toString(),
        lastActivityAtUtc: map['last_activity_at_utc']?.toString(),
        lastActivityAtJalali: map['last_activity_at_jalali']?.toString(),
      );

  factory UserAccount.fromJson(Map<String, dynamic> json) => UserAccount.fromMap(json);

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'display_name': displayName,
        'mobile': mobile,
        'email': email,
        'status': status,
        'role': role,
        'created_at_utc': createdAtUtc,
        'created_at_jalali': createdAtJalali,
        'last_login_at_utc': lastLoginAtUtc,
        'last_login_at_jalali': lastLoginAtJalali,
        'last_activity_at_utc': lastActivityAtUtc,
        'last_activity_at_jalali': lastActivityAtJalali,
      };
}
