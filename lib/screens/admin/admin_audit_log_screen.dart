// Admin Audit Log Screen: Displays Realtime System Audit Logs from public.audit_logs

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:bid_app/services/auction_service.dart';
import 'package:bid_app/services/server_time_service.dart';
import 'package:bid_app/theme/app_theme.dart';

class AdminAuditLogScreen extends StatefulWidget {
  const AdminAuditLogScreen({super.key});

  @override
  State<AdminAuditLogScreen> createState() => _AdminAuditLogScreenState();
}

class _AdminAuditLogScreenState extends State<AdminAuditLogScreen> {
  final AuctionService _service = AuctionService();
  List<Map<String, dynamic>> _auditLogs = [];
  bool _isLoading = true;
  String _filter = 'ALL';
  StreamSubscription<List<Map<String, dynamic>>>? _auditSubscription;

  @override
  void initState() {
    super.initState();
    _loadAuditLogs();
    _auditSubscription = _service.auditLogStream.listen((logs) {
      if (mounted) {
        setState(() {
          _auditLogs = logs;
          _isLoading = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _auditSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadAuditLogs() async {
    setState(() => _isLoading = true);
    final logs = await _service.fetchAuditLogs();
    if (mounted) {
      setState(() {
        _auditLogs = logs;
        _isLoading = false;
      });
    }
  }

  Color _getBadgeColor(String action) {
    if (action.contains('CREATE')) return AppColors.success;
    if (action.contains('BID')) return AppColors.navy;
    if (action.contains('DEPOSIT')) return AppColors.amber;
    if (action.contains('EXPIRE')) return AppColors.danger;
    return AppColors.primary;
  }

  @override
  Widget build(BuildContext context) {
    final filteredLogs = _filter == 'ALL'
        ? _auditLogs
        : _auditLogs
            .where((l) => (l['action'] as String).contains(_filter))
            .toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.cardBackground,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Row(
          children: [
            const Text(
              'System Audit Logs',
              style: TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.circle, color: AppColors.success, size: 8),
                  SizedBox(width: 4),
                  Text(
                    'LIVE',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      color: AppColors.success,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        iconTheme: const IconThemeData(color: AppColors.navy),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.navy),
            onPressed: _loadAuditLogs,
            tooltip: 'Refresh Audit Logs',
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Chips
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: AppColors.cardBackground,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children:
                    ['ALL', 'CREATE', 'BID', 'DEPOSIT', 'EXPIRE'].map((filter) {
                  final isSelected = _filter == filter;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: FilterChip(
                      selected: isSelected,
                      label: Text(
                        filter,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          color: isSelected ? Colors.white : AppColors.navy,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      selectedColor: AppColors.navy,
                      backgroundColor: AppColors.background,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(
                          color: isSelected ? AppColors.navy : AppColors.border,
                        ),
                      ),
                      onSelected: (_) => setState(() => _filter = filter),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // Log List
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary))
                : filteredLogs.isEmpty
                    ? const Center(
                        child: Text(
                          'No audit logs found.',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            color: AppColors.secondaryText,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: filteredLogs.length,
                        itemBuilder: (context, index) {
                          final log = filteredLogs[index];
                          final action = log['action'] ?? 'UNKNOWN';
                          final entityType = log['entity_type'] ?? '';
                          final createdAt =
                              DateTime.tryParse(log['created_at'] ?? '') ??
                                  DateTime.now();
                          final actorProfile =
                              log['profiles'] as Map<String, dynamic>?;
                          final actorName =
                              actorProfile?['full_name'] ?? 'System / User';
                          final details = log['details']?.toString() ?? '';
                          final badgeColor = _getBadgeColor(action);

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.cardBackground,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: badgeColor.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
                                      ),
                                      child: Text(
                                        action,
                                        style: TextStyle(
                                          fontFamily: 'Inter',
                                          color: badgeColor,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      ServerTimeService.formatNepal(createdAt, pattern: 'MMM d, h:mm:ss a', includeTzSuffix: true),
                                      style: const TextStyle(
                                        fontFamily: 'Inter',
                                        color: AppColors.secondaryText,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'Actor: $actorName',
                                  style: const TextStyle(
                                    fontFamily: 'Inter',
                                    color: AppColors.navy,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Entity: $entityType (${log['entity_id'] ?? ''})',
                                  style: const TextStyle(
                                    fontFamily: 'Inter',
                                    color: AppColors.secondaryText,
                                    fontSize: 12,
                                  ),
                                ),
                                if (details.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: AppColors.background,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: AppColors.border),
                                    ),
                                    child: Text(
                                      details,
                                      style: const TextStyle(
                                        fontFamily: 'Inter',
                                        color: AppColors.navy,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
