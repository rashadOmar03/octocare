"""Smoke tests for Smart Clinic API - run before starting servers."""
import sys
import uuid
from fastapi.testclient import TestClient

from main import app

client = TestClient(app)
PASS = 0
FAIL = 0
ISSUES = []


def ok(name: str):
    global PASS
    PASS += 1
    print(f"  PASS  {name}")


def fail(name: str, detail: str):
    global FAIL
    FAIL += 1
    ISSUES.append(f"{name}: {detail}")
    print(f"  FAIL  {name} -> {detail}")


def login(email: str, password: str):
    r = client.post("/auth/login", json={"email_or_phone": email, "password": password})
    if r.status_code != 200:
        return None
    return r.json()


def auth_headers(token: str):
    return {"Authorization": f"Bearer {token}"}


print("\n=== Smart Clinic Smoke Tests ===\n")

# 1. Health / root
r = client.get("/docs")
if r.status_code == 200:
    ok("API docs reachable")
else:
    fail("API docs reachable", f"status {r.status_code}")

# 2. Seed accounts login
accounts = {
    "admin": ("clinova.clinic@gmail.com", "admin1234"),
    "doctor": ("dr.ahmed@clinic.com", "doctor123"),
    "receptionist": ("reception@clinic.com", "reception123"),
}
tokens = {}
for role, (email, pwd) in accounts.items():
    data = login(email, pwd)
    if data and data.get("access_token"):
        tokens[role] = data["access_token"]
        ok(f"Login {role}")
    else:
        fail(f"Login {role}", "could not login - check seed data")

# Create a test patient for patient-specific tests
patient_email = f"smoke_patient_{uuid.uuid4().hex[:8]}@test.com"
r = client.post(
    "/auth/register",
    json={
        "email": patient_email,
        "phone": f"+9665{uuid.uuid4().int % 10**8:08d}",
        "password": "TestPass123!",
        "first_name": "Smoke",
        "last_name": "Patient",
        "role": "patient",
    },
)
if r.status_code == 201:
    tokens["patient"] = r.json()["access_token"]
    ok("Register smoke-test patient")
else:
    fail("Register smoke-test patient", r.text[:200])

if "patient" not in tokens:
    print("\nCannot continue without patient token.")
    sys.exit(1)

# 3. Profile GET/PUT with medical fields
r = client.get("/patients/profile", headers=auth_headers(tokens["patient"]))
if r.status_code == 200:
    ok("GET patient profile")
    profile = r.json()
else:
    fail("GET patient profile", r.text)

r = client.put(
    "/patients/profile",
    headers=auth_headers(tokens["patient"]),
    json={
        "allergies": "test-allergy",
        "chronic_diseases": "test-chronic",
        "existing_conditions": "test-condition",
        "dob": "1990-01-15",
    },
)
if r.status_code == 200:
    body = r.json()
    if body.get("allergies") == "test-allergy":
        ok("PUT profile saves allergies/chronic/conditions")
    else:
        fail("PUT profile saves allergies/chronic/conditions", f"allergies={body.get('allergies')}")
else:
    fail("PUT profile saves allergies/chronic/conditions", r.text)

# 4. Profile photo endpoint exists
r = client.post(
    "/patients/profile/photo",
    headers=auth_headers(tokens["patient"]),
    files={"file": ("test.jpg", b"\xff\xd8\xff fake jpeg", "image/jpeg")},
)
if r.status_code == 200 and r.json().get("photo_url"):
    ok("POST profile photo upload")
else:
    fail("POST profile photo upload", f"status={r.status_code} body={r.text[:200]}")

# 5. Document upload/list
r = client.post(
    "/patients/documents/upload",
    headers=auth_headers(tokens["patient"]),
    data={"category": "other"},
    files={"file": ("report.pdf", b"%PDF-1.4 test", "application/pdf")},
)
doc_id = None
if r.status_code == 200:
    doc_id = r.json().get("id")
    ok("POST document upload")
else:
    fail("POST document upload", f"status={r.status_code} {r.text[:200]}")

r = client.get("/patients/documents", headers=auth_headers(tokens["patient"]))
if r.status_code == 200 and isinstance(r.json(), list):
    ok("GET patient documents list")
else:
    fail("GET patient documents list", r.text[:200])

# Doctor can list patient documents by patient_id
if profile.get("id"):
    r = client.get(
        f"/patients/documents?patient_id={profile['id']}",
        headers=auth_headers(tokens["doctor"]),
    )
    if r.status_code == 200:
        ok("GET documents as doctor with patient_id")
    else:
        fail("GET documents as doctor with patient_id", r.text[:200])

# 6. Static uploads served
if doc_id:
    docs = client.get("/patients/documents", headers=auth_headers(tokens["patient"])).json()
    if docs:
        file_url = docs[0].get("file_url")
        r = client.get(file_url)
        if r.status_code == 200:
            ok("Static /uploads file accessible")
        else:
            fail("Static /uploads file accessible", f"status={r.status_code} url={file_url}")

# 7. Reports with token query param
r = client.get(f"/reports/my-report?token={tokens['patient']}")
if r.status_code == 200 and r.headers.get("content-type", "").startswith("application/pdf"):
    ok("Patient my-report PDF download")
else:
    fail("Patient my-report PDF download", f"status={r.status_code} type={r.headers.get('content-type')}")

r = client.get(f"/reports/appointments?token={tokens['admin']}")
if r.status_code == 200:
    ok("Admin appointments report PDF")
else:
    fail("Admin appointments report PDF", f"status={r.status_code}")

r = client.get(f"/reports/doctors?token={tokens['admin']}")
if r.status_code == 200:
    ok("Admin doctors report PDF")
else:
    fail("Admin doctors report PDF", f"status={r.status_code}")

# Security: patient should NOT access admin reports (currently may be open - flag it)
r = client.get(f"/reports/doctors?token={tokens['patient']}")
if r.status_code == 403:
    ok("Patient blocked from admin doctors report")
elif r.status_code == 200:
    fail("Report role security", "Patient can download admin doctors report (no role check)")
else:
    ok(f"Patient blocked from admin doctors report (status {r.status_code})")

# 8. Medical records & prescriptions
r = client.get("/records/patient/me", headers=auth_headers(tokens["patient"]))
if r.status_code == 200:
    ok("GET patient medical records")
else:
    fail("GET patient medical records", r.text[:200])

r = client.get("/prescriptions/", headers=auth_headers(tokens["patient"]))
if r.status_code == 200:
    ok("GET patient prescriptions")
else:
    fail("GET patient prescriptions", r.text[:200])

# 9. Register new user preserves profile fields
email = f"test_{uuid.uuid4().hex[:8]}@test.com"
r = client.post(
    "/auth/register",
    json={
        "email": email,
        "phone": f"+9665{uuid.uuid4().int % 10**8:08d}",
        "password": "TestPass123!",
        "first_name": "Smoke",
        "last_name": "Test",
        "role": "patient",
    },
)
if r.status_code == 201:
    ok("Register new patient")
    new_token = r.json()["access_token"]
    r2 = client.get("/patients/profile", headers=auth_headers(new_token))
    if r2.status_code == 200 and r2.json().get("first_name") == "Smoke":
        ok("Register preserves first_name in profile")
    else:
        fail("Register preserves first_name in profile", r2.text[:200])
else:
    fail("Register new patient", r.text[:200])

# 10. Change password field name
r = client.post(
    "/auth/change-password",
    headers=auth_headers(tokens["patient"]),
    json={"current_password": "wrong", "new_password": "NewPass123!"},
)
if r.status_code == 400:
    ok("Change password endpoint accepts current_password")
else:
    fail("Change password endpoint", f"status={r.status_code}")

print(f"\n=== Results: {PASS} passed, {FAIL} failed ===")
if ISSUES:
    print("\nIssues found:")
    for i, issue in enumerate(ISSUES, 1):
        print(f"  {i}. {issue}")
    sys.exit(1)
print("\nAll smoke tests passed.")
sys.exit(0)
