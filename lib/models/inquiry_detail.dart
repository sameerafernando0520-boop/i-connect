// lib/models/inquiry_detail.dart

/// Sales stage progression order for [nextStage].
const _stageOrder = ['new', 'contacted', 'quoted', 'negotiating', 'won'];

class InquiryDetail {
  final String id;
  final String ticketNumber;
  final String subject;
  final String? description;
  final String status;
  final String priority;
  final String salesStage;
  final double? dealValue;
  final double? quoteAmount;
  final String? adminNotes;
  final int? quantity;
  final String? deliveryAddress;
  final String? additionalRequirements;
  final String? expectedDelivery;
  final DateTime? quoteSentDate;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? closedAt;

  // ── Relationship IDs ────────────────────────────────────────
  final String? userId;
  final String? assignedTo;
  final String? catalogMachineId;

  // ── Sales-specific ──────────────────────────────────────────
  final bool isHotLead;
  final String? followUpDate;
  final DateTime? lastActivityAt;

  // ── Counts ──────────────────────────────────────────────────
  final int messageCount;
  final int unreadCount;

  // ── Relations ───────────────────────────────────────────────
  final InquiryCustomer? customer;
  final InquiryMachine? machine;
  final String? assignedEngineerName;

  // ── Preview (from RPC only, nullable for direct queries) ───
  final String? lastMessagePreview;

  const InquiryDetail({
    required this.id,
    required this.ticketNumber,
    required this.subject,
    this.description,
    required this.status,
    required this.priority,
    required this.salesStage,
    this.dealValue,
    this.quoteAmount,
    this.adminNotes,
    this.quantity,
    this.deliveryAddress,
    this.additionalRequirements,
    this.expectedDelivery,
    this.quoteSentDate,
    required this.createdAt,
    required this.updatedAt,
    this.closedAt,
    this.userId,
    this.assignedTo,
    this.catalogMachineId,
    this.isHotLead = false,
    this.followUpDate,
    this.lastActivityAt,
    this.messageCount = 0,
    this.unreadCount = 0,
    this.customer,
    this.machine,
    this.assignedEngineerName,
    this.lastMessagePreview,
  });

  // ═══════════════════════════════════════════════════════════
  //  FROM JSON
  // ═══════════════════════════════════════════════════════════

  factory InquiryDetail.fromJson(Map<String, dynamic> json) {
    // Related data — keys match PostgREST response
    final user = json['users'] as Map<String, dynamic>?;
    final machineCatalog =
        json['machine_catalog'] as Map<String, dynamic>?;

    // Assigned engineer — aliased join from repository
    // Repository: assigned_engineer:users!assigned_to(full_name)
    // RPC: assigned_engineer_name (flat string)
    final assignedEng =
        json['assigned_engineer'] as Map<String, dynamic>?;
    final engineerName = json['assigned_engineer_name'] as String? ??
        assignedEng?['full_name'] as String?;

    // Metadata JSONB extraction
    final metadata =
        json['metadata'] as Map<String, dynamic>? ?? {};

    // Customer ID — prefer the join's own id, fall back to FK
    final customerId =
        user?['id']?.toString() ?? json['user_id']?.toString() ?? '';

    // Machine ID — prefer the join's own id, fall back to FK
    final machineId = machineCatalog?['id']?.toString() ??
        json['catalog_machine_id']?.toString() ??
        '';

    return InquiryDetail(
      id: json['id'],
      ticketNumber: json['ticket_number'] ?? '',
      subject: json['subject'] ?? 'Inquiry',
      description: json['description'],
      status: json['status'] ?? 'open',
      priority: json['priority'] ?? 'medium',
      salesStage: json['sales_stage'] ?? 'new',
      dealValue: json['deal_value'] != null
          ? (json['deal_value'] as num).toDouble()
          : null,
      quoteAmount: json['quote_amount'] != null
          ? (json['quote_amount'] as num).toDouble()
          : null,
      adminNotes: json['admin_notes'],
      quantity: json['quantity'],
      deliveryAddress: json['delivery_address'],
      // Metadata fields — check metadata JSONB first, then top-level
      additionalRequirements:
          metadata['additional_requirements']?.toString() ??
              json['additional_requirements']?.toString(),
      expectedDelivery:
          metadata['expected_delivery']?.toString() ??
              json['expected_delivery']?.toString(),
      quoteSentDate: json['quote_sent_date'] != null
          ? DateTime.tryParse(json['quote_sent_date'])
          : null,
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
      closedAt: json['closed_at'] != null
          ? DateTime.tryParse(json['closed_at'])
          : null,
      // Relationship IDs
      userId: json['user_id'],
      assignedTo: json['assigned_to'],
      catalogMachineId: json['catalog_machine_id'],
      // Sales-specific
      isHotLead: json['is_hot_lead'] == true,
      followUpDate: json['follow_up_date']?.toString(),
      lastActivityAt: json['last_activity_at'] != null
          ? DateTime.tryParse(json['last_activity_at'])
          : null,
      // Counts (from RPC or default 0)
      messageCount: json['message_count'] ?? 0,
      unreadCount: json['unread_count'] ?? 0,
      // Relations
      customer: user != null
          ? InquiryCustomer.fromJson({
              'id': customerId,
              ...user,
            })
          : null,
      machine: machineCatalog != null
          ? InquiryMachine.fromJson({
              'id': machineId,
              ...machineCatalog,
            })
          : null,
      // Engineer name
      assignedEngineerName: engineerName,
      // Preview (only from RPC responses)
      lastMessagePreview: json['last_message_preview'],
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  COPY WITH
  // ═══════════════════════════════════════════════════════════

  /// Create a copy with updated fields.
  ///
  /// Use [clearDealValue] to explicitly set dealValue to null.
  /// Use [clearClosedAt] to explicitly set closedAt to null.
  InquiryDetail copyWith({
    String? salesStage,
    String? status,
    double? dealValue,
    bool clearDealValue = false,
    String? adminNotes,
    DateTime? quoteSentDate,
    DateTime? updatedAt,
    DateTime? closedAt,
    bool clearClosedAt = false,
    bool? isHotLead,
    String? followUpDate,
    int? messageCount,
    int? unreadCount,
    String? assignedEngineerName,
  }) {
    return InquiryDetail(
      id: id,
      ticketNumber: ticketNumber,
      subject: subject,
      description: description,
      status: status ?? this.status,
      priority: priority,
      salesStage: salesStage ?? this.salesStage,
      dealValue:
          clearDealValue ? null : (dealValue ?? this.dealValue),
      quoteAmount: quoteAmount,
      adminNotes: adminNotes ?? this.adminNotes,
      quantity: quantity,
      deliveryAddress: deliveryAddress,
      additionalRequirements: additionalRequirements,
      expectedDelivery: expectedDelivery,
      quoteSentDate: quoteSentDate ?? this.quoteSentDate,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      closedAt:
          clearClosedAt ? null : (closedAt ?? this.closedAt),
      userId: userId,
      assignedTo: assignedTo,
      catalogMachineId: catalogMachineId,
      isHotLead: isHotLead ?? this.isHotLead,
      followUpDate: followUpDate ?? this.followUpDate,
      lastActivityAt: lastActivityAt,
      messageCount: messageCount ?? this.messageCount,
      unreadCount: unreadCount ?? this.unreadCount,
      customer: customer,
      machine: machine,
      assignedEngineerName:
          assignedEngineerName ?? this.assignedEngineerName,
      lastMessagePreview: lastMessagePreview,
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  COMPUTED GETTERS
  // ═══════════════════════════════════════════════════════════

  /// Whether this inquiry is in a terminal state (won or lost).
  bool get isTerminal =>
      salesStage == 'won' || salesStage == 'lost';

  /// Whether this inquiry is still active (not terminal).
  bool get active => !isTerminal;

  bool get isWon => salesStage == 'won';
  bool get isLost => salesStage == 'lost';
  bool get hasDealValue => dealValue != null && dealValue! > 0;

  /// Duration since creation.
  Duration get age => DateTime.now().difference(createdAt);

  /// Number of days this inquiry has been open.
  int get daysOpen => DateTime.now().difference(createdAt).inDays;

  /// Returns the next logical stage in the pipeline, or null if
  /// the current stage is terminal (won/lost) or already at the end.
  ///
  /// Progression: new → contacted → quoted → negotiating → won
  String? nextStage() {
    if (isTerminal) return null;
    final idx = _stageOrder.indexOf(salesStage);
    if (idx < 0 || idx >= _stageOrder.length - 1) return null;
    return _stageOrder[idx + 1];
  }
}

// ═══════════════════════════════════════════════════════════
//  INQUIRY CUSTOMER
// ═══════════════════════════════════════════════════════════

class InquiryCustomer {
  final String id;
  final String fullName;
  final String? email;
  final String? companyName;
  final String? phoneNumber;
  final String? city;
  final String? profilePhoto;

  const InquiryCustomer({
    this.id = '',
    required this.fullName,
    this.email,
    this.companyName,
    this.phoneNumber,
    this.city,
    this.profilePhoto,
  });

  factory InquiryCustomer.fromJson(Map<String, dynamic> json) {
    return InquiryCustomer(
      id: json['id']?.toString() ?? '',
      fullName: json['full_name'] ?? 'Unknown',
      email: json['email'],
      companyName: json['company_name'],
      phoneNumber: json['phone_number'],
      city: json['city'],
      profilePhoto: json['profile_photo'],
    );
  }

  /// Initials for avatar display.
  ///
  /// Note: Screens should prefer [StringUtils.getInitials] for
  /// consistency. This getter is provided for model-level use.
  String get initials {
    if (fullName.isEmpty) return 'U';
    final parts = fullName.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return parts[0][0].toUpperCase();
  }
}

// ═══════════════════════════════════════════════════════════
//  INQUIRY MACHINE
// ═══════════════════════════════════════════════════════════

class InquiryMachine {
  final String id;
  final String machineName;
  final String? brand;
  final String? modelNumber;
  final String? category;
  final String? description;
  final String? imageUrl;
  final double? price;

  const InquiryMachine({
    this.id = '',
    required this.machineName,
    this.brand,
    this.modelNumber,
    this.category,
    this.description,
    this.imageUrl,
    this.price,
  });

  factory InquiryMachine.fromJson(Map<String, dynamic> json) {
    // Check product_images array first, then fall back to image_url
    final images = json['product_images'] as List?;
    final resolvedImage =
        (images != null && images.isNotEmpty)
            ? images[0]?.toString()
            : json['image_url'];

    return InquiryMachine(
      id: json['id']?.toString() ?? '',
      machineName: json['machine_name'] ?? 'Unknown',
      brand: json['brand'],
      modelNumber: json['model_number'],
      category: json['category'],
      description: json['description'],
      imageUrl: resolvedImage,
      price: (json['price'] as num?)?.toDouble(),
    );
  }

  bool get hasImage => imageUrl != null && imageUrl!.isNotEmpty;
}