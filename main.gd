extends Node2D

# ============================================================
#  UFO! – Magnavox Odyssey 2 clone  (paste into a Node2D)
#  Godot 4.x  –  single script, no assets needed
# ============================================================

# 4/4/2026 Created Game using Claude. Created Sound using FL Studio, Next steps, editing shapes and adding in sounds

var W: float
var H: float

# --- tunables ---
const SHIP_SPEED       := 200.0
const BULLET_SPEED     := 400.0
const SHIELD_RECHARGE  := 3.0      # seconds after firing
const SAT_SPEED        := 60.0
const HK_SPEED         := 90.0
const UFO_SPEED        := 130.0
const UFO_MISSILE_SPD  := 220.0
const SPAWN_INTERVAL   := 3.5
const MAX_ENEMIES      := 14

# --- colours (retro palette) ---
const C_BG     := Color(0.04, 0.04, 0.12)
const C_SHIP   := Color(0.2,  0.9,  0.3)
const C_SHIELD := Color(0.2,  0.5,  1.0, 0.85)
const C_BULLET := Color(1.0,  1.0,  0.4)
const C_SAT    := Color(0.7,  0.7,  0.7)
const C_HK     := Color(0.0,  1.0,  1.0)
const C_UFO    := Color(0.8,  0.2,  1.0)
const C_MISS   := Color(1.0,  0.2,  0.2)
const C_EXPL   := Color(1.0,  0.7,  0.1)
const C_TEXT   := Color(0.9,  0.95, 1.0)

# --- entity dictionaries stored in arrays ---
var ship       := {}
var bullets    := []
var enemies    := []   # {type, pos, vel, r, alive, flash}
var missiles   := []   # fired by UFO starships
var explosions := []   # {pos, life, r}

var score      := 0
var hi_score   := 0
var game_over  := false
var spawn_t    := 0.0
var ufo_fire_t := 0.0

var shield_was_down: bool = false
# ============================================================
func _ready() -> void:
	print("sartup")
	W = get_viewport().get_visible_rect().size.x
	H = get_viewport().get_visible_rect().size.y
	_reset_game()

func _reset_game() -> void:
	ship = {
		pos   = Vector2(W * 0.5, H * 0.5),
		vel   = Vector2.ZERO,
		angle = 0.0,          # aim dot angle (radians, around ship)
		shield_t = 0.0,       # countdown; 0 = shield UP
		alive = true,
		death_t = 0.0         # sparkling death timer
	}
	bullets.clear()
	enemies.clear()
	missiles.clear()
	explosions.clear()
	score      = 0
	game_over  = false
	spawn_t    = 1.5
	ufo_fire_t = 5.0
	# seed the field with satellites
	for i in 6:
		_spawn_satellite()

# ============================================================
func _process(delta: float) -> void:
	print("proceassa")
	if game_over:
		if Input.is_action_just_pressed("ui_accept"):
			hi_score = max(hi_score, score)
			_reset_game()
		queue_redraw()
		return

	_update_ship(delta)
	_update_bullets(delta)
	_update_enemies(delta)
	_update_missiles(delta)
	_update_explosions(delta)
	_check_collisions()
	_auto_spawn(delta)
	queue_redraw()

# ============================================================
#  SHIP
# ============================================================
func _update_ship(delta: float) -> void:
	if not ship.alive:
		ship.death_t -= delta
		var shield_now_up: bool = (ship.shield_t as float) <= 0.0
		if shield_now_up and shield_was_down:
			_play_sound("ShieldRecharge")
		shield_was_down = not shield_now_up
		if ship.death_t <= 0.0:
			game_over = true
			hi_score = max(hi_score, score)
		return

	# movement
	
	var dir := Vector2.ZERO
	if Input.is_action_pressed("ui_right"): dir.x += 1
	if Input.is_action_pressed("ui_left"):  dir.x -= 1
	if Input.is_action_pressed("ui_down"):  dir.y += 1
	if Input.is_action_pressed("ui_up"):    dir.y -= 1

	if dir.length_squared() > 0.0:
		ship.vel = dir.normalized() * SHIP_SPEED
		# aim dot rotates toward movement direction
		var target_angle := dir.angle()
		var diff := wrapf(target_angle - ship.angle, -PI, PI)
		ship.angle += diff * min(delta * 6.0, 1.0)
	else:
		ship.vel = ship.vel.lerp(Vector2.ZERO, delta * 4.0)

	ship.pos += ship.vel * delta
	ship.pos.x = wrapf(ship.pos.x, 0, W)
	ship.pos.y = wrapf(ship.pos.y, 0, H)

	# shield recharge
	if ship.shield_t > 0.0:
		ship.shield_t -= delta

	# fire
	if Input.is_action_just_pressed("ui_accept") and ship.shield_t <= 0.0:
		_fire_bullet()

# ============================================================
func _fire_bullet() -> void:
	ship.shield_t = SHIELD_RECHARGE   # shield drops on fire
	_play_sound("SheildDown")
	var dir: Vector2 = Vector2(cos(ship.angle as float), sin(ship.angle as float))
	bullets.append({
		pos  = ship.pos + (dir * 22.0),
		vel  = dir * BULLET_SPEED,
		life = 1.2
	})
	_play_sound("Shoot2")
	
# ============================================================
#  BULLETS
# ============================================================
func _update_bullets(delta: float) -> void:
	for b in bullets:
		b.pos += b.vel * delta
		b.pos.x = wrapf(b.pos.x, 0, W)
		b.pos.y = wrapf(b.pos.y, 0, H)
		b.life -= delta
	bullets = bullets.filter(func(b): return b.life > 0.0)

# ============================================================
#  ENEMIES
# ============================================================
func _auto_spawn(delta: float) -> void:
	spawn_t -= delta
	if spawn_t <= 0.0 and enemies.size() < MAX_ENEMIES:
		spawn_t = SPAWN_INTERVAL
		var r := randf()
		if   r < 0.55: _spawn_satellite()
		elif r < 0.82: _spawn_hunter_killer()
		else:          _spawn_ufo_starship()

func _spawn_satellite() -> void:
	var edge := _random_edge()
	var vel  := Vector2(randf_range(-1,1), randf_range(-1,1)).normalized() * SAT_SPEED
	enemies.append({type="sat", pos=edge, vel=vel, r=10.0, alive=true, flash=0.0})

func _spawn_hunter_killer() -> void:
	var edge := _random_edge()
	enemies.append({type="hk", pos=edge, vel=Vector2.ZERO, r=9.0, alive=true, flash=0.0})

func _spawn_ufo_starship() -> void:
	var edge := _random_edge()
	enemies.append({type="ufo", pos=edge, vel=Vector2.ZERO, r=12.0, alive=true, flash=0.0})
	_play_sound("Alarm")
	
func _random_edge() -> Vector2:
	match randi() % 4:
		0: return Vector2(randf_range(0, W), 0)
		1: return Vector2(randf_range(0, W), H)
		2: return Vector2(0, randf_range(0, H))
		_: return Vector2(W, randf_range(0, H))

func _update_enemies(delta: float) -> void:
	ufo_fire_t -= delta

	for e in enemies:
		if not e.alive: continue
		e.flash = max(0.0, e.flash - delta)

		match e.type:
			"sat":
				# gentle random drift + circular wobble
				e.pos += (e.vel as Vector2) * delta
			"hk":
				# home in on player
				var to_ship: Vector2 = Vector2(ship.pos) - Vector2(e.pos)
				if to_ship.length() > 1.0:
					e.vel = (e.vel as Vector2).lerp(to_ship.normalized() * HK_SPEED, delta * 1.5)
				e.pos += (e.vel as Vector2) * delta
			"ufo":
				# arc toward player slowly
				var to_ship: Vector2 = Vector2(ship.pos) - Vector2(e.pos)
				if to_ship.length() > 1.0:
					e.vel = (e.vel as Vector2).lerp(to_ship.normalized() * UFO_SPEED, delta * 0.8)
				e.pos += (e.vel as Vector2) * delta
				# fire missile periodically
				if ufo_fire_t <= 0.0 and ship.alive:
					ufo_fire_t = randf_range(3.0, 5.5)
					var mdir: Vector2 = (Vector2(ship.pos) - Vector2(e.pos)).normalized()
					var epos: Vector2 = e.pos
					missiles.append({pos=epos, vel=mdir * UFO_MISSILE_SPD, life=3.0})
					_play_sound("EnemyLaser")
		# wrap
		e.pos.x = wrapf(e.pos.x, 0, W)
		e.pos.y = wrapf(e.pos.y, 0, H)

	enemies = enemies.filter(func(e): return e.alive)

# ============================================================
#  MISSILES
# ============================================================
func _update_missiles(delta: float) -> void:
	for m in missiles:
		m.pos += m.vel * delta
		m.pos.x = wrapf(m.pos.x, 0, W)
		m.pos.y = wrapf(m.pos.y, 0, H)
		m.life -= delta
	missiles = missiles.filter(func(m): return m.life > 0.0)

# ============================================================
#  EXPLOSIONS
# ============================================================
func _update_explosions(delta: float) -> void:
	for ex in explosions:
		ex.life -= delta
		ex.r    += delta * 60.0
	explosions = explosions.filter(func(ex): return ex.life > 0.0)

func _explode(pos: Vector2, sz: float = 18.0) -> void:
	explosions.append({pos=Vector2(pos.x, pos.y), life=0.45, r=sz})
	_play_sound("ExplosionSmall")

# ============================================================
#  COLLISION
# ============================================================
func _check_collisions() -> void:
	# bullets vs enemies
	for b in bullets:
		for e in enemies:
			if not e.alive: continue
			if b.pos.distance_to(e.pos) < e.r + 5.0:
				e.alive = false
				if e.type == "ufo":
					print("UFO hit! playing Bomb")
					_play_sound("Bomb")
				b.life  = 0.0
				_explode(e.pos, e.r * 1.5)
				score += ({"sat":10, "hk":25, "ufo":50}.get(e.type, 10))
				# chain reaction: nearby enemies get flashed / destroyed
				for e2 in enemies:
					if e2.alive and e2.pos.distance_to(e.pos) < 48.0:
						e2.alive = false
						_explode(e2.pos, e2.r)
						score += ({"sat":5, "hk":12, "ufo":25}.get(e2.type, 5))
				break

	if not ship.alive: return

	var shield_up: bool = ship.shield_t <= 0.0
	var ship_r: float   = 14.0

	# enemies vs ship
	for e in enemies:
		if not e.alive: continue
		var d: float = (ship.pos as Vector2).distance_to(e.pos)
		if d < ship_r + (e.r as float):
			e.alive = false
			_explode(e.pos, e.r)
			if shield_up:
				score += ({"sat":10, "hk":25, "ufo":50}.get(e.type, 10))
				ship.shield_t = SHIELD_RECHARGE
				_play_sound("SheildDown")
			else:
				# shield absorbs one hit, goes down
				_kill_ship()

	# missiles vs ship
	for m in missiles:
		if (ship.pos as Vector2).distance_to(m.pos) < ship_r + 5.0:
			m.life = 0.0
			_explode(m.pos, 14.0)
			if shield_up:
				ship.shield_t = SHIELD_RECHARGE
			else:
				_kill_ship()

func _kill_ship() -> void:
	ship.alive  = false
	ship.death_t = 1.8
	_explode(ship.pos, 30.0)
	_play_sound("GameOver")
	
# ============================================================
#  DRAW
# ============================================================
func _draw() -> void:
	# background
	draw_rect(Rect2(0, 0, W, H), C_BG)

	# starfield (deterministic, cheap)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for i in 80:
		var sx := rng.randf_range(0, W)
		var sy := rng.randf_range(0, H)
		var bright := rng.randf_range(0.3, 0.9)
		draw_circle(Vector2(sx, sy), 1.0, Color(bright, bright, bright, 0.6))

	# explosions
	for ex in explosions:
		var a: float = ex.life / 0.45
		draw_circle(ex.pos, ex.r, Color(C_EXPL.r, C_EXPL.g * a, 0.0, a * 0.8))
		draw_circle(ex.pos, ex.r * 0.5, Color(1, 1, 0.8, a))

	# enemies
	for e in enemies:
		if not e.alive: continue
		var c: Color
		match e.type:
			"sat": c = C_SAT
			"hk":  c = C_HK
			"ufo": c = C_UFO
			_:     c = Color.WHITE
		_draw_enemy(e, c)

	# missiles
	for m in missiles:
		draw_circle(m.pos, 4.0, C_MISS)
		draw_line(m.pos, m.pos - m.vel.normalized() * 12.0, Color(C_MISS, 0.5), 2.0)

	# bullets
	for b in bullets:
		draw_circle(b.pos, 4.5, C_BULLET)
		draw_line(b.pos, b.pos - b.vel.normalized() * 10.0, Color(C_BULLET, 0.5), 2.0)

	# ship
	if ship.alive or fmod(ship.death_t, 0.12) > 0.06:
		_draw_ship()

	# HUD
	_draw_hud()

	if game_over:
		_draw_game_over()

# ----
func _draw_enemy(e: Dictionary, c: Color) -> void:
	var p: Vector2 = e.pos
	match e.type:
		"sat":
			# rotating plus/x trick (like the original)
			var t: float = Time.get_ticks_msec() * 0.003
			var a: float = fmod(t + (p.x as float) * 0.01, PI * 0.5)
			for i in 4:
				var ang: float = a + i * PI * 0.5
				var tip: Vector2 = p + Vector2(cos(ang), sin(ang)) * (e.r as float)
				draw_line(p, tip, c, 2.0)
		"hk":
			# X with circle (like original)
			for i in 2:
				var ang := PI * 0.25 + i * PI * 0.5
				draw_line(p + Vector2(cos(ang), sin(ang)) * e.r,
						  p + Vector2(cos(ang + PI), sin(ang + PI)) * e.r, c, 2.0)
			draw_arc(p, e.r, 0, TAU, 12, c, 1.5)
		"ufo":
			# classic saucer silhouette
			draw_arc(p, e.r, 0, TAU, 20, c, 2.0)
			draw_arc(p, e.r * 0.5, PI, TAU, 12, c, 2.0)
			draw_circle(p, 3.0, c)

func _draw_ship() -> void:
	var p: Vector2 = ship.pos
	# death flash colour
	var sc := C_SHIP
	if not ship.alive:
		var frac := fmod(ship.death_t * 8.0, 2.0)
		sc = C_EXPL if frac > 1.0 else Color(1, 0.2, 0.2)

	# body triangle
	var pts := PackedVector2Array()
	var nose  := -PI / 2.0
	var right := nose + deg_to_rad(55.0)
	var left  := nose - deg_to_rad(55.0)
	pts.append(p + Vector2(cos(nose),  sin(nose))  * 20.0)  # pointy front
	pts.append(p + Vector2(cos(right), sin(right)) * 12.0)  # right wing
	pts.append(p + Vector2(cos(left),  sin(left))  * 12.0)  # left wing

	draw_polygon(pts, [Color(sc, 0.3), Color(sc, 0.3), Color(sc, 0.3)])
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), sc, 2.0)
	
	# shield ring
	if ship.alive:
		var shield_up: bool = (ship.shield_t as float) <= 0.0
		var sa: float = 0.55 if shield_up else 0.15
		draw_arc(p, 20.0, 0, TAU, 32, Color(C_SHIELD, sa), 2.5)
		var dot_pos: Vector2 = p + Vector2(cos(ship.angle as float), sin(ship.angle as float)) * 20.0
		var dc: Color = Color(1, 1, 1, 0.9) if shield_up else Color(1, 0.5, 0.5, 0.5)
		draw_circle(dot_pos, 4.0, dc)

func _draw_hud() -> void:
	# simple pixel-style score bars at top
	var score_str := "SCORE  %05d" % score
	var hi_str    := "BEST   %05d" % hi_score
	draw_string(ThemeDB.fallback_font, Vector2(12, 22), score_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, C_TEXT)
	draw_string(ThemeDB.fallback_font, Vector2(W - 160, 22), hi_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, C_TEXT)

	# shield indicator
	if ship.alive:
		var shield_up: bool = ship.shield_t <= 0.0
		var label: String = "SHIELD: ACTIVE" if shield_up else "SHIELD: RECHARGING"
		var col: Color    = Color(0.3, 0.8, 1.0) if shield_up else Color(1.0, 0.4, 0.2)
		draw_string(ThemeDB.fallback_font, Vector2(W * 0.5 - 70, 22), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)

func _draw_game_over() -> void:
	draw_rect(Rect2(W*0.25, H*0.35, W*0.5, H*0.3), Color(0,0,0,0.75))
	draw_string(ThemeDB.fallback_font, Vector2(W*0.5 - 65, H*0.48), "GAME OVER", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, C_EXPL)
	draw_string(ThemeDB.fallback_font, Vector2(W*0.5 - 90, H*0.57), "SCORE: %d" % score, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, C_TEXT)
	draw_string(ThemeDB.fallback_font, Vector2(W*0.5 - 100, H*0.64), "SPACE to play again", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.7,0.7,0.7))
	
# SOUND STUFF

func _play_sound(node_name: String, pitch: float = 1.0) -> void:
	var node := get_node_or_null(node_name)
	if node:
		node.pitch_scale = pitch
		node.play()
