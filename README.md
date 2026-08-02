# AkinHub Growth AI Marketing

Growth operating system for Akin: multilingual content, relationship
intelligence, assisted SDR and meeting orchestration.

## Current status

This repository contains the production-oriented foundation:

- Next.js 16 App Router;
- TypeScript strict mode;
- Node.js 22 baseline;
- Supabase SSR client and Next.js `proxy.ts` session refresh;
- initial PostgreSQL schema with Row Level Security;
- health and secured daily cron routes;
- Vercel configuration;
- GitHub Actions quality gate;
- dashboard and deployment checklist.

The first release intentionally uses an assisted execution model. Generated
comments, posts and direct messages must pass through approval and channel
limits before external execution.

## Local setup

```bash
cp .env.example .env.local
npm install
npm run dev
```

The dashboard can build without Supabase credentials. Authentication and data
features require a dedicated Supabase project.

## Required infrastructure

- dedicated Vercel project;
- dedicated Supabase project;
- Google Cloud OAuth application for Drive and Calendar;
- Calendly token and webhook signing secret;
- official developer applications for each supported social platform.

## Commands

```bash
npm run dev
npm run lint
npm run typecheck
npm run build
npm run check
```

## Database

The initial migration is located in `supabase/migrations`. After creating and
linking the project, apply the migration, generate TypeScript database types,
and run both Supabase security and performance advisors.

## Security

- Never commit `.env.local` or any real credential.
- Never expose a secret or service-role key through a `NEXT_PUBLIC_` variable.
- Integration metadata may be stored in PostgreSQL; OAuth tokens belong in a
  secure secret store or encrypted vault.
- All public-schema tables use RLS.
- External actions require approval, idempotency and audit logging.

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the product boundary and
execution model.
