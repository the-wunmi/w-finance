#!/usr/bin/env bash
set -o errexit

echo "Installing gems..."
bundle install

echo "Clobbering old assets..."
bundle exec rails assets:clobber

echo "Precompiling assets for production..."
bundle exec rails assets:precompile

schema_version=$(bundle exec rails db:version | { grep "^Current version: [0-9]\\+$" || true; } | tr -s ' ' | cut -d ' ' -f3)

if [ "$schema_version" -eq "0" ]; then
  echo "Setting up database schema..."
  bundle exec rails db:schema:load
else
  echo "Running database migrations..."
  bundle exec rails db:migrate
fi

echo "Seeding database..."
bundle exec rails db:seed

echo "✅ Build complete"