class_name WashTool
extends RefCounted
## How a tool washes glass. Illustrative values from the PRD: bare hands have
## speed 1 and finish 1, a cotton cloth speed 2 and finish 3.

## Name shown to the player.
var name := ""
## Multiplies how fast the tool takes dirt off.
var rub_speed := 1.0
## Radius of the area it rubs, in meters.
var radius := 0.09
## Film it always leaves behind (lower is a better finish).
var residue := 0.08
## How much dirtier it gets per unit of dirt it takes off the glass.
var pickup := 0.1
## Dirt it picks up just by rubbing over dirt, per meter (also scaled by pickup).
var contact_pickup := 0.05
## Dirt a fully dirty tool smears back on per meter of rubbing.
var deposit := 0.3
## Seconds it takes to dry in the air.
var dry_seconds := 10.0
## Share of its water given to dry glass per meter of rubbing.
var water_per_meter := 0.3
## Gap between the hand's palm and the glass while rubbing, in meters.
var palm_gap := 0.018


static func bare_hands() -> WashTool:
	var tool := WashTool.new()
	tool.name = "mains nues"
	return tool


static func cloth() -> WashTool:
	var tool := WashTool.new()
	tool.name = "chiffon"
	tool.rub_speed = 2.0
	tool.radius = 0.11
	tool.residue = 0.08 / 3.0
	tool.pickup = 0.04
	tool.contact_pickup = 0.02
	tool.deposit = 0.25
	tool.dry_seconds = 20.0
	tool.water_per_meter = 0.15
	tool.palm_gap = 0.03
	return tool
