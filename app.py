from flask import Flask, jsonify
import os

app = Flask(__name__)
@app.route("/health")
def health():
    return jsonify(status="ok", version=os.environ.get("APP_VERSION", "dev"))

@app.route("/health/db")
def health_db():
    return jsonify(status="ok", database="connected")

@app.route("/api/v1/workouts")
def workouts():
    sample_workouts = [
            {"id":1, "name": "Morning Run", "duration_minutes": 30},
            {"id":2, "name": "Strength Training", "duration_minutes": 45},
    ]
    return jsonify(workouts=sample_workouts)

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)

