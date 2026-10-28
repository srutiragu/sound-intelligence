
from flask import Flask, jsonify, request
from flask_cors import CORS
from database import create_database
import sqlite3
import time
import os
import requests

app = Flask(__name__)
CORS(app)


# Create the database if it doesn't exist
create_database()


@app.route("/")
def home():
    return jsonify({
        "message": "Noise Monitoring Backend is running!",
        "status": "success"
    })


# Save a noise reading

def send_telegram_alert(noise_level):
    token = os.getenv("TELEGRAM_BOT_TOKEN")
    chat_id = os.getenv("TELEGRAM_CHAT_ID")

    if not token or not chat_id:
        print("Telegram credentials missing")
        return

    message = (
        "🚨 EchoSense Noise Alert!\n\n"
        f"Noise level: {noise_level} dB\n"
        f"Threshold: 95.0 dB\n"
        "Noise has remained above the threshold."
    )

    try:
        response = requests.post(
            f"https://api.telegram.org/bot{token}/sendMessage",
            data={"chat_id": chat_id, "text": message},
            timeout=10
        )
        response.raise_for_status()
        print("Telegram alert sent!")
    except requests.RequestException as e:
        print(f"Telegram alert failed: {e}")

def check_for_alert(noise_level):
    global above_since, last_alert_time, alert_acknowledged

    now = time.time()

    if noise_level <= NOISE_THRESHOLD:
        above_since = None
        last_alert_time = 0
        alert_acknowledged = False
        return False

    if above_since is None:
        above_since = now
        last_alert_time = 0
        alert_acknowledged = False

    if now - above_since < SUSTAIN_SECONDS:
        return False

    if alert_acknowledged:
        return False

    if last_alert_time != 0 and now - last_alert_time < REMINDER_SECONDS:
        return False

    connection = sqlite3.connect("noise.db")
    cursor = connection.cursor()
    cursor.execute(
        "INSERT INTO noise_alerts (noise_level, threshold) VALUES (?, ?)",
        (noise_level, NOISE_THRESHOLD)
    )
    connection.commit()
    connection.close()

    last_alert_time = now
    send_telegram_alert(noise_level)
    return True



@app.route("/noise", methods=["POST"])
def add_noise_reading():
    data = request.get_json(silent=True)

    if not data or "noise_level" not in data:
        return jsonify({"error": "Please provide noise_level"}), 400

    try:
        noise_level = float(data["noise_level"])
    except (ValueError, TypeError):
        return jsonify({"error": "noise_level must be a number"}), 400

    if noise_level < 0:
        return jsonify({"error": "noise_level cannot be negative"}), 400

    connection = sqlite3.connect("noise.db")
    cursor = connection.cursor()
    cursor.execute(
        "INSERT INTO noise_readings (noise_level) VALUES (?)",
        (noise_level,)
    )
    connection.commit()
    reading_id = cursor.lastrowid
    connection.close()

    alert_created = check_for_alert(noise_level)

    return jsonify({
        "message": "Noise reading saved successfully!",
        "id": reading_id,
        "noise_level": noise_level,
        "threshold": NOISE_THRESHOLD,
        "status": "HIGH" if noise_level > NOISE_THRESHOLD else "NORMAL",
        "alert_created": alert_created
    }), 201


# Retrieve saved noise readings
@app.route("/noise", methods=["GET"])
def get_noise_readings():
    connection = sqlite3.connect("noise.db")
    connection.row_factory = sqlite3.Row
    cursor = connection.cursor()

    cursor.execute("""
        SELECT id, noise_level, recorded_at
        FROM noise_readings
        ORDER BY id DESC
    """)

    readings = [dict(row) for row in cursor.fetchall()]
    connection.close()

    return jsonify(readings)

@app.route("/threshold", methods=["GET"])
def get_threshold():
    return jsonify({
        "threshold": NOISE_THRESHOLD,
        "unit": "dB"
    })


@app.route("/threshold", methods=["PUT"])
def update_threshold():
    global NOISE_THRESHOLD

    data = request.get_json(silent=True)

    if not data or "threshold" not in data:
        return jsonify({
            "error": "Please provide a threshold"
        }), 400

    try:
        new_threshold = float(data["threshold"])
    except (ValueError, TypeError):
        return jsonify({
            "error": "Threshold must be a number"
        }), 400

    if not 0 < new_threshold < 200:
        return jsonify({
            "error": "Threshold must be between 0 and 200"
        }), 400

    NOISE_THRESHOLD = new_threshold

    return jsonify({
        "message": "Threshold updated successfully!",
        "threshold": NOISE_THRESHOLD,
        "unit": "dB"
    })

@app.route("/noise/status", methods=["POST"])
def check_noise_status():
    data = request.get_json(silent=True)

    if not data or "noise_level" not in data:
        return jsonify({
            "error": "Please provide noise_level"
        }), 400

    try:
        noise_level = float(data["noise_level"])
    except (ValueError, TypeError):
        return jsonify({
            "error": "noise_level must be a number"
        }), 400

    if noise_level < 0:
        return jsonify({
            "error": "Noise level cannot be negative"
        }), 400

    return jsonify({
        "noise_level": noise_level,
        "threshold": NOISE_THRESHOLD,
        "status": (
            "HIGH" if noise_level > NOISE_THRESHOLD
            else "NORMAL"
        )
    })

@app.route("/noise", methods=["DELETE"])
def delete_noise_readings():
    connection = sqlite3.connect("noise.db")
    cursor = connection.cursor()

    cursor.execute("DELETE FROM noise_readings")

    deleted_count = cursor.rowcount

    connection.commit()
    connection.close()

    return jsonify({
        "message": "Noise history cleared successfully!",
        "deleted_count": deleted_count
    })

@app.route("/dashboard", methods=["GET"])
def get_dashboard():
    connection = sqlite3.connect("noise.db")
    connection.row_factory = sqlite3.Row
    cursor = connection.cursor()

    cursor.execute("""
        SELECT noise_level, recorded_at
        FROM noise_readings
        ORDER BY id DESC
        LIMIT 1
    """)

    latest_reading = cursor.fetchone()
    connection.close()

    if latest_reading is None:
        return jsonify({
            "latest_noise_level": None,
            "threshold": NOISE_THRESHOLD,
            "status": "NO_DATA",
            "recorded_at": None
        })

    noise_level = latest_reading["noise_level"]

    return jsonify({
        "latest_noise_level": noise_level,
        "threshold": NOISE_THRESHOLD,
        "status": (
            "HIGH" if noise_level > NOISE_THRESHOLD
            else "NORMAL"
        ),
        "recorded_at": latest_reading["recorded_at"]
    })


@app.route("/noise/statistics", methods=["GET"])
def get_noise_statistics():
    connection = sqlite3.connect("noise.db")
    cursor = connection.cursor()

    cursor.execute("""
        SELECT
            COUNT(*),
            AVG(noise_level),
            MAX(noise_level),
            MIN(noise_level)
        FROM noise_readings
    """)

    count, average, maximum, minimum = cursor.fetchone()
    connection.close()

    return jsonify({
        "total_readings": count,
        "average_noise": round(average, 2) if average is not None else None,
        "maximum_noise": maximum,
        "minimum_noise": minimum
    })

@app.route("/alerts", methods=["GET"])
def get_noise_alerts():
    connection = sqlite3.connect("noise.db")
    connection.row_factory = sqlite3.Row
    cursor = connection.cursor()

    cursor.execute("""
        SELECT id, noise_level, threshold, recorded_at
        FROM noise_alerts
        ORDER BY id DESC
    """)

    alerts = [dict(row) for row in cursor.fetchall()]
    connection.close()

    return jsonify(alerts)


@app.route("/alerts", methods=["POST"])
def create_noise_alert():
    data = request.get_json(silent=True)

    if not data or "noise_level" not in data:
        return jsonify({"error": "Please provide noise_level"}), 400

    try:
        noise_level = float(data["noise_level"])
    except (ValueError, TypeError):
        return jsonify({"error": "noise_level must be a number"}), 400

    if noise_level < 0:
        return jsonify({"error": "Noise level cannot be negative"}), 400

    if noise_level <= NOISE_THRESHOLD:
        return jsonify({
            "message": "Noise is within the threshold. No alert created.",
            "status": "NORMAL"
        }), 200

    connection = sqlite3.connect("noise.db")
    cursor = connection.cursor()

    cursor.execute(
        "INSERT INTO noise_alerts (noise_level, threshold) VALUES (?, ?)",
        (noise_level, NOISE_THRESHOLD)
    )

    connection.commit()
    alert_id = cursor.lastrowid
    connection.close()

    return jsonify({
        "message": "High-noise alert recorded!",
        "id": alert_id,
        "noise_level": noise_level,
        "threshold": NOISE_THRESHOLD,
        "status": "HIGH"
    }), 201

@app.route("/alerts", methods=["DELETE"])
def delete_noise_alerts():
    connection = sqlite3.connect("noise.db")
    cursor = connection.cursor()

    cursor.execute("DELETE FROM noise_alerts")
    deleted_count = cursor.rowcount

    connection.commit()
    connection.close()

    return jsonify({
        "message": "Alert history cleared successfully!",
        "deleted_count": deleted_count
    })

@app.route("/noise/filter", methods=["GET"])
def filter_noise_readings():
    date = request.args.get("date")

    if not date:
        return jsonify({
            "error": "Please provide a date in YYYY-MM-DD format"
        }), 400

    connection = sqlite3.connect("noise.db")
    connection.row_factory = sqlite3.Row
    cursor = connection.cursor()

    cursor.execute("""
        SELECT id, noise_level, recorded_at
        FROM noise_readings
        WHERE DATE(recorded_at) = ?
        ORDER BY id DESC
    """, (date,))

    readings = [dict(row) for row in cursor.fetchall()]
    connection.close()

    return jsonify({
        "date": date,
        "total_readings": len(readings),
        "readings": readings
    })

@app.route("/noise/daily-summary", methods=["GET"])
def daily_noise_summary():
    date = request.args.get("date")

    if not date:
        return jsonify({
            "error": "Please provide a date in YYYY-MM-DD format"
        }), 400

    connection = sqlite3.connect("noise.db")
    cursor = connection.cursor()

    cursor.execute("""
        SELECT
            COUNT(*),
            ROUND(AVG(noise_level), 2),
            MAX(noise_level),
            MIN(noise_level)
        FROM noise_readings
        WHERE DATE(recorded_at) = ?
    """, (date,))

    result = cursor.fetchone()
    connection.close()

    return jsonify({
        "date": date,
        "total_readings": result[0],
        "average_noise": result[1],
        "maximum_noise": result[2],
        "minimum_noise": result[3]
    })

@app.route("/alerts/acknowledge", methods=["POST"])
def acknowledge_alert():
    global alert_acknowledged

    if above_since is None:
        return jsonify({
            "message": "No active noise incident."
        }), 400

    alert_acknowledged = True

    return jsonify({
        "message": "Alert acknowledged. Repeat alerts stopped."
    })


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)


@app.route("/test-telegram")
def test_telegram():
    send_telegram_alert(100)
    return "Telegram test attempted"