# godot-probe: measured feasibility of Godot 4.7.2 + GDScript as the Maple Survivors runtime

Probe project, scripts, logs, screenshots: `C:\Users\itech\Coding\maple-survivors-refs\research\godot-probe\`
(`project\` = Godot project, `tools\` = runners/Node helpers, `logs\` = raw console output of every run, `screenshots\`, `movie\`, `export\`, `ext\` = inputs that live outside `res://`).

Test machine (from `logs/*.txt` `INFO` lines): AMD Ryzen 7 7800X3D (8C/16T), NVIDIA RTX 4070 SUPER (driver 610.88 GL / Vulkan 1.4.341), also an AMD Radeon iGPU (2 CU) used as a weak-GPU proxy. Window on a 3440x1440 @ 164.9 Hz screen, scale 1.0, 96 dpi. Godot `4.7.2.stable.official.ed1daf0bf`. **This is a high-end CPU; every number below is a best case. On weaker CPUs, expect the GDScript-bound numbers to be 2-3x worse (UNVERIFIED, not measured).**

## Summary

- **Godot 4.7.2 + GDScript can run the game, but GDScript CPU time is what limits it, not rendering.** With the full per-mob sim (chase, gravity, foothold lookup over 300 segments, spatial-hash hits from 200 projectiles, 100 damage numbers), all four render approaches hold 60 FPS (p95 < 16.67 ms) up to **N = 4000 mobs** and break somewhere **between 4000 and 8000** (editor binary and exported release, Forward+ and Compatibility). There is one exception: Sprite2D on Compatibility already has p95 = 16.99 ms at N = 4000. On Forward+, p99 for sprite and rs also crosses 16.67 at 4000 (17.32 ms). A later narrowing run (5000/6000/7000) ran under about 80-87% background CPU load from other processes and was noisy, so the practical ceiling on this PC is best stated as **about 4000-5000 mobs** (see the variance note in section 1). At N = 1000 a frame takes 2.5-3.3 ms on the editor binary and 2.1-2.6 ms on the exported release, so there is about 5x headroom at 60 FPS.
- **Sim cost is about 2.1 µs per mob per frame in GDScript** (editor) and about 1.8 µs (exported release, 15-25% faster). For example, sim = 2.05-2.35 ms at N = 1000 and 16.5-19.5 ms at N = 8000.
- **Rendering approach, render-isolated (cheap sim):** Sprite2D-with-region breaks 60 FPS at about **16k-32k sprites** (p95 16.4 ms at 16k on Forward+, 21.8 ms at 16k on Compatibility). MultiMesh with `INSTANCE_CUSTOM` frame index stays under 10.5 ms at **32k**. RenderingServer canvas_item per entity sits in between (12.8 ms at 32k). A single `_draw()` is within about 3% of MultiMesh (9.86 vs 9.55 ms at 32k). Sprite2D's per-entity sync cost is about 2-3.5x MultiMesh's (1.8x at 4k, 3.4x at 32k). **Recommendation: MultiMesh (or the single-`_draw` batch) for mobs, projectiles and damage numbers. Sprite2D is fine for fewer than 2k entities.**
- **Weak-GPU proxy (AMD 2-CU iGPU, Vulkan):** Sprite2D breaks 60 FPS at N = 4000 with the full sim (16.8 ms avg) and at 16k render-only. MultiMesh holds 4000 with the full sim at 11.2 ms and 32k render-only at 11.0 ms.
- **Vsync on** caps at the monitor rate (164.9 Hz, 6.06 ms/frame): N ≤ 1000 is flat at 165 FPS for every approach, N = 4000 drops to 87 (Sprite2D) or about 110 (others), and N = 8000 is below 60 for all.
- **zlib:** `PackedByteArray.decompress(size, FileAccess.COMPRESSION_DEFLATE)` **accepts the zlib `78 9C` header** and returns byte-exact output. It does **NOT** accept a header-stripped stream, a raw deflate stream, or zlib data in GZIP mode (all return size 0 with `Condition "err != 1"`). Cause: Godot's DEFLATE mode is `inflateInit2(window_bits=15)`, which is the zlib-wrapped format. Inflate speed equals native Node zlib: 2.8 ms for 1.5 MB, 5.6-5.8 ms for 3 MB.
- **Pixel conversion in pure GDScript is 10-40x slower than native:** BGRA4444→RGBA8 for 1024x768 takes 86-94 ms naive and 28-37 ms with a 64K LUT. BGRA8888→RGBA8 takes 21-30 ms. Node (JIT, roughly native) does either in about 2.3 ms. Uploading the raw bytes and swizzling in a shader costs 0 CPU and was verified visually identical. **Conclusion: WZ parsing and decoding belongs in a separate native (Rust) offline importer that emits PNG/atlas + metadata. Godot then only loads PNGs (or swizzles raw bytes in a shader if we ever decode at runtime).**
- **Runtime PNG loading from an absolute path outside `res://` works in an exported release build** (`template=true debug=false`). 500 small PNGs take 38.7 ms for `Image.load_from_file` plus 5.1 ms for `ImageTexture.create_from_image`, about 0.09 ms per PNG (editor binary: 0.11 ms).
- **Runtime MP3 from bytes works:** `AudioStreamMP3.new(); s.data = bytes` (and the static `AudioStreamMP3.load_from_buffer(bytes)`) plays both a Windows system MP3 and **an MPEG-2 Layer III BGM stream carved directly out of v83 `Sound.wz`** (166.6 s, 22.05 kHz, 80 kbps). This works in both the editor and the exported build. Godot 4.7.2 decodes MP3 with dr_mp3 (Unlicense / MIT-0).
- **Capture and pixel-perfect:** `get_viewport().get_texture().get_image().save_png()` works windowed. `--write-movie` writes a PNG sequence plus a `.wav`. An 800x600 viewport with `stretch/mode=viewport`, `scale_mode=integer` and nearest filtering produced **0 non-uniform 2x2 blocks** on a 1px checkerboard in the actual desktop capture of the window, including letterboxing at 1700x1300. A fractional-scale negative control produced 1623 bad blocks, which shows the check catches blur.

## Detailed findings

### 0. How things were run (CLI flags used)

| Purpose | Command (from `tools/run_swarm.sh`, `run_swarm2.sh`, `run_rest.sh`) |
|---|---|
| Run the project windowed (console exe for stdout) | `Godot_v4.7.2-stable_win64_console.exe --path project -- --test=swarm --approach=multimesh --vsync=off --counts=100,300,...` |
| Choose renderer | `--rendering-method forward_plus` / `--rendering-method gl_compatibility` |
| Weak-GPU proxy | `--gpu-index 1` (works with Forward+/Vulkan; **ignored by Compatibility**, see gotchas) |
| Window size override | `--resolution 1700x1300` |
| Movie Maker | `--write-movie <abs>/movie/frame.png --fixed-fps 30 --quit-after 30` |
| Headless import / export | `--headless --path project --import`, then `--headless --path project --export-release "Windows Desktop" <abs>/export/godot-probe.exe` (2.7 s) |
| User args to the script | everything after `--`, read with `OS.get_cmdline_user_args()` (`project/main.gd:9`) |

Vsync is set at runtime with `DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)` + `Engine.max_fps = 0` (`project/main.gd:18-22`), and the project default is also `window/vsync/vsync_mode=0`. Every log confirms `INFO vsync_mode=0 max_fps=0` for vsync-off runs.

### 1. Swarm test

**Workload** (`project/swarm.gd`). It uses typed GDScript with struct-of-arrays in `Packed*Array`s and one manager loop, not per-node `_process`:
- N mobs. Each mob uses a generated 384x64 atlas (6 frames of 64x64) and advances frames on per-frame delays `[120, 90, 150, 90, 120, 180]` ms, like WZ `delay` (`swarm.gd:14`, animation in `simulate` at `swarm.gd:381`). Each mob also does a horizontal chase toward a moving target, gravity, and a foothold lookup ("smallest y_at ≥ feet among segments spanning x") over **300 segments** in a **32 px x-bucket grid** (26 buckets, 400 entries; log line `INFO footholds=300 buckets=26 bucket_entries=400`). Mobs randomly jump and respawn on death.
- 200 projectiles move and test circle-vs-AABB (r = 6 vs a 40x50 hitbox) through a **uniform spatial hash** (64 px cells). The hash is rebuilt every frame with a counting sort into `PackedInt32Array`s. Hits spawn damage numbers and kill mobs after 3 hits.
- 100 floating damage-number sprites rise and fade.
- Render approaches (all use the same textures; screenshots `screenshots/smoke_{sprite,rs,multimesh,draw}.png` look equivalent):
  - `sprite`: one `Sprite2D` per entity with `region_enabled`. `region_rect` is updated only when the frame changes, and `position`/`flip_h` every frame.
  - `rs`: one `RenderingServer.canvas_item_create()` per entity. `canvas_item_set_transform` runs every frame; `canvas_item_clear` + `canvas_item_add_texture_rect_region` run on frame change.
  - `multimesh`: 3 `MultiMeshInstance2D`s (`TRANSFORM_2D`, `use_custom_data`). The whole `buffer` (`PackedFloat32Array`, 12 floats/instance) is written each frame. A canvas_item shader picks the frame with `UV.x = (UV.x + INSTANCE_CUSTOM.x) / frames` and alpha from `INSTANCE_CUSTOM.y` (`swarm.gd:310-317`). **Buffer layout verified empirically** with a screenshot: `[x.x, y.x, 0, origin.x, x.y, y.y, 0, origin.y, custom0..3]` (`swarm.gd:550`).
  - `draw`: one `Node2D` whose `_draw()` issues N `draw_texture_rect_region` calls, with `queue_redraw()` every frame (`project/drawer.gd`). Its GDScript cost is incurred inside the render step, so it shows up in frame time, not in "sync".
- Measurement (`swarm.gd:572` `_process`, `:618` `report`): 1 s warm-up, then 3 s of samples. "frame" is wall time between consecutive `_process` calls. "sim" and "sync" are `Time.get_ticks_usec()` around the sim and render-sync code. "RS-cpu" is `viewport_get_measured_render_time_cpu + get_frame_setup_time_cpu`; "RS-gpu" is `viewport_get_measured_render_time_gpu` (needs `viewport_set_measure_render_time(vp, true)`).
- **`Performance.TIME_PROCESS` is not a per-frame value.** Godot 4.7.2 `main/main.cpp:5099-5100` computes `process_max = MAX(process_ticks, process_max)` and `main.cpp:5121/5136` publishes it once per second (`if (frame > 1000000) … performance->set_process_time(USEC_TO_SEC(process_max))`). The window starts at `process_begin` (`main.cpp:5059`) and therefore includes `RenderingServer::draw()`. It reads as "max process+draw time over the last second". It is kept in the raw logs as `proc_mon_avg` but is not used in the tables. The source is in `godot-probe/tools/src_snippets/main_4.7.2.cpp`, fetched from tag `4.7.2-stable`.

**Table 1: full sim, editor binary, Forward+ (Vulkan, RTX 4070S), vsync OFF.** Cells show frame avg / p95 / p99 ms (FPS). **X** means p95 > 16.67 ms. Log files: `logs/swarm_forward_plus_*_vsyncoff.txt`.

| N | sprite | rs | multimesh | draw |
|---|---|---|---|---|
| 100 | 0.80 / 1.09 / 1.39 (1249) | 0.67 / 0.91 / 1.06 (1487) | 0.64 / 0.86 / 1.02 (1568) | 0.59 / 0.78 / 0.91 (1691) |
| 300 | 1.22 / 1.63 / 1.76 (822) | 1.13 / 1.48 / 1.63 (888) | 1.03 / 1.32 / 1.51 (972) | 1.07 / 1.45 / 1.71 (935) |
| 600 | 1.97 / 2.57 / 2.91 (507) | 1.90 / 2.70 / 2.99 (527) | 1.70 / 2.37 / 2.77 (588) | 1.81 / 2.38 / 2.76 (553) |
| 1000 | 3.28 / 4.35 / 4.67 (305) | 2.76 / 3.62 / 3.90 (363) | 2.52 / 3.02 / 3.35 (397) | 2.65 / 3.48 / 3.86 (377) |
| 2000 | 7.91 / 11.06 / 11.63 (126) | 5.21 / 7.50 / 7.85 (192) | 4.85 / 5.68 / 6.26 (206) | 5.26 / 6.55 / 7.24 (190) |
| 4000 | 12.11 / 15.40 / 17.32 (83) | 10.57 / 15.19 / 17.32 (95) | 9.76 / 12.74 / 13.64 (103) | 10.73 / 14.11 / 15.24 (93) |
| 8000 | 24.42 / 30.97 / 32.79 (41) **X** | 21.03 / 27.48 / 29.58 (48) **X** | 18.43 / 23.79 / 25.48 (54) **X** | 21.51 / 27.88 / 30.26 (47) **X** |
| 12000 | 42.74 / 51.77 / 57.18 (23) **X** | 39.43 / 47.90 / 56.82 (25) **X** | 30.59 / 39.57 / 45.86 (33) **X** | 35.74 / 48.37 / 53.11 (28) **X** |

Time breakdown for the same runs, as sim / sync / RS-cpu / RS-gpu ms:

| N | sprite | rs | multimesh | draw |
|---|---|---|---|---|
| 1000 | 2.35 / 0.50 / 0.14 / 0.09 | 2.23 / 0.18 / 0.13 / 0.11 | 2.05 / 0.25 / 0.02 / 0.11 | 2.15 / 0.003 / 0.06 / 0.08 |
| 4000 | 9.02 / 1.96 / 0.55 / 0.47 | 9.11 / 0.66 / 0.55 / 0.86 | 8.64 / 0.87 / 0.02 / 0.83 | 9.34 / 0.005 / 0.13 / 0.30 |
| 8000 | 17.03 / 4.59 / 1.33 / 1.40 | 17.79 / 1.63 / 1.31 / 1.63 | 16.49 / 1.65 / 0.03 / 1.67 | 19.53 / 0.007 / 0.13 / 0.29 |

**Table 2: the same full sim in the EXPORTED RELEASE build** (`export/godot-probe.exe`, `template=true debug=false`), Forward+, vsync off. Log files: `logs/swarm_exported_release_forward_plus_*`.

| N | sprite | rs | multimesh | draw |
|---|---|---|---|---|
| 1000 | 2.65 / 3.52 / 4.19 (378) | 2.14 / 2.81 / 2.99 (467) | 2.18 / 3.10 / 3.57 (458) | 2.27 / 3.18 / 3.64 (440) |
| 2000 | 4.60 / 5.61 / 6.38 (218) | 3.94 / 4.48 / 5.09 (254) | 3.85 / 4.40 / 5.00 (260) | 4.07 / 5.10 / 5.66 (246) |
| 4000 | 9.21 / 11.23 / 13.48 (109) | 7.95 / 8.66 / 9.77 (126) | 7.79 / 8.86 / 9.74 (128) | 8.60 / 10.57 / 12.43 (116) |
| 8000 | 18.72 / 25.43 / 27.48 (53) **X** | 17.44 / 23.11 / 26.42 (57) **X** | 15.65 / 21.53 / 23.21 (64) **X** | 17.91 / 25.19 / 30.89 (56) **X** |

Release sim at N = 1000 is 1.72-1.93 ms, against 2.05-2.35 ms on the editor binary.

**Table 3: render isolation (`--sim=light`: animation + trivial movement, no footholds or hash), Forward+, vsync off.** Log files: `logs/swarm_light_forward_plus_*`.

| N | sprite | rs | multimesh | draw |
|---|---|---|---|---|
| 1000 | 0.90 / 1.20 / 1.41 (1109) | 0.59 / 0.78 / 0.96 (1692) | 0.61 / 0.78 / 1.03 (1643) | 0.56 / 0.67 / 0.92 (1783) |
| 4000 | 2.47 / 2.98 / 3.40 (405) | 1.58 / 1.85 / 2.10 (631) | 1.46 / 1.83 / 2.27 (686) | 1.57 / 2.22 / 2.41 (637) |
| 8000 | 4.97 / 6.81 / 8.43 (201) | 2.91 / 3.42 / 3.81 (344) | 2.53 / 2.71 / 3.09 (395) | 2.72 / 3.39 / 4.38 (368) |
| 16000 | 12.57 / 16.41 / 17.91 (80) | 5.74 / 6.86 / 8.99 (174) | 4.79 / 5.06 / 5.44 (209) | 5.12 / 6.14 / 8.07 (195) |
| 32000 | 35.81 / 41.22 / 42.78 (28) **X** | 12.78 / 15.11 / 17.04 (78) | 9.55 / 10.43 / 12.57 (105) | 9.86 / 10.82 / 13.68 (102) |

At 32k, sync / RS-cpu is 19.6 / 5.75 ms for Sprite2D, 5.8 / 0.02 ms for MultiMesh and 4.6 / 4.0 ms for RS canvas items.

Compatibility (OpenGL 3.3) with the light sim gives the same ordering but is a bit worse at the top end: sprite **X** at 16k (13.3 / 21.8 / 23.8), rs and draw **X** at 32k, multimesh 10.7 / 11.8 / 12.9 at 32k (`logs/swarm_light_gl_compatibility_*`). In Compatibility, Sprite2D reports about 100 canvas draw calls against 3 for multimesh/draw and 8-11 for rs (`VIEWPORT_RENDER_INFO_TYPE_CANVAS`).

**Table 4: full sim, Compatibility renderer (editor binary), vsync off.** Log files: `logs/swarm_gl_compatibility_*`. The break point is the same (4000 OK, 8000 fails), except Sprite2D p95 = 16.99 at 4000.

| N | sprite | rs | multimesh (rerun) | draw |
|---|---|---|---|---|
| 1000 | 3.03 / 3.93 / 4.39 (331) | 2.89 / 3.75 / 4.09 (346) | 2.79 / 3.89 / 4.53 (359) | 2.67 / 3.28 / 3.59 (375) |
| 4000 | 12.22 / 16.99 / 18.83 (82) **X** | 12.63 / 15.78 / 18.48 (79) | 9.63 / 12.52 / 13.83 (104) | 10.81 / 15.39 / 17.21 (93) |
| 8000 | 24.60 / 29.95 / 32.15 (41) **X** | 23.39 / 30.95 / 33.85 (43) **X** | 18.77 / 24.02 / 25.71 (53) **X** (first run) | 20.15 / 25.86 / 27.91 (50) **X** |

Anomaly: the first GL multimesh run was pinned at exactly 6.90 ms (144.9 FPS) for N = 300-2000, and its RS timings were frozen at constant values. A re-run (`logs/swarm_rerun_gl_compatibility_multimesh_vsyncoff.txt`) did not reproduce it: 2.79 ms at N = 1000. The cause is probably an external presentation/DWM cap, but that is UNVERIFIED. The multimesh column above uses the re-run values for N ≤ 4000.

**Table 5: weak-GPU proxy, AMD Radeon iGPU via `--gpu-index 1`** (log line `Vulkan 1.4.315 - Forward+ - Using Device #1: AMD - AMD Radeon(TM) Graphics`). Log files: `logs/swarm_igpu_*`.

| run | N | sprite | multimesh |
|---|---|---|---|
| full sim | 1000 | 3.75 / 4.95 / 6.28 (267) | 2.98 / 3.98 / 4.67 (335) |
| full sim | 4000 | 16.77 / 19.80 / 20.68 (60) **X** | 11.19 / 13.90 / 14.46 (89) |
| light sim | 8000 | 8.38 / 11.91 / 13.13 (119) | 3.47 / 3.88 / 4.35 (289) |
| light sim | 16000 | 21.22 / 29.03 / 30.83 (47) **X** | 5.71 / 6.34 / 7.82 (175) |
| light sim | 32000 | 42.72 / 54.06 / 55.14 (23) **X** | 11.03 / 14.76 / 15.37 (91) |

On the iGPU, RS-gpu reaches 13.6 ms for 32k Sprite2D and 8.7 ms for 32k MultiMesh. The iGPU renders and the frames are probably presented on the NVIDIA-attached monitor via a cross-adapter copy that adds cost (UNVERIFIED, not measured).

**Table 6: vsync ON, Forward+, editor binary.** Log files: `logs/swarm_forward_plus_*_vsyncon.txt`. Capped at 164.9 Hz.

| N | sprite | rs | multimesh | draw |
|---|---|---|---|---|
| 100 | 6.07 / 6.34 / 7.35 (165) | 6.06 / 6.73 / 7.34 (165) | 6.07 / 6.72 / 7.84 (165) | 6.13 / 7.02 / 9.47 (163) |
| 1000 | 6.06 / 6.99 / 7.50 (165) | 6.07 / 7.17 / 8.02 (165) | 6.07 / 7.21 / 7.80 (165) | 6.08 / 7.38 / 8.29 (165) |
| 4000 | 11.55 / 14.17 / 15.74 (87) | 9.22 / 10.23 / 10.69 (109) | 9.04 / 10.26 / 12.24 (111) | 9.07 / 10.27 / 13.24 (110) |
| 8000 | 25.59 / 35.53 / 40.65 (39) **X** | 19.26 / 27.37 / 30.41 (52) **X** | 18.22 / 24.31 / 25.97 (55) **X** | 17.93 / 23.15 / 25.84 (56) **X** |

**Where 60 FPS breaks (p95 > 16.67 ms):**

| Config | sprite | rs | multimesh | draw |
|---|---|---|---|---|
| Full sim, Forward+, editor | 4000 < N ≤ 8000 | 4000 < N ≤ 8000 | 4000 < N ≤ 8000 | 4000 < N ≤ 8000 |
| Full sim, Forward+, exported release | 4000 < N ≤ 8000 (≤ 5000 in the loaded narrowing run) | same | same (avg 15.65 at 8000) | same |
| Full sim, Compatibility | 2000 < N ≤ 4000 (p95 16.99) | 4000 < N ≤ 8000 | 4000 < N ≤ 8000 | 4000 < N ≤ 8000 |
| Light sim (render-bound), Forward+ | 16000 < N ≤ 32000 (p95 16.41 at 16k) | > 32000 (p99 17.0) | > 32000 | > 32000 |
| Light sim, Compatibility | 8000 < N ≤ 16000 | 16000 < N ≤ 32000 | > 32000 | 16000 < N ≤ 32000 |
| iGPU, full sim | 1000 < N ≤ 4000 | n/a | > 4000 | n/a |
| iGPU, light sim | 8000 < N ≤ 16000 | n/a | > 32000 | n/a |

**Narrowing and run-to-run variance (exported release, Forward+):** `logs/swarm_exported_release_narrow_*` measured N = 5000/6000/7000. Every approach already exceeds p95 16.67 at 5000 (sprite 21.4 / 27.5 / 30.5, rs 16.7 / 22.7 / 27.8, multimesh 15.5 / 21.1 / 23.5, draw 15.0 / 21.2 / 23.5 ms). However, a repeat run of multimesh at 4000,5000,4000,5000,8000 (`logs/swarm_exported_release_variance_*`) gave 4000 → 12.4 / 18.6 / 19.8 and 11.3 / 13.4 / 14.3, 5000 → 13.1 / 15.5 / 17.8 and 14.2 / 18.0 / 21.1, and 8000 → 25.0 ms avg. Compare Table 2 earlier: 4000 → 7.8 ms, 8000 → 15.7 ms. During these late runs, `Get-Counter '\Processor(_Total)\% Processor Time'` read **81-87% total CPU busy** from other processes on the machine (other apps/sessions, not started by this probe). So the late runs are contaminated by up to about 1.6x. Background load during the main matrix was not recorded (UNVERIFIED), but its smooth monotonic scaling and consistent cross-approach sim times (2.05-2.35 ms at N = 1000) suggest it was stable. By interpolation from the clean runs (~1.75-2.1 µs/mob sim + 0.2-0.6 µs/mob sync), the clean break point is roughly N ≈ 6000-7000 for MultiMesh and ≈ 5000-6000 for Sprite2D. That is interpolation, not measurement. Treat every absolute number here as ±50% and re-measure on a quiet machine and on the target min-spec hardware.

How to read this: a Vampire-Survivors-style screen of 300-1000 mobs costs 1-3.5 ms on this machine. The budget left over goes to real game logic: skills, AI states, collision with the player, pickups, WZ-accurate mob physics. Real logic will cost more per mob than this probe, so keep hot loops in packed arrays. Consider moving the mob/projectile core loop into a GDExtension (Rust or C++) if real logic pushes per-mob cost far above 2 µs. Note that per-mob sim cost here includes the hash narrow-phase, which grows with density. At 8000 mobs in 800x600, each 64 px cell holds about 60+ mobs.

### 2. WZ-like decoding inside Godot

Inputs were generated by `tools/gen_wz_like.js` (Node 24): 1024x768 BGRA4444 (WZ canvas format 1) = 1,572,864 B and BGRA8888 (format 2) = 3,145,728 B, with sprite-like content (transparent background, gradient + noise). The files are `zlib.deflateSync` → `ext/wz/*.zlib` (header `78 9c`, 288,372 B and 1,224,935 B), `deflateRawSync` → `*.deflate`, raw `*.raw`, and expected RGBA8 `*.expected_rgba`. The test script is `project/decode.gd`, and logs are `logs/decode.txt` (editor) and `logs/exported_decode.txt` (release).

| Test | Result (editor / exported release) |
|---|---|
| A. zlib (`78 9C`) + `decompress(size, COMPRESSION_DEFLATE)` | **OK, byte-equal**. 4444: 2.78 / 2.73 ms. 8888: 5.81 / 5.54 ms. |
| B. strip 2 header bytes + DEFLATE | **FAIL**: size 0, `ERROR: Condition "err != 1" is true. Returning: -1` |
| C. raw deflate (`deflateRawSync`) + DEFLATE | **FAIL** (same error) |
| D. `decompress_dynamic(-1, DEFLATE)` on zlib data | OK, byte-equal. 3.55 ms (4444), 6.94 ms (8888). |
| E. zlib data + `COMPRESSION_GZIP` | **FAIL** (window_bits 31 = gzip only, no auto-detect) |
| Node baseline `zlib.inflateSync` (`logs/node_baseline.txt`) | 2.89 ms (4444), 5.69 ms (8888) |

Source evidence (Godot 4.7.2, `tools/src_snippets/compression_4.7.2.cpp`): `:177` `int window_bits = p_mode == MODE_DEFLATE ? 15 : 15 + 16;`, `:185` `inflateInit2(&strm, window_bits)`, `:196` `ERR_FAIL_COND_V(err != Z_STREAM_END, -1)`. That is the "err != 1" message seen. In zlib, windowBits 15 means "expect a zlib header". Also `:176`: a single DEFLATE/GZIP decompress is capped below 2 GiB.

Pixel conversion (median of 3, 1024x768 = 786,432 px):

| Conversion | GDScript editor | GDScript exported release | Node (V8 JIT) |
|---|---|---|---|
| BGRA4444 → RGBA8, naive per-byte loop | 85.7 ms | 93.8 ms | 2.31 ms |
| BGRA4444 → RGBA8, 64K-entry `PackedInt32Array` LUT + `to_byte_array()` (LUT build 5.6-6.5 ms) | 36.8 ms | 28.2 ms | – |
| BGRA8888 → RGBA8, swap bytes 0/2 | 30.3 ms | 21.2 ms | 2.34 ms |
| BGRA8888 → RGBA8 via `to_int32_array()` + bit ops | 36.1 ms | 29.2 ms | – |
| `Image.create_from_data(RGBA8)` | 0.001-0.002 ms | 0.001 ms | – |
| `ImageTexture.create_from_image` (3 MB) | 0.37 ms | 0.31-0.34 ms | – |
| Native `Image.convert` RGBA8→RGBA4444 / back (C++ reference) | 4.3 / 5.1 ms | – | – |

All conversions are verified byte-equal to the Node-computed expected output (`equal_expected=true`). `ImageTexture.create_from_image` only measures main-thread cost. Whether the GPU upload is deferred to the render thread is UNVERIFIED.

Format compatibility (`decode.gd`, `format_checks`):
- Godot `FORMAT_RGBA4444` is **not** WZ's layout. Bytes `21 43` (u16 0x4321; in WZ that means A=4 R=3 G=2 B=1) decode in Godot as r=4 g=3 b=2 a=1. Godot packs nibbles R-G-B-A from high to low; WZ packs A-R-G-B. WZ 4444 data needs a nibble rotate, a LUT, or a shader.
- Godot `FORMAT_RGB565`: `00 F8` → pure red and `1F 00` → pure blue, which is the standard R-high layout. WZ format 513 (RGB565) can likely be uploaded directly; this is UNVERIFIED against real WZ data.
- **Shader path (0 CPU conversion):** upload raw BGRA8888 as `FORMAT_RGBA8` (0.37 ms) and use `COLOR = t.bgra`, or upload raw BGRA4444 as `FORMAT_RG8` (0.30 ms) and decode the nibbles in the fragment shader. `screenshots/decode_shaderpath.png` shows both paths render identically (left: 8888, right: 4444).

**Conclusion on where WZ decoding lives:** inflate is native-speed in Godot, but per-pixel work in GDScript costs about 27-120 ns/px. A 100x100 mob frame takes about 0.3-1.2 ms, so a full map/mob set of a few thousand frames would add seconds to load time. Full WZ reading would also need directory/IMG parsing, string decryption, and handling for canvases whose first bytes aren't `78 xx` (key-XOR'd blocks; not chased here). Options:
1. **Separate native offline importer (Rust CLI) → PNG atlases + JSON/`.tres` metadata (recommended).** This fits the NO-Java/NO-.NET/NO-Python toolchain (Rust and Node are available), keeps the shipped runtime simple, and makes PNG/MP3 runtime loading (proven below) the only runtime I/O.
2. GDExtension (Rust, via godot-rust) in-engine. This gives native speed at runtime but adds a per-platform native build to the game. Use it only if runtime WZ reading is a hard requirement.
3. GDScript in-engine. Feasible for small or occasional assets: inflate is native, LUT conversion is about 30 ms per 1024x768. Too slow as the main path.
4. Shader-side decode (upload raw bytes, swizzle on the GPU). A cheap trick to combine with option 2 or 3 if decoding happens at runtime. Needs nearest filtering on RG8 (already the project default).

### 3. Runtime asset loading (outside `res://`)

`project/png.gd`. 500 PNGs (24-64 px, 199,113 B total) were generated by Godot into `godot-probe/ext/pngs/`, an absolute path outside the project. Results: `logs/png_editorbin.txt` and `logs/exported_png.txt`.

| Step (500 files) | Editor binary | **Exported release** (`template=true debug=false`) |
|---|---|---|
| `Image.load_from_file(abs_path)` | 47.6 ms | 38.7 ms |
| `FileAccess.get_file_as_bytes` + `Image.load_png_from_buffer` | 54.5 ms | 40.7 ms |
| `ImageTexture.create_from_image` | 6.3 ms | 5.1 ms |
| Total per PNG (load + texture) | 0.108 ms | 0.088 ms |

All 500 loaded (`ok=500`), and 120 were rendered on screen (`screenshots/png_runtime_exported.png`, `png_runtime_editorbin.png`). The export used `project/export_presets.cfg` (`embed_pck=true`, `application/modify_resources=false` to skip rcedit). It produced a single 109 MB `export/godot-probe.exe`, about the size of the 109 MB release template. Stdout from the GUI-subsystem release exe is still captured when redirected from bash.

### 4. Audio: runtime MP3 from bytes

`project/audio.gd`. Logs: `logs/audio.txt` (editor), `logs/exported_audio.txt` (release). Driver: WASAPI, mix rate 48000.

| File | Bytes | `s.data = bytes` | `get_length()` | Playback position after ~0.59 s (bus muted) |
|---|---|---|---|---|
| `C:\Windows\ImmersiveControlPanel\SystemSettings\Assets\Aria.mp3` (copied to `ext/`) | 119,225 | 0.16-0.18 ms | 14.759 s | 0.566-0.589 s, `playing=true` |
| `ext/wz_carved.mp3`: MPEG-2 Layer III, 22,050 Hz, 80 kbps, 6,379 frames carved from v83 `Sound.wz` at offset `0x51E` by `tools/carve_mp3.js` (frame-sync chain scan, ≥150 chained frames) | 1,666,351 | 1.4-2.0 ms | 166.635 s | 0.598 s, `playing=true` |

`AudioStreamMP3.load_from_buffer(bytes)` (static) also exists and gives the same length. Godot 4.7.2's MP3 module includes `thirdparty/dr_libs/dr_mp3.h` (`modules/mp3/audio_stream_mp3.h:35` at tag 4.7.2-stable). So v83 BGM bytes inside `Sound_DX8` nodes can be fed straight to Godot. A real importer should take the exact byte range from the WZ property rather than carving. Some WZ sounds may be PCM/WAV with a WAVEFORMATEX header; that was not checked here and is UNVERIFIED.

### 5. Evidence capture

- Windowed screenshot: `await RenderingServer.frame_post_draw`, then `get_viewport().get_texture().get_image().save_png(path)` → `screenshots/screenshot_windowed.png` (`err=0`, 800x600; `logs/shot.txt`). With `stretch/mode=viewport` this is the **logical 800x600 image**, not the 1600x1200 window.
- Real window pixels: `DisplayServer.screen_get_image_rect(Rect2i(window_get_position(), window_get_size()))` works on Windows (`FEATURE_SCREEN_CAPTURE=true`), e.g. `screenshots/pixel_viewport_1700x1300_window.png`. It needs the window unoccluded; `WINDOW_FLAG_ALWAYS_ON_TOP` was used.
- Movie Maker: `--write-movie <abs>/movie/frame.png --fixed-fps 30 --quit-after 30` → `movie/frame00000000.png` … `frame00000029.png` (800x600 RGB) plus `movie/frame.wav`. Godot printed `Movie Maker mode enabled, recording movie in 800×600 @ 30 FPS...` and `30 frames at 30 FPS … Encoding time: 0.24 seconds (average: 7.96 ms/frame)`. `delta` was exactly 0.0333 every frame (`logs/movie.txt`). Movie Maker forces fixed-step, non-real-time running, so it is good for deterministic visual regression and bad for benchmarks.

### 6. Pixel-perfect 800x600 with integer scaling

Project settings verified by reading them back at runtime (`--test=settings`, values printed by `ProjectSettings.get_setting`):

```ini
[display]
window/size/viewport_width=800
window/size/viewport_height=600
window/size/window_width_override=1600   ; 2x
window/size/window_height_override=1200
window/stretch/mode="viewport"           ; or "canvas_items"
window/stretch/aspect="keep"
window/stretch/scale_mode="integer"
[rendering]
textures/canvas_textures/default_texture_filter=0   ; Nearest
2d/snap/snap_2d_transforms_to_pixel=true
2d/snap/snap_2d_vertices_to_pixel=true
```

At runtime this showed `content_scale_mode=2` (VIEWPORT) and `content_scale_stretch=1` (INTEGER). The test (`project/pixel.gd`) draws a 64x64 1-px black/white checkerboard at an integer position and again at (116.5, 16.25), captures the real window from the desktop, and checks every logical pixel's s×s block:

| Config | Window | Int scale / letterbox offset | Non-uniform blocks / 4096 | Wrong-value blocks | Unique colours (checker / fractional-pos copy) |
|---|---|---|---|---|---|
| viewport, integer | 1600x1200 | 2 / (0,0) | **0** | 0 | 2 / 2 |
| viewport, integer | 1700x1300 (`--resolution`) | 2 / (50,50) black bars | **0** | 0 | 2 / 2 |
| canvas_items, integer | 1600x1200 | 2 / (0,0) | **0** | 0 | 2 / 2 |
| viewport, integer, canvas filter = linear | 1600x1200 | 2 | 0 | 0 | 2 / 2 (unscaled sprites aren't affected) |
| NEG CONTROL: viewport, **fractional** | 1700x1300 | (2.17) | 1623 | 2939 | 3 / 3 |
| NEG CONTROL: canvas_items, fractional, linear | 1700x1300 | (2.17) | 2244 | 4096 | 108 / 108 |

Tradeoff: `viewport` mode renders everything, UI included, at 800x600 and upscales it, which gives an authentic v83 look. `canvas_items` renders at window resolution, so text and any rotated or scaled sprites get extra resolution, which is less authentic. The default theme font is antialiased (`gui/theme/default_font_antialiasing=1`). For the v83 look, use a bitmap font or WZ-rendered digits and disable font AA.

## Exact numbers & IDs

| Item | Value |
|---|---|
| Godot build | `4.7.2.stable.official.ed1daf0bf` (Godot_v4.7.2-stable_win64[_console].exe) |
| Export templates | `%APPDATA%\Godot\export_templates\4.7.2.stable\windows_release_x86_64.exe` (109,268,480 B) |
| Forward+ device line | `Vulkan 1.4.341 - Forward+ - Using Device #0: NVIDIA - NVIDIA GeForce RTX 4070 SUPER` |
| Compatibility device line | `OpenGL API 3.3.0 NVIDIA 610.88 - Compatibility - Using Device: NVIDIA - NVIDIA GeForce RTX 4070 SUPER` |
| iGPU line | `Vulkan 1.4.315 - Forward+ - Using Device #1: AMD - AMD Radeon(TM) Graphics` |
| Default Windows driver in this project | `rendering/rendering_device/driver.windows = vulkan` |
| Full-sim GDScript cost | ~2.1 µs/mob/frame (editor), ~1.75-1.9 µs (release) |
| Render-sync per entity (light sim, 32k) | Sprite2D 0.61 µs + 0.18 µs RS-cpu; RS canvas_item 0.14 + 0.13 µs; MultiMesh 0.18 + ~0 µs; `_draw` included in frame |
| 60 FPS break, full sim, any approach (this PC) | measured between N = 4000 and 8000. About 4000-5000 under 80-87% background CPU load; about 5000-7000 interpolated for a quiet machine |
| zlib inflate in Godot | 2.73-2.78 ms per 1.5 MB, 5.54-5.81 ms per 3 MB |
| GDScript BGRA4444→RGBA8 | 28-94 ms per 786k px (LUT 28-37) |
| PNG runtime load (exported) | 0.088 ms per small PNG incl. texture |
| Carved v83 BGM | Sound.wz offset 0x51E, MPEG-2 L3 22,050 Hz 80 kbps, 166.6 s |
| Vsync-on cap | 164.9 Hz → 6.06 ms |

## Gotchas found

1. **`COMPRESSION_DEFLATE` means zlib-wrapped**, which suits WZ canvases since they start with `78 9C`. Do not strip the header. Raw deflate needs a different path; Godot exposes none for raw streams.
2. **`Performance.TIME_PROCESS` is a 1-second max that includes `RenderingServer::draw()`** (`main.cpp:5059,5099-5100,5136`), not a per-frame process time. Measure with `Time.get_ticks_usec()`.
3. **`--gpu-index` is ignored by the Compatibility renderer**: `WARNING: The Compatibility renderer does not support overriding the GPU with the --gpu-index command line argument.` (`logs/NOT_IGPU_gl_compat_ignores_gpu_index.txt`).
4. Godot `FORMAT_RGBA4444` nibble order ≠ WZ BGRA4444 (see section 2).
5. GDScript packed-array copy-on-write: `for arr in [mx, my]: arr.resize(n)` silently resizes **copies**. Resize the members directly. This was hit while writing the probe.
6. `viewport_get_measured_render_time_*` sometimes returns stale, repeated values across configs (e.g. GL multimesh first run, Forward+ draw 8k/12k). Treat RS-cpu/gpu as indicative only.
7. The console exe (`*_console.exe`) is a wrapper. `OS.get_executable_path()` reports the non-console `Godot_v4.7.2-stable_win64.exe`.
8. Exports: `debug/export_console_wrapper=1` only produces the console wrapper for debug exports. Release output still reaches redirected stdout. `application/modify_resources=false` avoids needing rcedit. Run `--headless --import` before `--export-release` on a fresh project. Import plus export took 2.1 s + 2.7 s here.
9. Movie Maker output size is the **viewport** size (800x600) in viewport stretch mode, and the run is fixed-step (not real time).
10. One unexplained transient 6.90 ms frame cap in a single GL run did not reproduce. Re-run any benchmark that looks pinned at a refresh-like interval.
11. In screenshots, `get_viewport().get_texture()` in `viewport` stretch mode gives the 800x600 logical image. Use `DisplayServer.screen_get_image_rect` to verify what the user actually sees.

## Licensing notes

- **Godot Engine**: MIT (`LICENSE.txt` at tag 4.7.2-stable: "Copyright (c) 2014-present Godot Engine contributors … Permission is hereby granted, free of charge…"). Third-party pieces exercised here, per `COPYRIGHT.txt` at tag 4.7.2-stable: zlib (`thirdparty/zlib`, Zlib license), libpng (`thirdparty/libpng`, PNG Reference Library license), dr_libs/dr_mp3 (`thirdparty/dr_libs`, "Unlicense or MIT-0"). Shipping Godot requires including its license and third-party notices. Godot source snippets saved under `godot-probe/tools/src_snippets/` were read for facts only.
- **Probe code** (`godot-probe/project/*.gd`, `tools/*.js`, `tools/*.sh`) is our own, written from scratch with no AGPL/GPL code. No Cosmic or HeavenMS source was used.
- **Test media are NOT redistributable**: `ext/Aria.mp3` is a Windows system file (Microsoft). `ext/wz_carved.mp3` is Nexon-copyrighted v83 BGM carved from the user's local install. Both are for local testing only and must never be committed or shipped. The `ext/wz/*` and `ext/pngs/*` data were generated by us.
- Node.js (MIT) and its bundled zlib were used only as tooling.

## Unknowns & risks

- **Hardware generality (biggest risk):** the 7800X3D is a top-tier gaming CPU and GDScript is CPU-bound. Breakpoints on a mid/low-end laptop CPU will likely be 2-3x lower (UNVERIFIED). The iGPU run shows GPU-side cost is fine with MultiMesh but painful with Sprite2D.
- The probe's sim is simpler than real WZ mob behaviour: no multi-layer foothold walking, edge detection along foothold chains, knockback, skills, or AI states. Real per-mob cost will be higher. Prototype the real loop early and set a per-mob µs budget (for example, ≤ 3 µs at 1000 mobs).
- Real WZ canvases: per-canvas size/format headers, possible key-XOR'd (non-`78`) canvas blocks, formats 517 (RGB565 16x16 block) and DXT3/DXT5. None were tested here. Whether v83 uses DXT at all is UNVERIFIED.
- Whether `ImageTexture.create_from_image`'s 0.3 ms includes the GPU upload or defers it is UNVERIFIED. This matters for bulk runtime texture creation (load-time hitches).
- Single-threaded measurement only. `WorkerThreadPool`-based sim and Godot's `rendering/driver/threads/thread_model` (separate render thread) were not tested and could add headroom.
- MultiMesh draws in instance order, so per-mob z-sorting (MapleStory layers/`z` values) must be done by sorting the buffer or splitting MultiMeshes. That cost was not measured.
- Godot `MP3` decoding of all v83 sound variants (MPEG-1 vs 2, mono/stereo, WAV-in-WZ entries) was verified only on one BGM stream.
- The GL Compatibility anomaly (one run pinned at 6.90 ms) is unexplained.
