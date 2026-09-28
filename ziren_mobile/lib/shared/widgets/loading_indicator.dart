import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';

/// Centered loading spinner using Ziren brand colour.
class LoadingIndicator extends StatelessWidget {
  const LoadingIndicator({super.key, this.size = 32});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: size,
        height: size,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          valueColor: AlwaysStoppedAnimation<Color>(ZirenTokens.brandOrange),
        ),
      ),
    );
  }
}
