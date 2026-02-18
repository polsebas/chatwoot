#!/usr/bin/env bash
# Build all images in the correct order (base must exist before rails/vite).
set -e
cd "$(dirname "$0")/.."
echo "Building base image (chatwoot:development)..."
docker compose build base
echo "Building rails, vite, and sidekiq images..."
docker compose build
