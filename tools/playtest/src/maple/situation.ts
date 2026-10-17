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

/** The situation's buckets, or null when the decide carries none. */
export function bucketsOf(situation: Record<string, unknown> | undefined): Buckets | null {
	const b = (situation as Situation | undefined)?.buckets;
	return b && typeof b === "object" ? b : null;
}
