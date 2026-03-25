import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

class AppPageScrollView extends StatelessWidget {
  const AppPageScrollView({
    super.key,
    required this.children,
    this.maxWidth = AppWidth.content,
    this.padding = const EdgeInsets.all(AppSpace.lg),
    this.physics = const AlwaysScrollableScrollPhysics(),
  });

  final List<Widget> children;
  final double maxWidth;
  final EdgeInsetsGeometry padding;
  final ScrollPhysics physics;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: physics,
      padding: padding,
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
    );
  }
}
