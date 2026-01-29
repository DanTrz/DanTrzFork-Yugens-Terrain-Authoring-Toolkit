@tool
extends MultiMeshInstance3D
class_name GrassPlanter


var _chunk : MarchingSquaresTerrainChunk
var terrain_system : MarchingSquaresTerrain
var _rng : RandomNumberGenerator

# Progressive loading state
var _pending_cells : Array[Vector2i] = []
var _is_loading_progressively : bool = false
var _cells_per_frame : int = 64  # Process 32 cells per frame
var _grass_generated : bool = false  # True only after grass transforms are actually set

# Threading state for parallel grass generation
var _thread_results : Array = []  # Array of Dictionaries with {index, transform, color}
var _results_mutex :Mutex= Mutex.new()
var _pending_thread_tasks : int = 0
var _cached_images : Array = []  # Pre-cached texture images
var _apply_batch_size : int = 512  # Apply 512 grass instances per frame to MultiMesh
var _use_threading : bool = true  # Enable/disable threaded generation

# Pre-computed thread-safe data (avoid accessing terrain_system in threads)
var _ts_grass_subdivisions : int = 3
var _ts_cell_size : Vector2 = Vector2(2, 2)
var _ts_dimensions : Vector3i = Vector3i(33, 32, 33)
var _ts_ledge_threshold : float = 0.1
var _ts_ridge_threshold : float = 0.1
var _ts_tex_has_grass : Array[bool] = [true, false, false, false, false, false]  # [tex1..6]
var _ts_texture_scales : Array[float] = [1.0, 1.0, 1.0, 1.0, 1.0, 1.0]  # [tex1..6]
var _ts_has_tex : Array[bool] = [false, false, false, false, false, false]  # [tex1..6] has shader param


func _ready() -> void:
	set_process(false)  # Disabled by default


func setup(chunk: MarchingSquaresTerrainChunk, redo: bool = true):
	_chunk = chunk
	terrain_system = _chunk.terrain_system
	
	if not _chunk or not terrain_system:
		printerr("ERROR: SETUP FAILED - no chunk or terrain system found for GrassPlanter")
		return
	
	if (redo and multimesh) or !multimesh:
		multimesh = MultiMesh.new()
		_grass_generated = false  # Reset flag when creating new multimesh
	multimesh.instance_count = 0
	
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.instance_count = (_chunk.dimensions.x-1) * (_chunk.dimensions.z-1) * terrain_system.grass_subdivisions * terrain_system.grass_subdivisions
	if terrain_system.grass_mesh:
		multimesh.mesh = terrain_system.grass_mesh
	else:
		multimesh.mesh = QuadMesh.new() # Create a temporary quad
	multimesh.mesh.size = terrain_system.grass_size
	
	cast_shadow = SHADOW_CASTING_SETTING_OFF


## Uses WorkerThreadPool for parallel computation when _use_threading is enabled
func start_progressive_regeneration() -> void:
	if _is_loading_progressively:
		return

	# Use threaded version if enabled but not in editor
	if _use_threading and not Engine.is_editor_hint():
		print("[Grass] Chunk ", _chunk.chunk_coords if _chunk else "?", " using THREADED mode")
		_threaded_mode = true
		start_progressive_regeneration_threaded()
		return

	# Non-threaded fallback
	print("[Grass] Chunk ", _chunk.chunk_coords if _chunk else "?", " using SINGLE-THREAD mode")
	_threaded_mode = false

	# Safety checks
	if not _chunk or not terrain_system:
		printerr("ERROR: GrassPlanter not set up for progressive regeneration")
		return

	if not multimesh:
		setup(_chunk)

	# cell_geometry is populated during regenerate_mesh() - if empty, we need to regenerate
	if _chunk.cell_geometry.is_empty():
		_chunk.regenerate_mesh()

	# Queue all cells
	_pending_cells.clear()
	for z in range(terrain_system.dimensions.z - 1):
		for x in range(terrain_system.dimensions.x - 1):
			_pending_cells.append(Vector2i(x, z))

	# Sort cells by distance from camera (nearest first) for better visual experience
	_sort_cells_by_camera_distance()

	_is_loading_progressively = true
	set_process(true)


## Sort pending cells by distance from camera (nearest first)
## This ensures grass appears first where the player is looking
func _sort_cells_by_camera_distance() -> void:
	var camera := _chunk.get_viewport().get_camera_3d() if _chunk else null
	if not camera:
		return  # Keep default order if no camera

	var camera_pos := camera.global_position
	var chunk_origin := _chunk.global_position
	var cell_size := terrain_system.cell_size

	# Sort by squared distance (faster than sqrt)
	_pending_cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var pos_a := chunk_origin + Vector3(a.x * cell_size.x, 0, a.y * cell_size.y)
		var pos_b := chunk_origin + Vector3(b.x * cell_size.x, 0, b.y * cell_size.y)
		return pos_a.distance_squared_to(camera_pos) < pos_b.distance_squared_to(camera_pos)
	)


## Cache terrain system properties for thread-safe access
func _cache_thread_safe_data() -> void:
	if not terrain_system:
		return
	_ts_grass_subdivisions = terrain_system.grass_subdivisions
	_ts_cell_size = terrain_system.cell_size
	_ts_dimensions = terrain_system.dimensions
	_ts_ledge_threshold = terrain_system.ledge_threshold
	_ts_ridge_threshold = terrain_system.ridge_threshold

	# Cache has_grass flags for textures 2-6
	_ts_tex_has_grass[0] = true  # Base grass always has grass
	_ts_tex_has_grass[1] = terrain_system.tex2_has_grass
	_ts_tex_has_grass[2] = terrain_system.tex3_has_grass
	_ts_tex_has_grass[3] = terrain_system.tex4_has_grass
	_ts_tex_has_grass[4] = terrain_system.tex5_has_grass
	_ts_tex_has_grass[5] = terrain_system.tex6_has_grass

	# Cache texture scales
	_ts_texture_scales[0] = terrain_system.texture_scale_1
	_ts_texture_scales[1] = terrain_system.texture_scale_2
	_ts_texture_scales[2] = terrain_system.texture_scale_3
	_ts_texture_scales[3] = terrain_system.texture_scale_4
	_ts_texture_scales[4] = terrain_system.texture_scale_5
	_ts_texture_scales[5] = terrain_system.texture_scale_6

	# Cache whether textures exist in shader
	var material = terrain_system.terrain_material
	if material:
		_ts_has_tex[0] = material.get_shader_parameter("vc_tex_rr") != null
		_ts_has_tex[1] = material.get_shader_parameter("vc_tex_rg") != null
		_ts_has_tex[2] = material.get_shader_parameter("vc_tex_rb") != null
		_ts_has_tex[3] = material.get_shader_parameter("vc_tex_ra") != null
		_ts_has_tex[4] = material.get_shader_parameter("vc_tex_gr") != null
		_ts_has_tex[5] = material.get_shader_parameter("vc_tex_gg") != null


## Start threaded progressive grass regeneration using WorkerThreadPool
func start_progressive_regeneration_threaded() -> void:
	if _is_loading_progressively:
		return

	# Safety checks
	if not _chunk or not terrain_system:
		printerr("ERROR: GrassPlanter not set up for threaded regeneration")
		return

	if not multimesh:
		setup(_chunk)

	# Ensure cell_geometry is populated
	if _chunk.cell_geometry.is_empty():
		_chunk.regenerate_mesh()

	# Pre-cache images on main thread (not thread-safe to call get_cached_texture_image from threads)
	terrain_system.ensure_texture_images_cached()
	_cached_images.clear()
	for i in range(1, 7):  # Texture IDs 1-6 for grass
		_cached_images.append(terrain_system.get_cached_texture_image(i))

	# Cache thread-safe data
	_cache_thread_safe_data()

	# Queue all cells
	_pending_cells.clear()
	for z in range(terrain_system.dimensions.z - 1):
		for x in range(terrain_system.dimensions.x - 1):
			_pending_cells.append(Vector2i(x, z))

	# Sort cells by camera distance
	_sort_cells_by_camera_distance()

	# Clear previous results
	_results_mutex.lock()
	_thread_results.clear()
	_pending_thread_tasks = _pending_cells.size()
	_results_mutex.unlock()

	# Submit all cells to worker thread pool
	var chunk_coords := _chunk.chunk_coords
	for cell in _pending_cells:
		var cell_geom : Dictionary = _chunk.cell_geometry.get(cell, {})
		if not cell_geom.is_empty():
			WorkerThreadPool.add_task(_thread_compute_cell.bind(cell, cell_geom, chunk_coords))
		else:
			# No geometry for this cell, decrement counter
			_results_mutex.lock()
			_pending_thread_tasks -= 1
			_results_mutex.unlock()

	_pending_cells.clear()
	_threaded_mode = true
	_is_loading_progressively = true
	set_process(true)


## Worker thread task - computes grass for a single cell
func _thread_compute_cell(cell_coords: Vector2i, cell_geom: Dictionary, chunk_coords: Vector2i) -> void:
	var results := _compute_grass_for_cell(cell_coords, cell_geom, _cached_images, chunk_coords)

	# Thread-safe append results
	_results_mutex.lock()
	_thread_results.append_array(results)
	_pending_thread_tasks -= 1
	_results_mutex.unlock()


var _threaded_mode := false  # Track whether we're in threaded mode

func _process(_delta: float) -> void:
	if not _is_loading_progressively:
		set_process(false)
		return

	if _threaded_mode:
		# Threaded mode: apply computed results from worker threads to MultiMesh
		_process_threaded_results()
	else:
		# Non-threaded mode: process cells directly on main thread
		_process_non_threaded()


## Process results from worker threads (main thread only)
func _process_threaded_results() -> void:
	# Get a batch of results to apply
	_results_mutex.lock()
	var batch := _thread_results.slice(0, _apply_batch_size)
	_thread_results = _thread_results.slice(_apply_batch_size)
	var remaining := _thread_results.size()
	var tasks_done := _pending_thread_tasks == 0
	_results_mutex.unlock()

	# Apply batch to MultiMesh (main thread only operation)
	for data in batch:
		if data.index < multimesh.instance_count:
			multimesh.set_instance_transform(data.index, data.transform)
			multimesh.set_instance_custom_data(data.index, data.color)

	# Check if done
	if tasks_done and remaining == 0:
		_is_loading_progressively = false
		_grass_generated = true
		_threaded_mode = false
		_cached_images.clear()  # Free cached images
		set_process(false)


## Process cells directly on main thread (non-threaded fallback)
func _process_non_threaded() -> void:
	# Process a few cells per frame
	for i in range(_cells_per_frame):
		if _pending_cells.is_empty():
			_is_loading_progressively = false
			_grass_generated = true  # Mark as complete
			set_process(false)
			return

		var cell := _pending_cells.pop_front()
		generate_grass_on_cell(cell)


## Clear all grass (for memory savings when chunk is far from camera)
func clear_grass() -> void:
	_is_loading_progressively = false
	_grass_generated = false
	_pending_cells.clear()
	_threaded_mode = false
	_cached_images.clear()
	_results_mutex.lock()
	_thread_results.clear()
	_pending_thread_tasks = 0
	_results_mutex.unlock()
	set_process(false)
	if multimesh:
		multimesh.instance_count = 0


## Check if grass has been generated (not just allocated)
func has_grass() -> bool:
	return _grass_generated


func regenerate_all_cells() -> void:
	# Safety checks:
	if not _chunk:
		printerr("ERROR: _chunk not set while regenerating cells")
		return

	if not terrain_system:
		printerr("ERROR: terrain_system not set while regenerating cells")
		return

	if not multimesh:
		setup(_chunk)

	# cell_geometry is populated during regenerate_mesh
	if _chunk.cell_geometry.is_empty():
		_chunk.regenerate_mesh()

	for z in range(terrain_system.dimensions.z-1):
		for x in range(terrain_system.dimensions.x-1):
			generate_grass_on_cell(Vector2i(x, z))

	_grass_generated = true  # Mark as complete


func generate_grass_on_cell(cell_coords: Vector2i) -> void:
	# Safety checks:
	if not _chunk:
		printerr("ERROR: GrassPlanter couldn't find a reference to _chunk")
		return

	if not terrain_system:
		printerr("ERROR: GrassPlanter couldn't find a reference to terrain_system")
		return

	if not _chunk.cell_geometry:
		printerr("ERROR: GrassPlatner couldn't find a reference to cell_geometry")
		return

	if not _chunk.cell_geometry.has(cell_coords):
		printerr("ERROR: GrassPlanter couldn't find a reference to cell_coords")
		return

	var cell_geometry = _chunk.cell_geometry[cell_coords]

	if not cell_geometry.has("verts") or not cell_geometry.has("uvs") or not cell_geometry.has("colors_0") or not cell_geometry.has("colors_1") or not cell_geometry.has("grass_mask") or not cell_geometry.has("is_floor"):
		printerr("ERROR: [GrassPlanter] cell_geometry doesn't have one of the following required data: 1) verts, 2) uvs, 3) colors, 4) grass_mask, 5) is_floor")
		return

	# Seed RNG for deterministic grass placement
	_rng = RandomNumberGenerator.new()
	_rng.seed = hash(Vector3i(_chunk.chunk_coords.x, _chunk.chunk_coords.y, cell_coords.x * 1000 + cell_coords.y))

	var points: PackedVector2Array = []
	var count = terrain_system.grass_subdivisions * terrain_system.grass_subdivisions

	for z in range(terrain_system.grass_subdivisions):
		for x in range(terrain_system.grass_subdivisions):
			points.append(Vector2(
				(cell_coords.x + (x + _rng.randf_range(0, 1)) / terrain_system.grass_subdivisions) * terrain_system.cell_size.x,
				(cell_coords.y + (z + _rng.randf_range(0, 1)) / terrain_system.grass_subdivisions) * terrain_system.cell_size.y
			))
	
	var index: int = (cell_coords.y * (_chunk.dimensions.x-1) + cell_coords.x) * count
	var end_index: int = index + count
	
	var verts: PackedVector3Array = cell_geometry["verts"]
	var uvs: PackedVector2Array = cell_geometry["uvs"]
	var colors_0: PackedColorArray = cell_geometry["colors_0"]
	var colors_1: PackedColorArray = cell_geometry["colors_1"]
	var grass_mask: PackedColorArray = cell_geometry["grass_mask"]
	var is_floor: Array = cell_geometry["is_floor"]
	
	for i in range(0, len(verts), 3):
		if i+2 >= len(verts):
			continue # skip incomplete triangle
		# only place grass on floors
		if not is_floor[i]:
			continue
		
		var a := verts[i]
		var b := verts[i+1]
		var c := verts[i+2]
		
		var v0 := Vector2(c.x - a.x, c.z - a.z)
		var v1 := Vector2(b.x - a.x, b.z - a.z)
		
		var dot00 := v0.dot(v0)
		var dot01 := v0.dot(v1)
		var dot11 := v1.dot(v1)
		var invDenom := 1.0/(dot00 * dot11 - dot01 * dot01)
		
		var point_index := 0
		while (point_index < len(points)):
			var v2 = Vector2(points[point_index].x - a.x, points[point_index].y - a.z)
			var dot02 := v0.dot(v2)
			var dot12 := v1.dot(v2)
			
			var u := (dot11 * dot02 - dot01 * dot12) * invDenom
			if u < 0:
				point_index += 1
				continue
			
			var v := (dot00 * dot12 - dot01 * dot02) * invDenom
			if v < 0:
				point_index += 1
				continue
			
			if u + v <= 1:
				# Point is inside triangle, won't be inside any other floor triangle
				points.remove_at(point_index)
				var p = a*(1-u-v) + b*u + c*v
				
				# Don't place grass on ledges
				var uv = uvs[i]*u + uvs[i+1]*v + uvs[i+2]*(1-u-v)
				var on_ledge: bool = uv.x > 1-_chunk.terrain_system.ledge_threshold or uv.y > 1-_chunk.terrain_system.ridge_threshold
				
				var color_0 = _chunk.get_dominant_color(colors_0[i]*u + colors_0[i+1]*v + colors_0[i+2]*(1-u-v))
				var color_1 = _chunk.get_dominant_color(colors_1[i]*u + colors_1[i+1]*v + colors_1[i+2]*(1-u-v))
				
				# Check grass mask first - green channel forces grass ON, red channel masks grass OFF
				var mask = grass_mask[i]*u + grass_mask[i+1]*v + grass_mask[i+2]*(1-u-v)
				var is_masked: bool = mask.r < 0.9999
				var force_grass_on: bool = mask.g >= 0.9999  # Preset override: force grass regardless of texture
				
				var on_grass_tex: bool = false
				var texture_id := _get_texture_id(color_0, color_1)
				
				if force_grass_on:
					# Preset has_grass=true overrides texture setting
					on_grass_tex = true
				elif texture_id == 1: # Base grass
					on_grass_tex = true
				elif texture_id >= 2 and texture_id <= 6:
					var has_grass : bool = false
					match texture_id:
						2:
							if terrain_system.tex2_has_grass:
								has_grass = true
						3:
							if terrain_system.tex3_has_grass:
								has_grass = true
						4:
							if terrain_system.tex4_has_grass:
								has_grass = true
						5:
							if terrain_system.tex5_has_grass:
								has_grass = true
						6:
							if terrain_system.tex6_has_grass:
								has_grass = true
					if has_grass:
						on_grass_tex = true
					else:
						on_grass_tex = false
				else:
					on_grass_tex = false
				
				if on_grass_tex and not on_ledge and not is_masked:
					var edge1 = b - a
					var edge2 = c - a
					var normal = edge1.cross(edge2).normalized()
					
					var right = Vector3.FORWARD.cross(normal).normalized()
					var forward = normal.cross(Vector3.RIGHT).normalized()
					
					var instance_basis = Basis(right, forward, -normal)
					
					multimesh.set_instance_transform(index, Transform3D(instance_basis, p))
					
					var has_tex : bool = false
					var material = terrain_system.terrain_material
					var tex_scale : float = terrain_system.texture_scale_1
					match texture_id:
						2:
							has_tex = true if material.get_shader_parameter("vc_tex_rg") != null else false
							tex_scale = terrain_system.texture_scale_2
						3:
							has_tex = true if material.get_shader_parameter("vc_tex_rb") != null else false
							tex_scale = terrain_system.texture_scale_3
						4:
							has_tex = true if material.get_shader_parameter("vc_tex_ra") != null else false
							tex_scale = terrain_system.texture_scale_4
						5:
							has_tex = true if material.get_shader_parameter("vc_tex_gr") != null else false
							tex_scale = terrain_system.texture_scale_5
						6:
							has_tex = true if material.get_shader_parameter("vc_tex_gg") != null else false
							tex_scale = terrain_system.texture_scale_6
						_: # Base grass
							has_tex = true if material.get_shader_parameter("vc_tex_rr") != null else false
					var terrain_image = null
					if has_tex:
						terrain_image = _get_terrain_image(texture_id)
					
					var instance_color : Color
					if terrain_image:
						var uv_x = clamp(p.x / (terrain_system.dimensions.x * terrain_system.cell_size.x), 0.0, 1.0)
						var uv_y = clamp(p.z / (terrain_system.dimensions.z * terrain_system.cell_size.y), 0.0, 1.0)
						
						uv_x *= tex_scale
						uv_y *= tex_scale
						
						uv_x = abs(fmod(uv_x, 1.0))
						uv_y = abs(fmod(uv_y, 1.0))
						
						var px = int(uv_x * (terrain_image.get_width() - 1))
						var py = int(uv_y * (terrain_image.get_height() - 1))
						
						instance_color = terrain_image.get_pixelv(Vector2(px, py))
					match texture_id:
						6:
							instance_color.a = 1.0
						5:
							instance_color.a = 0.8
						4:
							instance_color.a = 0.6
						3:
							instance_color.a = 0.4
						2:
							instance_color.a = 0.2
						_: # Base grass sprite
							instance_color.a = 0.0
					multimesh.set_instance_custom_data(index, instance_color)
				else:
					multimesh.set_instance_transform(index, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(9999, 9999, 9999)))
				index += 1
			else:
				point_index += 1
	
	# Fill remaining points with zero-sacaled transforms (invisible)
	while index < end_index:
		if index >= multimesh.instance_count:
			return
		multimesh.set_instance_transform(index, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(9999, 9999, 9999)))
		index += 1


func _get_terrain_image(texture_id: int) -> Image:
	# Use cached decompressed images from terrain system
	return terrain_system.get_cached_texture_image(texture_id)


func _get_texture_id(vc_col_0: Color, vc_col_1: Color) -> int:
	var id : int = 1;
	if vc_col_0.r > 0.9999:
		if vc_col_1.r > 0.9999:
			id = 1;
		elif vc_col_1.g > 0.9999:
			id = 2;
		elif vc_col_1.b > 0.9999:
			id = 3;
		elif vc_col_1.a > 0.9999:
			id = 4;
	elif vc_col_0.g > 0.9999:
		if vc_col_1.r > 0.9999:
			id = 5;
		elif vc_col_1.g > 0.9999:
			id = 6;
		elif vc_col_1.b > 0.9999:
			id = 7;
		elif vc_col_1.a > 0.9999:
			id = 8;
	elif vc_col_0.b > 0.9999:
		if vc_col_1.r > 0.9999:
			id = 9;
		elif vc_col_1.g > 0.9999:
			id = 10;
		elif vc_col_1.b > 0.9999:
			id = 11;
		elif vc_col_1.a > 0.9999:
			id = 12;
	elif vc_col_0.a > 0.9999:
		if vc_col_1.r > 0.9999:
			id = 13;
		elif vc_col_1.g > 0.9999:
			id = 14;
		elif vc_col_1.b > 0.9999:
			id = 15;
		elif vc_col_1.a > 0.9999:
			id = 16;
	return id;


## Static version of get_dominant_color for thread safety
static func _get_dominant_color_static(color: Color) -> Color:
	var max_val := color.r
	var result := Color(1, 0, 0, 0)
	if color.g > max_val:
		max_val = color.g
		result = Color(0, 1, 0, 0)
	if color.b > max_val:
		max_val = color.b
		result = Color(0, 0, 1, 0)
	if color.a > max_val:
		result = Color(0, 0, 0, 1)
	return result


## Returns array of dictionaries: [{index: int, transform: Transform3D, color: Color}, ...]
## cached_images: Array of pre-decompressed Images
func _compute_grass_for_cell(cell_coords: Vector2i, cell_geom: Dictionary, cached_images: Array, chunk_coords: Vector2i) -> Array:
	var results : Array = []

	# Check required data
	if not cell_geom.has("verts") or not cell_geom.has("uvs") or not cell_geom.has("colors_0") or not cell_geom.has("colors_1") or not cell_geom.has("grass_mask") or not cell_geom.has("is_floor"):
		return results

	# Seed RNG for deterministic grass placement (same as non-threaded version)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(chunk_coords.x, chunk_coords.y, cell_coords.x * 1000 + cell_coords.y))

	var points: PackedVector2Array = []
	var count := _ts_grass_subdivisions * _ts_grass_subdivisions

	for z in range(_ts_grass_subdivisions):
		for x in range(_ts_grass_subdivisions):
			points.append(Vector2(
				(cell_coords.x + (x + rng.randf_range(0, 1)) / _ts_grass_subdivisions) * _ts_cell_size.x,
				(cell_coords.y + (z + rng.randf_range(0, 1)) / _ts_grass_subdivisions) * _ts_cell_size.y
			))

	var base_index: int = (cell_coords.y * (_ts_dimensions.x - 1) + cell_coords.x) * count
	var current_index := base_index
	var end_index: int = base_index + count

	var verts: PackedVector3Array = cell_geom["verts"]
	var uvs: PackedVector2Array = cell_geom["uvs"]
	var colors_0: PackedColorArray = cell_geom["colors_0"]
	var colors_1: PackedColorArray = cell_geom["colors_1"]
	var grass_mask: PackedColorArray = cell_geom["grass_mask"]
	var is_floor: Array = cell_geom["is_floor"]

	for i in range(0, len(verts), 3):
		if i + 2 >= len(verts):
			continue  # skip incomplete triangle
		# only place grass on floors
		if not is_floor[i]:
			continue

		var a := verts[i]
		var b := verts[i + 1]
		var c := verts[i + 2]

		var v0 := Vector2(c.x - a.x, c.z - a.z)
		var v1 := Vector2(b.x - a.x, b.z - a.z)

		var dot00 := v0.dot(v0)
		var dot01 := v0.dot(v1)
		var dot11 := v1.dot(v1)
		var invDenom := 1.0 / (dot00 * dot11 - dot01 * dot01)

		var point_index := 0
		while point_index < len(points):
			var v2 := Vector2(points[point_index].x - a.x, points[point_index].y - a.z)
			var dot02 := v0.dot(v2)
			var dot12 := v1.dot(v2)

			var u := (dot11 * dot02 - dot01 * dot12) * invDenom
			if u < 0:
				point_index += 1
				continue

			var v := (dot00 * dot12 - dot01 * dot02) * invDenom
			if v < 0:
				point_index += 1
				continue

			if u + v <= 1:
				# Point is inside triangle
				points.remove_at(point_index)
				var p := a * (1 - u - v) + b * u + c * v

				# Don't place grass on ledges
				var uv := uvs[i] * u + uvs[i + 1] * v + uvs[i + 2] * (1 - u - v)
				var on_ledge: bool = uv.x > 1 - _ts_ledge_threshold or uv.y > 1 - _ts_ridge_threshold

				var color_0 := _get_dominant_color_static(colors_0[i] * u + colors_0[i + 1] * v + colors_0[i + 2] * (1 - u - v))
				var color_1 := _get_dominant_color_static(colors_1[i] * u + colors_1[i + 1] * v + colors_1[i + 2] * (1 - u - v))

				# Check grass mask
				var mask := grass_mask[i] * u + grass_mask[i + 1] * v + grass_mask[i + 2] * (1 - u - v)
				var is_masked: bool = mask.r < 0.9999
				var force_grass_on: bool = mask.g >= 0.9999

				var on_grass_tex: bool = false
				var texture_id := _get_texture_id(color_0, color_1)

				if force_grass_on:
					on_grass_tex = true
				elif texture_id == 1:
					on_grass_tex = true
				elif texture_id >= 2 and texture_id <= 6:
					on_grass_tex = _ts_tex_has_grass[texture_id - 2]

				if on_grass_tex and not on_ledge and not is_masked:
					var edge1 := b - a
					var edge2 := c - a
					var normal := edge1.cross(edge2).normalized()

					var right := Vector3.FORWARD.cross(normal).normalized()
					var forward := normal.cross(Vector3.RIGHT).normalized()

					var instance_basis := Basis(right, forward, -normal)
					var instance_transform := Transform3D(instance_basis, p)

					# Calculate instance color from cached texture
					var instance_color := Color.WHITE
					var tex_idx := min(texture_id - 1, 5)
					var tex_scale : float = _ts_texture_scales[tex_idx]
					var has_tex : bool = _ts_has_tex[tex_idx]

					if has_tex and texture_id - 1 < cached_images.size() and cached_images[texture_id - 1] != null:
						var terrain_image : Image = cached_images[texture_id - 1]
						var uv_x := clamp(p.x / (_ts_dimensions.x * _ts_cell_size.x), 0.0, 1.0)
						var uv_y := clamp(p.z / (_ts_dimensions.z * _ts_cell_size.y), 0.0, 1.0)

						uv_x *= tex_scale
						uv_y *= tex_scale

						uv_x = abs(fmod(uv_x, 1.0))
						uv_y = abs(fmod(uv_y, 1.0))

						var px := int(uv_x * (terrain_image.get_width() - 1))
						var py := int(uv_y * (terrain_image.get_height() - 1))

						instance_color = terrain_image.get_pixelv(Vector2(px, py))

					# Set alpha channel based on texture ID (sprite selection)
					match texture_id:
						6: instance_color.a = 1.0
						5: instance_color.a = 0.8
						4: instance_color.a = 0.6
						3: instance_color.a = 0.4
						2: instance_color.a = 0.2
						_: instance_color.a = 0.0

					results.append({"index": current_index, "transform": instance_transform, "color": instance_color})
				else:
					# Zero-scale invisible transform
					results.append({"index": current_index, "transform": Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(9999, 9999, 9999)), "color": Color.WHITE})

				current_index += 1
			else:
				point_index += 1

	# Fill remaining slots with invisible transforms
	while current_index < end_index:
		results.append({"index": current_index, "transform": Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(9999, 9999, 9999)), "color": Color.WHITE})
		current_index += 1

	return results
