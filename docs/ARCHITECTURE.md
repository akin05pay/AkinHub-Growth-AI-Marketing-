# AkinHub Growth AI — Architecture

## Product boundary

The application coordinates multilingual content, relationship intelligence,
lead qualification and meeting conversion. It does not share repositories,
databases, credentials, OAuth clients or deployment boundaries with Agrinvest,
AkinBot Trading, AgroDeri or another Akin product.

## Initial modules

1. **Scout** — collects authorized sources and creates normalized observations.
2. **Hunter** — enriches and scores permitted profiles using explicit criteria.
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

- **Application:** Next.js App Router on a dedicated Vercel project.
- **Runtime:** Node.js 22.
- **Database/Auth:** dedicated Supabase project.
- **Queue:** Supabase Queues (`pgmq`) transports bounded background work.
- **Workers:** small, idempotent Supabase Edge Function handlers.
- **State:** `agent_runs` is the workflow source of truth.
- **Files:** Google Drive stores editorial artifacts; Supabase stores metadata.
- **Schedules:** Vercel Cron invokes the authenticated orchestrator.
- **Secrets:** dedicated Vercel/Supabase secret stores, never repository files.

## Delivery order

1. Foundation, authentication and RLS.
2. Queue, state machine and assisted orchestration.
3. Google Drive incremental synchronization.
4. Editorial approval and multilingual versions.
5. CRM, LGPD controls and lead scoring.
6. Calendly and meeting briefing.
7. Social networks, one official integration at a time.

See [`ORCHESTRATION.md`](./ORCHESTRATION.md) for the worker contract and state
machine.
