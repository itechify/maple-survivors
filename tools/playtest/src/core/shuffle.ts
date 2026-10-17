// A seeded deterministic shuffle (game-agnostic core). Jev 1.13 leans toward a Choice's first option, and games often
// list guaranteed options first, so the brain presents options in an order derived from (run seed, decision id):
// reproducible for replays and recorded next to the on-screen order.

/** 32-bit FNV-1a of a string. */
function fnv1a(s: string): number {
	let h = 0x811c9dc5;
	for (let i = 0; i < s.length; i++) {
		h ^= s.charCodeAt(i);
		h = Math.imul(h, 0x01000193) >>> 0;
	}
	return h;
}

/** mulberry32: a small seeded PRNG giving floats in [0, 1). */
function mulberry32(seed: number): () => number {
	let a = seed >>> 0;
	return () => {
		a = (a + 0x6d2b79f5) >>> 0;
		let t = a;
		t = Math.imul(t ^ (t >>> 15), t | 1);
		t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
		return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
	};
}

/** A copy of `items` in a Fisher-Yates order seeded by run seed `seed` and decision `id`. */
export function seededShuffle<T>(items: readonly T[], seed: number, id: number): T[] {
	const out = [...items];
	const rand = mulberry32(fnv1a(`${seed}:${id}`));
	for (let i = out.length - 1; i > 0; i--) {
		const j = Math.floor(rand() * (i + 1));
		[out[i], out[j]] = [out[j], out[i]];
	}
	return out;
}
