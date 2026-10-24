
import sqlite3


def create_database():
    connection = sqlite3.connect("noise.db")
    cursor = connection.cursor()

    cursor.execute("""
        CREATE TABLE IF NOT EXISTS noise_readings (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            noise_level REAL NOT NULL,
            recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)
    
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS noise_alerts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            noise_level REAL NOT NULL,
            threshold REAL NOT NULL,
            recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)



    connection.commit()
    connection.close()

    print("Noise database and table created successfully!")


if __name__ == "__main__":
    create_database()
