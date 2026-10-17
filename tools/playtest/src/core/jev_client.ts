// The Jev client (game-agnostic core): one TypeSafe System One request per decision through the official
// @typesafe-ai/sdk, with a per-run request cap, token and model bookkeeping, and every failure turned into a
// JevUnavailable whose `reason` is safe to record (it never contains the API key). Dev tool only: this is the
// playtest CLI's network use; nothing under game/ talks to it except over the driver's stdin/stdout.
import { TypeSafeClient, APIError, APITimeoutError, APIConnectionError, AuthenticationError,
	PermissionDeniedError } from "@typesafe-ai/sdk";
import type { Fetch, Questions, RetryPolicy, SystemOneResult } from "@typesafe-ai/sdk";

export const DEFAULT_MODEL = "jev-latest";
export const DEFAULT_MAX_REQUESTS = 400;

/** Jev could not answer this decision; `reason` says why (no key, auth, HTTP status, timeout, cap). */
export class JevUnavailable extends Error {
	readonly reason: string;
	constructor(reason: string) {
		super(reason);
		this.reason = reason;
	}
}

export type JevClientOptions = {
	apiKey: string;
	model?: string;
	maxRequests?: number;
	/** Test seam: the SDK's HTTP transport (no network in tests). Default: global fetch. */
	fetch?: Fetch;
	/** Timeout per attempt in ms (SDK default 10 s). */
	timeoutMs?: number;
	/** Retry overrides (SDK default: 2 retries on 408/429/5xx, connection errors and timeouts). */
	retry?: Partial<RetryPolicy>;
};

export type JevStats = {
	requests: number;
	errors: number;
	input_tokens: number;
	output_tokens: number;
	/** Versioned model ids the API reported (e.g. jev-1.13.0), in first-seen order. */
	models: string[];
	max_requests: number;
	model_requested: string;
	/** Why Jev was switched off for the rest of the run (an auth failure), or null. */
	disabled: string | null;
};

export type JevReply<Q extends Questions> = { result: SystemOneResult<Q>; latencyMs: number };

export class JevClient {
	#client: TypeSafeClient;
	#stats: JevStats;

	constructor(o: JevClientOptions) {
		this.#client = new TypeSafeClient({ apiKey: o.apiKey, defaultModel: o.model ?? DEFAULT_MODEL, logLevel: "off",
			compression: false, ...(o.fetch ? { fetch: o.fetch } : {}), ...(o.timeoutMs ? { timeout: o.timeoutMs } : {}),
			...(o.retry ? { retry: o.retry } : {}) });
		this.#stats = { requests: 0, errors: 0, input_tokens: 0, output_tokens: 0, models: [],
			max_requests: o.maxRequests ?? DEFAULT_MAX_REQUESTS, model_requested: o.model ?? DEFAULT_MODEL, disabled: null };
	}

	/** Asks `questions` about `state` in one request. Throws JevUnavailable on any failure or when the cap is reached. */
	async ask<const Q extends Questions>(state: Record<string, unknown>, questions: Q): Promise<JevReply<Q>> {
		const s = this.#stats;
		if (s.disabled) throw new JevUnavailable(s.disabled);
		if (s.requests >= s.max_requests) throw new JevUnavailable(`Jev request cap (${s.max_requests}) reached`);
		s.requests++;
		const t0 = performance.now();
		try {
			const result = await this.#client.systemOne({ state: state as never, questions });
			s.input_tokens += result.usage?.input_tokens ?? 0;
			s.output_tokens += result.usage?.output_tokens ?? 0;
			if (result.model && !s.models.includes(result.model)) s.models.push(result.model);
			return { result, latencyMs: performance.now() - t0 };
		} catch (e) {
			s.errors++;
			const reason = describeJevError(e);
			if (e instanceof AuthenticationError || e instanceof PermissionDeniedError) {
				s.disabled = `${reason}; Jev disabled for the rest of the run`;
			}
			throw new JevUnavailable(reason);
		}
	}

	/** Requests, errors, tokens and models so far (a copy). */
	stats(): JevStats {
		return { ...this.#stats, models: [...this.#stats.models] };
	}
}

/** A short, key-free description of a TypeSafe SDK failure. */
export function describeJevError(e: unknown): string {
	if (e instanceof APIError) {
		const what = e instanceof AuthenticationError ? " (authentication failed)" : e instanceof PermissionDeniedError ? " (access denied)" : "";
		return `API error ${e.status}${what}`;
	}
	if (e instanceof APITimeoutError) return `API request timed out after ${e.timeoutMs} ms`;
	if (e instanceof APIConnectionError) return `API connection failed: ${e.message}`;
	return `API call failed: ${(e as Error)?.message ?? String(e)}`;
}
