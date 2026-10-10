// Online tab: exchange rates, nearby place shortcuts, and a news preview.

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:waffr/data/models/exchange_rate.dart';
import 'package:waffr/data/models/nearby_place_category.dart';
import 'package:waffr/data/models/news_article.dart';
import 'package:waffr/data/services/online_feed_service.dart';
import 'package:waffr/data/services/profile_identity.dart';
import 'package:waffr/core/sync/sync_service.dart';
import 'package:waffr/core/theme/app_palette.dart';
import 'package:waffr/core/utils/app_feedback.dart';
import 'package:waffr/core/utils/money.dart';
import 'package:waffr/screens/offline/login/login_screen.dart';
import 'package:waffr/screens/online/sheets/news_sheet.dart';
import 'package:waffr/widgets/button/glass_button.dart';
import 'package:waffr/widgets/containers/glass.dart';
import 'package:waffr/widgets/containers/glass_sheet.dart';

final NumberFormat _rateFormat = NumberFormat('#,##0.##', 'en');

// Hosts the three online cards and refreshes news when the app resumes.
// Guests see the cards behind a sign-in overlay; nothing is fetched for them.
class OnlineScreen extends StatefulWidget {
  const OnlineScreen({super.key});

  @override
  State<OnlineScreen> createState() => _OnlineScreenState();
}

// loading / ready / empty / error for the news preview card.
enum _NewsLoadState { loading, ready, empty, error }

class _OnlineScreenState extends State<OnlineScreen>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  String _selectedAsset = 'USD';
  List<NewsArticle> _articles = const [];
  _NewsLoadState _newsState = _NewsLoadState.loading;
  bool _newsRequestInFlight = false;
  final ProfileIdentity _identity = ProfileIdentity.instance;
  bool _wasSignedIn = false;

  @override
  bool get wantKeepAlive => true;

  bool get _signedIn => _identity.isLoaded && _identity.isLoggedIn;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _identity.addListener(_onIdentityChanged);
    _identity.ensureLoaded();
    _wasSignedIn = _signedIn;
    if (_wasSignedIn) _loadNews();
  }

  @override
  void dispose() {
    _identity.removeListener(_onIdentityChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadNews();
    }
  }

  // Loads the feed the moment the user is known to be signed in.
  void _onIdentityChanged() {
    final signedIn = _signedIn;
    if (signedIn && !_wasSignedIn) _loadNews();
    _wasSignedIn = signedIn;
    if (mounted) setState(() {});
  }

  // Same login route as Settings; the overlay lifts once sign-in succeeds.
  Future<void> _openLogin() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LoginScreen(
          allowGuest: false,
          popOnSuccess: true,
          onCompleted: () async {
            await SyncService.instance.syncNow();
          },
        ),
      ),
    );
    await _identity.reload();
  }

  // Fetches headlines; keeps prior articles on failure if we already had some.
  Future<void> _loadNews() async {
    if (!_signedIn) return;
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

  // Retry on error; otherwise open the full news sheet.
  void _onNewsTap() {
    if (_newsState == _NewsLoadState.error) {
      _loadNews();
      return;
    }
    showNewsSheet(context, articles: _articles);
  }

  // Opens Google Maps for the category; snacks if the URL launch fails.
  Future<void> _openPlace(NearbyPlaceCategory category) async {
    final opened = await openNearbyPlaceSearch(category);
    if (opened || !mounted) return;

    showAppSnackBar(context, 'تعذّر فتح خرائط Google');
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final locked = _identity.isLoaded && !_identity.isLoggedIn;

    final content = SingleChildScrollView(
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
            articles: _articles,
            state: _newsState,
            onTap: _newsState == _NewsLoadState.loading ? null : _onNewsTap,
          ),
        ],
      ),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        AbsorbPointer(
          absorbing: locked,
          child: ExcludeSemantics(excluding: locked, child: content),
        ),
        IgnorePointer(
          ignoring: !locked,
          child: AnimatedOpacity(
            opacity: locked ? 1 : 0,
            duration: const Duration(milliseconds: 360),
            curve: Curves.easeOutCubic,
            child: _SignInGate(onLogin: _openLogin),
          ),
        ),
      ],
    );
  }
}

// Frosted cover over the online cards for guests, with a sign-in action.
class _SignInGate extends StatelessWidget {
  final VoidCallback onLogin;

  const _SignInGate({required this.onLogin});

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
        child: ColoredBox(
          color: colors.background.withValues(alpha: 0.55),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: GlassContainer(
                colorType: GlassColorType.surface,
                tintOpacity: 1,
                borderRadius: 28,
                padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: colors.accent.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.public_rounded,
                          size: 28,
                          color: colors.accent,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'سجّل الدخول لاستخدام الميزات التي تحتاج إلى الإنترنت.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Outfit',
                        fontFamilyFallback: const ['Tajawal'],
                        fontSize: 16,
                        height: 1.5,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 18),
                    GlassButton(
                      onTap: onLogin,
                      colorType: GlassColorType.accent,
                      tintOpacity: 1,
                      borderRadius: 20,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      child: Text(
                        'تسجيل الدخول',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Outfit',
                          fontFamilyFallback: const ['Tajawal'],
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          color: colors.onAccent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Buy/sell rates for the selected FX asset, with an overlay currency picker.
class _ExchangeRateCard extends StatefulWidget {
  final ExchangeRate rate;
  final ValueChanged<String> onSelected;

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

  // Anchors an animated overlay menu under the pair label.
  void _showMenu() {
    if (_menuOpen || _closingMenu) return;

    final colors = AppPalette.of(context);
    final overlay = Overlay.of(context);
    final direction = Directionality.of(context);

    _menuEntry = OverlayEntry(
      builder: (context) {
        return _CurrencyMenuLayer(
          key: _menuKey,
          link: _menuLink,
          direction: direction,
          colors: colors,
          selected: widget.rate.code,
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

  // Plays the collapse animation, then removes the overlay entry.
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
    final colors = AppPalette.of(context);
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
              fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
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
                        key: ValueKey(rate.code),
                        style: TextStyle(
                          fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
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
                  valueKey: '${rate.code}-buy',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _RateValue(
                  label: 'بيع',
                  value: rate.sell,
                  colors: colors,
                  valueKey: '${rate.code}-sell',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Overlay dropdown listing available exchange assets.
class _CurrencyMenuLayer extends StatefulWidget {
  final LayerLink link;
  final TextDirection direction;
  final AppPalette colors;
  final String selected;
  final VoidCallback onDismiss;
  final ValueChanged<String> onSelected;

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
                    constraints: const BoxConstraints(
                      minWidth: 220,
                      maxWidth: 280,
                      maxHeight: 360,
                    ),
                    child: GlassContainer(
                      colorType: GlassColorType.surface,
                      tintOpacity: 1,
                      borderRadius: 22,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: OnlineFeedService.rates.length,
                        separatorBuilder: (context, index) => Divider(
                          height: 1,
                          thickness: 1,
                          indent: 14,
                          endIndent: 14,
                          color: widget.colors.textSecondary
                              .withValues(alpha: 0.12),
                        ),
                        itemBuilder: (context, i) {
                          final start =
                              i / OnlineFeedService.rates.length * 0.35;
                          return _CurrencyOption(
                            option: OnlineFeedService.rates[i],
                            selected:
                                OnlineFeedService.rates[i].code ==
                                widget.selected,
                            colors: widget.colors,
                            animation: CurvedAnimation(
                              parent: _controller,
                              curve: Interval(
                                start,
                                (start + 0.65).clamp(0.0, 1.0).toDouble(),
                                curve: Curves.easeOutCubic,
                              ),
                            ),
                            onTap: () => widget.onSelected(
                              OnlineFeedService.rates[i].code,
                            ),
                          );
                        },
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

// One currency row inside the exchange-rate overlay menu.
class _CurrencyOption extends StatelessWidget {
  final ExchangeRate option;
  final bool selected;
  final AppPalette colors;
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
                    option.code.length == 3
                        ? '${option.pairLabel} · ${option.code}'
                        : option.pairLabel,
                    style: TextStyle(
                      fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
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

// Buy or sell figure with a crossfade when the selected asset changes.
class _RateValue extends StatelessWidget {
  final String label;
  final double? value;
  final AppPalette colors;
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
              fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
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
                value == null
                    ? ExchangeRate.unavailable
                    : _rateFormat.format(value),
                key: ValueKey(valueKey),
                style: TextStyle(
                  fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: colors.accent,
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            sypCurrencyLabel,
            style: TextStyle(
              fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
              fontSize: 12,
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// Grid of nearby-place categories that launch Google Maps searches.
class _NearbyPlacesCard extends StatelessWidget {
  final ValueChanged<NearbyPlaceCategory> onOpen;

  const _NearbyPlacesCard({required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);

    return GlassContainer(
      colorType: GlassColorType.surface,
      borderRadius: 28,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'مواقع قريبة',
            style: TextStyle(
              fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
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
                          fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
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

// Headline teaser. Swipe up or down on the headline to move between articles
// without leaving the tab; tap opens the full news sheet (or retries on error).
class _NewsPreviewCard extends StatefulWidget {
  final List<NewsArticle> articles;
  final _NewsLoadState state;
  final VoidCallback? onTap;

  const _NewsPreviewCard({
    required this.articles,
    required this.state,
    required this.onTap,
  });

  @override
  State<_NewsPreviewCard> createState() => _NewsPreviewCardState();
}

class _NewsPreviewCardState extends State<_NewsPreviewCard> {
  // Title (3 lines) plus the source row.
  static const double _pageHeight = 108;

  final PageController _pages = PageController();
  int _index = 0;

  @override
  void didUpdateWidget(covariant _NewsPreviewCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final count = widget.articles.length;
    if (count == 0) {
      _index = 0;
    } else if (_index >= count) {
      _index = count - 1;
      if (_pages.hasClients) _pages.jumpToPage(_index);
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  // At the first or last article, the drag keeps scrolling the tab instead.
  bool _forwardOverscroll(OverscrollNotification notification) {
    if (notification.dragDetails == null) return false;
    final outer = Scrollable.maybeOf(context)?.position;
    if (outer == null) return false;
    final target = (outer.pixels + notification.overscroll).clamp(
      outer.minScrollExtent,
      outer.maxScrollExtent,
    );
    if (target != outer.pixels) outer.jumpTo(target);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final ready =
        widget.state == _NewsLoadState.ready && widget.articles.isNotEmpty;
    final count = widget.articles.length;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
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
                      'الأخبار',
                      style: TextStyle(
                        fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  if (ready && count > 1)
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: Text(
                        '${_index + 1} / $count',
                        key: ValueKey(_index),
                        textDirection: TextDirection.ltr,
                        style: TextStyle(
                          fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.keyboard_arrow_up_rounded,
                    color: colors.textSecondary,
                  ),
                ],
              ),
              const SizedBox(height: 17),
              if (ready)
                SizedBox(
                  height: _pageHeight,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: NotificationListener<OverscrollNotification>(
                          onNotification: _forwardOverscroll,
                          child: PageView.builder(
                            controller: _pages,
                            scrollDirection: Axis.vertical,
                            physics: const PageScrollPhysics(
                              parent: ClampingScrollPhysics(),
                            ),
                            itemCount: count,
                            onPageChanged: (index) =>
                                setState(() => _index = index),
                            itemBuilder: (context, index) => _NewsHeadline(
                              article: widget.articles[index],
                              colors: colors,
                            ),
                          ),
                        ),
                      ),
                      if (count > 1) ...[
                        const SizedBox(width: 10),
                        _NewsPageDots(
                          controller: _pages,
                          count: count,
                          activeColor: colors.accent,
                          inactiveColor:
                              colors.textSecondary.withValues(alpha: 0.35),
                        ),
                      ],
                    ],
                  ),
                )
              else
                _NewsStatus(state: widget.state, colors: colors),
            ],
          ),
        ),
      ),
    );
  }
}

// One article in the swipeable preview: title, source and time.
class _NewsHeadline extends StatelessWidget {
  final NewsArticle article;
  final AppPalette colors;

  const _NewsHeadline({required this.article, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Text(
            article.title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
              height: 1.55,
              color: colors.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                article.source,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: colors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${formatDate(article.publishedAt)} · ${formatTime(article.publishedAt)}',
              style: TextStyle(
                fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
                fontSize: 11.5,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// Vertical page marks beside the headline, like the balance-card currency
// dots. Long feeds show a window of marks around the current article.
class _NewsPageDots extends StatelessWidget {
  static const int _maxDots = 7;

  final PageController controller;
  final int count;
  final Color activeColor;
  final Color inactiveColor;

  const _NewsPageDots({
    required this.controller,
    required this.count,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final page = controller.hasClients
            ? (controller.page ?? controller.initialPage.toDouble())
            : controller.initialPage.toDouble();
        final visible = count < _maxDots ? count : _maxDots;
        final first = (page.round() - visible ~/ 2).clamp(0, count - visible);

        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = first; i < first + visible; i++)
              Builder(
                builder: (context) {
                  final selected = 1 - (page - i).abs().clamp(0.0, 1.0);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.5),
                    child: Container(
                      width: 5,
                      height: 5 + 11 * selected,
                      decoration: BoxDecoration(
                        color: Color.lerp(inactiveColor, activeColor, selected),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  );
                },
              ),
          ],
        );
      },
    );
  }
}

// Loading spinner or empty/error copy inside the news preview card.
class _NewsStatus extends StatelessWidget {
  final _NewsLoadState state;
  final AppPalette colors;

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
        ? 'تعذّر تحميل الأخبار'
        : 'لا توجد أخبار حالياً';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          message,
          style: TextStyle(
            fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
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
              fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
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
