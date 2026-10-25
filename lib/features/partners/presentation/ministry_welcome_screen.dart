import 'package:flutter/material.dart';
import '../data/ministry_profile.dart';

class MinistryWelcomeScreen extends StatelessWidget {
  const MinistryWelcomeScreen({
    super.key,
    required this.profile,
    required this.onExplore,
    required this.onUtilities,
    required this.onAbout,
  });
  final MinistryProfile profile;
  final VoidCallback onExplore;
  final VoidCallback onUtilities;
  final VoidCallback onAbout;

  @override
  Widget build(BuildContext context) => Theme(
    data: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Color(profile.accentColorArgb),
        brightness: Brightness.light,
      ),
    ),
    child: Scaffold(
      backgroundColor: const Color(0xFFF8F1E1),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, viewport) {
            final width = viewport.maxWidth;
            final height = viewport.maxHeight;
            final isAdl = profile.id == MinistryProfile.adventDefenseLeague.id;
            final artwork = profile.artworkAsset;
            final footerStart = isAdl ? 1390.0 : 1360.0;
            final footerHeight = width * (1536 - footerStart) / 1024;
            final mainHeight = height - footerHeight;
            final controlBottom = (footerHeight - 48) / 2;

            final overlayStyle = TextButton.styleFrom(
              backgroundColor: const Color(0x99F8F1E1),
              foregroundColor: Color(profile.accentColorArgb),
              padding: const EdgeInsets.all(4),
              minimumSize: const Size(48, 48),
            );
            return Stack(
              fit: StackFit.expand,
              children: [
                if (artwork != null)
                  Semantics(
                    label: profile.name,
                    image: true,
                    // Scale the main scene to fill its space, but render the
                    // original attribution strip uniformly so its logo cannot warp.
                    child: Column(
                      children: [
                        SizedBox(
                          height: mainHeight,
                          width: width,
                          child: ClipRect(
                            child: OverflowBox(
                              alignment: Alignment.topCenter,
                              minHeight: 0,
                              maxHeight: double.infinity,
                              child: Image.asset(
                                artwork,
                                key: const Key('ministry-artwork-main'),
                                width: width,
                                height: mainHeight * 1536 / footerStart,
                                fit: BoxFit.fill,
                                excludeFromSemantics: true,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          height: footerHeight,
                          width: width,
                          child: ClipRect(
                            child: OverflowBox(
                              alignment: Alignment.bottomCenter,
                              minHeight: 0,
                              maxHeight: double.infinity,
                              child: Image.asset(
                                artwork,
                                key: const Key('ministry-artwork-attribution'),
                                width: width,
                                height: width * 1.5,
                                fit: BoxFit.fill,
                                excludeFromSemantics: true,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Center(child: Text(profile.name)),
                if (artwork != null)
                  Positioned(
                    left: width * .09,
                    right: width * .09,
                    top: mainHeight * (isAdl ? 1280 : 1228) / footerStart,
                    height: mainHeight * (isAdl ? 110 : 120) / footerStart,
                    child: Semantics(
                      button: true,
                      label: 'Explore the Bible',
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onExplore,
                        child: const SizedBox.expand(),
                      ),
                    ),
                  )
                else
                  Center(
                    child: FilledButton(
                      onPressed: onExplore,
                      child: const Text('Explore the Bible'),
                    ),
                  ),
                Positioned(
                  left: width * .02,
                  width: width * .17,
                  bottom: controlBottom,
                  height: 48,
                  child: MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1.2,
                    child: TextButton(
                      onPressed: onAbout,
                      style: overlayStyle,
                      child: const Text(
                        'About',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: width * .01,
                  width: width * .18,
                  bottom: controlBottom,
                  height: 48,
                  child: MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1.2,
                    child: TextButton(
                      onPressed: onUtilities,
                      style: overlayStyle,
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.settings_outlined, size: 16),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              'Utilities',
                              maxLines: 1,
                              softWrap: false,
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}
