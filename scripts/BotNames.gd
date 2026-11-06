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
