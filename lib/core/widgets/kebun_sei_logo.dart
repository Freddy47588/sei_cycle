import 'package:flutter/material.dart';

/// Displays the original Kebun Sei artwork without its transparent margins.
/// The asset itself stays intact; the crop contains every nontransparent pixel.
class KebunSeiLogo extends StatelessWidget {
  const KebunSeiLogo({required this.size, super.key});

  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Logo Kebun Sei',
    image: true,
    child: SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
        child: Padding(
          padding: EdgeInsets.all(size * 0.04),
          child: FittedBox(
            fit: BoxFit.contain,
            child: ClipRect(
              child: Align(
                // Source: 210 x 148; visible bounds: (29, 6)–(177, 147).
                alignment: const Alignment(-4 / 62, 5 / 7),
                widthFactor: 148 / 210,
                heightFactor: 141 / 148,
                child: Image.asset(
                  'lib/assets/logo.png',
                  width: 210,
                  height: 148,
                  excludeFromSemantics: true,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
