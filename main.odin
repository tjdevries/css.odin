// Different characters: Turret character, Clone character
// Stacking upgrades - passive regen, etc
// 	Skill trees?!?
// Enemy that shoots back
// Barrier
// Gates for modifying bullets as you shoot
// Rock that is moving, can't take damage - doesn't do damage to your base


package main

import sa "core:container/small_array"
import "core:fmt"
import rand "core:math/rand"
import rl "vendor:raylib"

Velocity :: [2]f32

Entity :: struct {
	using body: rl.Rectangle,
	velocity:   Velocity,
	texture:    rl.Texture,
}

entity_tick :: proc(entity: ^Entity) {
	entity.x += entity.velocity.x * GAME_SIZE_SCALE
	entity.y += entity.velocity.y * GAME_SIZE_SCALE
}

entity_draw :: proc(entity: ^Entity) {
	rl.DrawTextureEx(entity.texture, {entity.x, entity.y}, 0, SPRITE_SCALE, rl.WHITE)
}

HEIGHT := 320
WIDTH := 160
MAX_HEALTH :: 100
LANE_WIDTH := WIDTH / len(Lane)

GAME_SIZE_SCALE: f32 = 1.0 // This is to scale things like movement speed of objects, since things are blazingly fast on smaller screens.
// What we should probably do is implement some relative coordinate system that's not based on pixels.

// BLOCK_SIZE is the size in width of a single lane.
// There are 5 lanes, so it's probably WIDTH / 5.
// We can scale the rest of the game according to this
// The width corresponds to 32 pixel art pixels
BLOCK_SIZE: f32 = 32
SPRITE_SCALE: f32 = 3.5

update_window_size :: proc(height: int) {
	HEIGHT = height
	WIDTH = HEIGHT * 9 / 16
	LANE_WIDTH = WIDTH / len(Lane)
	GAME_SIZE_SCALE = f32(WIDTH) / 1080
	SPRITE_SCALE = 3.5 * GAME_SIZE_SCALE
	BLOCK_SIZE = f32(WIDTH) / 5
}

player_texture: rl.Texture2D
player_turn_left_texture: rl.Texture2D
player_turn_right_texture: rl.Texture2D
enemy_texture: rl.Texture2D
road_texture: rl.Texture2D
upgrade_texture: rl.Texture2D
heart_texture: rl.Texture2D

// draw_text just calls rl.DrawText, but it scales the font according to the
// current window size.
draw_text :: proc(text: cstring, pos_x, pos_y: i32, font_size: i32, color: rl.Color) {
	font_size := i32(f32(font_size) * (f32(WIDTH) / 1080))
	rl.DrawText(text, pos_x, pos_y, font_size, rl.WHITE)
}

// measure_text just calls rl.MeasureText, but it scales the font according
// to the current window size. Useful for positioning font.
measure_text :: proc(text: cstring, font_size: i32) -> i32 {
	font_size := i32(f32(font_size) * (f32(WIDTH) / 1080))
	return rl.MeasureText(text, font_size)
}

ROAD_SPEED: f32 = 100
offset: f32 = 0
draw_static :: proc() {
	// Offset increases to make it look like the road is moving
	offset += ROAD_SPEED * GAME_SIZE_SCALE * rl.GetFrameTime()
	if offset > (BLOCK_SIZE) {
		offset -= BLOCK_SIZE
	}


	count: int = (HEIGHT / int(BLOCK_SIZE)) + 1 // Add an extra row for love
	for col := 0; col < 6; col += 1 {
		for i := -1; i < count; i += 1 {
			rl.DrawTexturePro(
				road_texture,
				{x = 0, y = 0, height = 32, width = 32},
				{
					x = f32(col) * BLOCK_SIZE,
					y = (BLOCK_SIZE) * f32(i) + offset,
					height = BLOCK_SIZE,
					width = BLOCK_SIZE,
				},
				{0, 0},
				0,
				rl.BLUE,
			)
		}
	}

	draw_health(game.health)
}

draw_health :: proc(health: f32) {
	rl.DrawRectanglePro(
		{20, BLOCK_SIZE * 0.2, health * SPRITE_SCALE, BLOCK_SIZE * 0.2},
		{0, 0},
		0,
		rl.Color{172, 50, 50, 255},
	)
	rl.DrawRectangleLinesEx(
		{20, BLOCK_SIZE * 0.2, MAX_HEALTH * SPRITE_SCALE, BLOCK_SIZE * 0.2},
		BLOCK_SIZE / 30,
		rl.WHITE,
	)
	rl.DrawTexturePro(
		heart_texture,
		{height = 32, width = 32},
		{-BLOCK_SIZE * 0.25, -BLOCK_SIZE * 0.25, BLOCK_SIZE, BLOCK_SIZE},
		{0, 0},
		0,
		rl.WHITE,
	)
}

// Not @wagslane, but you can check out boot.dev/teej for upcoming C/Memory Management course!
Lane :: enum {
	Left = 0,
	CenterLeft,
	Center,
	CenterRight,
	Right,
}

lane_move :: proc(lane: Lane, distance: i32) -> Lane {
	if distance > 0 {
		return Lane(min(len(Lane), i32(game.desired_lane) + distance))
	} else if distance < 0 {
		return Lane(max(0, i32(game.desired_lane) + distance))
	} else {
		return lane
	}
}

lane_to_x :: proc(lane: Lane) -> f32 {
	return (f32(lane) * 2 + 1) * f32(WIDTH) / 10
}

make_rectangle :: proc(lane: Lane, y, width, height: f32) -> rl.Rectangle {
	center_x := lane_to_x(lane)

	return rl.Rectangle{center_x - width / 2, y, width, height}
}

SplitStatus :: enum {
	Single,
	Split,
}

PlayerTurning :: enum {
	None,
	Left,
	Right,
}

Player :: struct {
	split:    SplitStatus,
	body:     rl.Rectangle,
	// bodies:   [3]Maybe(Body),
	distance: i32,
	frame:    i32,
	turning:  PlayerTurning,
}

count := 0
player_tick :: proc(player: ^Player) {
	if has_status(.Regeneration) {
		count += 1
		fmt.println("regen", count)
		game.health += 10.0 / 60.0
		game.health = min(game.health, MAX_HEALTH)
	}
}

player_intersects_rect :: proc(player: ^Player, rect: rl.Rectangle) -> bool {
	rects := player_rectangles(player)
	for r in sa.slice(&rects) {
		if rl.CheckCollisionRecs(r, rect) {
			return true
		}
	}

	return false
}

player_rectangles :: proc(player: ^Player) -> sa.Small_Array(2, rl.Rectangle) {
	rects: sa.Small_Array(2, rl.Rectangle)

	if player.split == .Single {
		sa.append(&rects, player.body)
	} else {
		left := player.body
		left.x -= lane_to_x(Lane(player.distance)) - f32(LANE_WIDTH) / 2
		if left.x < 0 {
			left.x = lane_to_x(.Left) - player.body.width / 2
		}
		sa.append(&rects, left)

		right := player.body
		right.x += lane_to_x(Lane(player.distance)) - f32(LANE_WIDTH) / 2
		if right.x > f32(WIDTH) {
			right.x = lane_to_x(.Right) - player.body.width / 2
		}
		sa.append(&rects, right)
	}

	return rects
}

PLAYER_FRAME_SPEED := 5 // Every how many frames should the player animation update?
player_draw :: proc(player: ^Player, frame: i32) {
	switch player.turning {
	case .None:
		if int(frame) % PLAYER_FRAME_SPEED == 0 {
			player.frame += 1
		}
		if player.frame > 2 {
			player.frame = 0
		}
		rl.DrawTexturePro(
			player_texture,
			rl.Rectangle{f32(player.frame * 32), 0, 32, 32},
			{player.body.x, player.body.y, BLOCK_SIZE, BLOCK_SIZE},
			{0, 0},
			0,
			rl.WHITE,
		)
	case .Left:
		rl.DrawTexturePro(
			player_turn_left_texture,
			rl.Rectangle{0, 0, 32, 32},
			{player.body.x, player.body.y, BLOCK_SIZE, BLOCK_SIZE},
			{0, 0},
			0,
			rl.WHITE,
		)
	case .Right:
		rl.DrawTexturePro(
			player_turn_right_texture,
			rl.Rectangle{0, 0, 32, 32},
			{player.body.x, player.body.y, BLOCK_SIZE, BLOCK_SIZE},
			{0, 0},
			0,
			rl.WHITE,
		)
	}
}

Status :: enum {
	DoubleBullets,
	DoubleSpeed,
	HomingBullets,

	// Slows enemies down
	SlowingBullets,

	// Regen player health
	Regeneration,
}

StatusEntity :: struct {
	body:     rl.Rectangle,
	status:   bit_set[Status],
	duration: int,
}

status_entity_tick :: proc(status: ^StatusEntity) {
	status.body.y += 10 * GAME_SIZE_SCALE
}

status_entity_draw :: proc(status: ^StatusEntity) {
	rl.DrawTexturePro(
		upgrade_texture,
		{0, 0, 32, 32},
		{status.body.x, status.body.y, BLOCK_SIZE, BLOCK_SIZE},
		{0, 0},
		0,
		rl.WHITE,
	)
}


Enemy :: struct {
	using entity: Entity,
	health:       f32,
}

enemy_make :: proc(body: rl.Rectangle, health: f32, velocity: Velocity) -> Enemy {
	return {body = body, health = health, velocity = velocity, texture = enemy_texture}
}

enemy_tick :: proc(enemy: ^Enemy) -> bool {
	entity_tick(enemy)
	if enemy.y > f32(HEIGHT) {
		game.health -= enemy.health
		return true
	}

	return false
}


enemy_draw :: proc(enemy: ^Enemy) {
	// rl.DrawRectangleRec(enemy.body, rl.RED)
	// rl.DrawTexturePro(
	// 	enemy_texture,
	// 	{0, 0, 32, 32},
	// 	{enemy.body.x, enemy.body.y, BLOCK_SIZE, BLOCK_SIZE},
	// 	{0, 0},
	// 	0,
	// 	rl.WHITE,
	// )
	// rl.DrawRectangleRec(enemy.body, rl.RED)
	// rl.DrawTextureEx(enemy_texture, {enemy.body.x, enemy.body.y}, 0, SPRITE_SCALE, rl.WHITE)

	entity_draw(enemy)
	text := rl.TextFormat("%0.f", enemy.health)
	draw_text(text, cast(i32)enemy.body.x, cast(i32)enemy.body.y, 50, rl.WHITE)
}


get_status_set :: proc() -> bit_set[Status] {
	set: bit_set[Status]
	for status in Status {
		if has_status(status) {
			set |= {status}
		}
	}

	return set
}

Bullet :: struct {
	body:   rl.Rectangle,
	speed:  f32,
	damage: f32,
	status: bit_set[Status],
}

// init_bullet :: proc(bullet: ^Bullet) -> (ok: bool) {}
new_bullet :: proc(pos: [2]f32, max_damage: f32) -> Bullet {
	return Bullet {
		body = {x = pos.x, y = pos.y, height = 4, width = 4},
		damage = max_damage * game.health / MAX_HEALTH,
		speed = 10,
		status = get_status_set(),
	}
}

bullet_tick :: proc(bullet: ^Bullet) {
	if .HomingBullets in bullet.status {
		distance: f32
		destination: rl.Vector2
		bullet_vec: rl.Vector2 = {bullet.body.x, bullet.body.y}
		for &enemy in game.enemies {
			if enemy.body.y - (f32(WIDTH) / 8) > bullet.body.y {
				continue
			}

			enemy_vec: rl.Vector2 = {enemy.body.x, enemy.body.y}
			enemy_dist := rl.Vector2Distance(bullet_vec, enemy_vec)
			if enemy_dist < distance || distance == 0 {
				distance = enemy_dist
				destination = enemy_vec
			}
		}

		if destination.x != 0 || destination.y != 0 {
			updated := rl.Vector2MoveTowards(
				bullet_vec,
				destination,
				bullet.speed * 1.2 * GAME_SIZE_SCALE,
			)
			bullet.body.x = updated.x
			bullet.body.y = updated.y

			return
		}
	}

	bullet.body.y -= bullet.speed * GAME_SIZE_SCALE
}

bullet_process :: proc(bullet: ^Bullet) -> bool {
	// Kill bullets that are out of screen
	if bullet.body.y < 0 {
		return true
	}

	for &enemy in game.enemies {
		if rl.CheckCollisionRecs(bullet.body, enemy.body) {
			enemy.health -= bullet.damage
			if .SlowingBullets in bullet.status {
				enemy.velocity *= 0.8
			}
			return true
		}
	}

	return false
}

draw_bullet :: proc(bullet: ^Bullet) {
	rl.DrawRectangleRec(bullet.body, rl.WHITE)
}


tick_bullets :: proc(frame: i32) {
	bps := i32(10)
	if has_status(.DoubleSpeed) {
		bps /= 2
	}

	if frame % bps == 0 {
		append_bullets(int(frame), &game.player)
	}

	i := 0
	for {
		if i >= len(game.bullets) {
			break
		}

		bullet := &game.bullets[i]
		bullet_tick(bullet)
		if bullet_process(bullet) {
			unordered_remove(&game.bullets, i)
		} else {
			i += 1
			draw_bullet(bullet)
		}

	}

}

append_bullets :: proc(frame: int, player: ^Player) {
	rects := player_rectangles(player)
	bodies := sa.len(rects)

	// randomInt := int(rand.int31())
	for body, index in sa.slice(&rects) {
		// TODO: Think about how this really works
		// if bodies > 1 && index % 2 == (frame + randomInt) % 2 {
		// 	continue
		// }

		bullet_pos := body
		bullet_pos.y -= 5
		bullet_pos.x += player.body.width / 2

		max_damage := 10.0 / f32(bodies)
		if has_status(.DoubleBullets) {
			append(&game.bullets, new_bullet({bullet_pos.x + 5, bullet_pos.y}, max_damage))
			append(&game.bullets, new_bullet({bullet_pos.x - 5, bullet_pos.y}, max_damage))
		} else {
			append(&game.bullets, new_bullet({bullet_pos.x, bullet_pos.y}, max_damage))
		}
	}

}

GameState :: enum {
	Waiting,
	Playing,
	Lost,
	NextLevel,
	Win,
}

Game :: struct {
	state:         GameState,
	health:        f32,
	player:        Player,
	status:        [Status]int,
	enemies:       [dynamic]Enemy,
	bullets:       [dynamic]Bullet,
	statuses:      [dynamic]StatusEntity,

	// The player's desired lane
	desired_lane:  Lane,

	// Levels
	current_level: int,
	levels:        [dynamic]Level,
}

game: Game
// Initializes the game state after the WIDTH and HEIGHT has been set
init_game :: proc() {
	game = Game {
		state = .Playing,
		health = 50,
		player = Player {
			body = {f32(WIDTH) / 2, f32(HEIGHT) - (BLOCK_SIZE * 1.1), BLOCK_SIZE, BLOCK_SIZE},
			distance = 1,
		},
		desired_lane = .Center,
	}
}


status_apply :: proc(status: ^StatusEntity) {
	for s in status.status {
		game.status[s] += status.duration
	}
}

Spawn :: union {
	Enemy,
	StatusEntity,
}

TimedSpawn :: struct {
	frame: i32,
	spawn: Spawn,
}

Level :: struct {
	last_enemy_frame: i32,
	spawns:           [dynamic]TimedSpawn,
}

level_append_spawn :: proc(level: ^Level, timed: TimedSpawn) {
	append(&level.spawns, timed)
	if timed.frame > level.last_enemy_frame {
		level.last_enemy_frame = timed.frame
	}
}

reset_state :: proc() {
	clear(&game.enemies)
	clear(&game.bullets)
}

has_status :: proc(status: Status) -> bool {
	return game.status[status] > 0
}

tick :: proc(frame: i32) -> i32 {
	draw_static()

	player := &game.player
	bullets := &game.bullets
	enemies := &game.enemies
	statuses := &game.statuses

	if game.state == .Waiting {
		MOVE_TEXT :: "Press H or L to move"
		text_width := measure_text(MOVE_TEXT, 80)
		draw_text(
			MOVE_TEXT,
			i32(WIDTH) / 2 - (text_width / 2),
			i32(HEIGHT) / 2 - 100,
			80,
			rl.WHITE,
		)

		BEGIN_TEXT :: "Press enter to begin"
		text_width = measure_text(BEGIN_TEXT, 80)
		draw_text(
			BEGIN_TEXT,
			i32(WIDTH) / 2 - (text_width / 2),
			i32(HEIGHT) / 2 - 100 - 200,
			80,
			rl.WHITE,
		)

		if rl.IsKeyPressed(.ENTER) {
			game.state = .Playing
		}

		return frame
	}

	if game.state == .NextLevel {
		reset_state()

		game.current_level += 1
		if game.current_level >= len(game.levels) {
			game.state = .Win
		} else {
			game.state = .Waiting
		}
		return 0
	}

	if game.state == .Win {
		draw_text("YOU W", i32(WIDTH) / 2 - 250, i32(HEIGHT) / 2 - 100, 200, rl.WHITE)
		return frame + 1
	}

	if game.state == .Lost {
		draw_text("BIG L", i32(WIDTH) / 2 - 250, i32(HEIGHT) / 2 - 100, 200, rl.WHITE)
		return frame + 1
	}

	if rl.IsKeyPressed(.H) || rl.IsKeyPressed(.LEFT) {
		game.desired_lane = lane_move(game.desired_lane, -1)
	}
	if rl.IsKeyPressed(.L) || rl.IsKeyPressed(.RIGHT) {
		game.desired_lane = lane_move(game.desired_lane, 1)
	}

	desired_x := lane_to_x(game.desired_lane) - player.body.width / 2
	TURN_DISTANCE :: 5 // The distance at which a turn is considered complete, even though the sprite might still move a little
	if int(player.body.x) < int(desired_x) - TURN_DISTANCE {
		player.turning = .Left
	} else if int(player.body.x) > int(desired_x) + TURN_DISTANCE {
		player.turning = .Right
	} else {
		player.turning = .None
	}
	if player.body.x != desired_x {
		player.body.x = rl.Lerp(player.body.x, desired_x, 0.2 * GAME_SIZE_SCALE)
	}

	if rl.IsKeyPressed(.K) || rl.IsKeyPressed(.UP) {
		if player.distance < len(Lane) {
			player.distance += 1
		}
	}

	if rl.IsKeyPressed(.J) || rl.IsKeyPressed(.DOWN) {
		if player.distance > 0 {
			player.distance -= 1
		}
	}

	if rl.IsKeyPressed(.SPACE) {
		if player.split == .Single {
			player.split = .Split
		} else {
			player.split = .Single
		}
	}

	rl.BeginDrawing()
	rl.ClearBackground(rl.BLUE)

	player_tick(&game.player)

	level := &game.levels[game.current_level]
	for &spawn in level.spawns {
		if spawn.frame == frame {
			switch value in spawn.spawn {
			case Enemy:
				append(enemies, value)
			case StatusEntity:
				append(statuses, value)
			}
		}

	}

	for s in Status {
		if game.status[s] > 0 {
			game.status[s] -= 1
		}
	}

	tick_bullets(frame)

	{
		i := 0
		for {
			if i >= len(enemies) {
				break
			}

			enemy := &enemies[i]

			pastBounds := enemy_tick(enemy)
			hitPlayer := player_intersects_rect(player, enemy.body)
			if hitPlayer {
				game.health -= enemy.health
			}

			if pastBounds || hitPlayer || enemy.health <= 0 {
				unordered_remove(enemies, i)
			} else {
				enemy_draw(enemy)
				i += 1
			}

		}

		if len(enemies) == 0 && frame > level.last_enemy_frame {
			game.state = .NextLevel
		}
	}

	{
		i := 0
		for {
			if i >= len(statuses) {
				break
			}

			se := &statuses[i]
			status_entity_tick(se)
			if player_intersects_rect(player, se.body) {
				status_apply(se)
				unordered_remove(statuses, i)
				continue
			}

			status_entity_draw(se)
			i += 1
		}

		if len(enemies) == 0 && frame > level.last_enemy_frame {
			game.state = .NextLevel
		}
	}

	if game.health <= 0 {
		game.state = .Lost
		return 0
	}

	player_draw(player, frame)
	return frame + 1
}

main :: proc() {
	rl.SetTargetFPS(60)
	rl.InitWindow(i32(WIDTH), i32(HEIGHT), "Cool Scamming Shooter: CSS for short")

	enemy_texture = rl.LoadTexture("assets/mushroom-enemy.png")
	road_texture = rl.LoadTexture("assets/road_low.png")
	player_texture = rl.LoadTexture("assets/player_sheet.png")
	player_turn_left_texture = rl.LoadTexture("assets/player_turn_left.png")
	player_turn_right_texture = rl.LoadTexture("assets/player_turn_right.png")
	upgrade_texture = rl.LoadTexture("assets/bullet_upgrade.png")
	heart_texture = rl.LoadTexture("assets/heart.png")


	// Initialize window size based on current monitor
	current_monitor := rl.GetCurrentMonitor()
	height := int(f32(rl.GetMonitorHeight(current_monitor)) * 0.9)
	update_window_size(height)

	rl.SetWindowSize(i32(WIDTH), i32(HEIGHT))

	// Could probably make the window resizable as well

	// LOL rotated monitors
	// 3840 x 2160
	// 2160 x 3840
	rl.SetWindowPosition((rl.GetMonitorWidth(current_monitor) - i32(WIDTH)) / 2, 0)

	init_game()

	{
		level := Level{}
		level_append_spawn(
			&level,
			TimedSpawn {
				frame = 0,
				spawn = enemy_make(
					body = make_rectangle(.CenterLeft, 10, BLOCK_SIZE, BLOCK_SIZE),
					health = 100,
					velocity = {0, 5},
				),
			},
		)
		level_append_spawn(
			&level,
			TimedSpawn {
				frame = 1,
				spawn = StatusEntity {
					body     = make_rectangle(.CenterRight, 10, BLOCK_SIZE, BLOCK_SIZE),
					// status = {.DoubleBullets, .DoubleSpeed, .HomingBullets},
					status   = {.Regeneration, .DoubleBullets},
					duration = 5000,
				},
			},
		)
		level_append_spawn(
			&level,
			TimedSpawn {
				frame = 120,
				spawn = enemy_make(
					body = make_rectangle(.Left, 10, BLOCK_SIZE, BLOCK_SIZE),
					health = 100,
					velocity = {0, 10},
				),
			},
		)

		append(&game.levels, level)
	}

	{
		level := Level{}
		level_append_spawn(
			&level,
			TimedSpawn {
				frame = 0,
				spawn = enemy_make(
					body = make_rectangle(.Left, 10, BLOCK_SIZE, BLOCK_SIZE),
					health = 100,
					velocity = {0, 10},
				),
			},
		)
		level_append_spawn(
			&level,
			TimedSpawn {
				frame = 120,
				spawn = enemy_make(
					body = make_rectangle(.Center, 10, BLOCK_SIZE, BLOCK_SIZE),
					health = 100,
					velocity = {0, 20},
				),
			},
		)

		append(&game.levels, level)
	}

	frame: i32 = 0
	for !rl.WindowShouldClose() {
		rl.BeginDrawing()


		frame = tick(frame)

		rl.EndDrawing()
	}

	rl.CloseWindow()
}
