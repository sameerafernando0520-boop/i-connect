// ============================================================
// iFrontiers Connect — Promotional Banner Carousel
// Auto-scrolling banner carousel for customer home page
// Loads from promotional_banners table via get_active_promotions()
// ============================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/supabase_config.dart';
import '../../config/brand_colors.dart';

class PromotionalCarousel extends StatefulWidget {
  /// Called when a banner links to a machine detail page
  /// Passes the catalog machine ID
  final void Function(String machineId)? onNavigateToMachine;

  /// Called when a banner links to a catalog category
  /// Passes the category name
  final void Function(String category)? onNavigateToCatalog;

  const PromotionalCarousel({
    super.key,
    this.onNavigateToMachine,
    this.onNavigateToCatalog,
  });

  @override
  State<PromotionalCarousel> createState() => _PromotionalCarouselState();
}

class _PromotionalCarouselState extends State<PromotionalCarousel> {
  List<Map<String, dynamic>> _banners = [];
  bool _isLoading = true;
  int _currentPage = 0;

  late PageController _pageController;
  Timer? _autoScrollTimer;
  final Set<String> _trackedImpressions = {};

  static const _autoScrollDuration = Duration(seconds: 5);
  static const _scrollAnimDuration = Duration(milliseconds: 400);

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.92);
    _loadBanners();
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  // ── Data ─────────────────────────────────────────────────
  Future<void> _loadBanners() async {
    try {
      final data = await SupabaseConfig.client.rpc('get_active_promotions');

      if (!mounted) return;

      final banners = List<Map<String, dynamic>>.from(data as List);

      setState(() {
        _banners = banners;
        _isLoading = false;
      });

      if (_banners.length > 1) {
        _startAutoScroll();
      }

      // Track first banner impression
      if (_banners.isNotEmpty) {
        _trackImpression(_banners[0]['id']);
      }
    } catch (e) {
      debugPrint('PromotionalCarousel load error: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  void _startAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = Timer.periodic(_autoScrollDuration, (_) {
      if (!mounted || _banners.isEmpty) return;

      final nextPage = (_currentPage + 1) % _banners.length;
      _pageController.animateToPage(
        nextPage,
        duration: _scrollAnimDuration,
        curve: Curves.easeInOut,
      );
    });
  }

  void _pauseAutoScroll() {
    _autoScrollTimer?.cancel();
  }

  void _resumeAutoScroll() {
    if (_banners.length > 1) {
      _startAutoScroll();
    }
  }

  // ── Tracking ─────────────────────────────────────────────
  Future<void> _trackImpression(String bannerId) async {
    if (_trackedImpressions.contains(bannerId)) return;
    _trackedImpressions.add(bannerId);

    try {
      await SupabaseConfig.client.rpc('track_banner_interaction', params: {
        'p_banner_id': bannerId,
        'p_interaction_type': 'impression',
      });
    } catch (_) {}
  }

  Future<void> _trackClick(String bannerId) async {
    try {
      await SupabaseConfig.client.rpc('track_banner_interaction', params: {
        'p_banner_id': bannerId,
        'p_interaction_type': 'click',
      });
    } catch (_) {}
  }

  // ── Navigation ───────────────────────────────────────────
  void _handleBannerTap(Map<String, dynamic> banner) {
    final linkType = banner['link_type'] as String? ?? 'none';
    final linkValue = banner['link_value'] as String?;
    final bannerId = banner['id'] as String;

    _trackClick(bannerId);

    if (linkType == 'none' || linkValue == null || linkValue.isEmpty) return;

    switch (linkType) {
      case 'machine':
        widget.onNavigateToMachine?.call(linkValue);
        break;
      case 'catalog':
        widget.onNavigateToCatalog?.call(linkValue);
        break;
      case 'url':
        _launchUrl(linkValue);
        break;
    }
  }

  Future<void> _launchUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Failed to launch URL: $e');
    }
  }

  // ── Season Helpers ───────────────────────────────────────
  IconData _getSeasonIcon(String? tag) {
    switch (tag) {
      case 'new_year':
        return Icons.celebration_rounded;
      case 'holiday':
        return Icons.card_giftcard_rounded;
      case 'mid_year':
        return Icons.local_offer_rounded;
      case 'special':
        return Icons.star_rounded;
      default:
        return Icons.campaign_rounded;
    }
  }

  Color _getSeasonColor(String? tag) {
    switch (tag) {
      case 'new_year':
        return const Color(0xFFE91E63);
      case 'holiday':
        return const Color(0xFFE53935);
      case 'mid_year':
        return const Color(0xFFFF9800);
      case 'special':
        return const Color(0xFF9C27B0);
      default:
        return Brand.royalBlue;
    }
  }

  // ── Build ────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // Don't render anything if loading or no banners
    if (_isLoading) return _buildShimmer();
    if (_banners.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 180,
          child: GestureDetector(
            onPanDown: (_) => _pauseAutoScroll(),
            onPanEnd: (_) => _resumeAutoScroll(),
            onPanCancel: () => _resumeAutoScroll(),
            child: PageView.builder(
              controller: _pageController,
              itemCount: _banners.length,
              onPageChanged: (index) {
                setState(() => _currentPage = index);
                _trackImpression(_banners[index]['id']);
              },
              itemBuilder: (context, index) {
                return _buildBannerItem(_banners[index], isDark);
              },
            ),
          ),
        ),
        if (_banners.length > 1) ...[
          const SizedBox(height: 12),
          _buildDotIndicators(isDark),
        ],
      ],
    );
  }

  // ── Banner Item ──────────────────────────────────────────
  Widget _buildBannerItem(Map<String, dynamic> banner, bool isDark) {
    final title = banner['title'] as String? ?? '';
    final subtitle = banner['subtitle'] as String?;
    final imageUrl = banner['image_url'] as String? ?? '';
    final seasonTag = banner['season_tag'] as String?;
    final linkType = banner['link_type'] as String? ?? 'none';
    final hasLink = linkType != 'none' &&
        banner['link_value'] != null &&
        (banner['link_value'] as String).isNotEmpty;

    return GestureDetector(
      onTap: () => _handleBannerTap(banner),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: isDark ? null : [
            BoxShadow(
              color: Brand.royalBlue.withAlpha(31),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ── Background Image ──
              CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  color:
                      isDark ? Brand.darkCardElevated : Brand.royalBlueSurface,
                  child: Center(
                    child: Icon(
                      Icons.image_rounded,
                      size: 40,
                      color:
                          isDark ? Brand.darkTextTertiary : Brand.subtleLight,
                    ),
                  ),
                ),
                errorWidget: (_, __, ___) => Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isDark
                          ? [Brand.royalBlueDark, Brand.darkCard]
                          : [Brand.royalBlue, Brand.royalBlueLight],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      _getSeasonIcon(seasonTag),
                      size: 48,
                      color: Colors.white.withAlpha(((0.3) * 255).toInt()),
                    ),
                  ),
                ),
              ),

              // ── Gradient Overlay ──
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withAlpha(((0.1) * 255).toInt()),
                      Colors.black.withAlpha(((0.65) * 255).toInt()),
                    ],
                    stops: const [0.3, 0.55, 1.0],
                  ),
                ),
              ),

              // ── Season Tag Badge ──
              if (seasonTag != null)
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _getSeasonColor(seasonTag).withAlpha(((0.9) * 255).toInt()),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: _getSeasonColor(seasonTag).withAlpha(((0.4) * 255).toInt()),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_getSeasonIcon(seasonTag),
                            size: 12, color: Colors.white),
                        const SizedBox(width: 4),
                        Text(
                          _getSeasonLabel(seasonTag),
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // ── Link Indicator ──
              if (hasLink)
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(((0.2) * 255).toInt()),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.arrow_forward_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),

              // ── Text Content ──
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        height: 1.2,
                        shadows: [
                          Shadow(
                            color: Colors.black45,
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null && subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withAlpha(((0.85) * 255).toInt()),
                          height: 1.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getSeasonLabel(String? tag) {
    switch (tag) {
      case 'new_year':
        return 'NEW YEAR';
      case 'holiday':
        return 'HOLIDAY';
      case 'mid_year':
        return 'MID-YEAR';
      case 'special':
        return 'SPECIAL';
      default:
        return 'PROMO';
    }
  }

  // ── Dot Indicators ───────────────────────────────────────
  Widget _buildDotIndicators(bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_banners.length, (index) {
        final isActive = index == _currentPage;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: isActive ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: isActive
                ? (isDark ? Brand.darkIconActive : Brand.royalBlue)
                : (isDark
                    ? Brand.darkBorderLight
                    : Brand.subtleLight.withAlpha(((0.3) * 255).toInt())),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }

  // ── Shimmer Loading ──────────────────────────────────────
  Widget _buildShimmer() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        height: 180,
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? Brand.darkCard
              : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(20),
        ),
        child: _ShimmerEffect(
          baseColor: Theme.of(context).brightness == Brightness.dark
              ? Brand.darkBorderLight
              : Brand.subtleLight,
        ),
      ),
    );
  }
}

// ── Shimmer Effect Widget ──────────────────────────────────
class _ShimmerEffect extends StatefulWidget {
  final Color baseColor;
  const _ShimmerEffect({required this.baseColor});

  @override
  State<_ShimmerEffect> createState() => _ShimmerEffectState();
}

class _ShimmerEffectState extends State<_ShimmerEffect>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final value = _controller.value;
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(-1 + 2 * value, 0),
              end: Alignment(-1 + 2 * value + 1, 0),
              colors: [
                widget.baseColor.withAlpha(((0.05) * 255).toInt()),
                widget.baseColor.withAlpha(((0.15) * 255).toInt()),
                widget.baseColor.withAlpha(((0.05) * 255).toInt()),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
          ),
        );
      },
    );
  }
}
