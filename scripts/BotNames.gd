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

static var _deck: Array = []

## Next callsign; `taken` = names already in this roster (a fresh reshuffle can't repeat them).
static func next_name(taken: Array = []) -> String:
	if _deck.is_empty():
		_deck = NAMES.duplicate()
		_deck.shuffle()
	for i in _deck.size():
		if not taken.has(_deck[i]):
			return _deck.pop_at(i)
	return _deck.pop_back()
