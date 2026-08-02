# AkinHub Growth AI — Architecture

## Product boundary

The application coordinates multilingual content, relationship intelligence,
lead qualification and meeting conversion. It does not share databases,
credentials or deployment boundaries with AkinBot Trading.

## Initial modules

1. **Scout** — collects authorized sources and creates normalized observations.
2. **Hunter** — enriches and scores profiles using explicit criteria.
3. **Content** — creates, translates, versions and submits content for approval.
4. **SDR** — drafts contextual messages and follow-ups.
5. **Closer** — turns qualified replies into meetings and opportunities.

## Human-control boundary

The default execution path is:

`discover -> analyze -> draft -> approve -> schedule -> execute -> audit`

Any connector capable of publishing, commenting or messaging must implement:

- platform-specific authorization;
- rate and volume limits;
- idempotency;
- approval status;
- an emergency disable switch;
- immutable operational logs;
- explicit handling of API and account restrictions.

## Infrastructure

- **Application:** Next.js App Router on Vercel.
- **Runtime:** Node.js 22.
- **Database/Auth:** dedicated Supabase project.
- **Files:** Google Drive for editorial artifacts; Supabase stores metadata.
- **Schedules:** Vercel Cron invokes authenticated queue endpoints.
- **Secrets:** Vercel/Supabase secret stores, never repository files.

## Delivery order

1. Foundation, authentication and RLS.
2. Google Drive content pipeline.
3. Editorial approval and multilingual versions.
4. CRM and lead scoring.
5. Calendly and meeting briefing.
6. Social networks, one official integration at a time.
