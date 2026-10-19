# Security Policy

## Supported versions

The project currently provides security updates for the main branch and the latest release tracked in GitHub.

## Reporting a vulnerability

Please do not open a public issue for any suspected security vulnerability.

Use one of the following channels:

- GitHub Security Advisories for this repository
- A private report through the repository maintainer contact if one is configured

When reporting, include:

- a clear description of the issue
- affected files, routes, APIs, or components
- reproduction steps or proof of concept
- the impact on confidentiality, integrity, or availability
- any recommended mitigation

We will acknowledge reports promptly and work toward a fix with responsible disclosure.

## Security expectations

This repository contains a production-oriented Flutter + Supabase application. Please keep the following in mind when contributing:

- never commit real credentials or secret keys to source control
- store payment secrets only in Supabase Edge Function environment variables
- validate access control and row-level security rules before merging changes that affect payments, profiles, orders, or attachments
- avoid exposing raw payment details, card numbers, or CVVs in logs or client-side storage
