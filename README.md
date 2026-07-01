# Smart Clinic Management System
# نظام إدارة العيادة الذكية

---

## English

### Overview
Smart Clinic is a comprehensive healthcare management platform for a single private clinic. It includes clinic management, appointment scheduling, medical records, prescriptions, AI-assisted documentation, IoT vital monitoring, and reporting.

### System Users
1. **Patient** - Book appointments, view records, use AI assistant, monitor vitals
2. **Doctor** - Manage patients, create records/prescriptions, AI-assisted documentation
3. **Receptionist** - Manage appointments, queue, payments, register patients
4. **Administrator** - Manage users, specialties, reports, system settings

### Tech Stack
- **Frontend**: Flutter (Android, iOS, Web)
- **Backend**: FastAPI (Python)
- **Database**: SQLite (via SQLAlchemy)
- **AI Engine**: Gemma (via LM Studio, optional)
- **Authentication**: JWT + Refresh Tokens

### Prerequisites
- Python 3.10+
- Flutter 3.x+
- Dart 3.x+

### Setup Instructions

#### 1. Backend Setup

```bash
cd backend

# Install dependencies
pip install -r requirements.txt

# Run the server
python -m uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

The backend will:
- Automatically create the SQLite database (`clinic.db`)
- Seed default data (admin account, specialties, sample doctors)
- Start at http://localhost:8000
- API docs at http://localhost:8000/docs

**Default Admin Login:**
- Email: `admin@clinic.com`
- Password: `admin123`

**Sample Doctor Login:**
- Email: `dr.ahmed@clinic.com`
- Password: `doctor123`

**Sample Receptionist Login:**
- Email: `reception@clinic.com`
- Password: `reception123`

#### 2. Frontend Setup

```bash
cd smart_clinic

# Get dependencies
flutter pub get

# Run on web
flutter run -d chrome

# Run on Android
flutter run -d android

# Run on iOS
flutter run -d ios
```

#### 3. AI Setup (Optional)
To enable AI features with a local model:
1. Install [LM Studio](https://lmstudio.ai/)
2. Download the Gemma model
3. Start the LM Studio server on port 1234
4. Set `AI_ENABLED=true` in backend `.env`

Without LM Studio, the AI features work with mock responses.

#### 4. IoT Setup (Optional)
Connect ESP32 sensor via Bluetooth to the mobile app. The app reads heart rate, SpO2, and temperature data and uploads it to the backend.

### Features
- ✅ Multi-role authentication (Patient, Doctor, Receptionist, Admin)
- ✅ Appointment booking with wizard flow
- ✅ Medical records with SOAP notes
- ✅ Prescription management with multi-medication support
- ✅ AI medical assistant (bilingual)
- ✅ AI clinical documentation (speech-to-text, symptom extraction, SOAP generation)
- ✅ IoT vital monitoring (heart rate, SpO2, temperature)
- ✅ Queue management
- ✅ Payment tracking
- ✅ PDF report generation
- ✅ Bilingual support (Arabic RTL + English LTR)
- ✅ Dark mode + Light mode
- ✅ Push notifications
- ✅ Audit trail for medical records

---

## العربية

### نظرة عامة
نظام العيادة الذكية هو منصة شاملة لإدارة الرعاية الصحية لعيادة خاصة واحدة. يشمل إدارة العيادة، جدولة المواعيد، السجلات الطبية، الوصفات الطبية، التوثيق بمساعدة الذكاء الاصطناعي، مراقبة العلامات الحيوية عبر إنترنت الأشياء، وإعداد التقارير.

### مستخدمو النظام
1. **المريض** - حجز المواعيد، عرض السجلات، استخدام المساعد الذكي، مراقبة العلامات الحيوية
2. **الطبيب** - إدارة المرضى، إنشاء السجلات/الوصفات، التوثيق بمساعدة الذكاء الاصطناعي
3. **موظف الاستقبال** - إدارة المواعيد، الطوابير، المدفوعات، تسجيل المرضى
4. **المدير** - إدارة المستخدمين، التخصصات، التقارير، إعدادات النظام

### المتطلبات الأساسية
- Python 3.10+
- Flutter 3.x+
- Dart 3.x+

### تعليمات الإعداد

#### 1. إعداد الخادم الخلفي

```bash
cd backend

# تثبيت المتطلبات
pip install -r requirements.txt

# تشغيل الخادم
python -m uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

**بيانات تسجيل الدخول الافتراضية للمدير:**
- البريد الإلكتروني: `admin@clinic.com`
- كلمة المرور: `admin123`

#### 2. إعداد الواجهة الأمامية

```bash
cd smart_clinic

# تحميل المتطلبات
flutter pub get

# تشغيل على الويب
flutter run -d chrome

# تشغيل على أندرويد
flutter run -d android
```

#### 3. إعداد الذكاء الاصطناعي (اختياري)
لتفعيل ميزات الذكاء الاصطناعي مع نموذج محلي:
1. ثبّت [LM Studio](https://lmstudio.ai/)
2. حمّل نموذج Gemma
3. شغّل خادم LM Studio على المنفذ 1234
4. اضبط `AI_ENABLED=true` في ملف `.env` الخاص بالخادم

بدون LM Studio، تعمل ميزات الذكاء الاصطناعي بردود تجريبية.

### الميزات
- ✅ مصادقة متعددة الأدوار (مريض، طبيب، موظف استقبال، مدير)
- ✅ حجز المواعيد بخطوات متتالية
- ✅ السجلات الطبية مع ملاحظات SOAP
- ✅ إدارة الوصفات الطبية مع دعم أدوية متعددة
- ✅ المساعد الطبي الذكي (ثنائي اللغة)
- ✅ التوثيق السريري بالذكاء الاصطناعي
- ✅ مراقبة العلامات الحيوية عبر IoT
- ✅ إدارة الطوابير
- ✅ تتبع المدفوعات
- ✅ إنشاء تقارير PDF
- ✅ دعم ثنائي اللغة (عربي RTL + إنجليزي LTR)
- ✅ الوضع الداكن + الوضع الفاتح
- ✅ إشعارات فورية
- ✅ سجل تدقيق للسجلات الطبية
