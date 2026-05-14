from flask import Flask, send_file
import os

app = Flask(__name__)
DATA_FILE = "trades.json"

@app.route('/')
def serve_json():
    if os.path.exists(DATA_FILE):
        # Serve as plain text for "raw" view
        return send_file(DATA_FILE, mimetype='text/plain')
    else:
        return "No trades data available yet. Please run the scraper.", 404

if __name__ == '__main__':
    # Running on port 5000 by default
    print(f"Starting server to serve {DATA_FILE} at http://localhost:5000")
    app.run(host='0.0.0.0', port=5000)
