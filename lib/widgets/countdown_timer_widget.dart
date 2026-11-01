// Widget: Live Visual Countdown Timer (Server Time Synchronized)
// Supports Days, Hours, Minutes, Seconds with resilient live re-sync.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:bid_app/services/server_time_service.dart';
import 'package:bid_app/theme/app_theme.dart';

enum TimerMode { startsIn, endsIn, depositDeadline }

class CountdownTimerWidget extends StatefulWidget {
  final DateTime targetTime;
  final TimerMode mode;
  final VoidCallback? onTimerExpired;
  final bool compact;

  const CountdownTimerWidget({
    super.key,
    required this.targetTime,
    this.mode = TimerMode.endsIn,
    this.onTimerExpired,
    this.compact = false,
  });

  @override
  State<CountdownTimerWidget> createState() => _CountdownTimerWidgetState();
}

class _CountdownTimerWidgetState extends State<CountdownTimerWidget> {
  Timer? _timer;
  int _remainingSeconds = 0;
  bool _expiredFired = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void didUpdateWidget(CountdownTimerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.targetTime != widget.targetTime || oldWidget.mode != widget.mode) {
      _expiredFired = false;
      _startTimer();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = null;

    final remaining = ServerTimeService().getRemainingSeconds(widget.targetTime);
    _remainingSeconds = remaining;

    if (_remainingSeconds > 0) {
      _expiredFired = false;
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    } else {
      _handleExpiration();
    }
  }

  void _tick() {
    if (!mounted) return;
    final remaining = ServerTimeService().getRemainingSeconds(widget.targetTime);

    setState(() {
      _remainingSeconds = remaining;
    });

    if (remaining <= 0) {
      _timer?.cancel();
      _timer = null;
      _handleExpiration();
    }
  }

  void _handleExpiration() {
    if (_expiredFired) return;
    _expiredFired = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.onTimerExpired?.call();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }

  String _twoDigits(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    if (_remainingSeconds <= 0) {
      final isStartsIn = widget.mode == TimerMode.startsIn;
      final label = isStartsIn
          ? 'AUCTION STARTING...'
          : (widget.mode == TimerMode.depositDeadline ? 'DEADLINE EXPIRED' : 'AUCTION CLOSED');

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isStartsIn
              ? AppColors.primary.withValues(alpha: 0.1)
              : const Color(0xFFFEE4E2),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isStartsIn ? AppColors.primary : AppColors.danger.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isStartsIn ? Icons.hourglass_top_rounded : Icons.timer_off_outlined,
              size: 14,
              color: isStartsIn ? AppColors.primary : AppColors.danger,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Inter',
                color: isStartsIn ? AppColors.primary : AppColors.danger,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }

    final days = _remainingSeconds ~/ 86400;
    final hours = (_remainingSeconds % 86400) ~/ 3600;
    final minutes = (_remainingSeconds % 3600) ~/ 60;
    final seconds = _remainingSeconds % 60;

    final isEndingSoon =
        _remainingSeconds <= 300 && widget.mode == TimerMode.endsIn;
    final isDepositUrgent =
        _remainingSeconds <= 300 && widget.mode == TimerMode.depositDeadline;

    final baseColor = isEndingSoon || isDepositUrgent
        ? AppColors.danger
        : AppColors.navy;

    final labelText = widget.mode == TimerMode.startsIn
        ? 'STARTS IN'
        : (widget.mode == TimerMode.depositDeadline
            ? 'DEPOSIT TIME REMAINING'
            : 'AUCTION ENDS IN');

    if (widget.compact) {
      final timeStr = days > 0
          ? '${days}d ${_twoDigits(hours)}h ${_twoDigits(minutes)}m'
          : '${_twoDigits(hours)}h ${_twoDigits(minutes)}m ${_twoDigits(seconds)}s';

      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer_outlined, size: 15, color: baseColor),
          const SizedBox(width: 4),
          Text(
            timeStr,
            style: TextStyle(
              fontFamily: 'Inter',
              color: baseColor,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isEndingSoon || isDepositUrgent
              ? AppColors.danger
              : AppColors.border,
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            labelText,
            style: TextStyle(
              fontFamily: 'Inter',
              color: isEndingSoon || isDepositUrgent
                  ? AppColors.danger
                  : AppColors.secondaryText,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (days > 0) ...[
                _buildTimeUnit('${days}d', 'Days', baseColor),
                _buildColon(baseColor),
              ],
              _buildTimeUnit(_twoDigits(hours), 'Hours', baseColor),
              _buildColon(baseColor),
              _buildTimeUnit(_twoDigits(minutes), 'Mins', baseColor),
              _buildColon(baseColor),
              _buildTimeUnit(_twoDigits(seconds), 'Secs', baseColor),
            ],
          ),
          if (isEndingSoon) ...[
            const SizedBox(height: 6),
            const Text(
              'Ending soon - Place your bid now',
              style: TextStyle(
                fontFamily: 'Inter',
                color: AppColors.danger,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTimeUnit(String value, String label, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(
            value,
            style: TextStyle(
              fontFamily: 'Inter',
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Inter',
            color: AppColors.secondaryText,
            fontSize: 9,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildColon(Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        ':',
        style: TextStyle(
          fontFamily: 'Inter',
          color: color,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
