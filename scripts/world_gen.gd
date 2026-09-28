class_name WorldGen
extends RefCounted
# Gera os blocos de um chunk por ruído em camadas: superfície, subterrâneo, cavernas, submundo.

const CHUNK := 16
const HEIGHT := 128
const SIZE_CHUNKS := 16        # mundo finito: 16x16 chunks = 256x256 blocos
const UNDERWORLD_TOP := 20     # abaixo disto: submundo
const CAVERN_TOP := 48         # abaixo disto: camada de cavernas (pedra)
const SURFACE := 76            # altura média da superfície

var height_noise := FastNoiseLite.new()
var rock_noise := FastNoiseLite.new()
var cave_noise := FastNoiseLite.new()
var hell_noise := FastNoiseLite.new()
var AIR := 0
var GRASS: int
var DIRT: int
var STONE: int
var ASH: int
var BEDROCK: int


func _init(seed: int) -> void:
	for n in [height_noise, rock_noise, cave_noise, hell_noise]:
		n.seed = seed
		seed += 1
	height_noise.frequency = 0.008
	height_noise.fractal_octaves = 4
	rock_noise.frequency = 0.06
	cave_noise.frequency = 0.035
	hell_noise.frequency = 0.05
	GRASS = Blocks.ids.grass
	DIRT = Blocks.ids.dirt
	STONE = Blocks.ids.stone
	ASH = Blocks.ids.ash
	BEDROCK = Blocks.ids.bedrock


func surface_height(wx: int, wz: int) -> int:
	return SURFACE + int(height_noise.get_noise_2d(wx, wz) * 14.0)


# ponytail: ~dezenas de ms por chunk em GDScript na thread principal; se travar, mover para WorkerThreadPool.
func generate(cx: int, cz: int) -> PackedByteArray:
	var d := PackedByteArray()
	d.resize(CHUNK * CHUNK * HEIGHT)
	for z in CHUNK:
		for x in CHUNK:
			var wx := cx * CHUNK + x
			var wz := cz * CHUNK + z
			var h := surface_height(wx, wz)
			var hell := hell_noise.get_noise_2d(wx, wz)
			var floor_h := 5 + int(hell * 4.0)
			var ceil_h := UNDERWORLD_TOP - 4 + int(hell * 3.0)
			var i := x + z * CHUNK
			for y in h + 1:
				var b := STONE
				if y == 0:
					b = BEDROCK
				elif y < UNDERWORLD_TOP:
					b = ASH if y < floor_h or y > ceil_h else AIR
				elif y < h - 4 and cave_noise.get_noise_3d(wx, y, wz) > (0.35 if y < CAVERN_TOP else 0.5):
					b = AIR
				elif y == h:
					b = GRASS
				elif y >= CAVERN_TOP:
					b = STONE if rock_noise.get_noise_3d(wx, y, wz) > 0.35 else DIRT
				elif rock_noise.get_noise_3d(wx, y, wz) > 0.55:
					b = DIRT
				d[i + y * CHUNK * CHUNK] = b
	return d
