// The Screenshots report section of a windowed replay (adapter, ticket #100), registered into the core report
// registry on import: the planned screenshots (--shots-at times, the recording's timed findings, final.png at a
// TIMEOUT) with their run time, tick and reason, the ones that could not be saved and why, and RunScene's own event
// shots (level-ups, job changes, death, clear, bosses). Data: ctx.data.windowed, the scene's replay.json.
import { registerSection, runClock } from "../core/report.ts";
import type { WindowedVerdict } from "./windowed_replay.ts";

registerSection({
	id: "screenshots",
	order: 30,
	markdown: (ctx) => {
		const v = ctx.data.windowed as WindowedVerdict | null | undefined;
		if (!v || v.error) return [];
		const shots = v.shots ?? [];
		const saved = shots.filter((s) => s.saved);
		const lines = ["## Screenshots", "",
			"800x600 frames of the game window, in `shots/` (evidence/ is gitignored; never commit them). Look at them: numbers alone do not show a broken sprite.", ""];
		if (saved.length) {
			lines.push("| run time | file | why |", "|---|---|---|",
				...saved.map((s) => `| ${runClock(s.time)} (tick ${s.tick}) | \`shots/${s.name}\` | ${s.reason.replaceAll("|", "\\|")} |`), "");
		} else lines.push("No planned screenshot was saved.", "");
		for (const s of shots.filter((x) => !x.saved)) lines.push(`- \`${s.name}\` not saved (${runClock(s.time)}): ${s.why ?? "unknown"}`);
		const events = v.event_shots ?? [];
		if (events.length) lines.push(`- event shots (RunScene): ${events.map((n) => `\`shots/${n}\``).join(", ")}`);
		return lines;
	},
	json: (ctx) => {
		const v = ctx.data.windowed as WindowedVerdict | null | undefined;
		return v && !v.error ? { shots: v.shots ?? [], event_shots: v.event_shots ?? [] } : null;
	},
});
