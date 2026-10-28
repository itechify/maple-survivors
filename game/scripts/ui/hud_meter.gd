class_name HudMeter
extends HudWidget
## Event-fed, job-neutral meter pips beside the skill bar. Jobs without a meter draw nothing.
## Uses the configured state/1 orb image when available, otherwise draws a code pip.

## tier C: 12 px pitch and 4 px pip radius keep ten units beside the skill row at base resolution.
const PITCH := 12.0
const RADIUS := 4.0

## Number of visible capacity pips.
func pip_count() -> int:
	return maxi(0, int(run_info.get("meter", {}).get("max", 0)))

## Number of lit pips.
func filled_count() -> int:
	return clampi(int(run_info.get("meter", {}).get("value", 0)), 0, pip_count())

## Changes only when the counter does; no per-frame redraw for an unchanged meter.
func update(ps: Dictionary, info: Dictionary) -> void:
	if run_info.get("meter", {}) == info.get("meter", {}):
		return
	super.update(ps, info)

func _draw() -> void:
	var art := String(run_info.get("meter", {}).get("art", ""))
	var orb := _frame(art + "/1") if art != "" else null
	for i in pip_count():
		var center := Vector2(244 + i * PITCH, 20)
		draw_circle(center, RADIUS + 1, Color(0.12, 0.09, 0.16, 0.9))
		if orb != null and i < filled_count():
			PixelDraw.blit_scaled(self, orb.page, Rect2(center - Vector2(5, 5), Vector2(10, 10)), orb.region, Color.WHITE)
			continue
		draw_circle(center, RADIUS, Color(0.75, 0.45, 1.0) if i < filled_count() else Color(0.28, 0.25, 0.32))
