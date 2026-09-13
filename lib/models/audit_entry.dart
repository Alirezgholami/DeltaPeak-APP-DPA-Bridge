class AuditEntry {
  const AuditEntry({
    required this.auditId,
    required this.entityType,
    required this.entityId,
    required this.action,
    required this.actor,
    required this.changedAtJalali,
    this.peakId,
    this.fieldName,
    this.oldValue,
    this.newValue,
  });

  final int auditId;
  final String? peakId;
  final String entityType;
  final String entityId;
  final String action;
  final String? fieldName;
  final String? oldValue;
  final String? newValue;
  final String actor;
  final String changedAtJalali;

  factory AuditEntry.fromMap(Map<String, Object?> map) => AuditEntry(
        auditId: (map['audit_id'] as num?)?.toInt() ?? 0,
        peakId: map['peak_id']?.toString(),
        entityType: (map['entity_type'] ?? '').toString(),
        entityId: (map['entity_id'] ?? '').toString(),
        action: (map['action'] ?? '').toString(),
        fieldName: map['field_name']?.toString(),
        oldValue: map['old_value']?.toString(),
        newValue: map['new_value']?.toString(),
        actor: (map['actor'] ?? '').toString(),
        changedAtJalali: (map['changed_at_jalali'] ?? '').toString(),
      );
}
