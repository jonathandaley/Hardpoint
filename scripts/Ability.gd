class_name Ability
extends Resource

const TRIGGER_ACTIVE: int = 0
const TRIGGER_PASSIVE: int = 1

@export var ability_name: String = ""
@export var trigger: int = TRIGGER_ACTIVE
@export var effect_key: String = ""
@export var duration: float = 0.0
@export var cooldown: float = 0.0
## T454 (user 2026-11-17: "two charges ... The charges should recharge sequentially, but the first
## should recharge as soon as it's spent and not wait for the second"): uses stored; one recharges
## at a time (`cooldown` each), starting the moment one is spent, the next straight after.
## ponytail: instant abilities only (a duration ability's cooldown starts in _deactivate_ability).
@export var charges: int = 1
## T454: how much of the pilot's ABILITY RECHARGE skill applies (DASH 0.25: max -15%, so a fully
## skilled Swift stays slower than a fully skilled Slip over distance; user: "slower than slip").
@export var recharge_skill_k: float = 1.0
