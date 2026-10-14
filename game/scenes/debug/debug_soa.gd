class_name DebugSoA
extends RefCounted
## A bag of named packed arrays that reads like a sim struct-of-arrays (`obj.state`, `obj.x`, ...), used by the map
## viewer to feed the swarm/projectile/pickup renderers without a running RunWorld.

## Field name -> packed array.
var fields: Dictionary = {}


func _get(property: StringName) -> Variant:
	return fields.get(String(property))


## Creates `n` slots of the given fields: {"x": TYPE_PACKED_FLOAT32_ARRAY, ...}.
static func make(n: int, spec: Dictionary) -> DebugSoA:
	var s := DebugSoA.new()
	for k: String in spec.keys():
		var arr: Variant
		match int(spec[k]):
			TYPE_PACKED_FLOAT32_ARRAY:
				arr = PackedFloat32Array()
			TYPE_PACKED_INT32_ARRAY:
				arr = PackedInt32Array()
			TYPE_PACKED_BYTE_ARRAY:
				arr = PackedByteArray()
		arr.resize(n)
		s.fields[k] = arr
	return s


## Sets one element (packed arrays are values, so write through the dictionary).
func put(field: String, i: int, v: Variant) -> void:
	var arr: Variant = fields[field]
	arr[i] = v
	fields[field] = arr
