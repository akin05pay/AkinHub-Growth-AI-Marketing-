# Agent orchestration

## Boundary

This orchestration layer belongs exclusively to
`akin05pay/AkinHub-Growth-AI-Marketing-`.

It must not connect to or reuse Agrinvest, AkinBot Trading, AgroDeri or another
Akin database, deployment, OAuth client or secret store.

## Runtime path

```text
authenticated API
  -> enqueue_agent_run()
  -> agent_runs source-of-truth row
  -> pgmq agent_jobs queue
  -> agent-orchestrator Edge Function
  -> bounded handler
  -> status event + audit log
  -> human approval when required
```

The queue transports work. `agent_runs` stores the durable state and audit
context. A queue message never becomes the canonical business record.

## States

- `queued`
- `leased`
- `running`
- `waiting_for_approval`
- `retry_scheduled`
- `succeeded`
- `failed`
- `cancelled`
- `expired`

The worker uses a lease and a visibility timeout. A failed execution is
re-enqueued with a delay until `max_attempts` is reached.

## Idempotency

Every caller should supply an `idempotencyKey` derived from the business action,
not from the HTTP request. Examples:

```text
content:draft:<content-id>:<version>
lead:qualify:<lead-id>:<profile-version>
publication:<content-id>:linkedin:<account-id>
```

The database enforces uniqueness per organization.

## Human control

Scout, Hunter, Content, SDR and Closer handlers currently run in assisted mode.
They stop at `waiting_for_approval` and execute no external side effect.

Approval is recorded through `approve_agent_run()`. The bootstrap handler then
finishes the run without publishing, commenting, messaging or modifying a
third-party account. Each connector will receive a separate implementation and
kill switch later.

## LGPD controls

Lead records include:

- lawful basis;
- collection source and method;
- processing purpose;
- consent and revocation timestamps;
- privacy-notice version;
- legitimate-interest assessment reference;
- do-not-contact and opt-out;
- retention expiration.

Public availability of data is not treated as a legal basis by itself.

## Deployment order

1. Create a dedicated Supabase project.
2. Apply migrations.
3. Run Supabase security and performance advisors.
4. Deploy `agent-orchestrator` with JWT verification enabled.
5. Configure `ORCHESTRATOR_SECRET` in Vercel and Supabase.
6. Configure the dedicated Vercel project.
7. Test only `system.healthcheck`.
8. Enable assisted handlers.
9. Add Google Drive after the queue path is verified.

## Edge Function secrets

```text
SUPABASE_URL
SUPABASE_SERVICE_ROLE_KEY
ORCHESTRATOR_SECRET
AGENT_QUEUE_BATCH_SIZE
AGENT_QUEUE_VISIBILITY_TIMEOUT
```

Do not commit values. `SUPABASE_SERVICE_ROLE_KEY` must never reach the browser.
