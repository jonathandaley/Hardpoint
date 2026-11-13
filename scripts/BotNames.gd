extends RefCounted
# T325 (HUMAN_FOUND 2026-11-05 late): bot callsigns from a preset list -- cool, cheesy is fine,
# nothing objectionable -- dealt from a shuffled deck so names don't repeat until the deck runs
# out (then it reshuffles). Assigned once per match in the roster (Lobby._build_roster), which
# every peer receives, so all peers show the same names.

const NAMES := [
	"MurderousMaximus27", "IroncladIvan", "ThunderTread", "RustBucket", "SirLaserLot",
	"CaptainCrater", "BoltThrower", "MegaMauler", "TitaniumTina", "GrimReaperX",
	"ColonelKaboom", "StompyMcStompface", "Gearhead42", "WreckingRalph", "PistonPete",
	"BlastRadius", "CogsworthPrime", "TankTopTony", "ScrapyardSally", "MissileMagnet",
	"HeavyMetalHank", "ChromeDome", "TurboTurtle", "RivetRita", "SteelSnoozer",
	"DukeOfDents", "BarrageBetty", "Shrapnelly", "OverclockedOtto", "GrindhouseGus",
	"ClankAttack", "VoltageVic", "TorqueMonster", "SmokestackSam", "DieselDan",
	"ArmorAmy", "CrashCourse", "BigIronBob", "CraterMaker99", "LaserLarry",
	"MechaMaverick", "SparkPlugSid", "TheRustler", "WarpathWendy", "BulldozerBill",
	"ThrottleJockey", "OctaneOllie", "HammerheadHal", "FlakJacket", "SiegeEngineer",
	"Ricochet", "BunkerBuster", "CannonFodder7", "MajorMeltdown", "DentedDave",
	"ShockAndAwe", "RoboRascal", "BoomBoomBernie", "GrapeshotGreg", "MortarMarty",
	"RampageRhonda", "BrassKnuckles", "GasketCase", "IronMatriarch", "CrankyCrank",
	"BlitzBoy", "NitroNed", "FlywheelFred", "CobaltCarl", "WelderWes",
	"SteamrollerSue", "TurretTim", "BolterBrian", "RecoilRoy", "ArcLightAl",
	"TrebuchetTrev", "ScorchMark", "HotShotHarry", "SprocketRocket", "HydraulicHugo",
	"MagnumMabel", "LugnutLou", "AmmoDump", "TheJuggernaut", "BrawlerBeau",
	"GatlingGabe", "DemolitionDot", "KilowattKyle", "ShellShock", "PlasmaPaul",
	"MuzzleFlash", "ExhaustPipe", "TractorBeam", "QuakeMaker", "GunmetalGwen",
	"BallisticBarry", "RocketRonnie", "ClutchKicker", "SalvoSteve", "SledgehammerSam",
	"CarbonCopy", "FuseboxFiona", "DamageControl", "ArmageddonAndy", "BrimstoneBo",
	"Overkill3000", "WarthogWally", "MeteorMike", "ShieldBashSheila", "IronsideIrene",
	"PowerSurge", "HavocHolly", "CrossfireCraig", "ReactorRick", "MechanicalMolly",
	"StaticShockSteve", "TheBigStomp", "DropForgeDebbie", "RampartRex", "ThermiteTheo",
	"GyroGina", "WarheadWalt", "SonicBoomer", "BedlamBen", "PileDriverPam",
	"NuclearNancy", "TungstenTom", "FireSaleFrank", "CircuitBreaker", "ChassisChad",
	"BlastDoorBecky", "CruiseMissile", "IronHorseHenry", "TankBusterTess", "RedlineRuss",
	"DeadeyeDolores", "HollowPointHank", "VolcanoVince", "MaulerMaude", "TriggerHappyTed",
	"ScrapMetalMax", "BigBerthaBev", "AnvilAnnie", "MolotovMo", "CrusherCrowley",
	"RiveterRuby", "ZapperZed", "SteelToeSteph", "BulletSpongeBud", "DynamoDiane",
]

# T335: ELITE bots -- a short list of good gamertags, each a pilot with a fixed build (skill ->
# level 1..12, Game.SKILL_TREE) that comes with the name every match: the upgrades are what make
# Elite > Hard (T282). 12 names cover a full 6v6 of bots.
const ELITE := {
	"Inexorable": {"health": 12, "move_speed": 12, "beacon_capture": 12, "contested_hold": 12},
	"Vantablack": {"damage": 12, "projectile_speed": 12, "spread_reduction": 12, "health": 6},
	"Sable":      {"ability_recharge": 12, "reload_speed": 12, "lock_speed": 12, "damage": 6},
	"Deadlock":   {"damage": 12, "lock_speed": 12, "reload_speed": 10, "health": 6},
	"Bastion":    {"health": 12, "shield_capacity": 12, "repair_rate": 12},
	"Wraith":     {"damage": 10, "move_speed": 12, "ability_recharge": 12},
	"Halcyon":    {"health": 12, "repair_rate": 12, "move_speed": 10},
	"Nocturne":   {"damage": 12, "projectile_speed": 8, "spread_reduction": 12, "reload_speed": 8},
	"Paragon":    {"damage": 8, "health": 8, "move_speed": 8, "reload_speed": 8, "ability_recharge": 8},
	"Tempest":    {"damage": 10, "projectile_speed": 12, "move_speed": 12},
	"Obsidian":   {"health": 12, "shield_capacity": 12, "damage": 8},
	"Corsair":    {"damage": 10, "reload_speed": 12, "ability_recharge": 10},
}

# T350 (HUMAN_FOUND 2026-11-08: "Elites definitely should have preset hangars ... modified AI with
# personality ... a hangar that makes sense with their abilities and playstyles"): each Elite's
# squad -- [mech, weapon family (Lobby.WEAPON_CATALOG prefix)] x 5, every family fitting that mech's
# slots -- and how it fights: role (attacker / flanker / defender), range_k (x its weapon's usual
# fighting distance: < 1 closes in, > 1 holds off), retreat_hp (health share it gives ground at).
# T377 (HUMAN_FOUND 2026-11-09: "Elites should have different hangars based on game mode"): "squad"
# is the beacons hangar, "squad_dm" the death match one (no beacons to rush or hold: brawlers,
# missiles over aerial strikes, Taurus where a pilot rams). Same personality in both.
const ELITE_KIT := {
	"Inexorable": {"squad": [["Hippogriff", "MG"], ["Everest", "MG"], ["Hornet", "SHOTGUN"], ["Vesuvius", "MG"], ["Hippogriff", "SHOTGUN"]],
		"squad_dm": [["Taurus", "SHOTGUN"], ["Everest", "MG"], ["Taurus", "MG"], ["Vesuvius", "SHOTGUN"], ["Hippogriff", "SHOTGUN"]],
		"personality": {"role": "attacker", "range_k": 0.7, "retreat_hp": 0.12}},   # health + speed + capture: rushes beacons
	"Vantablack": {"squad": [["Slip", "SNIPER"], ["Seeker", "SNIPER"], ["Hornet", "SNIPER"], ["Slip", "SNIPER"], ["Seeker", "SNIPER"]],
		"squad_dm": [["Slip", "SNIPER"], ["Seeker", "SNIPER"], ["Hornet", "SNIPER"], ["Kestrel", "SNIPER"], ["Seeker", "SNIPER"]],
		"personality": {"role": "attacker", "range_k": 1.8, "retreat_hp": 0.4}},    # damage + accuracy: holds range
	"Sable":      {"squad": [["Cesh", "ROCKET"], ["Pegasus", "ARC"], ["Cesh", "ARC"], ["Pegasus", "ROCKET"], ["Kestrel", "ROCKET"]],
		"squad_dm": [["Cesh", "ROCKET"], ["Pegasus", "ARC"], ["Cesh", "MISSILE"], ["Hornet", "ROCKET"], ["Pegasus", "MISSILE"]],
		"personality": {"role": "flanker", "range_k": 1.2, "retreat_hp": 0.3}},     # abilities + lock speed: locks from the side
	"Deadlock":   {"squad": [["Vesuvius", "AERIAL"], ["Hippogriff", "MISSILE"], ["Everest", "AERIAL"], ["Kestrel", "ARC"], ["Seeker", "AERIAL"]],
		"squad_dm": [["Hippogriff", "MISSILE"], ["Vesuvius", "MISSILE"], ["Kestrel", "MISSILE"], ["Everest", "AERIAL"], ["Hornet", "MISSILE"]],
		"personality": {"role": "attacker", "range_k": 1.3, "retreat_hp": 0.3}},    # lock weapons
	"Bastion":    {"squad": [["Kestrel", "LASER"], ["Everest", "LASER"], ["Kestrel", "RIFLE"], ["Everest", "MG"], ["Kestrel", "LASER"]],
		"squad_dm": [["Kestrel", "LASER"], ["Everest", "LASER"], ["Kestrel", "MG"], ["Vesuvius", "LASER"], ["Kestrel", "RIFLE"]],
		"personality": {"role": "defender", "range_k": 1.0, "retreat_hp": 0.15}},   # shields + repair: holds what it has
	"Wraith":     {"squad": [["Cesh", "SHOTGUN"], ["Slip", "SHOTGUN"], ["Cesh", "SHOTGUN"], ["Hornet", "SHOTGUN"], ["Cesh", "MG"]],
		"squad_dm": [["Cesh", "SHOTGUN"], ["Slip", "SHOTGUN"], ["Cesh", "SHOTGUN"], ["Taurus", "SHOTGUN"], ["Cesh", "MG"]],
		"personality": {"role": "flanker", "range_k": 0.6, "retreat_hp": 0.25}},    # speed + stealth: ambushes up close
	"Halcyon":    {"squad": [["Pegasus", "RIFLE"], ["Pegasus", "LASER"], ["Hornet", "RIFLE"], ["Pegasus", "RIFLE"], ["Hippogriff", "RIFLE"]],
		"squad_dm": [["Pegasus", "RIFLE"], ["Pegasus", "LASER"], ["Pegasus", "MG"], ["Hornet", "RIFLE"], ["Hippogriff", "LASER"]],
		"personality": {"role": "attacker", "range_k": 1.0, "retreat_hp": 0.45}},   # repair + jump heal: steps out to heal
	"Nocturne":   {"squad": [["Seeker", "SNIPER"], ["Slip", "RIFLE"], ["Seeker", "SNIPER"], ["Hornet", "SNIPER"], ["Slip", "SNIPER"]],
		"squad_dm": [["Seeker", "SNIPER"], ["Slip", "SNIPER"], ["Cesh", "SNIPER"], ["Seeker", "SNIPER"], ["Hornet", "SNIPER"]],
		"personality": {"role": "flanker", "range_k": 1.6, "retreat_hp": 0.35}},    # a sniper on the flank
	"Paragon":    {"squad": [["Pegasus", "RIFLE"], ["Hippogriff", "MISSILE"], ["Hornet", "MG"], ["Kestrel", "LASER"], ["Vesuvius", "RIFLE"]],
		"squad_dm": [["Pegasus", "RIFLE"], ["Hippogriff", "MISSILE"], ["Taurus", "SHOTGUN"], ["Kestrel", "LASER"], ["Vesuvius", "RIFLE"]],
		"personality": {"role": "attacker", "range_k": 1.0, "retreat_hp": 0.3}},    # all-rounder
	"Tempest":    {"squad": [["Slip", "MG"], ["Seeker", "RIFLE"], ["Slip", "RIFLE"], ["Hornet", "MG"], ["Slip", "MG"]],
		"squad_dm": [["Slip", "MG"], ["Seeker", "MG"], ["Slip", "RIFLE"], ["Hornet", "MG"], ["Cesh", "MG"]],
		"personality": {"role": "flanker", "range_k": 0.9, "retreat_hp": 0.3}},     # fast, fast shots
	"Obsidian":   {"squad": [["Everest", "PATIENCE"], ["Vesuvius", "MG"], ["Everest", "MG"], ["Vesuvius", "PATIENCE"], ["Kestrel", "MG"]],
		"squad_dm": [["Everest", "PATIENCE"], ["Vesuvius", "MG"], ["Taurus", "MG"], ["Vesuvius", "PATIENCE"], ["Everest", "MG"]],
		"personality": {"role": "defender", "range_k": 1.1, "retreat_hp": 0.12}},   # a wall that hits hard
	"Corsair":    {"squad": [["Hippogriff", "MISSILE"], ["Pegasus", "SHOTGUN"], ["Hippogriff", "MG"], ["Hornet", "MISSILE"], ["Pegasus", "MG"]],
		"squad_dm": [["Hippogriff", "MISSILE"], ["Pegasus", "SHOTGUN"], ["Taurus", "SHOTGUN"], ["Hornet", "MISSILE"], ["Pegasus", "MG"]],
		"personality": {"role": "attacker", "range_k": 0.9, "retreat_hp": 0.3}},    # reloads fast, presses
}

static var _deck: Array = []
static var _elite_deck: Array = []

## Next callsign; `taken` = names already in this roster (a fresh reshuffle can't repeat them).
static func next_name(taken: Array = [], elite := false) -> String:
	var deck: Array = _elite_deck if elite else _deck
	if deck.is_empty():
		deck.append_array(ELITE.keys() if elite else NAMES)
		deck.shuffle()
	for i in deck.size():
		if not taken.has(deck[i]):
			return deck.pop_at(i)
	return deck.pop_back()
