// lib/models/dashboard_stats.dart

class DashboardStats {
  final int totalMachines;
  final int totalCustomers;
  final int openTickets;
  final int totalInquiries;
  final int resolvedTickets;
  final int newCustomersThisMonth;
  final int urgentTickets;
  final int pendingInquiries;
  final int totalOrders;
  final double totalRevenue;

  const DashboardStats({
    this.totalMachines = 0,
    this.totalCustomers = 0,
    this.openTickets = 0,
    this.totalInquiries = 0,
    this.resolvedTickets = 0,
    this.newCustomersThisMonth = 0,
    this.urgentTickets = 0,
    this.pendingInquiries = 0,
    this.totalOrders = 0,
    this.totalRevenue = 0,
  });

  double get resolutionRate {
    final total = openTickets + resolvedTickets;
    if (total == 0) return 0;
    return resolvedTickets / total;
  }

  int get resolutionPercentage => (resolutionRate * 100).round();

  factory DashboardStats.fromRpc(Map<String, dynamic> data) {
    return DashboardStats(
      totalMachines: data['total_machines'] ?? 0,
      totalCustomers: data['total_customers'] ?? 0,
      openTickets: data['open_tickets'] ?? 0,
      totalInquiries: data['total_inquiries'] ?? 0,
      resolvedTickets: data['resolved_tickets'] ?? 0,
      newCustomersThisMonth: data['new_customers_month'] ?? 0,
      urgentTickets: data['urgent_tickets'] ?? 0,
      pendingInquiries: data['pending_inquiries'] ?? 0,
      totalOrders: data['total_orders'] ?? 0,
      totalRevenue: (data['total_revenue'] ?? 0).toDouble(),
    );
  }

  DashboardStats copyWith({
    int? totalMachines,
    int? totalCustomers,
    int? openTickets,
    int? totalInquiries,
    int? resolvedTickets,
    int? newCustomersThisMonth,
    int? urgentTickets,
    int? pendingInquiries,
    int? totalOrders,
    double? totalRevenue,
  }) {
    return DashboardStats(
      totalMachines: totalMachines ?? this.totalMachines,
      totalCustomers: totalCustomers ?? this.totalCustomers,
      openTickets: openTickets ?? this.openTickets,
      totalInquiries: totalInquiries ?? this.totalInquiries,
      resolvedTickets: resolvedTickets ?? this.resolvedTickets,
      newCustomersThisMonth: newCustomersThisMonth ?? this.newCustomersThisMonth,
      urgentTickets: urgentTickets ?? this.urgentTickets,
      pendingInquiries: pendingInquiries ?? this.pendingInquiries,
      totalOrders: totalOrders ?? this.totalOrders,
      totalRevenue: totalRevenue ?? this.totalRevenue,
    );
  }

  static const empty = DashboardStats();
}

class RecentInquiry {
  final String id;
  final String ticketNumber;
  final String subject;
  final String status;
  final String? priority;
  final DateTime createdAt;
  final String? customerName;
  final String? companyName;
  final String? customerEmail;
  final String? machineName;
  final String? machineBrand;
  final int messageCount;

  const RecentInquiry({
    required this.id,
    required this.ticketNumber,
    required this.subject,
    required this.status,
    this.priority,
    required this.createdAt,
    this.customerName,
    this.companyName,
    this.customerEmail,
    this.machineName,
    this.machineBrand,
    this.messageCount = 0,
  });

  factory RecentInquiry.fromJson(Map<String, dynamic> json) {
    final customer = json['users'] as Map<String, dynamic>?;
    final machine = json['machine_catalog'] as Map<String, dynamic>?;

    return RecentInquiry(
      id: json['id'],
      ticketNumber: json['ticket_number'] ?? '',
      subject: json['subject'] ?? 'Inquiry',
      status: json['status'] ?? 'open',
      priority: json['priority'],
      createdAt: DateTime.parse(json['created_at']),
      customerName: customer?['full_name'],
      companyName: customer?['company_name'],
      customerEmail: customer?['email'],
      machineName: machine?['machine_name'],
      machineBrand: machine?['brand'],
    );
  }

  String get displayTitle => machineName ?? subject;
}

class RecentCustomer {
  final String id;
  final String fullName;
  final String? companyName;
  final String? email;
  final String? phone;
  final String? city;
  final DateTime createdAt;

  const RecentCustomer({
    required this.id,
    required this.fullName,
    this.companyName,
    this.email,
    this.phone,
    this.city,
    required this.createdAt,
  });

  factory RecentCustomer.fromJson(Map<String, dynamic> json) {
    return RecentCustomer(
      id: json['id'],
      fullName: json['full_name'] ?? 'Unknown',
      companyName: json['company_name'],
      email: json['email'],
      phone: json['phone_number'],
      city: json['city'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  String get initials {
    if (fullName.isEmpty) return 'A';
    final parts = fullName.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return parts[0][0].toUpperCase();
  }
}
