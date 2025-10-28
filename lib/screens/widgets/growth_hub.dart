import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:villagebanking/brick/moodels/group.model.dart';
import 'package:villagebanking/brick/repository.dart';
import 'package:villagebanking/theme.dart';
import 'package:brick_offline_first/brick_offline_first.dart';
import 'package:brick_core/query.dart';

class GrowthHub extends StatelessWidget {
  final double growthLevel;
  final String? selectedGroupId;
  final AnimationController animationController;

  const GrowthHub({
    super.key,
    required this.growthLevel,
    required this.selectedGroupId,
    required this.animationController,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final secondaryTextColor = isDarkMode ? Colors.grey[400] : Colors.grey[600];

    final LinearGradient soilGradient = LinearGradient(
      colors: isDarkMode
          ? [const Color(0xFF444444), const Color(0xFF1F1F1F)]
          : [const Color(0xFFCCCCCC), const Color(0xFFF7F7F7)],
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
    );

    final Color growthColor =
        Color.lerp(
          growthAccent.withOpacity(0.3),
          growthAccent,
          growthLevel,
        ) ??
        growthAccent;

    return Container(
      padding: const EdgeInsets.all(24.0),
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12.0),
        boxShadow: [
          BoxShadow(
            color: isDarkMode
                ? Colors.black.withOpacity(0.5)
                : Colors.black.withOpacity(0.05),
            spreadRadius: 0,
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
        border: Border.all(
          color: isDarkMode ? const Color(0xFF333333) : const Color(0xFFE0E0E0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'My Group Savings',
                style: theme.textTheme.titleMedium,
              ),
              Icon(Icons.visibility_off, color: secondaryTextColor),
            ],
          ),
          const SizedBox(height: 8.0),
          FutureBuilder(
            future: Repository().get<Group>(
              policy: OfflineFirstGetPolicy.alwaysHydrate,
              query: selectedGroupId != null
                  ? Query(where: [Where.exact('id', selectedGroupId)])
                  : Query(limit: 1),
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return SizedBox(
                  width: 200.0,
                  height: 100.0,
                  child: Shimmer.fromColors(
                    baseColor: const Color.fromARGB(255, 167, 163, 163),
                    highlightColor: const Color.fromARGB(255, 59, 128, 255),
                    child: Center(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Icon(
                            growthLevel < 0.3
                                ? Icons.eco_outlined
                                : growthLevel < 0.7
                                ? Icons.scatter_plot_rounded
                                : Icons.trending_up,
                            color: Colors.white,
                            size: 40,
                          ),
                          Align(
                            alignment: Alignment.bottomCenter,
                            child: Container(
                              height: 25,
                              decoration: BoxDecoration(
                                gradient: soilGradient,
                                borderRadius: const BorderRadius.vertical(
                                  bottom: Radius.circular(50),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Text(
                              'Loading',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              } else if (snapshot.hasError) {
                return Column(
                  children: [
                    AnimatedBuilder(
                      animation: animationController,
                      builder: (context, child) {
                        return Text(
                          'Unable to load group data',
                          style: theme.textTheme.headlineMedium,
                        );
                      },
                    ),
                    const SizedBox(height: 20.0),
                    Center(
                      child: Container(
                        height: 100,
                        width: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [growthColor.withOpacity(0.7), growthColor],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: growthColor.withOpacity(0.4),
                              blurRadius: 20,
                              spreadRadius: 3,
                            ),
                          ],
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Icon(
                              growthLevel < 0.3
                                  ? Icons.eco_outlined
                                  : growthLevel < 0.7
                                  ? Icons.scatter_plot_rounded
                                  : Icons.trending_up,
                              color: Colors.white,
                              size: 40,
                            ),
                            Align(
                              alignment: Alignment.bottomCenter,
                              child: Container(
                                height: 25,
                                decoration: BoxDecoration(
                                  gradient: soilGradient,
                                  borderRadius: const BorderRadius.vertical(
                                    bottom: Radius.circular(50),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Text(
                                '${(growthLevel * 100).toInt()}%',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20.0),
                  ],
                );
              } else if (snapshot.hasData) {
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(child: Text('No data to show yet.'));
                }
                return Column(
                  children: [
                    Center(
                      child: AnimatedBuilder(
                        animation: animationController,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: 1.0 + (animationController.value * 0.1),
                            child: Container(
                              height: 100,
                              width: 100,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: [growthColor.withOpacity(0.7), growthColor],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: growthColor.withOpacity(0.4),
                                    blurRadius: 20,
                                    spreadRadius: 3,
                                  ),
                                ],
                              ),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Icon(
                                    growthLevel < 0.3
                                        ? Icons.eco_outlined
                                        : growthLevel < 0.7
                                        ? Icons.scatter_plot_rounded
                                        : Icons.trending_up,
                                    color: Colors.white,
                                    size: 40,
                                  ),
                                  Align(
                                    alignment: Alignment.bottomCenter,
                                    child: Container(
                                      height: 25,
                                      decoration: BoxDecoration(
                                        gradient: soilGradient,
                                        borderRadius: const BorderRadius.vertical(
                                          bottom: Radius.circular(50),
                                        ),
                                      ),)
                                  ),
                                  Positioned(
                                    top: 8,
                                    right: 8,
                                    child: Text(
                                      '${(growthLevel * 100).toInt()}%',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 20.0),
                  ],
                );
              } else {
                return const Center();
              }
            },
          ),
        ],
      ),
    );
  }
}
