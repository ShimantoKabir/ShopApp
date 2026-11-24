import 'package:material_ui/material_ui.dart';

import '../../core/bangla.dart';

/// The app's logo (a hammer and a wrench). If the picture cannot be loaded, a
/// plain shop icon is shown instead, so a screen never breaks over it.
class AppLogo extends StatelessWidget {
  final double size;
  const AppLogo({super.key, this.size = 64});

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.22),
        child: Image.asset(
          'assets/branding/logo.png',
          width: size,
          height: size,
          semanticLabel: Bn.appTitle,
          errorBuilder: (context, error, stack) => SizedBox(
            width: size,
            height: size,
            child: Icon(Icons.storefront, size: size * 0.8, color: Theme.of(context).colorScheme.primary),
          ),
        ),
      );
}
