import 'package:flutter/material.dart';
import 'package:i_connect/config/brand_colors.dart';
import 'package:i_connect/config/admin_theme.dart';
import 'package:i_connect/config/supabase_config.dart';
import 'package:intl/intl.dart';
import 'package:i_connect/widgets/ds/ds_widgets.dart';

class PointsHistoryPage extends StatefulWidget {
  const PointsHistoryPage({super.key});

  @override
  State<PointsHistoryPage> createState() => _PointsHistoryPageState();
}

class _PointsHistoryPageState extends State<PointsHistoryPage> {
  bool _isLoading = true;
  String _errorMessage = '';
  List<Map<String, dynamic>> _activities = [];

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  Future<void> _fetchHistory() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final supa = SupabaseConfig.client;
      final userId = supa.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('User not logged in');
      }

      final response = await supa
          .from('point_activities')
          .select('activity_type, final_points, description, created_at')
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _activities = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Brand.canvas(isDark),
      body: Column(children: [
        const DsPageHeader(title: 'Points History', subtitle: 'Loyalty rewards'),
        Expanded(
          child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline_rounded,
                            color: StatusColors.danger, size: 48),
                        const SizedBox(height: 16),
                        Text(
                          _errorMessage,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: isDark
                                  ? Brand.darkTextSecondary
                                  : Brand.subtleLight),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _fetchHistory,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Brand.royalBlue,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : _activities.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.history_rounded,
                              size: 64,
                              color: (isDark
                                      ? Brand.darkTextTertiary
                                      : Brand.subtleLight)
                                  .withAlpha(128)),
                          const SizedBox(height: 16),
                          Text(
                            'No points history yet',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? Brand.darkTextSecondary
                                  : Brand.subtleLight,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
                      itemCount: _activities.length,
                      itemBuilder: (context, index) {
                        final p = _activities[index];
                        final type = p['activity_type'] as String? ?? '';
                        final pts = (p['final_points'] as num?)?.toInt() ?? 0;
                        final desc = p['description'] as String? ?? type;
                        final dateStr = p['created_at'] as String? ?? '';
                        final isPositive = pts >= 0;

                        String fmtDate = '';
                        if (dateStr.isNotEmpty) {
                          try {
                            final dt = DateTime.parse(dateStr).toLocal();
                            fmtDate = DateFormat('MMM d, yyyy • h:mm a').format(dt);
                          } catch (_) {}
                        }

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Brand.darkCardElevated
                                : Brand.scaffoldLight,
                            borderRadius: BorderRadius.circular(Brand.r(16)),
                            border: Border.all(
                              color: isDark
                                  ? Brand.darkBorder
                                  : Brand.borderLight,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: (isPositive
                                          ? StatusColors.success
                                          : StatusColors.danger)
                                      .withAlpha(isDark ? 30 : 20),
                                  borderRadius: BorderRadius.circular(Brand.r(12)),
                                ),
                                child: Icon(
                                  isPositive
                                      ? Icons.add_rounded
                                      : Icons.remove_rounded,
                                  size: 24,
                                  color: isPositive
                                      ? StatusColors.success
                                      : StatusColors.danger,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      desc,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: isDark
                                            ? Brand.darkTextPrimary
                                            : Brand.royalBlueDark,
                                      ),
                                    ),
                                    if (fmtDate.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        fmtDate,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isDark
                                              ? Brand.darkTextTertiary
                                              : Brand.subtleLight,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              Text(
                                '${isPositive ? '+' : ''}$pts',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: isPositive
                                      ? StatusColors.success
                                      : StatusColors.danger,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}
