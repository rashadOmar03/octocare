import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/localization.dart';
import '../../config/routes.dart';
import '../../providers/auth_provider.dart';
import '../../services/appointment_service.dart';
import '../../services/api_service.dart';
import '../../services/review_service.dart';
import '../../models/doctor.dart';
import '../../utils/time_format.dart';

class BookAppointmentScreen extends StatefulWidget {
  const BookAppointmentScreen({super.key});

  @override
  State<BookAppointmentScreen> createState() => _BookAppointmentScreenState();
}

class _BookAppointmentScreenState extends State<BookAppointmentScreen> {
  final AppointmentService _appointmentService = AppointmentService();
  final ReviewService _reviewService = ReviewService();
  int _currentStep = 0;
  bool _isLoading = false;

  List<Map<String, dynamic>> _specialties = [];
  List<Doctor> _doctors = [];
  List<Map<String, dynamic>> _slots = [];
  bool _doctorOnVacation = false;
  String? _vacationReason;
  String? _slotsBlockReason;
  String? _slotsWorkingDaysLabel;

  dynamic _selectedSpecialtyId;
  String? _selectedSpecialtyName;
  Doctor? _selectedDoctor;
  DateTime? _selectedDate;
  String? _selectedTime;

  List<int> _workingDays = [];
  String _workingDaysLabel = '';
  bool _bookingInfoLoaded = false;
  late Future<void> _bookingInfoFuture;

  @override
  void initState() {
    super.initState();
    _bookingInfoFuture = _loadBookingInfo();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final auth = Provider.of<AuthProvider>(context, listen: false);
      if (!auth.profileComplete) {
        Navigator.pushReplacementNamed(context, AppRoutes.profileComplete);
        return;
      }
      _loadSpecialties();
    });
  }

  Future<void> _loadBookingInfo() async {
    try {
      final response = await ApiService.instance.get('/appointments/booking-info');
      final days = response['working_days'];
      if (days is List && days.isNotEmpty) {
        _workingDays = days.map((d) => d is int ? d : int.parse('$d')).toList();
      }
      final label = response['working_days_label']?.toString();
      if (label != null && label.isNotEmpty) {
        _workingDaysLabel = label;
      }
    } catch (_) {}
    _bookingInfoLoaded = true;
    _syncSelectedDate();
    if (mounted) setState(() {});
  }

  bool _isClinicOpen(DateTime day) {
    if (_workingDays.isEmpty) return false;
    final pythonDow = day.weekday == DateTime.sunday ? 6 : day.weekday - 1;
    return _workingDays.contains(pythonDow);
  }

  DateTime _nextOpenDay(DateTime from) {
    var day = DateTime(from.year, from.month, from.day);
    final limit = DateTime.now().add(const Duration(days: 60));
    while (!day.isAfter(limit)) {
      if (_isClinicOpen(day)) return day;
      day = day.add(const Duration(days: 1));
    }
    return DateTime(from.year, from.month, from.day);
  }

  void _syncSelectedDate() {
    if (!_bookingInfoLoaded || _workingDays.isEmpty) return;
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final base = _selectedDate ?? tomorrow;
    final start = base.isBefore(tomorrow) ? tomorrow : base;
    final fixed = _nextOpenDay(start);
    if (_selectedDate == null || !_isClinicOpen(_selectedDate!)) {
      _selectedDate = fixed;
    }
  }

  Future<void> _loadSpecialties() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiService.instance.get('/appointments/specialties');
      if (response is List) {
        _specialties = response.map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    }
    setState(() => _isLoading = false);
  }

  Future<void> _loadDoctors(dynamic specialtyId) async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiService.instance.get('/appointments/doctors?specialty_id=$specialtyId');
      if (response is List) {
        _doctors = response.map((u) => Doctor.fromJson(Map<String, dynamic>.from(u))).toList();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    }
    setState(() => _isLoading = false);
  }

  Future<void> _loadSlots() async {
    if (_selectedDoctor?.id == null || _selectedDate == null) return;
    setState(() => _isLoading = true);
    try {
      final dateStr = '${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}';
      final result = await _appointmentService.fetchAvailableSlots(_selectedDoctor!.id!, dateStr);
      _slots = (result['slots'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      _doctorOnVacation = result['doctor_on_vacation'] == true || result['reason'] == 'vacation';
      _vacationReason = result['vacation_reason']?.toString();
      _slotsBlockReason = result['reason']?.toString();
      _slotsWorkingDaysLabel = result['working_days_label']?.toString();
      final apiDays = result['working_days_label'];
      if (apiDays != null && apiDays.toString().isNotEmpty) {
        _workingDaysLabel = apiDays.toString();
      }
    } catch (_) {
      _slots = [];
      _doctorOnVacation = false;
      _vacationReason = null;
      _slotsBlockReason = null;
    }
    setState(() => _isLoading = false);
  }

  Future<void> _bookAppointment() async {
    if (_selectedDoctor == null || _selectedDate == null || _selectedTime == null) return;
    setState(() => _isLoading = true);
    try {
      final dateStr = '${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}';
      await _appointmentService.bookAppointment({
        'doctor_id': _selectedDoctor!.id,
        'date': dateStr,
        'time_slot': _selectedTime,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.tr('appointment_booked')), backgroundColor: const Color(0xFF388E3C)),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    }
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.tr('book_appointment'))),
      body: Stepper(
        currentStep: _currentStep,
        onStepContinue: _onStepContinue,
        onStepCancel: () {
          if (_currentStep > 0) setState(() => _currentStep--);
        },
        controlsBuilder: (context, details) {
          return Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Row(
              children: [
                ElevatedButton(
                  onPressed: _canContinue() ? details.onStepContinue : null,
                  child: _isLoading && _currentStep == 3
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(_currentStep == 3 ? AppLocalizations.tr('confirm') : AppLocalizations.tr('next')),
                ),
                const SizedBox(width: 12),
                if (_currentStep > 0)
                  OutlinedButton(
                    onPressed: details.onStepCancel,
                    child: Text(AppLocalizations.tr('previous')),
                  ),
              ],
            ),
          );
        },
        steps: [
          Step(
            title: Text(AppLocalizations.tr('select_specialty')),
            isActive: _currentStep >= 0,
            content: _isLoading && _currentStep == 0
                ? const Center(child: CircularProgressIndicator())
                : _buildSpecialtyGrid(),
          ),
          Step(
            title: Text(AppLocalizations.tr('select_doctor')),
            isActive: _currentStep >= 1,
            content: _isLoading && _currentStep == 1
                ? const Center(child: CircularProgressIndicator())
                : _buildDoctorList(),
          ),
          Step(
            title: Text(AppLocalizations.tr('select_date')),
            isActive: _currentStep >= 2,
            content: _buildDatePicker(),
          ),
          Step(
            title: Text(AppLocalizations.tr('select_time')),
            isActive: _currentStep >= 3,
            content: _isLoading && _currentStep == 3
                ? const Center(child: CircularProgressIndicator())
                : _buildTimeGrid(),
          ),
        ],
      ),
    );
  }

  bool _canContinue() {
    switch (_currentStep) {
      case 0:
        return _selectedSpecialtyId != null;
      case 1:
        return _selectedDoctor != null;
      case 2:
        return _selectedDate != null && _isClinicOpen(_selectedDate!);
      case 3:
        return _selectedTime != null;
      default:
        return false;
    }
  }

  void _onStepContinue() async {
    if (_currentStep == 0 && _selectedSpecialtyId != null) {
      await _loadDoctors(_selectedSpecialtyId!);
      if (_doctors.isNotEmpty) {
        setState(() => _currentStep = 1);
      }
    } else if (_currentStep == 1 && _selectedDoctor != null) {
      await _bookingInfoFuture;
      _syncSelectedDate();
      setState(() => _currentStep = 2);
    } else if (_currentStep == 2 && _selectedDate != null) {
      if (!_isClinicOpen(_selectedDate!)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.tr('clinic_closed_day'))),
        );
        return;
      }
      await _loadSlots();
      setState(() => _currentStep = 3);
    } else if (_currentStep == 3 && _selectedTime != null) {
      _bookAppointment();
    }
  }

  Widget _buildSpecialtyGrid() {
    if (_specialties.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(AppLocalizations.tr('no_data')),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 2.5, crossAxisSpacing: 8, mainAxisSpacing: 8),
      itemCount: _specialties.length,
      itemBuilder: (ctx, i) {
        final s = _specialties[i];
        final isSelected = _selectedSpecialtyId == s['id'];
        return GestureDetector(
          onTap: () => setState(() {
            _selectedSpecialtyId = s['id'];
            _selectedSpecialtyName = s['name'];
          }),
          child: Container(
            decoration: BoxDecoration(
              color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isSelected ? Theme.of(context).colorScheme.primary : const Color(0xFFE0E0E0)),
            ),
            alignment: Alignment.center,
            child: Text(
              s['name'] ?? '',
              style: TextStyle(
                color: isSelected ? Colors.white : Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _ratingLine(Doctor d) {
    if (d.reviewCount == null || d.reviewCount! <= 0) {
      return Text(
        AppLocalizations.tr('no_reviews_yet'),
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    final avg = d.averageRating ?? 0;
    return Row(
      children: [
        ...List.generate(5, (i) {
          final filled = avg >= i + 1;
          final half = !filled && avg > i && avg < i + 1;
          return Icon(
            filled ? Icons.star : (half ? Icons.star_half : Icons.star_border),
            size: 16,
            color: const Color(0xFFF9A825),
          );
        }),
        const SizedBox(width: 6),
        Text('${d.averageRating?.toStringAsFixed(1) ?? '0.0'} (${d.reviewCount})'),
      ],
    );
  }

  Future<void> _showDoctorReviews(Doctor d) async {
    if (d.id == null) return;
    try {
      final data = await _reviewService.getDoctorReviews(d.id!);
      if (!mounted) return;
      final reviews = (data['reviews'] as List?) ?? [];
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          minChildSize: 0.35,
          maxChildSize: 0.9,
          builder: (_, controller) => Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d.name ?? '', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                _ratingLine(d),
                const SizedBox(height: 12),
                Text(AppLocalizations.tr('patient_reviews'), style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Expanded(
                  child: reviews.isEmpty
                      ? Center(child: Text(AppLocalizations.tr('no_reviews_yet')))
                      : ListView.separated(
                          controller: controller,
                          itemCount: reviews.length,
                          separatorBuilder: (_, __) => const Divider(height: 16),
                          itemBuilder: (_, i) {
                            final r = Map<String, dynamic>.from(reviews[i] as Map);
                            final stars = r['doctor_rating'] is int ? r['doctor_rating'] as int : int.tryParse('${r['doctor_rating']}') ?? 0;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    ...List.generate(5, (j) => Icon(
                                      j < stars ? Icons.star : Icons.star_border,
                                      size: 16,
                                      color: const Color(0xFFF9A825),
                                    )),
                                    const Spacer(),
                                    Text(r['created_at']?.toString().split('T').first ?? ''),
                                  ],
                                ),
                                if ((r['doctor_comment'] ?? '').toString().isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(r['doctor_comment'].toString()),
                                  ),
                              ],
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    }
  }

  Widget _buildDoctorList() {
    if (_doctors.isEmpty) {
      return Padding(padding: const EdgeInsets.all(16), child: Text(AppLocalizations.tr('no_data')));
    }
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _doctors.length,
      itemBuilder: (ctx, i) {
        final d = _doctors[i];
        final isSelected = _selectedDoctor?.id == d.id;
        final displayName = (d.name ?? '').trim();
        return Card(
          color: isSelected ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1) : null,
          child: ListTile(
            leading: CircleAvatar(child: Text(displayName.isNotEmpty ? displayName[0] : '?')),
            title: Text(displayName.isEmpty ? AppLocalizations.tr('doctor') : displayName),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (d.qualifications != null && d.qualifications!.trim().isNotEmpty)
                  Text(d.qualifications!.trim()),
                Text(d.specialty ?? _selectedSpecialtyName ?? ''),
                if (d.consultationFee != null)
                  Text('${AppLocalizations.tr('consultation_fee')}: ${d.consultationFee!.toStringAsFixed(0)} EGP'),
                if (d.onVacationToday == true)
                  Text(
                    AppLocalizations.tr('doctor_not_available_today'),
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                const SizedBox(height: 4),
                _ratingLine(d),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (d.reviewCount != null && d.reviewCount! > 0)
                  IconButton(
                    icon: const Icon(Icons.rate_review_outlined),
                    tooltip: AppLocalizations.tr('patient_reviews'),
                    onPressed: () => _showDoctorReviews(d),
                  ),
                if (isSelected) Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary),
              ],
            ),
            isThreeLine: true,
            onTap: () => setState(() => _selectedDoctor = d),
          ),
        );
      },
    );
  }

  Widget _buildDatePicker() {
    if (!_bookingInfoLoaded) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final tomorrow = DateTime.now().add(const Duration(days: 1));
    var initial = _selectedDate ?? tomorrow;
    if (!_isClinicOpen(initial)) {
      initial = _nextOpenDay(tomorrow);
    }
    if (_selectedDate == null || !_isClinicOpen(_selectedDate!)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_selectedDate == null || !_isClinicOpen(_selectedDate!)) {
          setState(() => _selectedDate = initial);
        }
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            AppLocalizations.tr('book_day_before'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (_workingDaysLabel.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
              '${AppLocalizations.tr('working_days')}: $_workingDaysLabel',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        CalendarDatePicker(
          key: ValueKey('booking-cal-${_workingDays.join('-')}-${initial.year}-${initial.month}-${initial.day}'),
          initialDate: initial,
          firstDate: tomorrow,
          lastDate: DateTime.now().add(const Duration(days: 60)),
          selectableDayPredicate: _isClinicOpen,
          onDateChanged: (date) {
            if (!_isClinicOpen(date)) return;
            setState(() {
              _selectedDate = date;
              _selectedTime = null;
            });
          },
        ),
      ],
    );
  }

  Widget _buildTimeGrid() {
    if (_doctorOnVacation) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(Icons.beach_access, size: 48, color: Theme.of(context).colorScheme.error.withValues(alpha: 0.6)),
            const SizedBox(height: 8),
            Text(
              _vacationReason?.isNotEmpty == true
                  ? '${AppLocalizations.tr('doctor_on_vacation')}: $_vacationReason'
                  : AppLocalizations.tr('doctor_on_vacation'),
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    if (_slots.isEmpty) {
      final daysLabel = _slotsWorkingDaysLabel ?? _workingDaysLabel;
      String message;
      switch (_slotsBlockReason) {
        case 'clinic_closed':
          message = AppLocalizations.tr('clinic_closed_day');
          break;
        case 'doctor_day_off':
          message = AppLocalizations.tr('doctor_day_off');
          break;
        case 'all_slots_booked':
          message = AppLocalizations.tr('all_slots_booked');
          break;
        case 'no_schedule_hours':
          message = AppLocalizations.tr('doctor_hours_not_set');
          break;
        default:
          message = AppLocalizations.tr('no_slots_available').replaceAll('{days}', daysLabel);
      }
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(Icons.event_busy, size: 48, color: Theme.of(context).colorScheme.error.withValues(alpha: 0.5)),
            const SizedBox(height: 8),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            if (_slotsBlockReason == 'clinic_closed' || _slotsBlockReason == null) ...[
              const SizedBox(height: 8),
              Text(
                '${AppLocalizations.tr('working_days')}: $daysLabel',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _slots.map((slot) {
        final time = slot['time'] as String;
        final available = slot['available'] as bool? ?? true;
        final isSelected = _selectedTime == time;
        return ChoiceChip(
          label: Text(TimeFormat.format24To12(time)),
          selected: isSelected,
          onSelected: available ? (selected) => setState(() => _selectedTime = selected ? time : null) : null,
          backgroundColor: available ? null : const Color(0xFFEEEEEE),
          selectedColor: Theme.of(context).colorScheme.primary,
          labelStyle: TextStyle(
            color: isSelected ? Colors.white : (available ? null : const Color(0xFF9E9E9E)),
          ),
        );
      }).toList(),
    );
  }
}
