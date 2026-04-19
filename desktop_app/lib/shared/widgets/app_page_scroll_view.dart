import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

class AppPageScrollView extends StatelessWidget {
  const AppPageScrollView({
    super.key,
    required this.children,
    this.maxWidth = AppWidth.content,
    this.padding = const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.lg, AppSpace.xxl),
    this.physics = const AlwaysScrollableScrollPhysics(),
  });

  final List<Widget> children;
  final double maxWidth;
  final EdgeInsetsGeometry padding;
  final ScrollPhysics physics;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        IgnorePointer(
          child: Stack(
            children: const [
              Positioned(
                top: -96,
                right: -56,
                child: _BackdropOrb(
                  size: 260,
                  colors: <Color>[AppColors.brandSoft, Color(0x00F2DEC8)],
                ),
              ),
              Positioned(
                top: 220,
                left: -40,
                child: _BackdropOrb(
                  size: 180,
                  colors: <Color>[AppColors.warningSoft, Color(0x00F7E7CD)],
                ),
              ),
              Positioned(
                bottom: -110,
                right: 30,
                child: _BackdropOrb(
                  size: 240,
                  colors: <Color>[AppColors.successSoft, Color(0x00DDE8DD)],
                ),
              ),
            ],
          ),
        ),
        ListView(
          physics: physics,
          padding: padding,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _BackdropOrb extends StatelessWidget {
  const _BackdropOrb({
    required this.size,
    required this.colors,
  });

  final double size;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: colors),
      ),
    );
  }
}
