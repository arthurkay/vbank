AnimatedBuilder(
            animation: animationController,
            builder: (context, child) {
              final displayedBalance =
                  currentBalance * animationController.value;
              return Text(
                '\$${displayedBalance.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w900,
                  color: primaryTextColor,
                  letterSpacing: -1.0,
                ),
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
          Text(
            'Next Goal: \$2000 Savings Milestone',
            style: TextStyle(
              color: secondaryTextColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8.0),
          LinearProgressIndicator(
            value: growthLevel,
            borderRadius: BorderRadius.circular(6),
            minHeight: 8,
            backgroundColor: isDarkMode
                ? const Color(0xFF333333)
                : const Color(0xFFE0E0E0),
            valueColor: AlwaysStoppedAnimation<Color>(growthColor),
          ),