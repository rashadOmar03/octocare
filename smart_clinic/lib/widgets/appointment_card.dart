import 'package:flutter/material.dart';
import '../models/appointment.dart';
import '../l10n/localization.dart';
import '../utils/time_format.dart';
import 'role_badge.dart';
import 'user_avatar.dart';

class AppointmentCard extends StatelessWidget {
  final Appointment appointment;
  final VoidCallback? onTap;
  final VoidCallback? onCancel;
  final VoidCallback? onConfirm;
  final VoidCallback? onMarkArrived;
  final VoidCallback? onReschedule;
  final VoidCallback? onLeaveQueue;
  final VoidCallback? onRecordPayment;
  final VoidCallback? onReview;
  final bool showPatient;
  final bool showDoctor;

  const AppointmentCard({
    super.key,
    required this.appointment,
    this.onTap,
    this.onCancel,
    this.onConfirm,
    this.onMarkArrived,
    this.onReschedule,
    this.onLeaveQueue,
    this.onRecordPayment,
    this.onReview,
    this.showPatient = false,
    this.showDoctor = true,
  });

  Color _statusColor(String? status) {
    switch (status) {
      case 'confirmed':
        return const Color(0xFF388E3C);
      case 'pending':
        return const Color(0xFFF57C00);
      case 'cancelled':
        return const Color(0xFFD32F2F);
      case 'completed':
        return const Color(0xFF1565C0);
      case 'arrived':
        return const Color(0xFF7B1FA2);
      default:
        return const Color(0xFF757575);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (showPatient && appointment.patientName != null) ...[
                    UserAvatar(
                      name: appointment.patientName,
                      photoUrl: appointment.patientPhotoUrl,
                      patientId: appointment.patientPhotoUrl == null ? appointment.patientId : null,
                      radius: 22,
                      loadFromApi: false,
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (showDoctor && appointment.doctorName != null)
                          Text(
                            appointment.doctorName!,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        if (showPatient && appointment.patientName != null)
                          Text(
                            appointment.patientName!,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        if (appointment.specialtyName != null)
                          Text(
                            appointment.specialtyName!,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                      ],
                    ),
                  ),
                  RoleBadge(
                    label: AppLocalizations.tr(appointment.status ?? 'pending'),
                    color: _statusColor(appointment.status),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.calendar_today, size: 16, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 6),
                  Text(appointment.date ?? '', style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(width: 16),
                  Icon(Icons.access_time, size: 16, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 6),
                  Text(TimeFormat.format24To12(appointment.timeSlot), style: Theme.of(context).textTheme.bodyMedium),
                  if (appointment.isPaid) ...[
                    const SizedBox(width: 12),
                    Icon(Icons.payments, size: 16, color: const Color(0xFF388E3C)),
                    const SizedBox(width: 4),
                    Text(AppLocalizations.tr('paid'), style: const TextStyle(color: Color(0xFF388E3C), fontWeight: FontWeight.w600)),
                  ],
                  if (appointment.needsPayment) ...[
                    const SizedBox(width: 12),
                    Icon(Icons.warning_amber, size: 16, color: const Color(0xFFF57C00)),
                    const SizedBox(width: 4),
                    Text(
                      AppLocalizations.tr('collect_payment_again'),
                      style: const TextStyle(color: Color(0xFFF57C00), fontWeight: FontWeight.w600, fontSize: 12),
                    ),
                  ],
                ],
              ),
              if (appointment.status == 'arrived' && appointment.queueNumber != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7B1FA2).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.format_list_numbered, size: 18, color: Color(0xFF7B1FA2)),
                      const SizedBox(width: 8),
                      Text(
                        '${AppLocalizations.tr('your_queue_number')}: #${appointment.queueNumber}',
                        style: const TextStyle(color: Color(0xFF7B1FA2), fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
              if (onCancel != null || onConfirm != null || onMarkArrived != null || onReschedule != null || onLeaveQueue != null || onRecordPayment != null || onReview != null) ...[
                const SizedBox(height: 12),
                const Divider(),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 4,
                  children: [
                    if (onReschedule != null)
                      TextButton.icon(
                        onPressed: onReschedule,
                        icon: const Icon(Icons.event, size: 18),
                        label: Text(AppLocalizations.tr('reschedule')),
                      ),
                    if (onLeaveQueue != null)
                      TextButton.icon(
                        onPressed: onLeaveQueue,
                        icon: Icon(Icons.undo, size: 18),
                        label: Text(AppLocalizations.tr('remove_from_queue')),
                        style: TextButton.styleFrom(foregroundColor: const Color(0xFFD32F2F)),
                      ),
                    if (onReview != null)
                      TextButton.icon(
                        onPressed: onReview,
                        icon: const Icon(Icons.star_rate, size: 18),
                        label: Text(AppLocalizations.tr('leave_review')),
                        style: TextButton.styleFrom(foregroundColor: const Color(0xFFF9A825)),
                      ),
                    if (onCancel != null)
                      TextButton.icon(
                        onPressed: onCancel,
                        icon: const Icon(Icons.close, size: 18),
                        label: Text(AppLocalizations.tr('cancel')),
                        style: TextButton.styleFrom(foregroundColor: const Color(0xFFD32F2F)),
                      ),
                    if (onConfirm != null)
                      TextButton.icon(
                        onPressed: onConfirm,
                        icon: const Icon(Icons.check, size: 18),
                        label: Text(AppLocalizations.tr('confirm')),
                        style: TextButton.styleFrom(foregroundColor: const Color(0xFF388E3C)),
                      ),
                    if (onMarkArrived != null && appointment.isPaid)
                      TextButton.icon(
                        onPressed: onMarkArrived,
                        icon: const Icon(Icons.person_pin, size: 18),
                        label: Text(AppLocalizations.tr('mark_arrived')),
                        style: TextButton.styleFrom(foregroundColor: const Color(0xFF7B1FA2)),
                      ),
                    if (onRecordPayment != null &&
                        !appointment.isPaid &&
                        appointment.status != 'cancelled' &&
                        appointment.status != 'completed')
                      TextButton.icon(
                        onPressed: onRecordPayment,
                        icon: const Icon(Icons.payment, size: 18),
                        label: Text(
                          appointment.needsPayment
                              ? AppLocalizations.tr('collect_payment_again')
                              : AppLocalizations.tr('record_payment'),
                        ),
                        style: TextButton.styleFrom(foregroundColor: const Color(0xFFF57C00)),
                      ),
                    if (onMarkArrived != null && !appointment.isPaid && appointment.status == 'confirmed') ...[
                      const SizedBox(width: 8),
                      Text(
                        AppLocalizations.tr('payment_required_arrive'),
                        style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
