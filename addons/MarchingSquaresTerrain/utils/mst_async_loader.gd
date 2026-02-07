## Orchestrates async chunk loading across multiple frames.
## Drives chunks through phases: IDLE → CELLS_GENERATING → MESH_COMMIT → GRASS → IDLE
## Created by MarchingSquaresTerrain during _deferred_enter_tree().
extends RefCounted
class_name MSTAsyncLoader

signal chunk_ready(chunk_coords: Vector2i)

enum Phase { IDLE, CELLS_GENERATING, MESH_COMMIT, GRASS }

var grass_rows_per_frame : int = 24

var _queue : Array[MarchingSquaresTerrainChunk] = []
var _phase : Phase = Phase.IDLE
var _active_chunk : MarchingSquaresTerrainChunk = null
var _active_pool : MarchingSquaresThreadPool = null
var _cam_pos : Vector3 = Vector3.ZERO
var _grass_row_order : Array[int] = []
var _grass_row_idx : int = 0


func start(p_chunks: Array, cam_pos: Vector3, p_grass_rows_per_frame: int = 8) -> void:
	grass_rows_per_frame = p_grass_rows_per_frame
	_cam_pos = cam_pos
	for chunk in p_chunks:
		_queue.append(chunk)
	_sort_by_distance(cam_pos)


## Called once per frame by terrain._process(). Returns true if still working.
func tick() -> bool:
	match _phase:
		Phase.IDLE:
			if _queue.is_empty():
				return false
			_active_chunk = _queue.pop_front()
			_active_pool = _active_chunk.create_cell_generation_pool()
			_phase = Phase.CELLS_GENERATING

		Phase.CELLS_GENERATING:
			if _active_pool.is_done():
				_active_pool.wait()
				_active_pool = null
				_phase = Phase.MESH_COMMIT

		Phase.MESH_COMMIT:
			_active_chunk.commit_mesh_sync()
			_active_chunk.grass_planter.setup(_active_chunk, true)
			_active_chunk.grass_planter.begin_incremental()
			_grass_row_order = _compute_grass_row_order(_active_chunk)
			_grass_row_idx = 0
			_phase = Phase.GRASS

		Phase.GRASS:
			var total_rows : int = _grass_row_order.size()
			var rows_this_frame : int = mini(grass_rows_per_frame, total_rows - _grass_row_idx)
			for i in range(rows_this_frame):
				_active_chunk.grass_planter.generate_grass_row(
					_grass_row_order[_grass_row_idx])
				_grass_row_idx += 1
			if _grass_row_idx >= total_rows:
				chunk_ready.emit(_active_chunk.chunk_coords)
				_active_chunk = null
				_phase = Phase.IDLE
	return true


func is_chunk_pending(chunk: MarchingSquaresTerrainChunk) -> bool:
	return _queue.has(chunk) or _active_chunk == chunk


## Computes grass row indices sorted by Z-distance to camera (nearest first).
func _compute_grass_row_order(chunk: MarchingSquaresTerrainChunk) -> Array[int]:
	var max_z : int = chunk.terrain_system.dimensions.z - 1
	var order : Array[int] = []
	for z in range(max_z):
		order.append(z)
	var chunk_z : float = chunk.position.z
	var csz : float = chunk.cell_size.y
	var cam_z : float = _cam_pos.z
	order.sort_custom(func(a: int, b: int) -> bool:
		var az : float = chunk_z + (a + 0.5) * csz
		var bz : float = chunk_z + (b + 0.5) * csz
		return abs(az - cam_z) < abs(bz - cam_z)
	)
	return order


func _sort_by_distance(cam_pos: Vector3) -> void:
	_queue.sort_custom(func(a: MarchingSquaresTerrainChunk, b: MarchingSquaresTerrainChunk) -> bool:
		return a.position.distance_squared_to(cam_pos) < b.position.distance_squared_to(cam_pos)
	)
