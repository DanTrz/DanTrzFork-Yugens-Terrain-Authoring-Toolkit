@tool
extends Resource
class_name MarchingSquaresTextureList


const GRASS_TEXTURE : Texture2D = preload("res://addons/MarchingSquaresTerrain/resources/materials/grass_terrain_noise.res")
const WALL_TEXTURE : Texture2D = preload("res://addons/MarchingSquaresTerrain/resources/materials/wall_noise_texture.res")
const GRASS_SPRITE : Texture2D = preload("res://addons/MarchingSquaresTerrain/resources/materials/grass_leaf_sprite.png")

@export var floor_textures : Array[Texture2D] = [
	GRASS_TEXTURE, GRASS_TEXTURE, GRASS_TEXTURE, GRASS_TEXTURE,
	GRASS_TEXTURE, GRASS_TEXTURE, Texture2D.new(), Texture2D.new(),
	Texture2D.new(), Texture2D.new(), Texture2D.new(), Texture2D.new(),
	Texture2D.new(), Texture2D.new(), Texture2D.new(),
]

@export var grass_sprites : Array[Texture2D] = [
	GRASS_SPRITE, GRASS_SPRITE, GRASS_SPRITE,
	GRASS_SPRITE, GRASS_SPRITE, GRASS_SPRITE,
]

@export var grass_colors : Array[Color] = [
	Color("647851ff"), Color("527b62ff"), Color("5f6c4bff"),
	Color("647941ff"), Color("4a7e5dff"), Color("71725dff"),
]

@export var has_grass : Array[bool] = [
	true, true, true, true, true,
]

@export var wall_textures : Array[Texture2D] = [
	WALL_TEXTURE, WALL_TEXTURE, WALL_TEXTURE,
	WALL_TEXTURE, WALL_TEXTURE, WALL_TEXTURE,
]

@export var wall_colors : Array[Color] = [
	Color("5e5645ff"), Color("665950ff"), Color("595240ff"),
	Color("615745ff"), Color("5c5442ff"), Color("6b614cff"),
]
