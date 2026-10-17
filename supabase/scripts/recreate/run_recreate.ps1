# Recreates the entire eRefill Supabase database from scratch
# Requires Supabase CLI logged in and linked to project ormmjxtbwosnraijphra

$ErrorActionPreference = "Stop"
Write-Host "==> Step 1: Wiping database, storage files, auth users, and resetting schema..." -ForegroundColor Cyan
npx supabase db query --linked --file (Join-Path $PSScriptRoot "01_wipe_all.sql")

Write-Host "==> Step 2: Applying complete database schema..." -ForegroundColor Cyan
npx supabase db query --linked --file (Join-Path $PSScriptRoot "02_schema.sql")

Write-Host "==> Step 3: Applying post-setup (stations table, storage buckets & policies, triggers, system config, admin account)..." -ForegroundColor Cyan
npx supabase db query --linked --file (Join-Path $PSScriptRoot "03_post_setup.sql")

Write-Host "==> Step 4: Applying transactional proof-of-delivery receipts and private storage policies..." -ForegroundColor Cyan
npx supabase db query --linked --file (Join-Path $PSScriptRoot "..\automated_proof_of_delivery.sql")

Write-Host "==> Step 5: Applying app release management tables, policies, and initial release..." -ForegroundColor Cyan
npx supabase db query --linked --file (Join-Path $PSScriptRoot "..\app_version_management_system.sql")

Write-Host "==> Database recreation complete! Admin account ready: Admin@gmail.com / admin123" -ForegroundColor Green
