// ═══════════════════════════════════════════════════════════════
// FILE: lib/widgets/admin/inquiry/customer_info_card.dart
// UPDATED v18 — Dark mode shadow adjustments
// ═══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../config/admin_theme.dart';
import '../../../config/brand_colors.dart';
import '../../../models/inquiry_detail.dart';

class CustomerInfoCard extends StatelessWidget {
  final InquiryCustomer customer;
  final VoidCallback onChatTap;

  const CustomerInfoCard({
    super.key,
    required this.customer,
    required this.onChatTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [Brand.royalBlueDark, Brand.royalBlue]
              : [AdminColors.primary, Brand.royalBlueLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AdminColors.primary.withAlpha(isDark ? 40 : 75),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          // Customer info row
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(38),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: Colors.white.withAlpha(50),
                    width: 2,
                  ),
                ),
                child: Center(
                  child: Text(
                    customer.initials,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customer.fullName,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    if (customer.companyName != null &&
                        customer.companyName!.isNotEmpty)
                      Text(
                        customer.companyName!,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withAlpha(180),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Contact details box
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(25),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                if (customer.email != null)
                  _buildContactRow(Icons.email_outlined, customer.email!),
                if (customer.phoneNumber != null) ...[
                  if (customer.email != null) const SizedBox(height: 8),
                  _buildContactRow(Icons.phone_outlined, customer.phoneNumber!),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Action buttons
          Row(
            children: [
              if (customer.email != null)
                Expanded(
                  child: _ContactButton(
                    icon: Icons.email_rounded,
                    label: 'Email',
                    color: Colors.white,
                    onTap: () => _launchEmail(customer.email!),
                  ),
                ),
              if (customer.email != null) const SizedBox(width: 8),
              if (customer.phoneNumber != null)
                Expanded(
                  child: _ContactButton(
                    icon: Icons.phone_rounded,
                    label: 'Call',
                    color: AdminColors.accent,
                    onTap: () => _launchPhone(customer.phoneNumber!),
                  ),
                ),
              if (customer.phoneNumber != null) const SizedBox(width: 8),
              Expanded(
                child: _ContactButton(
                  icon: Icons.chat_rounded,
                  label: 'Chat',
                  color: Colors.white,
                  onTap: onChatTap,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildContactRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.white.withAlpha(150)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 13, color: Colors.white),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Future<void> _launchPhone(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _launchEmail(String email) async {
    final uri = Uri(scheme: 'mailto', path: email);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }
}

class _ContactButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ContactButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(30),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withAlpha(200),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
