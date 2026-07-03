"""CLI: python -m scripts.purge_patients"""

from __future__ import annotations

import sys
from pathlib import Path

BACKEND = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BACKEND))

from database import SessionLocal
from patient_purge import purge_all_patients


def main() -> None:
    confirm = input('Type DELETE_ALL_PATIENTS to permanently remove every patient: ').strip()
    if confirm != "DELETE_ALL_PATIENTS":
        print("Aborted.")
        sys.exit(1)
    db = SessionLocal()
    try:
        stats = purge_all_patients(db)
        print("Done:", stats)
    finally:
        db.close()


if __name__ == "__main__":
    main()
