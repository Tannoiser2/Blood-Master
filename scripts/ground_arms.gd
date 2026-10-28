extends SkeletonModifier3D
class_name GroundArms
## A terra (e caduto per sempre) le clip lasciavano braccia infilate nel corpo e armi a due mani
## che attraversavano il busto. Qui, mentre il personaggio è disteso, le braccia vengono aperte
## verso l'esterno: di lato, un po' verso i piedi e appoggiate a terra; l'arma resta solo nella
## mano destra (è agganciata a lei) e la sinistra lascia l'asta. Rialzandosi tornano alla clip.

const DOWN_CLIPS := ["A terra", "Morte"]
var ap: AnimationPlayer
var weight := 0.0
var _last_ms := 0

func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or ap == null:
		return
	# quanto aprire: dalla metà della caduta in poi, fino in fondo; morbido anche quando si rialza
	var target := 0.0
	var clip := str(ap.assigned_animation)
	if clip in DOWN_CLIPS and ap.has_animation(clip):
		var length := maxf(ap.get_animation(clip).length, .01)
		target = clampf((ap.current_animation_position / length - .45) / .4, 0.0, 1.0)
	var now := Time.get_ticks_msec()
	var dt := clampf(float(now - _last_ms) / 1000.0, 0.0, .1) if _last_ms > 0 else .016
	_last_ms = now
	weight = move_toward(weight, target, dt * 2.5)
	if weight <= .001:
		return
	var b := func(n: String) -> int: return sk.find_bone(n)
	var hips: int = b.call("Hips"); var neck: int = b.call("neck")
	var la: int = b.call("LeftArm"); var ra: int = b.call("RightArm")
	if hips < 0 or neck < 0 or la < 0 or ra < 0:
		return
	var spine: Vector3 = (sk.get_bone_global_pose(neck).origin - sk.get_bone_global_pose(hips).origin).normalized()
	var lat: Vector3 = sk.get_bone_global_pose(la).origin - sk.get_bone_global_pose(ra).origin
	lat = (lat - spine * lat.dot(spine)).normalized()
	var down: Vector3 = (sk.global_transform.basis.inverse() * Vector3.DOWN).normalized()
	for side in [["Left", 1.0], ["Right", -1.0]]:
		var arm: int = b.call(side[0] + "Arm"); var fore: int = b.call(side[0] + "ForeArm"); var hand: int = b.call(side[0] + "Hand")
		if arm < 0 or fore < 0 or hand < 0:
			continue
		var out: Vector3 = lat * float(side[1])
		# braccio: di lato, un po' verso i piedi, appoggiato al suolo
		var want: Vector3 = (out * .78 - spine * .5 + down * .28).normalized()
		_aim(sk, arm, fore, want)
		# avambraccio quasi dritto, appena piegato verso terra
		_aim(sk, fore, hand, (want * .9 + down * .2 + out * .1).normalized())
		# arma (o arco, scudo a parte) piatta a terra, sul prolungamento del braccio, lontana dal corpo
		var wdir := _weapon_axis(sk, hand)
		if wdir != Vector3.ZERO:
			var ht: Transform3D = sk.get_bone_global_pose(hand)
			var cur: Vector3 = (ht.basis * wdir).normalized()
			var flat: Vector3 = want - down * want.dot(down)
			if flat.length() > .05:
				var q := Quaternion.IDENTITY.slerp(Quaternion(cur, flat.normalized()), weight)
				ht.basis = Basis(q) * ht.basis
				sk.set_bone_global_pose(hand, ht)

func _aim(sk: Skeleton3D, bone: int, child: int, want: Vector3) -> void:
	var t: Transform3D = sk.get_bone_global_pose(bone)
	var cur: Vector3 = sk.get_bone_global_pose(child).origin - t.origin
	if cur.length() < 1e-5:
		return
	var q := Quaternion(cur.normalized(), want)
	q = Quaternion.IDENTITY.slerp(q, weight)
	t.basis = Basis(q) * t.basis
	sk.set_bone_global_pose(bone, t)

## asse dell'arma impugnata da questa mano (nel riferimento dell'osso): dalla presa verso l'estremo
## più lontano della mesh visibile più lunga agganciata alla mano. Gli scudi stanno sull'avambraccio.
var _axis_cache := {}
func _weapon_axis(sk: Skeleton3D, hand: int) -> Vector3:
	var name := sk.get_bone_name(hand)
	var best := Vector3.ZERO; var best_len := .25   # sotto i 25 cm (pugnali corti, mani) non serve
	for att in sk.get_children():
		if not (att is BoneAttachment3D) or att.bone_name != name:
			continue
		for mi in att.find_children("*", "MeshInstance3D", true, false):
			if not mi.is_visible_in_tree() or mi.mesh == null:
				continue
			var key := str(mi.get_instance_id())
			if not _axis_cache.has(key):
				var far := Vector3.ZERO
				var arr: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
				var rel: Transform3D = att.global_transform.affine_inverse() * mi.global_transform
				for v in arr:
					var p: Vector3 = rel * v
					if p.length() > far.length():far = p
				_axis_cache[key] = far
			var f: Vector3 = _axis_cache[key]
			var len := f.length() * sk.global_transform.basis.get_scale().x
			if len > best_len:
				best_len = len; best = f.normalized()
	return best
