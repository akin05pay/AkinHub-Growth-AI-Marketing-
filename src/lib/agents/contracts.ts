import { z } from "zod";

export const agentNames = [
  "scout",
  "hunter",
  "content",
  "sdr",
  "closer",
  "system",
] as const;

export const agentRunStatuses = [
  "queued",
  "leased",
  "running",
  "waiting_for_approval",
  "retry_scheduled",
  "succeeded",
  "failed",
  "cancelled",
  "expired",
] as const;

export const agentNameSchema = z.enum(agentNames);
export const agentRunStatusSchema = z.enum(agentRunStatuses);

export const enqueueAgentRunSchema = z
  .object({
    organizationId: z.string().uuid(),
    agentName: agentNameSchema,
    runType: z.string().trim().min(3).max(100),
    input: z.record(z.string(), z.unknown()).default({}),
    entityType: z.string().trim().min(1).max(80).nullable().optional(),
    entityId: z.string().trim().min(1).max(200).nullable().optional(),
    parentRunId: z.string().uuid().nullable().optional(),
    idempotencyKey: z.string().trim().min(8).max(200).nullable().optional(),
    priority: z.number().int().min(0).max(1000).default(100),
    maxAttempts: z.number().int().min(1).max(10).default(3),
  })
  .strict();

export const approveAgentRunSchema = z
  .object({
    approved: z.boolean(),
    note: z.string().trim().max(2000).nullable().optional(),
  })
  .strict();

export type AgentName = z.infer<typeof agentNameSchema>;
export type AgentRunStatus = z.infer<typeof agentRunStatusSchema>;
export type EnqueueAgentRunInput = z.infer<typeof enqueueAgentRunSchema>;
