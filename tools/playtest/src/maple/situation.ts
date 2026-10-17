// The Maple situation that travels with every decide (adapter). The driver builds it in
// game/tools/playtest/playtest_situation.gd; that header is the source of truth, these types mirror it. Keys are only
// ever added (later tickets may add bucket keys), never renamed or removed.

export type PoolBucket = "critical" | "low" | "ok" | "full";
export type MobsBucket = "none" | "few" | "crowd" | "swarm";
export type BossBucket = "none" | "present" | "attacking";
export type StockBucket = "none" | "few" | "plenty";
export type CountBucket = "none" | "some" | "many";
export type PhaseBucket = "early" | "mid" | "late" | "boss";

/** Named buckets computed in code so the brain judges meaning, not arithmetic. */
export type Buckets = {
	hp: PoolBucket;
	mp: PoolBucket;
	mobs_near: MobsBucket;
	/** mobs_near as an ordinal 0..3. */
	mobs_near_step: number;
	boss: BossBucket;
	potions_hp: StockBucket;
	potions_mp: StockBucket;
	drops_near: CountBucket;
	drops_above: CountBucket;
	phase: PhaseBucket;
	/** FootholdMap platform under the player (-1 none). */
	platform: number;
	recent_hits: CountBucket;
	[key: string]: unknown;
};

/** The tactic state on a `tactic` decide. */
export type TacticState = { current: string; trigger: string; held_s: number; switches: number };

export type Situation = {
	state?: string; time?: number; level?: number; job_id?: number; job?: string; hp?: number; max_hp?: number;
	mp?: number; max_mp?: number; kills?: number; alive?: number; skills?: string[]; advancement?: boolean; bonus?: boolean;
	buckets?: Buckets;
	tactic?: TacticState;
	[key: string]: unknown;
};

/** tier C: the game-side bucket thresholds (playtest_situation.gd POOL_* and MOBS_*), mirrored for the one place the
 * Node side buckets recorded numbers itself (the evaluation facts over timeline rows). Decides carry their buckets;
 * never bucket a decide's raw pools here. test/situation.test.ts keeps these equal to the GDScript constants. */
export const SITUATION_THRESHOLDS = {
	POOL_CRITICAL: 0.25, POOL_LOW: 0.5, POOL_FULL: 0.95, MOBS_FEW: 1, MOBS_CROWD: 4, MOBS_SWARM: 12,
} as const;

/** playtest_situation.gd pool_bucket: "critical" | "low" | "ok" | "full" for `value` of a pool of `max` (empty: full). */
export function poolBucket(value: number, max: number): PoolBucket {
	if (max <= 0) return "full";
	const f = value / max;
	if (f < SITUATION_THRESHOLDS.POOL_CRITICAL) return "critical";
	if (f < SITUATION_THRESHOLDS.POOL_LOW) return "low";
	return f >= SITUATION_THRESHOLDS.POOL_FULL ? "full" : "ok";
}

/** playtest_situation.gd mobs_bucket: "none" | "few" | "crowd" | "swarm" for `n` mobs near. */
export function mobsBucket(n: number): MobsBucket {
	if (n >= SITUATION_THRESHOLDS.MOBS_SWARM) return "swarm";
	if (n >= SITUATION_THRESHOLDS.MOBS_CROWD) return "crowd";
	return n >= SITUATION_THRESHOLDS.MOBS_FEW ? "few" : "none";
}

/** What a deterministic answer read, for decisions.jsonl `situation_shown` (story 20): the decide's buckets and, on
 * a tactic decide, the current tactic, the trigger and how long it was held. Small on purpose (no raw facts, no
 * options: those are recorded beside it). A Jev answer records its exact request state instead. */
export function fallbackSituation(situation: Record<string, unknown> | undefined): Record<string, unknown> {
	const t = (situation as Situation | undefined)?.tactic;
	return { ...(bucketsOf(situation) ? { buckets: bucketsOf(situation) } : {}),
		...(t ? { tactic: { current: t.current, trigger: t.trigger, held_s: t.held_s } } : {}) };
}

/** The situation's buckets, or null when the decide carries none. */
export function bucketsOf(situation: Record<string, unknown> | undefined): Buckets | null {
	const b = (situation as Situation | undefined)?.buckets;
	return b && typeof b === "object" ? b : null;
}
