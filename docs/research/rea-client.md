# rea-client: can REA recover gameplay behavior from the v83 client?

Investigator: Phase-0 research subagent, 2026-10-13. Scratch code and outputs are in `C:\Users\itech\Coding\maple-survivors-refs\research\rea-client\`. Nothing was executed from the target, and nothing was unpacked. Every check was a static, read-only parse of files on disk.

## Summary

- **REA cannot do any native code analysis on this machine as it is set up now.** Every deep provider is unavailable. Ghidra is `not_configured`: `GHIDRA_INSTALL_DIR` is unset and `java.exe` is missing (`runtime_missing`). Hopper is `unsupported_host` ("Hopper integration is not supported on win32"). IDA is `not_configured`. As a result `binary_overview`, `search_strings`, `list_strings`, `list_segments`, `read_bytes`, decompile and xrefs all return `provider_unavailable`. `inspect_binary_layout` only supports Linux x64 through pwntools, and `inspect_signature` only works on macOS.
- **What REA did produce for MapleStory.exe** came from its provider-neutral and .NET static paths. It identified a PE32 x86 image (machine `0x014c`) with 7 sections and characteristics `271` (0x10F). The CLI directory is absent, so the image is not managed code. SHA-256 is `ed5a6994…2848`. `inspect_pe_resources` refused the file with "Resource range is not entirely file-backed in one section", which is a packing symptom.
- **The section, entropy, import and string facts below come from my own read-only Node parser** (`pe-inspect.mjs`), not from REA, because REA's native path was unavailable.
- **The evidence fits Themida/WinLicense-class protection, but no literal Themida marker was found:**
  - Section names: `"   \0    "` (blank), `.rsrc`, `.idata`, `"        "` (blank), `ytkjcptk`, `albasygk`, `jbhyjsdw`, plus an 8th leftover header `ygdiffxt` filled with junk values.
  - All code sections are RWX (`0xE0000040`).
  - The main section has entropy 7.98 with 5.35 MB of virtual-only space. Whole-file entropy is 7.977.
  - The import table is a single entry: `kernel32.dll!IsValidCodePage`.
  - The entry point is in `albasygk` (RVA `0xA90000`), not in the first section.
  - There are no base relocations, no TLS directory and no debug directory.
  - No "Themida", "WinLicense", "Oreans" or "SecureEngine" string appears. The entry stub is a self-locating `call $+1 / int3 / pop` sequence of the kind commonly attributed to Themida/WinLicense 2.x. I did not confirm it against a signature database (UNVERIFIED).
- **No gameplay code or constants are visible statically.** I searched the whole 4.29 MB file for ASCII and UTF-16LE runs of 6+ characters. There were zero hits for `Physics`, `walkForce`, `gravityAcc`, `jumpSpeed`, `fallSpeed`, `Map/Physics.img`, `Physics.img`, `foothold`, `ladderRope`, `CVecCtrl`, `CWvsContext`, `CWvsPhysicalSpace2D`, `CUserLocal`, `CMob`, `.wz` and `.img`. The only readable content is:
  - the PE header text;
  - the version resource ("Wizet MapleStory", FileVersion 1.0.0.1, © 2003);
  - a `requireAdministrator` manifest;
  - 3 exports (`ZtlTaskMemAllocImp`, `ZtlTaskMemFreeImp`, `ZtlTaskMemReallocImp`);
  - the Authenticode block (NEXON Corp. via Thawte Code Signing CA, signing time 2010-02-17 16:18:26Z). I did not check the signature cryptographically.
- **Getting past the protection would mean unpacking it, and the project has ruled that out.** Even with Ghidra and a JDK installed, static analysis would only show the protector stub and encrypted or virtualized bytes. REA's own DISCLAIMER says the project "does not support, and will not help with … circumventing DRM, license checks, anti-cheat systems or other technical protection measures" (DISCLAIMER.md:10-13).
- **The physics constants live in the WZ data, and I read them directly from the canonical asset.** I wrote a minimal read-only WZ reader (`wz-physics.mjs`). It confirmed `Map.wz` version 83 (encVersion 172 matches) and read `Physics.img` (19 props): `walkForce 140000`, `walkSpeed 125`, `walkDrag 80000`, `slipForce 60000`, `slipSpeed 120`, `floatDrag1 100000`, `floatDrag2 10000`, `floatCoefficient 0.01`, `swimForce 120000`, `swimSpeed 140`, `flyForce 120000`, `flySpeed 200`, `gravityAcc 2000`, `fallSpeed 670`, `jumpSpeed 555`, `maxFriction 2`, `minFriction 0.05`, `swimSpeedDec 0.9`, `flyJumpDec 0.35` (float). The Cosmic XML export has `flyJumpDec` as `35.0`, which does not match the original (0.35). Use the original WZ.
- **The integration rules that turn those constants into motion are not in WZ.** That covers tick rate, how friction and slope are applied, speed-stat scaling, knockback impulse and camera smoothing. Open-source reimplementations disagree on these. For example, ground `FRICTION` is 0.3 in JourneyClient but 0.5 in ryantpayton/MapleStory-Client, and both use hand-tuned per-8 ms constants (GRAVFORCE 0.14) rather than Physics.img. These remain reimplementation-derived and are not verified against the original client.
- **To enable REA's native path anyway**, you would need four things: Ghidra 12.1.x (verified with 12.1.4), a 64-bit full JDK 21+ that includes `javac`, `GHIDRA_INSTALL_DIR`, `JAVA_HOME` and `REA_ANALYSIS_PROVIDER=ghidra` added to the `rea` MCP registration's `env`, and a client restart. Windows Ghidra support is "experimental" and read-only ("P0"). For this target it would add nothing beyond the protector stub, so it is not worth doing for this project.
- **HeavenMS-localhost-WINDOW.exe was not analyzed.** Defender flagged it as Trojan:MSIL/Cryptor!rfn (severity 5) and deleted it. Analyzing it is an opt-in decision for the project owner.

## Detailed findings

### 1. What REA is, how it installs, and which backends it needs

- **Identity and license.** REA ("Reverse Engineer Anything") is an MCP server plus CLI, published on npm as `rea-agents`, at https://github.com/morluto/rea. The local clone is at commit `80592b82a6f854886862978533bb405e3f2e38c5`, package version 6.4.0 (`rea/package.json:4`). The license is MIT, "Copyright (c) 2026 morluto" (`rea/LICENSE:1-3`). Third-party engines keep their own licenses (`rea/THIRD_PARTY_NOTICES.md`; Ghidra is Apache-2.0 with NOTICE qualifications).
- **Runtime requirement.** Node.js 22.x (≥22.19), 24.x (≥24.11) or 26+ (`rea/README.md:157`). This host has Node 24.21.0 (from `rea doctor`).
- **Install workflow.**
  - The usual route is `npx rea-agents setup` (README.md:71-77) or `npm install --global rea-agents` (README.md:104-109).
  - `install.sh` runs only on macOS and Linux (`install.sh:110-111`: `[ "$platform" = "Darwin" ] || [ "$platform" = "Linux" ] || fail ...`). It installs the npm package and can then run `rea setup`.
  - On this machine REA is already registered in `~/.claude.json` as `node …\npm-cache\_npx\9b9809298fe40d2c\node_modules\rea-agents\scripts\rea.mjs mcp`. That entry has no `env` block, so no provider is configured. The installed version is also 6.4.0.
- **Backends by target type** (README.md:160-184):
  - Native pseudocode, assembly, strings and xrefs need "Hopper, Ghidra or IDA".
  - .NET, JavaScript, Go and Rust static inspection need no engine.
  - Offline ELF layout needs pwntools on Linux x64.
  - objdump and Rizin are optional, caller-supplied tools (`docs/reverse-engineering-tools.md:3,79`). Neither is on PATH here (`which objdump rizin` → not found).
- **Hopper.** It is commercial. The automated installer supports only macOS and some Linux distributions (`docs/installation.md:314-317`), and REA reports `unsupported_host` on win32.
- **IDA.** It is commercial and bring-your-own, wired up through `REA_IDA_MCP_CONFIG` (README.md:198-200, `docs/ida-provider.md`).
- **Ghidra (the only free route on Windows).** Requirements:
  - Ghidra 12.1.x, verified with 12.1.4. It needs a 64-bit full JDK in the installation's declared range, which is JDK 21+ for 12.1 (`docs/installation.md:491-498`).
  - Windows support is the "experimental Windows x64 support for the read-only P0 boundary" (`docs/windows-ghidra-p0.md:9`). It admits "native x86 (32-bit) PE" on repo main (`windows-ghidra-p0.md:7`; `installation.md:522`). The installed `rea-agents` is 6.4.0, the same version as the clone's `package.json`, so this 32-bit admission should apply to this install (UNVERIFIED until run with Ghidra).
  - Configuration is `GHIDRA_INSTALL_DIR`, `JAVA_HOME` and `REA_ANALYSIS_PROVIDER=ghidra`, set in the MCP registration's `env` (`windows-ghidra-p0.md:63-105`).
  - REA "does not install or upgrade Ghidra, Java, Python…" (`windows-ghidra-p0.md:48-50`; `AGENTS.md:11`).
  - Cold imports can take up to the 330-second provider startup deadline (`windows-ghidra-p0.md:108-110`).
- **What it would take to enable the decompiler here.**
  1. Install a 64-bit JDK 21+ that includes `javac` (for example Temurin 21, GPLv2+CE).
  2. Extract Ghidra 12.1.4 (Apache-2.0).
  3. Add `"env": {"REA_ANALYSIS_PROVIDER":"ghidra","GHIDRA_INSTALL_DIR":"…","JAVA_HOME":"…"}` to the `rea` MCP entry.
  4. Restart the client.

  I did none of this, as the brief requires. Do not run `rea setup` just to fix the "config_drift" it reports: that would rewrite registrations for Copilot CLI, Cursor and VS Code.
- **REA's responsible-use limits** (`rea/DISCLAIMER.md:10-19`): the project "does not support, and will not help with: circumventing DRM, license checks, anti-cheat systems or other technical protection measures; developing game cheats…; copying proprietary software or reproducing its protected code and assets". AGENTS.md:7 says protection recovery needs a maintainer scope decision. REA's own scope therefore excludes unpacking Themida.

**`rea doctor --json` (run from the installed npx package, read-only), excerpt:**
```
{"healthy":false, ... "scope_checks":[{"name":"node","ok":true,"detail":"24.21.0"},{"name":"host","ok":true,"detail":"win32 x64"},
{"name":"hopper","ok":false,"classification":"missing_analysis_engine"},
{"name":"ghidra","ok":false,"classification":"missing_analysis_engine","detail":"GHIDRA_INSTALL_DIR is not set"},
{"name":"ida-registration","ok":false,"classification":"missing_analysis_engine"}, ... config_drift for copilot_cli/cursor/vscode ...],
"identity":{"cli_package_version":"6.4.0", ... "catalog":{"counts":{"cli_commands":127,"mcp_tools":170,"mcp_prompts":6}}}}
```

### 2. REA tool results on `v83-original\MapleStory.exe`

| REA tool | Result |
|---|---|
| `open_binary` | OK: `format: pe, kind: executable, architecture: x86, sha256 ed5a699407b9705528b6a653cdee7395e6e1b7317b9711dcfb34681092072848` |
| `inspect_artifact` (record-and-continue) | OK: provider `rea-artifact-graph`. Size 4,286,088 B, 1 node, "Artifact has no child container entries". Next probes: `inspect_managed_artifact`, then `open_binary`. |
| `inspect_managed_artifact` | OK: provider `rea-dotnet-static`. `machine 332 (0x014c)`, `pe32`, `section_count 7`, `characteristics 271`, classification `not-managed`, evidence `cli-directory-absent`. |
| `inspect_pe_resources` | REJECTED: `invalid_format`, "Resource range is not entirely file-backed in one section." |
| `binary_overview`, `search_strings("Physics")` | `provider_unavailable`. Candidates `ghidra` (not_configured: GHIDRA_INSTALL_DIR unset; `java.exe` runtime_missing; analyzeHeadless and native decompiler missing), `hopper` (unsupported_host win32), `ida` (not_configured). |
| `inspect_signature` | `capability_unavailable`: "Native macOS utilities require macOS." |
| `inspect_binary_layout` | `capability_unavailable`: "The initial real-verified pwntools artifact profile supports Linux x64 only." |

These are host and provider limits. They say nothing about the target itself.

### 3. My own static PE parse (because REA's native path was unavailable)

Command: `node research/rea-client/pe-inspect.mjs v83-original/MapleStory.exe research/rea-client/pe-inspect.json`. It is read-only; the full JSON is saved there. A second script, `extra.mjs`, writes `extra-output.txt` with the version info, exports and certificate.

**Headers**
- COFF: machine `0x14c`, 7 sections, TimeDateStamp `1266423241` = **2010-02-17 16:14:01 UTC**, characteristics `0x10F` (relocs stripped, executable, line numbers and local symbols stripped, 32-bit).
- Optional header:
  - magic `0x10B` (PE32), linker 6.0, ImageBase `0x400000`, SizeOfImage `0xA92000`.
  - SizeOfCode `0x6EF000`, FileAlignment `0x1000`, Subsystem 2 (GUI), DllCharacteristics `0x0` (no ASLR or DEP flags).
  - **AddressOfEntryPoint `0xA90000`, VA `0xE90000`, which is in section `albasygk`.**
- Entry-point bytes (file offset `0x406000`): `83ec045053e801000000cc588bd8402d00d011002d5d365f000552365f00803b`. That decodes to `sub esp,4; push eax; push ebx; call $+5+1; int3; pop eax; mov ebx,eax; inc eax; sub eax,0x11D000; sub eax,0x5F365D; add eax,…; cmp byte [ebx],…`. This is a self-locating, anti-debug (`int3`) stub, not compiler-generated CRT startup code. A web search did not find this exact sequence documented as a Themida signature, so the protector identification stays UNVERIFIED.

**Sections** (perms: X = execute, R = read, W = write; H = Shannon entropy of the raw bytes, in bits per byte)

| # | Name (raw) | VA | VirtualSize | RawSize | RawPtr | Flags | Perms | H | Virtual-only bytes |
|---|---|---|---|---|---|---|---|---|---|
| 0 | `"   \0    "` (blank) | 0x1000 | 0x7F8000 | 0x2DD000 | 0x1000 | 0xE0000040 | XRW | **7.9805** | 5,353,472 |
| 1 | `.rsrc` | 0x7F9000 | 0x1F4D0 | 0x9000 | 0x2DE000 | 0xC0000040 | RW | 7.8622 | 91,344 |
| 2 | `.idata` | 0x819000 | 0x1000 | 0x1000 | 0x2E7000 | 0xC0000040 | RW | 0.1256 | 0 |
| 3 | `"        "` (blank) | 0x81A000 | 0x159000 | 0x1000 | 0x2E8000 | 0xE0000040 | XRW | 0.0422 | 1,409,024 |
| 4 | `ytkjcptk` | 0x973000 | 0x11D000 | 0x11D000 | 0x2E9000 | 0xE0000040 | XRW | **7.9233** | 0 |
| 5 | `albasygk` (entry point) | 0xA90000 | 0x1000 | 0x1000 | 0x406000 | 0xE0000040 | XRW | 0.2843 | 0 |
| 6 | `jbhyjsdw` | 0xA91000 | 0x1000 | 0x1000 | 0x407000 | 0xE0000040 | XRW | 2.2343 | 0 |
| (7) | `ygdiffxt`, a leftover header beyond NumberOfSections | junk: va 0xC8BAAFCE, vsize 0xC87F6FCE | | | | 0xE0000040 | | | |

- Whole-file entropy is **7.9771**.
- The overlay after the last section (file offset 0x408000) is 59,016 bytes. It is 53,408 bytes of other data followed by a 5,608-byte Authenticode `WIN_CERTIFICATE` (revision 0x200, type 2 = PKCS#7) at file offset `0x4150A0` that runs to EOF. (`pe-inspect.json` lists the `security` directory as "not file-backed" because the generic parser treated its value as an RVA. That value is actually a file offset; `extra.mjs` parses it correctly.)

**Data directories**
- **Import:** RVA 0x819043, 87 bytes, in `.idata`. The **only import is `kernel32.dll!IsValidCodePage` (1 function in total).**
- **Export:** RVA 0xA8E774, in `ytkjcptk`. Module name `MapleStory.exe`. Exports: `ZtlTaskMemAllocImp` (rva 0x5F2503), `ZtlTaskMemFreeImp` (0x5F2514), `ZtlTaskMemReallocImp` (0x5F2525).
- **Resource:** RVA 0x7F9000, size 0x1F4D0. It starts file-backed in `.rsrc`, but its end lies beyond `.rsrc`'s 0x9000 raw bytes (`endFileBacked: false`). That is the same condition that made REA reject `inspect_pe_resources`.
- **Missing directories:** base relocations, TLS, debug, load config, IAT, delay import and CLR are all 0.

**Readable strings** (ASCII runs of 6+ characters: 5,183, most of them random high-entropy noise; UTF-16LE runs of 6+: 26)
- The version resource sits inside `ytkjcptk` at file offset 0x40563C (relocated by the protector): CompanyName `Wizet`, FileDescription `MapleStory`, FileVersion `1, 0, 0, 1`, LegalCopyright `Copyright … 2003`, ProductName `Wizet MapleStory`, OriginalFilename `MapleStory.exe`, translation `041204b0`.
- The manifest at 0x4059B7 has `assemblyIdentity name="MapleStory" processorArchitecture="x86"` and `requestedExecutionLevel level="requireAdministrator"`.
- Certificate strings: `NEXON Corp.`, `Development Department`, `Seoul`, `Gangnam-gu`, `www.nexon.com`, `Thawte Code Signing CA`, `VeriSign Time Stamping Services Signer - G2`. Certificate validity is 080515072742Z–100515072742Z. The last UTCTime, `100217161826Z`, is presumably the signing time; it is 4.5 minutes after the link timestamp. I did not verify the signature's validity.
- **Zero hits** in either encoding for: Physics, walkForce, walkSpeed, walkDrag, gravityAcc, fallSpeed, jumpSpeed, swimForce, flyForce, Map/Physics.img, Physics.img, foothold, ladderRope, CVecCtrl, CWvsContext, CWvsPhysicalSpace2D, CUserLocal, CMob, .wz, .img, Themida, WinLicense, Oreans, SecureEngine, HackShield, AhnLab, EHSvc, nProtect, GameGuard, xigncode, MSVCR, zlib, inflate.
- An unpacked MSVC game client would normally contain hundreds of readable strings: WZ paths, RTTI class names such as `.?AVCWvsContext@@`, CRT messages. Their absence, together with entropy around 7.9–8.0 in the two large sections, means the original code and data are stored compressed or encrypted.

**Verdict on protection.** Confirmed: the binary is packed or protected. Every structural signal in the brief checks out: the random lowercase 8-character section names `ytkjcptk`, `albasygk` and `jbhyjsdw`; a one-function kernel32 import table; the entry point in a protector section; RWX sections; large virtual-only regions; and high entropy. It also has an extra junk section header. All of this fits Themida/WinLicense 2.x. The specific vendor attribution is UNVERIFIED: I found no literal marker string and no signature-database match.

### 4. The behaviors in the WZ data, verified from the canonical asset

Command: `node research/rea-client/wz-physics.mjs v83-original/Map.wz Physics.img 83`. This is a minimal read-only WZ reader using the GMS IV `4D 23 C7 2B` and the standard MapleStory AES key. Output is in `wz-physics-output.txt`. Map.wz SHA-256: `a0657907c42962d5b8a38e007defbcb9ba4f8a61bc32884e9f8c2bc1cb0ebebe`.

```
fileStart=60 encVersion=172 computedFor83=172 MATCH
top-level entries: 8 Physics.img, Effect.img, MapHelper.img, Tile, WorldMap, Obj, Back, Map
Physics.img @162502 size 405, 19 props: walkForce 140000, walkSpeed 125, walkDrag 80000, slipForce 60000, slipSpeed 120,
floatDrag1 100000, floatDrag2 10000, floatCoefficient 0.01, swimForce 120000, swimSpeed 140, flyForce 120000, flySpeed 200,
gravityAcc 2000, fallSpeed 670, jumpSpeed 555, maxFriction 2, minFriction 0.05, swimSpeedDec 0.9, flyJumpDec 0.35 (float32)
```

Cross-checks:
- **Cosmic XML** (`cosmic-server/wz/Map.wz/Physics.img.xml:3-21`, AGPL-3.0 repo) has the same 18 values but gives `flyJumpDec` as `<float … value="35.0"/>`. The original reads float32 0.35, so the Cosmic value does not match the original.
- **Harepacker-resurrected** (MPL-2.0) hard-codes the same defaults, including `flyJumpDec 0.35` (`HaCreator/GUI/MapPhysicsEditor.cs:18-21`). Its MapSimulator loads them from `Map.wz/Physics.img` at runtime (`HaCreator/MapSimulator/MapSimulator.cs:20651-20656`).

## Exact numbers & IDs

### Target identity

| Item | Value |
|---|---|
| File | `C:\Users\itech\Coding\maple-survivors-refs\v83-original\MapleStory.exe` |
| Size / SHA-256 | 4,286,088 B / `ed5a699407b9705528b6a653cdee7395e6e1b7317b9711dcfb34681092072848` |
| Link time | 2010-02-17 16:14:01 UTC (0x4B7C15C9 = 1266423241) |
| Signing time | 100217161826Z (UTCTime in the PKCS#7; certificate validity not verified) |
| Entry point | RVA 0xA90000 / VA 0xE90000 (section `albasygk`) |
| Imports | 1: `kernel32.dll!IsValidCodePage` |
| Exports | `ZtlTaskMemAllocImp`, `ZtlTaskMemFreeImp`, `ZtlTaskMemReallocImp` |
| Version resource | Wizet MapleStory, 1.0.0.1, lang 0412/04b0 |

### Physics.img (`Map.wz`, original v83), units as conventionally interpreted

The "Meaning" column is my interpretation, UNVERIFIED against original code.

| Key | Value | Meaning (UNVERIFIED) |
|---|---|---|
| walkForce | 140000 | ground acceleration force |
| walkSpeed | 125 | base max walk speed, px/s |
| walkDrag | 80000 | ground deceleration |
| slipForce / slipSpeed | 60000 / 120 | slippery (ice) footholds |
| floatDrag1 / floatDrag2 / floatCoefficient | 100000 / 10000 / 0.01 | air and float drag |
| swimForce / swimSpeed / swimSpeedDec | 120000 / 140 / 0.9 | swimming maps |
| flyForce / flySpeed / flyJumpDec | 120000 / 200 / 0.35 | flying |
| gravityAcc | 2000 | px/s² |
| fallSpeed | 670 | terminal fall speed, px/s |
| jumpSpeed | 555 | initial jump velocity, px/s |
| maxFriction / minFriction | 2 / 0.05 | friction clamp |

### Behavior source map

Sources are classed as: WZ = data in the original WZ files; RI = reimplementation-derived (not verified against the original client); UNKNOWN = not recoverable without original code.

| Behavior | Best source | Status / evidence |
|---|---|---|
| Movement speed, accel, drag | WZ `Map.wz/Physics.img` (verified above). The speed stat comes from equips and skills. | Constants: **WZ (verified)**. How the SPEED stat scales `walkSpeed`: **RI**. ryantpayton uses `0.05 + 0.11*SPEED/100` per tick (`Character/Player.cpp:465-468`). Original formula **UNKNOWN**. |
| Jump, gravity, terminal velocity | `gravityAcc 2000`, `jumpSpeed 555`, `fallSpeed 670` | Constants: **WZ (verified)**. Integrator and tick: **RI**. JourneyClient and ryantpayton step every 8 ms (`Constants.h:26`, `Constants.h:29`) with a hand-tuned `GRAVFORCE = 0.14` that does not come from WZ (`Gameplay/Physics/Physics.cpp:22-23`). Original **UNKNOWN**. |
| Friction and slopes | `walkDrag`, `max/minFriction`, `slip*` in WZ | Application formula: **RI, and implementations disagree**. `FRICTION = 0.3` in JourneyClient (`Physics.cpp:25`) vs `0.5` in ryantpayton (`Physics.cpp:24`); both use `SLOPEFACTOR 0.1` and `GROUNDSLIP 3.0`. |
| Knockback | Mob.wz `info/pushed` (knockback threshold) | The value is read by reimplementations (ryantpayton `Gameplay/MapleMap/Mob.cpp:44`). Impulse and duration: **RI / UNKNOWN**. Harepacker `Physics/CVecCtrl.cs:10-20` claims "Based on MapleStory client's CVecCtrl class from IDA Pro analysis" (third-party reverse engineering of an unstated client version). Its provenance and accuracy for v83 are UNVERIFIED. |
| Foothold collision | Map.wz `<map>.img/foothold` geometry | Geometry: **WZ**. Collision and edge rules: **RI** (`Gameplay/Physics/Foothold*.cpp` in JourneyClient and ryantpayton). |
| Ladders and ropes | Map.wz `<map>.img/ladderRope` (`l`, `uf`, x, y1, y2) | Geometry: **WZ** (ryantpayton `Gameplay/MapleMap/MapInfo.cpp:51,118`). Climb speed: **RI** (`get_climbforce = SPEED/100`, `Player.cpp:475-478`). |
| Animation timing | per-frame `delay` (ms) in Character/Mob/Skill/Effect/Npc .wz | **WZ** (ryantpayton `Graphics/Animation.cpp:33` reads `src["delay"]`). |
| Mob movement | Mob.wz `info/speed`, `flySpeed`, `noFlip`, `bodyAttack` | Values: **WZ**. Conversion to px/tick: **RI** (`speed += 100; speed *= 0.001f`, `Mob.cpp:82-86`). AI and pathing: **UNKNOWN** (original control was server-driven). |
| Skill timing | Skill.wz `level/N/time`, `cooltime`, `mpCon`, `mobCount`, `attackCount`, plus Character.wz action frame delays | **WZ** (Cosmic reads `time`, `mpCon`, `mobCount`, `cooltime` at `src/main/java/server/StatEffect.java:241,246,272-273`, AGPL-3.0, read for facts only). |
| Damage formula | none in WZ | **RI** from server emulators (Cosmic `client/Character.java:792 calculateMaxBaseDamage`). The original client-side roll is **UNKNOWN**. |
| Damage numbers (visuals) | Effect.wz `BasicEff.img/NoRed0`, `NoRed1`, … digit sprites | **WZ** (ryantpayton `Gameplay/Combat/DamageNumber.cpp:194-197`). Float, rise and fade timing: **RI / UNKNOWN**. |
| Camera | Map.wz `info` bounds (VR*) plus a smoothing rule | Bounds: **WZ**. Smoothing: **RI** (ryantpayton `Gameplay/Camera.cpp:45-54`, `delta * 12/VWIDTH`). |
| Parallax backgrounds | Map.wz `back` nodes (`rx`, `ry`, `cx`, `cy`, `type`) | Values: **WZ**. Shift math: **RI** (`shift_x = rx*(WOFFSET-viewx)/100 + WOFFSET`, ryantpayton `Gameplay/MapleMap/MapBackgrounds.cpp:43-44,110,122`). |
| UI art and layout | UI.wz | **WZ** for art and origins. Widget behavior: RI. |
| Sound | Sound.wz | **WZ**. |

## Licensing notes

- **REA** (morluto/rea): MIT (`rea/LICENSE`). Its responsible-use DISCLAIMER excludes circumventing protection measures and "copying proprietary software or reproducing its protected code and assets".
- **Ghidra**: Apache-2.0 plus NOTICE. **OpenJDK**: GPLv2 with Classpath Exception. Both are needed only if the decompiler path is ever enabled. **Hopper, IDA and JEB** are commercial; REA grants no license (README.md:379-385).
- **Cosmic server** (P0nk/Cosmic): AGPL-3.0 (`cosmic-server/LICENSE`, commit `fec53bc7`). I read it for facts only. Do not copy its code or XML into shipped code.
- **Prior-art repos cited** (license read from each repo's LICENSE file):
  - SYJourney/JourneyClient: AGPL-3.0 (commit `5546c998`).
  - ryantpayton/MapleStory-Client: AGPL-3.0 (commit `cbb0fe27`).
  - HypatiaOfAlexandria/MortalClient: AGPL-3.0.
  - NoLifeDev/NoLifeStory: AGPL-3.0.
  - lastbattle/Harepacker-resurrected: MPL-2.0 (commit `4d7fcecb`). MPL-2.0 is file-level copyleft, and its CVecCtrl port says it is based on third-party IDA analysis of a Nexon client, which is a provenance risk for anything ported from it.
  - lastbattle/MapleLib: GPL-3.0.
  - Kagamia/WzComparerR2 and Elem8100/MapleNecrocer: MIT.
  - Elem8100/MapleStory-GM-Client: MPL-2.0.
  - spd789562/wz-reader-rs: MIT.
  - toyobayashi/wz, ryantpayton/NoLifeWzToNx and wuzekang/maple-rs: no LICENSE file found at the top level (UNVERIFIED).
- **Formulas** reimplemented from AGPL or MPL code should be re-derived and documented as facts (numbers and behavior), not copied verbatim.
- **My scratch scripts** (`pe-inspect.mjs`, `extra.mjs`, `wz-physics.mjs`) are original. The WZ reader uses the publicly known GMS IV and AES key layout as facts, not copied code.
- **MapleStory.exe and the WZ files** are Nexon property. Reading them locally for facts is the project's premise. Redistributing them is a separate question that this report does not address.

## Unknowns & risks

- **Original integration rules are UNKNOWN.** That covers tick length, how `walkForce` and `walkDrag` combine with friction and slope, SPEED and JUMP stat scaling, the knockback impulse curve, mob AI, and the client-side damage roll. They are inside the protected code and can only be approximated. The best available proxies are reimplementations that disagree with each other (FRICTION 0.3 vs 0.5) and Harepacker's port, which describes itself as based on IDA analysis, of unstated client version and license provenance. Treat any value from these as a tunable to check against reference footage, not as ground truth.
- **The protector attribution (Themida/WinLicense 2.x) is UNVERIFIED.** It is consistent with every structural signal, but I found no marker string and no signature-database match. This does not affect any decision, because the project will not unpack it.
- **Enabling Ghidra in REA would not change the conclusion** for this exe. Ghidra would see only the stub and packed bytes, plus the same headers and resources. It might matter only if the project later chooses to analyze an unprotected binary (none is present) and accepts that legal and provenance decision.
- **REA's Windows Ghidra support is "experimental" and read-only ("P0")**, and REA's per-section and entropy tools are not available on Windows (`inspect_binary_layout` runs only on Linux x64). Any future REA work on this host needs a Linux VM or WSL for those features.
- **The Cosmic WZ XML is HeavenMS-edited and contains at least one value that does not match the original** (`flyJumpDec 35.0` vs the original 0.35). Always read canonical values from `v83-original\*.wz`.
- **I did not verify the Authenticode signature cryptographically.** Signer and time strings were read as raw ASN.1 text.
- **HeavenMS-localhost-WINDOW.exe** (the modified Cosmic client) was flagged by Microsoft Defender as **Trojan:MSIL/Cryptor!rfn (severity 5)** during download and deleted. I did not obtain or analyze it. Any analysis is an opt-in decision for the project owner.
- **The physics meanings in the table are conventional interpretations** from community tooling, not from original code.
