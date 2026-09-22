import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:waffer/core/data/exchange_rate.dart';
import 'package:waffer/core/data/nearby_place_category.dart';
import 'package:waffer/core/data/news_article.dart';
import 'package:waffer/core/data/online_feed_service.dart';
import 'package:waffer/core/theme/app_color.dart';
import 'package:waffer/core/utils/money.dart';
import 'package:waffer/screens/online/sheets/news_sheet.dart';
import 'package:waffer/widgets/button/glass_button.dart';
import 'package:waffer/widgets/containers/glass.dart';
import 'package:waffer/widgets/containers/glass_sheet.dart';

final NumberFormat _rateFormat = NumberFormat('#,##0.##', 'en');

class OnlineScreen extends StatefulWidget {
  const OnlineScreen({super.key});

  @override
  State<OnlineScreen> createState() => _OnlineScreenState();
}

enum _NewsLoadState { loading, ready, empty, error }

class _OnlineScreenState extends State<OnlineScreen>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  ExchangeAsset _selectedAsset = ExchangeAsset.usd;
  List<NewsArticle> _articles = const [];
  _NewsLoadState _newsState = _NewsLoadState.loading;
  bool _newsRequestInFlight = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadNews();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadNews();
    }
  }

  Future<void> _loadNews() async {
    if (_newsRequestInFlight) return;
    _newsRequestInFlight = true;
    final showLoading = _articles.isEmpty;
    if (showLoading && mounted) {
      setState(() => _newsState = _NewsLoadState.loading);
    }

    try {
      final articles = await OnlineFeedService.instance.fetchArticles();
      if (!mounted) return;
      setState(() {
        _articles = articles;
        _newsState =
            articles.isEmpty ? _NewsLoadState.empty : _NewsLoadState.ready;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _newsState =
            _articles.isEmpty ? _NewsLoadState.error : _NewsLoadState.ready;
      });
    } finally {
      _newsRequestInFlight = false;
    }
  }

  void _onNewsTap() {
    if (_newsState == _NewsLoadState.error) {
      _loadNews();
      return;
    }
    showNewsSheet(context, articles: _articles);
  }

  Future<void> _openPlace(NearbyPlaceCategory category) async {
    final opened = await openNearbyPlaceSearch(category);
    if (opened || !mounted) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'تعذر فتح خرائط Google',
          style: TextStyle(fontFamily: 'Tajawal'),
        ),
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ExchangeRateCard(
            rate: OnlineFeedService.rateFor(_selectedAsset),
            onSelected: (asset) => setState(() => _selectedAsset = asset),
          ),
          const SizedBox(height: 6),
          _NearbyPlacesCard(onOpen: _openPlace),
          const SizedBox(height: 6),
          _NewsPreviewCard(
            article: _articles.isEmpty ? null : _articles.first,
            state: _newsState,
            onTap: _newsState == _NewsLoadState.loading ? null : _onNewsTap,
          ),
        ],
      ),
    );
  }
}

class _OnlineColors {
  final Color accent;
  final Color textPrimary;
  final Color textSecondary;

  const _OnlineColors({
    required this.accent,
    required this.textPrimary,
    required this.textSecondary,
  });

  factory _OnlineColors.of(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return _OnlineColors(
      accent: isDark ? AppColors.darkAccent : AppColors.lightAccent,
      textPrimary:
          isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
      textSecondary:
          isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
    );
  }
}

class _ExchangeRateCard extends StatefulWidget {
  final ExchangeRate rate;
  final ValueChanged<ExchangeAsset> onSelected;

  const _ExchangeRateCard({
    required this.rate,
    required this.onSelected,
  });

  @override
  State<_ExchangeRateCard> createState() => _ExchangeRateCardState();
}

class _ExchangeRateCardState extends State<_ExchangeRateCard> {
  final LayerLink _menuLink = LayerLink();
  final GlobalKey<_CurrencyMenuLayerState> _menuKey = GlobalKey();
  OverlayEntry? _menuEntry;
  bool _menuOpen = false;
  bool _closingMenu = false;

  @override
  void dispose() {
    _menuEntry?.remove();
    _menuEntry = null;
    super.dispose();
  }

  void _toggleMenu() {
    if (_menuOpen) {
      _hideMenu();
    } else {
      _showMenu();
    }
  }

  void _showMenu() {
    if (_menuOpen || _closingMenu) return;

    final colors = _OnlineColors.of(context);
    final overlay = Overlay.of(context);
    final direction = Directionality.of(context);

    _menuEntry = OverlayEntry(
      builder: (context) {
        return _CurrencyMenuLayer(
          key: _menuKey,
          link: _menuLink,
          direction: direction,
          colors: colors,
          selected: widget.rate.asset,
          onDismiss: _hideMenu,
          onSelected: (asset) {
            widget.onSelected(asset);
            _hideMenu();
          },
        );
      },
    );

    overlay.insert(_menuEntry!);
    setState(() => _menuOpen = true);
  }

  Future<void> _hideMenu() async {
    if (!_menuOpen || _closingMenu) return;
    _closingMenu = true;
    await _menuKey.currentState?.collapse();
    _menuEntry?.remove();
    _menuEntry = null;
    _closingMenu = false;
    if (mounted) {
      setState(() => _menuOpen = false);
    } else {
      _menuOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = _OnlineColors.of(context);
    final rate = widget.rate;

    return GlassContainer(
      colorType: GlassColorType.surface,
      borderRadius: 28,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'سعر الصرف',
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 13,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          CompositedTransformTarget(
            link: _menuLink,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleMenu,
              child: Row(
                children: [
                  Flexible(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 280),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.18),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        );
                      },
                      child: Text(
                        'الليرة السورية · ${rate.pairLabel}',
                        key: ValueKey(rate.asset),
                        style: TextStyle(
                          fontFamily: 'Tajawal',
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: _menuOpen ? 0.5 : 0,
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOutBack,
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: colors.accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _RateValue(
                  label: 'شراء',
                  value: rate.buy,
                  colors: colors,
                  valueKey: '${rate.asset}-buy',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _RateValue(
                  label: 'بيع',
                  value: rate.sell,
                  colors: colors,
                  valueKey: '${rate.asset}-sell',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CurrencyMenuLayer extends StatefulWidget {
  final LayerLink link;
  final TextDirection direction;
  final _OnlineColors colors;
  final ExchangeAsset selected;
  final VoidCallback onDismiss;
  final ValueChanged<ExchangeAsset> onSelected;

  const _CurrencyMenuLayer({
    super.key,
    required this.link,
    required this.direction,
    required this.colors,
    required this.selected,
    required this.onDismiss,
    required this.onSelected,
  });

  @override
  State<_CurrencyMenuLayer> createState() => _CurrencyMenuLayerState();
}

class _CurrencyMenuLayerState extends State<_CurrencyMenuLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      reverseDuration: const Duration(milliseconds: 200),
    );
    final curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _fade = curve;
    _scale = Tween<double>(begin: 0.92, end: 1).animate(curve);
    _slide = Tween<Offset>(
      begin: const Offset(0, -0.06),
      end: Offset.zero,
    ).animate(curve);
    _controller.forward();
  }

  Future<void> collapse() => _controller.reverse();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: widget.onDismiss,
          ),
        ),
        CompositedTransformFollower(
          link: widget.link,
          showWhenUnlinked: false,
          targetAnchor:
              AlignmentDirectional.bottomStart.resolve(widget.direction),
          followerAnchor: AlignmentDirectional.topStart.resolve(widget.direction),
          offset: const Offset(0, 8),
          child: FadeTransition(
            opacity: _fade,
            child: SlideTransition(
              position: _slide,
              child: ScaleTransition(
                scale: _scale,
                alignment: AlignmentDirectional.topStart.resolve(widget.direction),
                child: Material(
                  color: Colors.transparent,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 220, maxWidth: 280),
                    child: GlassContainer(
                      colorType: GlassColorType.surface,
                      tintOpacity: 1,
                      borderRadius: 22,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < OnlineFeedService.rates.length; i++) ...[
                            if (i > 0)
                              Divider(
                                height: 1,
                                thickness: 1,
                                indent: 14,
                                endIndent: 14,
                                color: widget.colors.textSecondary
                                    .withValues(alpha: 0.12),
                              ),
                            _CurrencyOption(
                              option: OnlineFeedService.rates[i],
                              selected:
                                  OnlineFeedService.rates[i].asset ==
                                  widget.selected,
                              colors: widget.colors,
                              animation: CurvedAnimation(
                                parent: _controller,
                                curve: Interval(
                                  0.18 + (i * 0.12),
                                  1,
                                  curve: Curves.easeOutCubic,
                                ),
                              ),
                              onTap: () => widget.onSelected(
                                OnlineFeedService.rates[i].asset,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CurrencyOption extends StatelessWidget {
  final ExchangeRate option;
  final bool selected;
  final _OnlineColors colors;
  final Animation<double> animation;
  final VoidCallback onTap;

  const _CurrencyOption({
    required this.option,
    required this.selected,
    required this.colors,
    required this.animation,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.08, 0),
          end: Offset.zero,
        ).animate(animation),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    option.pairLabel,
                    style: TextStyle(
                      fontFamily: 'Tajawal',
                      fontSize: 15,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      color: selected ? colors.accent : colors.textPrimary,
                    ),
                  ),
                ),
                if (selected)
                  Icon(Icons.check_rounded, size: 18, color: colors.accent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RateValue extends StatelessWidget {
  final String label;
  final double value;
  final _OnlineColors colors;
  final String valueKey;

  const _RateValue({
    required this.label,
    required this.value,
    required this.colors,
    required this.valueKey,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: sheetFieldColor(context),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.22),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: Text(
                _rateFormat.format(value),
                key: ValueKey(valueKey),
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: colors.accent,
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            currencyLabel,
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 12,
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _NearbyPlacesCard extends StatelessWidget {
  final ValueChanged<NearbyPlaceCategory> onOpen;

  const _NearbyPlacesCard({required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final colors = _OnlineColors.of(context);

    return GlassContainer(
      colorType: GlassColorType.surface,
      borderRadius: 28,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'مواقع قريبة:',
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: nearbyPlaceCategories.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              childAspectRatio: 3.1,
            ),
            itemBuilder: (context, index) {
              final category = nearbyPlaceCategories[index];
              return GlassButton(
                onTap: () => onOpen(category),
                colorType: GlassColorType.background,
                borderRadius: 16,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(
                  children: [
                    Icon(category.icon, size: 18, color: colors.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        category.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Tajawal',
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _NewsPreviewCard extends StatelessWidget {
  final NewsArticle? article;
  final _NewsLoadState state;
  final VoidCallback? onTap;

  const _NewsPreviewCard({
    required this.article,
    required this.state,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = _OnlineColors.of(context);
    final item = state == _NewsLoadState.ready ? article : null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: GlassContainer(
          colorType: GlassColorType.surface,
          borderRadius: 28,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'الأخبار:',
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.keyboard_arrow_up_rounded,
                    color: colors.textSecondary,
                  ),
                ],
              ),
              const SizedBox(height:17),
              if (item != null) ...[
                Text(
                  item.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    height: 1.55,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.source,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Tajawal',
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${formatDate(item.publishedAt)} · ${formatTime(item.publishedAt)}',
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        fontSize: 11.5,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ] else
                _NewsStatus(state: state, colors: colors),
            ],
          ),
        ),
      ),
    );
  }
}

class _NewsStatus extends StatelessWidget {
  final _NewsLoadState state;
  final _OnlineColors colors;

  const _NewsStatus({
    required this.state,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    if (state == _NewsLoadState.loading) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            color: colors.accent,
          ),
        ),
      );
    }

    final message = state == _NewsLoadState.error
        ? 'تعذر تحميل الأخبار'
        : 'لا توجد أخبار حالياً';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          message,
          style: TextStyle(
            fontFamily: 'Tajawal',
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
            height: 1.55,
            color: colors.textSecondary,
          ),
        ),
        if (state == _NewsLoadState.error) ...[
          const SizedBox(height: 10),
          Text(
            'اضغط لإعادة المحاولة',
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}
