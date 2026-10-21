# Historical character snapshots

These eleven fixtures retain their original numeric state and `_doc` generation revision/options. They are saved
characters from earlier builds, not examples of the current advancement grants. Spec #226 (#232, 2026-10-18)
deliberately keeps them rather than regenerating: snapshot migration preserves equipment (including old spare
advancement weapons) and explicit weapon paths. Changing the grant rules does not invalidate an existing save.

| Fixture | Load behavior after #226 |
|---|---|
| `lv11_warrior_1st.json` | Infer Spear from the worn weapon; keep old spare weapons. |
| `lv34_fighter_2nd.json` | Infer Sword from the deepest multi-family job (Fighter). |
| `lv34_page_2nd.json` | Infer Blunt Weapon from the worn weapon at Page. |
| `lv34_spearman_2nd.json` | Infer Spear from the worn weapon at Spearman. |
| `hunter_2nd.json` | Keep its explicit Bow path and equipment. |
| `crossbowman_2nd.json` | Keep its explicit Bow path despite the worn crossbow; a single-family advancement preserves the first-job path. |
| `assassin_2nd.json`, `bandit_2nd.json` | Keep explicit Claw / Dagger and the historical opposite-family spare. |
| `lv37_brawler_2nd.json`, `lv36_gunslinger_2nd.json` | Keep explicit Knuckle / Gun and the historical opposite-family spare. |
| `lv35_magician_2nd.json` | Magician grants and its existing format-1-to-2 migration are unchanged. |

`test_advancement_paths.gd` covers path inference and inventory preservation; `test_bot_weapon_paths.gd` also loads
every committed snapshot and checks its expected path, unchanged equipment and idempotence. The line-specific fixture
tests still exercise their actual skills and restoration with the real cache. New-game chosen-only grants are covered
separately by deterministic advancement tests and the injected-input flow scenarios.

The old `_doc` commands reproduce their recorded revision, not the current bot: #232 intentionally adds job-stream-8
draws at every multi-family advancement. BotShop now upgrades the recorded family, even after a manual swap or weapon
destruction. Re-running an old fixture command on a newer revision can therefore produce a different character.
