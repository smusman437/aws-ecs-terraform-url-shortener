from flask import Flask, request, jsonify, redirect
import os
import random
import string

app = Flask(__name__)

url_store = {}

BASE_URL = os.environ.get("BASE_URL", "http://localhost:8080").rstrip("/")


def generate_code(length=6):
    chars = string.ascii_letters + string.digits
    return "".join(random.choices(chars, k=length))


@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok"}), 200


@app.route("/shorten", methods=["POST"])
def shorten():
    data = request.get_json()

    if not data or "url" not in data:
        return jsonify({"error": "Please provide a 'url' field"}), 400

    original_url = data["url"]

    code = generate_code()
    while code in url_store:
        code = generate_code()

    url_store[code] = original_url

    return jsonify({
        "short_code": code,
        "original": original_url,
        "short_url": f"{BASE_URL}/{code}",
    }), 201


@app.route("/<code>", methods=["GET"])
def redirect_url(code):
    original = url_store.get(code)
    if not original:
        return jsonify({"error": "Short code not found"}), 404
    return redirect(original, code=302)


@app.route("/all", methods=["GET"])
def list_all():
    return jsonify(url_store), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080, debug=False)
