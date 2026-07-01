import os
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, declarative_base

# NOTE: For production migrations, use Alembic (alembic init, alembic revision --autogenerate, alembic upgrade head).

DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./clinic.db")

# Railway gives postgres:// but SQLAlchemy 2.x requires postgresql://
if DATABASE_URL.startswith("postgres://"):
    DATABASE_URL = DATABASE_URL.replace("postgres://", "postgresql://", 1)

connect_args = {"check_same_thread": False} if "sqlite" in DATABASE_URL else {}
engine = create_engine(DATABASE_URL, connect_args=connect_args)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
