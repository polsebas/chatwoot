#!/usr/bin/env bash
# Ensures Ruby (rbenv, rvm, or system) is on PATH before running dev processes.
# Use: ./script/dev-all.sh or pnpm run dev:all

set -e

# Load rbenv if available (most common in Chatwoot dev)
if [ -d "${HOME}/.rbenv" ]; then
  export PATH="${HOME}/.rbenv/shims:${HOME}/.rbenv/bin:${PATH}"
  if command -v rbenv &>/dev/null; then
    eval "$(rbenv init - bash 2>/dev/null || rbenv init - 2>/dev/null)" || true
  fi
fi

# RVM
if [ -f "${HOME}/.rvm/scripts/rvm" ]; then
  # shellcheck source=/dev/null
  source "${HOME}/.rvm/scripts/rvm"
fi

# asdf
if [ -f "${HOME}/.asdf/asdf.sh" ]; then
  # shellcheck source=/dev/null
  source "${HOME}/.asdf/asdf.sh"
fi

if ! command -v ruby &>/dev/null; then
  echo "Error: Ruby not found. Install Ruby (e.g. rbenv install \$(cat .ruby-version)) and ensure it is on PATH." >&2
  exit 1
fi

cd "$(dirname "$0")/.."
exec pnpm exec concurrently -n backend,worker,vite -c blue,magenta,green \
  "bin/rails s -p 3000" \
  "bundle exec dotenv bundle exec sidekiq -C config/sidekiq.yml" \
  "bin/vite dev"
