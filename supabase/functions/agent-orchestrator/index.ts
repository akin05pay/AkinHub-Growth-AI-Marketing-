import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "@supabase/supabase-js";

type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[];

type AgentRunStatus =
  | "queued"
  | "leased"
  | "running"
  | "waiting_for_approval"
  | "retry_scheduled"
  | "succeeded"
  | "failed"
  | "cancelled"
  | "expired";

interface QueueMessage {
  msg_id: number | string;
  read_ct: number | string;
  enqueued_at: string;
  vt: string;
  message: {
    run_id?: string;
    organization_id?: string;
  };
}

interface AgentRun {
  id: string;
  organization_id: string;
  agent_name: string;
  run_type: string;
  status: AgentRunStatus;
  input: Json;
  output: Json | null;
  approved_at: string | null;
  attempt_count: number;
  max_attempts: number;
}

interface HandlerResult {
  status: "succeeded" | "waiting_for_approval";
  output: Record<string, Json>;
}

class RunError extends Error {
  constructor(
    message: string,
    readonly code: string,
    readonly retryDelaySeconds = 60,
  ) {
    super(message);
  }
}

const queueBatchSize = clamp(
  Number(Deno.env.get("AGENT_QUEUE_BATCH_SIZE") ?? "5"),
  1,
  20,
);
const visibilityTimeout = clamp(
  Number(Deno.env.get("AGENT_QUEUE_VISIBILITY_TIMEOUT") ?? "120"),
  30,
  900,
);
const workerId = `edge:${crypto.randomUUID()}`;

const supabaseUrl = Deno.env.get("SUPABASE_URL");
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const orchestratorSecret = Deno.env.get("ORCHESTRATOR_SECRET");

if (!supabaseUrl || !serviceRoleKey) {
  throw new Error("Supabase server credentials are not configured");
}

const supabase = createClient(supabaseUrl, serviceRoleKey, {
  auth: {
    autoRefreshToken: false,
    persistSession: false,
  },
});

function clamp(value: number, minimum: number, maximum: number) {
  if (!Number.isFinite(value)) {
    return minimum;
  }

  return Math.min(Math.max(Math.trunc(value), minimum), maximum);
}

function firstRow<T>(value: T | T[] | null): T | null {
  if (Array.isArray(value)) {
    return value[0] ?? null;
  }

  return value;
}

async function transition(
  runId: string,
  status: AgentRunStatus,
  output: Record<string, Json> | null = null,
) {
  const { data, error } = await supabase.rpc("transition_agent_run", {
    p_run_id: runId,
    p_worker_id: workerId,
    p_to_status: status,
    p_output: output,
  });

  if (error) {
    throw new RunError(error.message, "TRANSITION_FAILED");
  }

  return firstRow(data as AgentRun | AgentRun[] | null);
}

async function archiveMessage(messageId: number | string) {
  const { error } = await supabase.rpc("archive_agent_queue_message", {
    p_msg_id: Number(messageId),
  });

  if (error) {
    throw new RunError(error.message, "QUEUE_ARCHIVE_FAILED");
  }
}

async function markFailed(runId: string, error: unknown) {
  const runError =
    error instanceof RunError
      ? error
      : new RunError(
          error instanceof Error ? error.message : "Unknown orchestrator error",
          "UNEXPECTED_ERROR",
        );

  const { error: failureError } = await supabase.rpc("fail_agent_run", {
    p_run_id: runId,
    p_worker_id: workerId,
    p_error_code: runError.code,
    p_error_message: runError.message.slice(0, 4000),
    p_retry_delay_seconds: runError.retryDelaySeconds,
  });

  if (failureError) {
    throw new RunError(failureError.message, "FAILURE_RECORDING_FAILED");
  }
}

async function assistedHandler(run: AgentRun): Promise<HandlerResult> {
  if (run.approved_at) {
    return {
      status: "succeeded",
      output: {
        execution_mode: "human_approved_bootstrap",
        external_side_effects: false,
        message:
          "Approval recorded. External connector execution remains disabled until its dedicated handler is implemented.",
      },
    };
  }

  return {
    status: "waiting_for_approval",
    output: {
      execution_mode: "assisted",
      external_side_effects: false,
      message:
        "The run was classified and paused before any external action. Human approval is required.",
    },
  };
}

async function dispatch(run: AgentRun): Promise<HandlerResult> {
  if (run.run_type === "system.healthcheck") {
    return {
      status: "succeeded",
      output: {
        worker_id: workerId,
        checked_at: new Date().toISOString(),
        external_side_effects: false,
      },
    };
  }

  if (
    ["scout", "hunter", "content", "sdr", "closer"].includes(run.agent_name)
  ) {
    return assistedHandler(run);
  }

  throw new RunError(
    `No handler registered for ${run.agent_name}/${run.run_type}`,
    "HANDLER_NOT_REGISTERED",
    300,
  );
}

async function processMessage(message: QueueMessage) {
  const runId = message.message?.run_id;

  if (!runId) {
    await archiveMessage(message.msg_id);
    return "invalid";
  }

  const { data, error } = await supabase.rpc("claim_agent_run", {
    p_run_id: runId,
    p_worker_id: workerId,
    p_lease_seconds: visibilityTimeout,
  });

  if (error) {
    throw new RunError(error.message, "CLAIM_FAILED");
  }

  const run = firstRow(data as AgentRun | AgentRun[] | null);

  if (!run) {
    await archiveMessage(message.msg_id);
    return "stale";
  }

  try {
    await transition(run.id, "running");
    const result = await dispatch(run);
    await transition(run.id, result.status, result.output);
    await archiveMessage(message.msg_id);
    return result.status;
  } catch (error) {
    await markFailed(run.id, error);
    await archiveMessage(message.msg_id);
    return "failed";
  }
}

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return Response.json(
      { ok: false, error: "method_not_allowed" },
      { status: 405 },
    );
  }

  if (
    !orchestratorSecret ||
    request.headers.get("x-orchestrator-secret") !== orchestratorSecret
  ) {
    return Response.json(
      { ok: false, error: "unauthorized" },
      { status: 401 },
    );
  }

  const { data, error } = await supabase.rpc("read_agent_queue", {
    p_batch_size: queueBatchSize,
    p_visibility_timeout: visibilityTimeout,
  });

  if (error) {
    return Response.json(
      { ok: false, error: "queue_read_failed" },
      { status: 500 },
    );
  }

  const messages = (data ?? []) as QueueMessage[];
  const results: Record<string, number> = {};

  for (const message of messages) {
    try {
      const result = await processMessage(message);
      results[result] = (results[result] ?? 0) + 1;
    } catch (processingError) {
      console.error("agent message processing failed", {
        messageId: message.msg_id,
        error:
          processingError instanceof Error
            ? processingError.message
            : String(processingError),
      });
      results.unhandled = (results.unhandled ?? 0) + 1;
    }
  }

  return Response.json({
    ok: true,
    workerId,
    received: messages.length,
    results,
    executedAt: new Date().toISOString(),
  });
});
