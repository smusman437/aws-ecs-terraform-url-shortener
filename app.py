from flask import Flask, request, jsonify, redirect
from flasgger import Swagger
import os
import random
import string

app = Flask(__name__)

url_store = {}

BASE_URL = os.environ.get("BASE_URL", "http://localhost:8080").rstrip("/")

# Swagger UI at /apidocs — interactive API testing in the browser
swagger_config = {
    "headers": [],
    "specs": [
        {
            "endpoint": "apispec",
            "route": "/apispec.json",
            "rule_filter": lambda rule: True,
            "model_filter": lambda tag: True,
        }
    ],
    "static_url_path": "/flasgger_static",
    "swagger_ui": True,
    "specs_route": "/apidocs",
}

swagger_template = {
    "swagger": "2.0",
    "info": {
        "title": "URL Shortener API",
        "description": "Create short links and redirect to original URLs. "
        "Use **Try it out** on each endpoint below to test.",
        "version": "1.0.0",
    },
    "host": BASE_URL.replace("http://", "").replace("https://", ""),
    "basePath": "/",
    "schemes": ["http"] if BASE_URL.startswith("http://") else ["https"],
    "tags": [
        {"name": "Health", "description": "Load balancer health checks"},
        {"name": "Shortener", "description": "Create and resolve short URLs"},
    ],
}

Swagger(app, config=swagger_config, template=swagger_template)


def generate_code(length=6):
    chars = string.ascii_letters + string.digits
    return "".join(random.choices(chars, k=length))


@app.route("/health", methods=["GET"])
def health():
    """Health check for ALB and monitoring
    ---
    tags:
      - Health
    responses:
      200:
        description: Service is healthy
        schema:
          type: object
          properties:
            status:
              type: string
              example: ok
    """
    return jsonify({"status": "ok"}), 200


@app.route("/shorten", methods=["POST"])
def shorten():
    """Create a short code for a long URL
    ---
    tags:
      - Shortener
    consumes:
      - application/json
    parameters:
      - in: body
        name: body
        required: true
        schema:
          type: object
          required:
            - url
          properties:
            url:
              type: string
              example: https://www.google.com
              description: The long URL to shorten
    responses:
      201:
        description: Short URL created
        schema:
          type: object
          properties:
            short_code:
              type: string
              example: xK9mP2
            original:
              type: string
              example: https://www.google.com
            short_url:
              type: string
              example: http://localhost:8080/xK9mP2
      400:
        description: Missing or invalid request body
        schema:
          type: object
          properties:
            error:
              type: string
              example: "Please provide a 'url' field"
    """
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


@app.route("/<code>", methods=["GET"], endpoint="redirect_url")
def redirect_url(code):
    """Redirect to the original URL for a short code
    ---
    tags:
      - Shortener
    parameters:
      - in: path
        name: code
        type: string
        required: true
        description: Short code from POST /shorten
        example: xK9mP2
    responses:
      302:
        description: Redirects to the original URL (browser follows automatically)
      404:
        description: Short code not found
        schema:
          type: object
          properties:
            error:
              type: string
              example: Short code not found
    """
    original = url_store.get(code)
    if not original:
        return jsonify({"error": "Short code not found"}), 404
    return redirect(original, code=302)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080, debug=False)
