import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// One destination in [IosStyleBottomNavBar].
class IosNavBarItem {
  const IosNavBarItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.semanticLabel,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final String semanticLabel;
}

/// Floating iOS-style bottom tab bar — visual parity with iOS `MainTabView`.
///
/// Unlike Material 3's [NavigationBar] (whose per-destination indicator
/// fades/scales in place rather than travelling across the bar), this widget
/// measures each destination's rendered bounds via [GlobalKey] and slides a
/// single white capsule between them with [AnimatedPositioned].
class IosStyleBottomNavBar extends StatefulWidget {
  const IosStyleBottomNavBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final List<IosNavBarItem> items;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  State<IosStyleBottomNavBar> createState() => _IosStyleBottomNavBarState();
}

class _IosStyleBottomNavBarState extends State<IosStyleBottomNavBar> {
  static const _slideDuration = Duration(milliseconds: 260);
  static const _slideCurve = Curves.easeOutCubic;

  final _stackKey = GlobalKey();
  List<GlobalKey> _itemKeys = const [];
  Rect? _capsuleRect;

  @override
  void initState() {
    super.initState();
    _itemKeys = List.generate(widget.items.length, (_) => GlobalKey());
    _scheduleMeasure();
  }

  @override
  void didUpdateWidget(covariant IosStyleBottomNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.length != widget.items.length) {
      _itemKeys = List.generate(widget.items.length, (_) => GlobalKey());
    }
    _scheduleMeasure();
  }

  void _scheduleMeasure() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  void _measure() {
    if (!mounted || widget.selectedIndex >= _itemKeys.length) return;
    final stackBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    final itemBox = _itemKeys[widget.selectedIndex].currentContext
        ?.findRenderObject() as RenderBox?;
    if (stackBox == null ||
        itemBox == null ||
        !stackBox.hasSize ||
        !itemBox.attached) {
      return;
    }
    final origin = itemBox.localToGlobal(Offset.zero, ancestor: stackBox);
    final rect = origin & itemBox.size;
    if (rect != _capsuleRect) {
      setState(() => _capsuleRect = rect);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Destinations can change size (rotation, split-screen, item count) —
    // re-measure the capsule after every layout pass rather than hardcoding
    // a breakpoint.
    _scheduleMeasure();

    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = _needsCompactLabels(constraints.maxWidth);
            return Stack(
              key: _stackKey,
              alignment: Alignment.center,
              children: [
                if (_capsuleRect != null)
                  AnimatedPositioned(
                    duration: _slideDuration,
                    curve: _slideCurve,
                    left: _capsuleRect!.left,
                    top: _capsuleRect!.top,
                    width: _capsuleRect!.width,
                    height: _capsuleRect!.height,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius:
                            BorderRadius.circular(_capsuleRect!.height / 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: List.generate(widget.items.length, (i) {
                    final selected = i == widget.selectedIndex;
                    return _NavBarButton(
                      key: _itemKeys[i],
                      item: widget.items[i],
                      selected: selected,
                      showLabel: !compact || selected,
                      onTap: () => widget.onDestinationSelected(i),
                    );
                  }),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// True when the sum of each destination's natural width (icon + label)
  /// would exceed the available bar width — computed from real text/icon
  /// metrics rather than a fixed screen-width breakpoint, so it adapts to
  /// any item count, label length, or device size.
  bool _needsCompactLabels(double maxWidth) {
    final textDirection = Directionality.of(context);
    double total = 0;
    for (final item in widget.items) {
      final painter = TextPainter(
        text: TextSpan(text: item.label, style: _NavBarButton.labelStyle(true)),
        textDirection: textDirection,
        maxLines: 1,
      )..layout();
      total += _NavBarButton.horizontalPadding * 2 +
          (painter.width > _NavBarButton.iconSize
              ? painter.width
              : _NavBarButton.iconSize);
      painter.dispose();
    }
    return total > maxWidth;
  }
}

class _NavBarButton extends StatelessWidget {
  const _NavBarButton({
    super.key,
    required this.item,
    required this.selected,
    required this.showLabel,
    required this.onTap,
  });

  final IosNavBarItem item;
  final bool selected;
  final bool showLabel;
  final VoidCallback onTap;

  static const double iconSize = 24;
  static const double horizontalPadding = 14;
  static const double verticalPadding = 8;
  static const _selectedColor = AppColors.primary;
  static const _unselectedColor = Colors.black;
  static const _colorDuration = Duration(milliseconds: 200);

  static TextStyle labelStyle(bool selected) => TextStyle(
        fontSize: 11,
        height: 1.0,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        color: selected ? _selectedColor : _unselectedColor,
      );

  @override
  Widget build(BuildContext context) {
    final color = selected ? _selectedColor : _unselectedColor;
    return Semantics(
      label: item.semanticLabel,
      selected: selected,
      button: true,
      child: Material(
        color: Colors.transparent,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: verticalPadding,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSwitcher(
                  duration: _colorDuration,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(scale: animation, child: child),
                  ),
                  child: Icon(
                    selected ? item.selectedIcon : item.icon,
                    key: ValueKey(selected),
                    size: iconSize,
                    color: color,
                  ),
                ),
                if (showLabel) ...[
                  const SizedBox(height: 3),
                  AnimatedDefaultTextStyle(
                    duration: _colorDuration,
                    style: labelStyle(selected),
                    child: Text(item.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
