import { type NextRequest } from "next/server";
import {
  approveAgentRunSchema,
  enqueueAgentRunSchema,
} from "@/lib/agents/contracts";
import { createClient } from "@/lib/supabase/server";

async function requireUser() {
  const supabase = await createClient();
  const {
    data: { user },
    error,
  } = await supabase.auth.getUser();

  if (error || !user) {
    return { supabase, user: null };
  }

  return { supabase, user };
}

export async function GET(request: NextRequest) {
  const organizationId = request.nextUrl.searchParams.get("organizationId");

  if (!organizationId) {
    return Response.json(
      { ok: false, error: "organizationId is required" },
      { status: 400 },
    );
  }

  const { supabase, user } = await requireUser();

  if (!user) {
    return Response.json(
      { ok: false, error: "unauthorized" },
      { status: 401 },
    );
  }

  const { data, error } = await supabase
    .from("agent_runs")
    .select(
      [
        "id",
        "agent_name",
        "run_type",
        "status",
        "entity_type",
        "entity_id",
        "priority",
        "attempt_count",
        "max_attempts",
        "approval_required",
        "error_code",
        "error_message",
        "created_at",
        "updated_at",
      ].join(","),
    )
    .eq("organization_id", organizationId)
    .order("created_at", { ascending: false })
    .limit(100);

  if (error) {
    return Response.json(
      { ok: false, error: "could_not_load_agent_runs" },
      { status: 400 },
    );
  }

  return Response.json({ ok: true, data });
}

export async function POST(request: NextRequest) {
  const parsed = enqueueAgentRunSchema.safeParse(await request.json());

  if (!parsed.success) {
    return Response.json(
      {
        ok: false,
        error: "invalid_request",
        issues: parsed.error.flatten(),
      },
      { status: 400 },
    );
  }

  const { supabase, user } = await requireUser();

  if (!user) {
    return Response.json(
      { ok: false, error: "unauthorized" },
      { status: 401 },
    );
  }

  const input = parsed.data;
  const { data: runId, error } = await supabase.rpc("enqueue_agent_run", {
    p_organization_id: input.organizationId,
    p_agent_name: input.agentName,
    p_run_type: input.runType,
    p_input: input.input,
    p_entity_type: input.entityType ?? null,
    p_entity_id: input.entityId ?? null,
    p_parent_run_id: input.parentRunId ?? null,
    p_idempotency_key: input.idempotencyKey ?? null,
    p_priority: input.priority,
    p_max_attempts: input.maxAttempts,
  });

  if (error) {
    return Response.json(
      { ok: false, error: "could_not_enqueue_agent_run" },
      { status: 400 },
    );
  }

  return Response.json(
    {
      ok: true,
      runId,
      status: "queued",
    },
    { status: 202 },
  );
}

export async function PATCH(request: NextRequest) {
  const runId = request.nextUrl.searchParams.get("runId");

  if (!runId) {
    return Response.json(
      { ok: false, error: "runId is required" },
      { status: 400 },
    );
  }

  const parsed = approveAgentRunSchema.safeParse(await request.json());

  if (!parsed.success) {
    return Response.json(
      {
        ok: false,
        error: "invalid_request",
        issues: parsed.error.flatten(),
      },
      { status: 400 },
    );
  }

  const { supabase, user } = await requireUser();

  if (!user) {
    return Response.json(
      { ok: false, error: "unauthorized" },
      { status: 401 },
    );
  }

  const { error } = await supabase.rpc("approve_agent_run", {
    p_run_id: runId,
    p_approved: parsed.data.approved,
    p_note: parsed.data.note ?? null,
  });

  if (error) {
    return Response.json(
      { ok: false, error: "could_not_review_agent_run" },
      { status: 400 },
    );
  }

  return Response.json({
    ok: true,
    runId,
    approved: parsed.data.approved,
  });
}
