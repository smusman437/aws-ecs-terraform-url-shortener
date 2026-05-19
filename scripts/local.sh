#!/usr/bin/env bash
# =============================================================================
# local.sh — Run the URL shortener on your laptop (no AWS required)
# Usage: ./scripts/local.sh
# =============================================================================

set -euo pipefail

# Go to project root (parent of scripts/)
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

echo "==> Building image..."
# --platform linux/arm64 matches Apple Silicon Mac; same arch as ECS Fargate ARM64
docker build --platform linux/arm64 -t url-shortener .

echo "==> Starting container on http://localhost:8080"
echo "    Press Ctrl+C to stop"
# --rm = delete container when stopped
# -p 8080:8080 = map laptop port 8080 → container port 8080
docker run --rm -p 8080:8080 url-shortener
