-- Smart Clinic Management System - Database Schema
-- SQLite Compatible

-- Enable foreign keys
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS users (
    id TEXT PRIMARY KEY,
    email TEXT UNIQUE NOT NULL,
    phone TEXT UNIQUE,
    password_hash TEXT NOT NULL,
    role TEXT NOT NULL CHECK (role IN ('patient', 'doctor', 'receptionist', 'admin')),
    google_id TEXT UNIQUE,
    is_active INTEGER DEFAULT 1,
    must_change_password INTEGER DEFAULT 0,
    created_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS profiles (
    id TEXT PRIMARY KEY,
    user_id TEXT UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    first_name TEXT NOT NULL,
    middle_name TEXT,
    last_name TEXT NOT NULL,
    dob TEXT NOT NULL,
    gender TEXT NOT NULL CHECK (gender IN ('male', 'female')),
    phone TEXT UNIQUE NOT NULL,
    address TEXT NOT NULL,
    emergency_contact_name TEXT NOT NULL,
    emergency_contact_phone TEXT NOT NULL,
    blood_type TEXT NOT NULL CHECK (blood_type IN ('A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-')),
    allergies TEXT,
    chronic_diseases TEXT,
    existing_conditions TEXT,
    photo_url TEXT,
    is_complete INTEGER DEFAULT 0
);

CREATE TABLE IF NOT EXISTS specialties (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT UNIQUE NOT NULL,
    description TEXT
);

CREATE TABLE IF NOT EXISTS doctors (
    id TEXT PRIMARY KEY,
    profile_id TEXT UNIQUE NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    specialty_id INTEGER NOT NULL REFERENCES specialties(id) ON DELETE RESTRICT,
    qualifications TEXT,
    bio TEXT
);

CREATE TABLE IF NOT EXISTS doctor_schedules (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    doctor_id TEXT NOT NULL REFERENCES doctors(id) ON DELETE CASCADE,
    day_of_week INTEGER NOT NULL CHECK (day_of_week BETWEEN 0 AND 6),
    start_time TEXT NOT NULL,
    end_time TEXT NOT NULL,
    is_available INTEGER DEFAULT 1,
    UNIQUE(doctor_id, day_of_week, start_time, end_time)
);

CREATE TABLE IF NOT EXISTS appointments (
    id TEXT PRIMARY KEY,
    patient_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    doctor_id TEXT NOT NULL REFERENCES doctors(id) ON DELETE CASCADE,
    date TEXT NOT NULL,
    time_slot TEXT NOT NULL,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'confirmed', 'completed', 'cancelled')),
    queue_number INTEGER,
    notes TEXT,
    created_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS payments (
    id TEXT PRIMARY KEY,
    appointment_id TEXT UNIQUE NOT NULL REFERENCES appointments(id) ON DELETE RESTRICT,
    amount REAL NOT NULL,
    payment_method TEXT CHECK (payment_method IN ('cash', 'card', 'wallet')),
    payment_status TEXT DEFAULT 'unpaid' CHECK (payment_status IN ('unpaid', 'paid', 'partial')),
    receptionist_id TEXT REFERENCES profiles(id) ON DELETE SET NULL,
    created_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS medical_records (
    id TEXT PRIMARY KEY,
    appointment_id TEXT UNIQUE REFERENCES appointments(id) ON DELETE RESTRICT,
    patient_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    doctor_id TEXT NOT NULL REFERENCES doctors(id) ON DELETE CASCADE,
    chief_complaint TEXT NOT NULL,
    symptoms TEXT NOT NULL,
    diagnosis TEXT NOT NULL,
    severity TEXT CHECK (severity IN ('mild', 'moderate', 'severe')),
    treatment_plan TEXT NOT NULL,
    notes TEXT,
    soap_subjective TEXT,
    soap_objective TEXT,
    soap_assessment TEXT,
    soap_plan TEXT,
    created_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS prescriptions (
    id TEXT PRIMARY KEY,
    medical_record_id TEXT NOT NULL REFERENCES medical_records(id) ON DELETE CASCADE,
    status TEXT DEFAULT 'active' CHECK (status IN ('active', 'completed', 'cancelled')),
    created_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS prescription_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    prescription_id TEXT NOT NULL REFERENCES prescriptions(id) ON DELETE CASCADE,
    medication_name TEXT NOT NULL,
    dosage TEXT NOT NULL,
    frequency TEXT NOT NULL,
    duration TEXT NOT NULL,
    notes TEXT
);

CREATE TABLE IF NOT EXISTS sensor_data (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    patient_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    heart_rate INTEGER NOT NULL,
    temperature REAL NOT NULL,
    timestamp TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS documents (
    id TEXT PRIMARY KEY,
    patient_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    uploaded_by TEXT REFERENCES users(id),
    category TEXT NOT NULL CHECK (category IN ('lab_report', 'x_ray', 'mri', 'prescription', 'other')),
    file_name TEXT NOT NULL,
    file_url TEXT NOT NULL,
    upload_date TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS notifications (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    is_read INTEGER DEFAULT 0,
    created_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS audit_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id TEXT REFERENCES users(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    entity_type TEXT NOT NULL,
    entity_id TEXT,
    details TEXT,
    timestamp TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS profile_update_requests (
    id TEXT PRIMARY KEY,
    patient_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    request_type TEXT NOT NULL,
    old_value TEXT,
    new_value TEXT NOT NULL,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
    doctor_id TEXT REFERENCES doctors(id) ON DELETE SET NULL,
    created_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS ai_conversations (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (role IN ('patient', 'doctor')),
    messages TEXT NOT NULL,
    summary TEXT,
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS ai_suggestions (
    id TEXT PRIMARY KEY,
    doctor_id TEXT NOT NULL REFERENCES doctors(id) ON DELETE CASCADE,
    patient_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    appointment_id TEXT REFERENCES appointments(id),
    transcript TEXT,
    extracted_data TEXT,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'draft', 'approved', 'rejected')),
    created_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS clinic_settings (
    id INTEGER PRIMARY KEY DEFAULT 1,
    clinic_name TEXT NOT NULL DEFAULT 'Smart Clinic',
    address TEXT,
    phone TEXT,
    email TEXT,
    logo_url TEXT,
    default_fee REAL DEFAULT 100.0,
    working_hours_start TEXT DEFAULT '08:00',
    working_hours_end TEXT DEFAULT '17:00',
    working_days TEXT DEFAULT '0,1,2,3,4',
    appointment_duration INTEGER DEFAULT 30
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_profiles_user_id ON profiles(user_id);
CREATE INDEX IF NOT EXISTS idx_appointments_patient ON appointments(patient_id);
CREATE INDEX IF NOT EXISTS idx_appointments_doctor ON appointments(doctor_id);
CREATE INDEX IF NOT EXISTS idx_appointments_date ON appointments(date);
CREATE INDEX IF NOT EXISTS idx_medical_records_patient ON medical_records(patient_id);
CREATE INDEX IF NOT EXISTS idx_sensor_data_patient ON sensor_data(patient_id);
CREATE INDEX IF NOT EXISTS idx_sensor_data_timestamp ON sensor_data(timestamp);
CREATE INDEX IF NOT EXISTS idx_notifications_user ON notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_entity ON audit_logs(entity_type, entity_id);

-- Seed specialties
INSERT OR IGNORE INTO specialties (name, description) VALUES
    ('Cardiology', 'Heart and cardiovascular system'),
    ('Dermatology', 'Skin, hair, and nail conditions'),
    ('Pediatrics', 'Medical care for infants and children'),
    ('Orthopedics', 'Bones, joints, and musculoskeletal system'),
    ('Neurology', 'Brain and nervous system disorders'),
    ('General Practice', 'Primary healthcare and general medicine'),
    ('Ophthalmology', 'Eye care and vision'),
    ('ENT', 'Ear, Nose, and Throat');

-- Seed clinic settings
INSERT OR IGNORE INTO clinic_settings (id, clinic_name) VALUES (1, 'Smart Clinic');
