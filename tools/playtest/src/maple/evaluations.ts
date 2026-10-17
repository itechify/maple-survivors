// Jev-assisted evaluations (adapter, #99): after the round, narrow questions over facts that code prepared
// (eval_facts.ts), one request per state with its independent questions batched (TypeSafe speculative fan-out), the
// requests sent in parallel:
//   death     (DEAD only) a Score "how fair was this death" from clearly fair to clearly unfair, plus a Noul "could a
//             careful player have avoided this death with what was on screen?"
//   pacing    one Score per run minute, "how busy and engaging", from busy to nothing happening
//   movement  a Noul "does this look like the player was stuck or moving awkwardly?"
// plus card offers, which need no request: the meaningfulness Score the Jev brain asked with every card (#94).
//
// Classification policy (explicit here; thresholds are tier C, ours): each question has a direction ("higher" or
// "lower" is worse) and a threshold. Past the threshold with confidence >= FLAG_CONFIDENCE is Jev-flagged; past it
// with less confidence needs human review; otherwise it is not reported. A Noul has no confidence of its own: we use
// |2p - 1| (TypeSafe's Confidence page). Jev results never change the exit code unless --strict-eval is set
// (run.ts), and "needs review" never does.
import { noul, score } from "@typesafe-ai/sdk";
import type { JevClient } from "../core/jev_client.ts";
import { JevUnavailable } from "../core/jev_client.ts";
import type { Opinion } from "../core/report.ts";
import { deathFacts, minuteFacts, movementFacts, cardOffers, finalRound } from "./eval_facts.ts";
import type { RunData } from "./eval_facts.ts";

/** tier C: Jev-flagged needs at least this confidence (ticket #99). */
export const FLAG_CONFIDENCE = 0.6;

export type Rule = { type: "score" | "noul"; threshold: number; worse: "higher" | "lower" };

/** tier C: the flag thresholds, per question. Scores are on their level scale (0 = first level). */
export const RULES = {
	/** Fairness levels 0..3, 3 = clearly unfair: "somewhat unfair" or worse. */
	death_fairness: { type: "score", threshold: 2, worse: "higher" },
	/** p(a careful player could have avoided it): a likely "no" is the finding. */
	death_avoidable: { type: "noul", threshold: 0.4, worse: "lower" },
	/** Pacing levels 0..3, 3 = nothing happening: "slow" or worse. */
	minute_pacing: { type: "score", threshold: 2, worse: "higher" },
	/** Meaningfulness levels 0..3 (jev_brain.ts MEANINGFUL_LEVELS, higher = better): "weak" or "empty", i.e. every card was
	 * minor for the character. */
	card_offer: { type: "score", threshold: 1, worse: "lower" },
	/** p(stuck or awkward). */
	movement: { type: "noul", threshold: 0.6, worse: "higher" },
} as const satisfies Record<string, Rule>;

export type EvalClass = "flagged" | "review" | "none";

/** A Noul's confidence-style number: |2p - 1| (0 at p = 0.5, 1 at p = 0 or 1). */
export function noulConfidence(p: number): number {
	return Math.round(Math.abs(2 * p - 1) * 1000) / 1000;
}

/** The class of `value` (a score or a Noul p) with `confidence` under `rule`. */
export function classify(rule: Rule, value: number, confidence: number): EvalClass {
	const past = rule.worse === "higher" ? value >= rule.threshold : value <= rule.threshold;
	if (!past) return "none";
	return confidence >= FLAG_CONFIDENCE ? "flagged" : "review";
}

export const FAIRNESS_LEVELS = [
	"Clearly fair: the danger was visible for a while and the player had the time and the means to react",
	"Mostly fair: the danger was visible, though the margin was small",
	"Somewhat unfair: the danger built up faster than a player could reasonably answer",
	"Clearly unfair: the player died suddenly to something they could not see coming or could not escape",
] as const;

export const PACING_LEVELS = [
	"Busy and engaging: plenty of fighting, progress or choices",
	"Active: something worthwhile happened",
	"Slow: little happened",
	"Nothing happening: no fights, no progress, no choices",
] as const;

export type EvalRequest = { id: "death" | "pacing" | "movement"; state: Record<string, unknown>;
	questions: Record<string, ReturnType<typeof score> | ReturnType<typeof noul>> };

/** The evaluation requests for `d`: death (DEAD only), pacing (when a minute is long enough) and movement (with a
 * timeline). */
export function evaluationRequests(d: RunData): EvalRequest[] {
	const out: EvalRequest[] = [];
	const death = deathFacts(d);
	if (death) {
		out.push({ id: "death", state: death.state, questions: {
			fairness: score("How fair was this death for the player?", FAIRNESS_LEVELS),
			avoidable: noul("Could a careful player have avoided this death with what was on screen?", {
				true: "A careful player could have seen the danger in time and escaped it, for example by moving away, drinking a potion or not closing in",
				false: "Even a careful player would most likely have died here" }),
		} });
	}
	const pacing = minuteFacts(d);
	if (pacing.minutes.length) {
		out.push({ id: "pacing", state: pacing.state, questions: Object.fromEntries(pacing.minutes.map((m) =>
			[m.key, score(`How busy and engaging was "${m.label}" for the player?`, PACING_LEVELS)])) });
	}
	if (finalRound(d).timeline.length) {
		out.push({ id: "movement", state: movementFacts(d).state, questions: {
			awkward: noul("Does this look like the player was stuck or moving awkwardly?", {
				true: "The player stayed in one place for long stretches while there was a reason to move, kept getting stuck, or ignored drops that were left above",
				false: "The player moved around the map in a normal way" }),
		} });
	}
	return out;
}

export type EvalResult = {
	id: string; kind: "death_fairness" | "death_avoidable" | "minute_pacing" | "movement" | "card_offer";
	question: string; value: number; confidence: number; probabilities?: Record<string, number>;
	rule: Rule; class: EvalClass; time?: number; tick?: number; label?: string; detail?: string;
};

export type Evaluations = {
	status: "done" | "partial" | "skipped" | "failed";
	/** Why the evaluations were skipped. */
	reason?: string;
	/** One line per failed request: "<request>: <reason>". */
	errors: string[];
	results: EvalResult[];
	requests: number; input_tokens: number; output_tokens: number; models: string[];
	/** The facts sent with each request (the exact state), by request id. */
	states: Record<string, unknown>;
	/** Minutes not judged, with why. */
	skipped_minutes: string[];
	/** A tier chain is judged on its last round only (its tier), else null. */
	tier: number | null;
	thresholds: { flag_confidence: number; rules: typeof RULES };
};

const r3 = (x: number) => Math.round(x * 1000) / 1000;

/** Runs the evaluations of `data` with `client` (null: skipped, with `skip` as the reason). Never throws: a failed
 * request is recorded in `errors` and its questions are left out. */
export async function runEvaluations(o: { client: JevClient | null; skip?: string; data: RunData }): Promise<Evaluations> {
	const base: Evaluations = { status: "skipped", errors: [], results: [], requests: 0, input_tokens: 0, output_tokens: 0,
		models: [], states: {}, skipped_minutes: [], tier: finalRound(o.data).tier, thresholds: { flag_confidence: FLAG_CONFIDENCE, rules: RULES } };
	if (!o.client) return { ...base, reason: o.skip ?? "no Jev client" };
	const client = o.client;
	const results: EvalResult[] = [];
	const errors: string[] = [];
	const death = deathFacts(o.data);
	const pacing = minuteFacts(o.data);
	const move = movementFacts(o.data);
	const reqs = evaluationRequests(o.data);
	const replies = await Promise.all(reqs.map(async (req) => {
		try {
			return { req, reply: await client.ask(req.state, req.questions) };
		} catch (e) {
			errors.push(`${req.id}: ${e instanceof JevUnavailable ? e.reason : (e as Error).message}`);
			return { req, reply: null };
		}
	}));
	type Ans = { score?: number; noul?: number; confidence?: number; probabilities?: Record<string, number> };
	for (const { req, reply } of replies) {
		if (!reply) continue;
		const a = reply.result.answers as Record<string, Ans>;
		const scoreResult = (id: string, kind: EvalResult["kind"], rule: Rule, ans: Ans | undefined, question: string,
			extra: Partial<EvalResult>) => {
			if (typeof ans?.score !== "number") return;
			const confidence = r3(ans.confidence ?? 0);
			results.push({ id, kind, question, value: r3(ans.score), confidence, probabilities: ans.probabilities, rule,
				class: classify(rule, ans.score, confidence), ...extra });
		};
		const noulResult = (id: string, kind: EvalResult["kind"], rule: Rule, ans: Ans | undefined, question: string,
			extra: Partial<EvalResult>) => {
			if (typeof ans?.noul !== "number") return;
			const confidence = noulConfidence(ans.noul);
			results.push({ id, kind, question, value: r3(ans.noul), confidence, rule, class: classify(rule, ans.noul, confidence), ...extra });
		};
		if (req.id === "death" && death) {
			const at = { time: death.time, tick: death.tick, detail: death.title };
			scoreResult("death_fairness", "death_fairness", RULES.death_fairness, a.fairness, "How fair was this death for the player?", at);
			noulResult("death_avoidable", "death_avoidable", RULES.death_avoidable, a.avoidable,
				"Could a careful player have avoided this death with what was on screen?", at);
		} else if (req.id === "pacing") {
			for (const m of pacing.minutes) {
				scoreResult(`minute_pacing:${m.key}`, "minute_pacing", RULES.minute_pacing, a[m.key],
					`How busy and engaging was "${m.label}" for the player?`, { time: m.start, tick: Math.round(m.start * 60), label: m.label });
			}
		} else if (req.id === "movement") {
			noulResult("movement", "movement", RULES.movement, a.awkward, "Does this look like the player was stuck or moving awkwardly?",
				move.longestStart !== null ? { time: move.longestStart, tick: Math.round(move.longestStart * 60) } : {});
		}
	}
	for (const c of cardOffers(o.data)) {
		results.push({ id: `card_offer:${c.id}`, kind: "card_offer", question: "How meaningful is this card offer for this character right now?",
			value: r3(c.score), confidence: r3(c.confidence), rule: RULES.card_offer, class: classify(RULES.card_offer, c.score, c.confidence),
			...(c.time !== null ? { time: c.time } : {}), ...(c.tick !== null ? { tick: c.tick } : {}),
			detail: `offered ${c.options.join(", ")}; took ${c.answer}` });
	}
	const stats = client.stats();
	const status = errors.length === 0 ? "done" : errors.length < reqs.length ? "partial" : "failed";
	return { ...base, status, errors, results, requests: replies.filter((r) => r.reply).length + errors.length,
		input_tokens: stats.input_tokens, output_tokens: stats.output_tokens, models: stats.models,
		states: Object.fromEntries(reqs.map((r) => [r.id, r.state])), skipped_minutes: pacing.skipped };
}

const RANK: Record<EvalClass, number> = { flagged: 0, review: 1, none: 2 };
const worst = (xs: EvalClass[]): EvalClass => xs.reduce((a, b) => (RANK[b] < RANK[a] ? b : a), "none" as EvalClass);
const lvl = (r: EvalResult, top: number) => `${r.value} of ${top} (confidence ${r.confidence})`;

/** The report entries of `e`: one per finding past its threshold (the two death questions merge into one entry,
 * consecutive dull minutes of one class into one stretch), flagged and review alike, by run time. */
export function opinionsOf(e: Evaluations): Opinion[] {
	const out: Opinion[] = [];
	const shown = e.results.filter((r) => r.class !== "none");
	const deaths = e.results.filter((r) => r.kind === "death_fairness" || r.kind === "death_avoidable");
	const deathClass = worst(deaths.map((r) => r.class));
	if (deathClass !== "none") {
		const f = deaths.find((r) => r.kind === "death_fairness");
		const v = deaths.find((r) => r.kind === "death_avoidable");
		out.push({ kind: "death_fairness", class: deathClass, title: "death felt unfair", message: (f ?? v)!.detail ?? "",
			time: (f ?? v)!.time, tick: (f ?? v)!.tick,
			evidence: [f ? `unfairness ${lvl(f, FAIRNESS_LEVELS.length - 1)}` : "", v ? `avoidable by a careful player: p ${v.value}` : ""]
				.filter(Boolean).join("; ") });
	}
	const minutes = shown.filter((r) => r.kind === "minute_pacing");
	for (let i = 0; i < minutes.length;) {
		let j = i;
		while (j + 1 < minutes.length && minutes[j + 1].class === minutes[i].class
			&& (minutes[j + 1].time ?? 0) - (minutes[j].time ?? 0) <= 60.001) j++;
		const run = minutes.slice(i, j + 1);
		out.push({ kind: "minute_pacing", class: minutes[i].class, title: run.length > 1 ? "dull stretch" : "dull minute",
			message: run.map((r) => r.label).join(", "), time: run[0].time, tick: run[0].tick,
			evidence: run.map((r) => `${r.label?.split(" (")[0]}: dullness ${lvl(r, PACING_LEVELS.length - 1)}`).join("; ") });
		i = j + 1;
	}
	for (const r of shown.filter((x) => x.kind === "movement")) {
		out.push({ kind: "movement", class: r.class, title: "stuck or awkward movement", message: "the movement summary looks stuck or awkward",
			time: r.time, tick: r.tick, evidence: `p ${r.value} (confidence ${r.confidence})` });
	}
	for (const r of shown.filter((x) => x.kind === "card_offer")) {
		out.push({ kind: "card_offer", class: r.class, title: "minor card offer", message: `every card looked minor for the character: ${r.detail}`,
			time: r.time, tick: r.tick, evidence: `meaningfulness ${lvl(r, 3)}` });
	}
	return out.sort((a, b) => RANK[a.class] - RANK[b.class] || (a.time ?? Infinity) - (b.time ?? Infinity));
}

/** One line on the evaluations for the report header and the Problems section. */
export function evaluationsLine(e: Evaluations): string {
	if (e.status === "skipped") return `skipped (${e.reason})`;
	const flagged = e.results.filter((r) => r.class === "flagged").length;
	const review = e.results.filter((r) => r.class === "review").length;
	const kinds = [...new Set(e.results.map((r) => r.kind.replace(/_(fairness|avoidable)$/, "")))].join(", ");
	return `${e.status}: ${e.results.length} judgements (${kinds || "none"}), ${flagged} flagged, ${review} need review; ` +
		`${e.requests} requests, ${e.input_tokens} input + ${e.output_tokens} output tokens${e.models.length ? `, ${e.models.join(", ")}` : ""}` +
		(e.errors.length ? `; failed: ${e.errors.join("; ")}` : "");
}
