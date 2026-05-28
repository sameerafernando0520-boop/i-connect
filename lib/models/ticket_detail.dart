// lib/models/ticket_detail.dart

class TicketUser {
  final String id;
  final String fullName;
  final String? email;
  final String? phoneNumber;
  final String? companyName;
  final String? profilePhoto;
  final String? role; // ← ADDED
  final List<String>? specializations;
  final String? availabilityStatus;

  TicketUser({
    required this.id,
    required this.fullName,
    this.email,
    this.phoneNumber,
    this.companyName,
    this.profilePhoto,
    this.role, // ← ADDED
    this.specializations,
    this.availabilityStatus,
  });

  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return fullName.isNotEmpty ? fullName[0].toUpperCase() : '?';
  }

  factory TicketUser.fromJson(Map<String, dynamic> j) => TicketUser(
        // H10: id must never be null — fall back to empty string so the
        // non-nullable contract on this class holds even if the DB row
        // comes back malformed. Callers use `id.isEmpty` to detect this.
        id: (j['id'] as Object?)?.toString() ?? '',
        fullName: (j['full_name'] as String?) ?? 'Unknown',
        email: j['email'] as String?,
        phoneNumber: j['phone_number'] as String?,
        companyName: j['company_name'] as String?,
        profilePhoto: j['profile_photo'] as String?,
        role: j['role'] as String?,
        // Guard against `specializations` being stored as a non-List
        // (e.g., stringified JSON) — List.from would otherwise throw.
        specializations: j['specializations'] is List
            ? List<String>.from(
                (j['specializations'] as List).whereType<Object>().map((e) => e.toString()))
            : null,
        availabilityStatus: j['availability_status'] as String?,
      );
}

class TicketMachine {
  final String? customerMachineId;
  final String machineName;
  final String? serialNumber;
  final String? brand;
  final String? imageUrl;
  final String? modelNumber;
  final String? category;
  final String? machineStatus;

  TicketMachine({
    this.customerMachineId,
    required this.machineName,
    this.serialNumber,
    this.brand,
    this.imageUrl,
    this.modelNumber,
    this.category,
    this.machineStatus,
  });

  factory TicketMachine.fromCustomerMachine(Map<String, dynamic> j) {
    final cat = j['catalog'] as Map<String, dynamic>?;
    return TicketMachine(
      customerMachineId: j['id'],
      machineName: cat?['machine_name'] ?? 'Unknown Machine',
      serialNumber: j['serial_number'],
      brand: cat?['brand'],
      imageUrl: cat?['image_url'],
      modelNumber: cat?['model_number'],
      category: cat?['category'],
      machineStatus: j['status'],
    );
  }

  factory TicketMachine.fromMetadata(Map<String, dynamic> m) => TicketMachine(
        machineName: m['machine_name'] ?? 'Ordered Machine',
        brand: m['brand'],
      );
}

class TicketDetail {
  final String id;
  final String ticketNumber;
  final String? userId;
  final String? assignedTo;
  final String? customerMachineId;
  final String? catalogMachineId;
  final String ticketType;
  final String subject;
  final String? description;
  final String status;
  final String priority;
  final String? category;
  final Map<String, dynamic> metadata;
  final bool escalated;
  final DateTime? escalatedAt;
  final String? escalationReason;
  final int? customerRating;
  final String? customerFeedback;
  final int quantity;
  final String? salesStage;
  final String? deliveryAddress;
  final DateTime? quoteSentDate;
  final DateTime? estimatedResolution;
  final DateTime? firstResponseAt;
  final int reopenedCount;
  final DateTime? closedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? adminNotes;
  final TicketUser? customer;
  final TicketUser? engineer;
  final TicketMachine? machine;

  TicketDetail({
    required this.id,
    required this.ticketNumber,
    this.userId,
    this.assignedTo,
    this.customerMachineId,
    this.catalogMachineId,
    required this.ticketType,
    required this.subject,
    this.description,
    required this.status,
    required this.priority,
    this.category,
    this.metadata = const {},
    this.escalated = false,
    this.escalatedAt,
    this.escalationReason,
    this.customerRating,
    this.customerFeedback,
    this.quantity = 1,
    this.salesStage,
    this.deliveryAddress,
    this.quoteSentDate,
    this.estimatedResolution,
    this.firstResponseAt,
    this.reopenedCount = 0,
    this.closedAt,
    required this.createdAt,
    required this.updatedAt,
    this.adminNotes,
    this.customer,
    this.engineer,
    this.machine,
  });

  // ── Computed ──
  bool get isUrgent => priority == 'urgent' || escalated;
  bool get isClosed => status == 'closed' || status == 'resolved';
  bool get isOrder => ticketType == 'order';
  Duration get age => DateTime.now().difference(createdAt);

  String get ageDisplay {
    final d = age;
    if (d.inDays > 7) return '${d.inDays ~/ 7}w';
    if (d.inDays > 0) return '${d.inDays}d';
    if (d.inHours > 0) return '${d.inHours}h';
    if (d.inMinutes > 0) return '${d.inMinutes}m';
    return 'now';
  }

  Map<String, dynamic>? get orderDetails =>
      isOrder && metadata.isNotEmpty ? metadata : null;

  // ── Factory ──
  factory TicketDetail.fromJson(Map<String, dynamic> j) {
    final custJ = j['customer'] as Map<String, dynamic>?;
    final engJ = j['engineer'] as Map<String, dynamic>?;
    final cmJ = j['customer_machine'] as Map<String, dynamic>?;
    final meta = (j['metadata'] as Map<String, dynamic>?) ?? {};

    TicketMachine? machine;
    if (cmJ != null) {
      machine = TicketMachine.fromCustomerMachine(cmJ);
    } else if (j['ticket_type'] == 'order' && meta.isNotEmpty) {
      machine = TicketMachine.fromMetadata(meta);
    }

    return TicketDetail(
      id: (j['id'] as Object?)?.toString() ?? '',
      ticketNumber: (j['ticket_number'] as String?) ?? '',
      userId: j['user_id'],
      assignedTo: j['assigned_to'],
      customerMachineId: j['customer_machine_id'],
      catalogMachineId: j['catalog_machine_id'],
      ticketType: j['ticket_type'] ?? 'support',
      subject: j['subject'] ?? '',
      description: j['description'],
      status: j['status'] ?? 'open',
      priority: j['priority'] ?? 'medium',
      category: j['category'],
      metadata: meta,
      escalated: j['escalated'] ?? false,
      escalatedAt: _dt(j['escalated_at']),
      escalationReason: j['escalation_reason'],
      customerRating: j['customer_rating'],
      customerFeedback: j['customer_feedback'],
      quantity: j['quantity'] ?? 1,
      salesStage: j['sales_stage'],
      deliveryAddress: j['delivery_address'],
      quoteSentDate: _dt(j['quote_sent_date']),
      estimatedResolution: _dt(j['estimated_resolution']),
      firstResponseAt: _dt(j['first_response_at']),
      reopenedCount: (j['reopened_count'] as int?) ?? 0,
      closedAt: _dt(j['closed_at']),
      // Fall back to `now` if the timestamp is missing/malformed rather than
      // throwing — avoids crashing the entire inquiry/ticket page on bad data.
      createdAt:
          _dt(j['created_at']) ?? _dt(j['updated_at']) ?? DateTime.now(),
      updatedAt:
          _dt(j['updated_at']) ?? _dt(j['created_at']) ?? DateTime.now(),
      adminNotes: j['admin_notes'],
      customer: custJ != null ? TicketUser.fromJson(custJ) : null,
      engineer: engJ != null ? TicketUser.fromJson(engJ) : null,
      machine: machine,
    );
  }

  static DateTime? _dt(dynamic v) => v != null ? DateTime.tryParse(v) : null;

  // ── CopyWith ──
  TicketDetail copyWith({
    String? status,
    String? priority,
    String? assignedTo,
    String? adminNotes,
    bool? escalated,
    DateTime? escalatedAt,
    String? escalationReason,
    TicketUser? engineer,
  }) =>
      TicketDetail(
        id: id,
        ticketNumber: ticketNumber,
        userId: userId,
        assignedTo: assignedTo ?? this.assignedTo,
        customerMachineId: customerMachineId,
        catalogMachineId: catalogMachineId,
        ticketType: ticketType,
        subject: subject,
        description: description,
        status: status ?? this.status,
        priority: priority ?? this.priority,
        category: category,
        metadata: metadata,
        escalated: escalated ?? this.escalated,
        escalatedAt: escalatedAt ?? this.escalatedAt,
        escalationReason: escalationReason ?? this.escalationReason,
        customerRating: customerRating,
        customerFeedback: customerFeedback,
        quantity: quantity,
        salesStage: salesStage,
        deliveryAddress: deliveryAddress,
        quoteSentDate: quoteSentDate,
        estimatedResolution: estimatedResolution,
        firstResponseAt: firstResponseAt,
        reopenedCount: reopenedCount,
        closedAt: closedAt,
        createdAt: createdAt,
        updatedAt: updatedAt,
        adminNotes: adminNotes ?? this.adminNotes,
        customer: customer,
        engineer: engineer ?? this.engineer,
        machine: machine,
      );
}
