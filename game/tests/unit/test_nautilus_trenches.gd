extends TestCase
## Pirate Test Room local survivor geometry: player, bot and walkers cross the crate faces (#279).
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0/60.0
const RAMPS := [[13,64,66,67],[21,57,59,60],[30,38,40,41]]
func _world() -> RunWorld:
	var data := RF.quiet_data()
	data.stages.stages.quiet.maps = []
	data.stages.stages.quiet.map_id = 108000500
	data.stages.stages.quiet.trench_ramps = RAMPS
	var setup := RF.setup("quiet",1,data)
	setup.map_img = JSON.parse_string(FileAccess.get_file_as_string(AssetCachePaths.resolve_cache_root().path_join("Map.wz/Map/Map1/108000500.img.json")))
	return RunWorld.new(setup)
func test_player_crosses_each_crate_in_both_directions() -> void:
	if not require_cache(): return
	for x: float in [265,1538,2926]:
		for dir: int in [-1,1]:
			var w := _world()
			var start := x-100 if dir>0 else x+172
			var floor_y := -INF
			for f in w.fhm.count():
				if w.fhm.x1[f] <= start and start <= w.fhm.x2[f] and w.fhm.x1[f] < w.fhm.x2[f]:
					floor_y = maxf(floor_y,w.fhm.y_at(f,start))
			w.player.place(Vector2(start,floor_y),w.fhm)
			for tick in 240:
				w.player.step(DT,MoveInput.make(dir<0,dir>0),w.fhm,w.ladders,Rect2())
			assert_true(w.player.pos.x > x+72 if dir>0 else w.player.pos.x < x,"crossed %s direction %s, ended %s"%[x,dir,w.player.pos])


func _place(w: RunWorld, x: float) -> void:
	var y := -INF
	for f in w.fhm.count():
		if w.fhm.x1[f] <= x and x <= w.fhm.x2[f] and w.fhm.x1[f] < w.fhm.x2[f]:
			y = maxf(y,w.fhm.y_at(f,x))
	w.player.place(Vector2(x,y),w.fhm)
	w.update_view()
func test_bot_collects_drops_across_all_three_crates() -> void:
	if not require_cache(): return
	for x: float in [265,1538,2926]:
		for dir: int in [-1,1]:
			var w := _world()
			_place(w,x-200 if dir>0 else x+272)
			var target := x+272 if dir>0 else x-200
			w.pickups.spawn(Vector2(target,150),1,4000019)
			var memo := {}
			for tick in 900:
				w.step(DT,BotInput.decide(w,memo))
				w.drain_events()
			assert_eq(w.pickups.collected_exp,1,"bot crosses crate %s direction %s (%s)"%[x,dir,w.player.pos])
func test_walking_mobs_pursue_across_each_crate() -> void:
	if not require_cache(): return
	for x: float in [265,1538,2926]:
		for dir: int in [-1,1]:
			var w := _world()
			w.god = true
			var start := x-220 if dir>0 else x+292
			_place(w,start)
			var slot := w.spawn_mob(int(w.kind_of_id[100100]),w.player.pos,w.player.fh,1000,false)
			_place(w,x+292 if dir>0 else x-220)
			for tick in 1800:
				w.step(DT,MoveInput.new())
				w.drain_events()
			assert_true(w.swarm.x[slot] > x+72 if dir>0 else w.swarm.x[slot] < x,"walking mob crossed %s direction %s (x%s)"%[x,dir,w.swarm.x[slot]])
func test_override_is_inert_on_other_shipped_maps() -> void:
	if not require_cache(): return
	var data := DataRepo.load_all()
	for stage: Dictionary in data.stages.stages.values():
		for entry: Dictionary in stage.get("maps",[]):
			var id := int(entry.map_id)
			if id == 108000500: continue
			var img: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(AssetCachePaths.resolve_cache_root().path_join("Map.wz/Map/Map%d/%d.img.json"%[id/100000000,id])))
			var d := RF.quiet_data()
			d.stages.stages.quiet.maps = []
			d.stages.stages.quiet.map_id = id
			d.stages.stages.quiet.trench_ramps = RAMPS
			var setup := RF.setup("quiet",1,d)
			setup.map_img = img
			var w := RunWorld.new(setup)
			var original := FootholdMap.from_wz(img)
			assert_eq(w.fhm.x1,original.x1,"%s x1"%id)
			assert_eq(w.fhm.x2,original.x2,"%s x2"%id)
			assert_eq(w.fhm.y1,original.y1,"%s y1"%id)
			assert_eq(w.fhm.y2,original.y2,"%s y2"%id)
			assert_eq(w.fhm.prev,original.prev,"%s prev"%id)
			assert_eq(w.fhm.next,original.next,"%s next"%id)
