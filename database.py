import os
import psycopg2
from psycopg2.extras import DictCursor


def get_connection():
    url = os.getenv("DATABASE_URL")
    if not url:
        raise RuntimeError("DATABASE_URL is not configured")
    return psycopg2.connect(url, cursor_factory=DictCursor)


def create_database():
    connection = get_connection()
    try:
        with connection.cursor() as cursor:
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS noise_readings (
                    id BIGSERIAL PRIMARY KEY,
                    noise_level DOUBLE PRECISION NOT NULL,
                    recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS noise_alerts (
                    id BIGSERIAL PRIMARY KEY,
                    noise_level DOUBLE PRECISION NOT NULL,
                    threshold DOUBLE PRECISION NOT NULL,
                    recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)
        connection.commit()
        print("Neon PostgreSQL tables ready!")
    except Exception:
        connection.rollback()
        raise
    finally:
        connection.close()
