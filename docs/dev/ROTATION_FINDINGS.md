# RotationCore — сводный отчёт (аудит + исправления)

Обновлено: 2026-10-18. Источник данных: официальные БД 3.3.5a
(wotlkdb.com, db.rising-gods.de, wotlk.cavernoftime.com; wowhead
wotlk / evowow — за Cloudflare).

## 1. Исправлено в hotfix40 (проверено по БД)

| Класс | Что было | Что стало | Причина |
|---|---|---|---|
| Hunter | Aimed Shot моделировался как каст 2.9 с | мгновенный, `sim.gcd` | В 3.3.5a Aimed Shot — мгновенный (КД 10 с) |
| Hunter | Kill Command КД 50 с | 60 с, вне GCD | Реальный КД — 60 с, GCD 0 |
| Paladin | В карту `art_of_war` входил id таланта 53488 (и неизвестный 53490) | оставлены только проки 59578 и 53489 | 53488 — пассивный талант, проком бафа не является → «вечно активный» AoW |
| Paladin | Prot не заполнял `has_ds` | `has_ds = talent.divine_storm.rank > 0` | Divine Storm в AoE никогда не выдавался (мёртвая ветка) |
| Mage | `MANA_GEM = 42987` | `42985` | Conjure Mana Gem = Mana Sapphire 42985 |
| DK | Unholy не ставил `has_howling_blast` | ставится из таланта | Мёртвая ветка AoE |
| DK | Blood/Unholy Blood Tap без гейта КД | добавлен КД 60 с + настройка `use_blood_tap` | КД не отслеживался, способность могла рекомендоваться вне КД |
| Rogue | Preparation КД 300 с | 480 с (8 мин) | В 3.3.5a КД Preparation = 8 минут |
| Druid | Berserk КД 120 с | 180 с (3 мин) | В 3.3.5a КД Berserk = 3 минуты |
| Paladin | Exorcism (AoW) под глобальным гейтом кулдаунов | только персональный тумблер `use_exorcism` | Прок «умирал» при `cooldown_order=manual` / `auto_cooldowns=off` |
| Paladin | Нет апкипа печати в Ret/Prot | апкип печати (пусто → SoV, AoE → SoC) | Потеря DPS без активной печати |

## 1b. Исправлено в hotfix42 (полный аудит всех spell id)

Сверены ВСЕ зарегистрированные id: способности, баффы, дебаффы, глифы,
кулдауны (312 id способностей + 469 уникальных id мап + 247 id глифов/кд).

| Класс | Что было | Что стало |
|---|---|---|
| DK | Blood/Frost Presence перепутаны (48263/48266) — выдавалась неверная стойка; ошибка была и в buff-карте | 48263 = Frost, 48266 = Blood |
| DK | Sudden Doom id 81340 не существует → прок бесплатного Death Coil НЕ детектился | реальные ранги 49018 / 49529 / 49530 |
| DK | Таблица глифов перепутана: 58657 (Plague Strike) стоял на *obliterate*, 58671 (Obliterate) на *heart_strike* и т.д. | все 7 глифов исправлены на реальные id |
| Druid | дебафф-карта: ранг Rip (9752) помечен как *rake*; чужие id (6800 = Shred, 48467 = Hurricane) как rip/insect_swarm | реальные ранги rake/rip/insect_swarm |
| Hunter | глиф Aimed Shot указывал на заглушку 57231 («Death Knight Glyph 25») | реальный Glyph of Aimed Shot 56869 |
| Priest | дебафф SW:P содержал чужие id 11678 (Rain of Fire) и 11679 (нет) | реальные ранги SW:P |
| Shaman | дебафф Flame Shock содержал id 10458 (Frostbrand Attack) | реальные ранги Flame Shock |
| Warrior | дебафф Rend содержал тестовый спелл 47464 и 25874 (Viscidus) | реальные ранги Rend |
| Warrior | способность Hamstring использовала ранг 1 (1715) | макс. ранг SPELLS.HAMSTRING (7373) |

Косметика (id валиден, отличается лишь имя в БД от внутреннего ключа):
Warrior Bloodsurge = «Slam!», Warlock Curse of Elements («the»), DK
Unholy Frenzy («Hysteria») — функционально корректны.

Несуществующий глиф: Druid `omen_of_clarity` (id 413895 из другого патча).
В 3.3.5a такого глифа нет; код защищён `and`, поэтому безвреден.

## 2. Проверено по БД — уже корректно (не трогали)

- DK: Rune Tap 48982 (60 с), Vampiric Blood 55233 (60 с), Bone Shield
  49222 (60 с), Blood Tap 45529 (60 с) — все вне GCD, значения совпадают.
- DK: Frost Fever / Blood Plague — база 15 с, +3 с/ранг Epidemic
  (`15 + rank*3`) — верно.
- DK: Howling Blast 49184 — КД 8 с, накладывает Frost Fever.
- DK: Pestilence 50842 — без КД, GCD 1.5 с.
- Paladin: Exorcism 48801 — КД 15 с, каст 1.5 с (мгновенный под AoW).
- Mage: основные id способностей корректны.
- Warlock: Haunt 8 с, Demonic Empowerment 60 с (вне GCD), Immolation Aura 30 с,
  Chaos Bolt 12 с, Shadowfury 20 с — верно.
- Warrior: Mortal Strike 6 с, Overpower 5 с, Bloodthirst 4 с, Death Wish 180 с,
  Recklessness 300 с — верно.
- Priest: Mind Blast 8 с, Shadow Word: Death 12 с, Shadowfiend 300 с,
  Dispersion 120 с, Inner Focus 180 с — верно.
- Shaman: Stormstrike 8 с, Chain Lightning 6 с, Feral Spirit 180 с,
  Shamanistic Rage 60 с, Lava Burst 8 с — верно.
- Mage: Arcane Power 120 с, Presence of Mind 120 с, Icy Veins 180 с,
  Deep Freeze 30 с, Blast Wave 30 с — верно.
- Druid: Force of Nature 180 с, Starfall 90 с, Tiger's Fury 30 с — верно.
- Rogue: Vanish 180 с, Blade Flurry 120 с, Cold Blood 180 с, Killing Spree 120 с,
  Adrenaline Rush 180 с, Shadow Dance 60 с, Shadowstep 30 с — верно.

## 3. Известные остаточные вопросы (требуют проверки в игре)

Приоритет: HIGH — влияет на выдачу; MED — качество; LOW — косметика.

- **MED. Hunter, MM.** Silencing Shot предлагается как DPS-кулдаун
  (по настройке `use_silencing_shot`). Позиционно это утилити-прерывание;
  оставить опциональным, но не ставить высоко в очередь.
- **MED. Hunter.** Нет модели маны (Aspect of the Viper / манa-менеджмент).
- **MED. DK, Blood.** Defensive-кулдауны (Vampiric Blood, Rune Tap,
  Bone Shield) перечислены в `cds`, но в ротации не выдаются — для
  DPS-ротации приемлемо, но стоит решить, показывать ли их вообще.
- **LOW.** У некоторых способностей GCD в 3.3.5a нулевой (вне GCD) —
  Blood Tap, Rune Tap, Vampiric Blood, Demonic Empowerment, Vanish,
  Shadowfury. Симулятор продвигает время на GCD; при желании можно
  выставить `getAdvanceTime = 0` для таких ключей (влияние минимально).
- **LOW. Paladin, Ret.** Exorcism к нежити/демонам в 3.3.5a всё равно
  используется только под проком AoW (сверено с гайдами) — оставлено как есть.

## 4. Надёжность (Reliability)

Выполнено ранее (hotfix39 и до): pcall-обёртки вокруг инициализации,
тик-цикла, обработчиков событий и combat-log; защитные проверки
`GetSetting`/`SetSettingRaw`, `MergeDefaults`, `GetActiveSpec`, спеку-профилей,
позиций/размеров окон; `DeferNextFrame` через очередь; нормализация
аналитики. Отдельно проверено: в аддоне нет `InCombatLockdown`,
`SetAttribute`, `SecureActionButtonTemplate`, `hooksecurefunc`, `C_*`
(риска таинта нет).

## 5. Локализация

- Механические правки (переименования ключей, 8 новых ключей, устранение
  перекрёстного заражения языков, локализация баннера ошибок) — сделаны,
  `verify.py` = PASS.
- Дополнительно переведены ~55 «английских утечек» в Help и на страницах
  слэш-команд для всех 8 зеркал. Осталось 2 допустимых совпадения
  (кoгнаты/пути команд).
