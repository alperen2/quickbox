import * as z from "zod";
import { isValidTimeZone, parseISODate } from "../core/calendar";

/**
 * Changes a device sends to the cloud. Devices apply them locally first (offline-friendly) and
 * the server replays them on its copy; every op carries a client-generated `opId` so a retry
 * after a lost response is applied only once.
 */
const opId = z.string().min(8).max(64).regex(/^[A-Za-z0-9_-]+$/);
const taskId = z.string().min(1).max(64).regex(/^[A-Za-z0-9_-]+$/);
const localNow = z.object({
  date: z.string().refine((value) => parseISODate(value) !== null, "Expected YYYY-MM-DD"),
  time: z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/, "Expected HH:mm"),
});

const patch = z
  .object({
    text: z.string().max(2000).optional(),
    due: z.string().max(64).nullable().optional(),
    priority: z.union([z.literal(1), z.literal(2), z.literal(3)]).nullable().optional(),
    assignee: z.string().max(64).nullable().optional(),
    ref: z.string().max(256).nullable().optional(),
    done: z.boolean().optional(),
    metadata: z.record(z.string().max(64), z.string().max(256).nullable()).optional(),
  })
  .strict();

export const syncOpSchema = z.discriminatedUnion("type", [
  z.object({ opId, type: z.literal("add"), text: z.string().min(1).max(2000), capturedAt: localNow }).strict(),
  z.object({ opId, type: z.literal("update"), taskId, patch }).strict(),
  z.object({ opId, type: z.literal("delete"), taskId }).strict(),
  z.object({ opId, type: z.literal("insertLine"), path: z.string().max(256), line: z.string().max(4000) }).strict(),
  z.object({ opId, type: z.literal("importFile"), path: z.string().max(256), content: z.string().max(1024 * 1024) }).strict(),
]);

export const MAX_OPS_PER_PUSH = 200;

export const pushRequestSchema = z
  .object({
    /** The device's IANA time zone; the server uses it for tasks agents add without a date. */
    timeZone: z.string().max(64).refine(isValidTimeZone, "Unknown time zone").optional(),
    ops: z.array(syncOpSchema).max(MAX_OPS_PER_PUSH),
  })
  .strict();

export type SyncOp = z.infer<typeof syncOpSchema>;
export type PushRequest = z.infer<typeof pushRequestSchema>;

export type OpResult =
  | { opId: string; ok: true }
  | { opId: string; ok: false; error: { code: string; message: string } };

export interface ChangesResponse {
  /** Pass back as `cursor` next time; the response then holds only newer versions. */
  cursor: number;
  files: { path: string; content: string; version: number }[];
}
