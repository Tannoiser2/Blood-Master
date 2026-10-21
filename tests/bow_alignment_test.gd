extends SceneTree
# Arciere: dopo Incoccare, la posa ferma deve avere la freccia verso il fronte (angolo ~0°).
func _init():call_deferred("run")
func run():
	var b=ArenaBoard3D.new();var g=BloodRules.new()
	g.new_game([{"character":"kylvia","team":0,"controller":"ai"},{"character":"gascor","team":1,"controller":"ai"}],"libero",3,8)
	b.game=g;root.add_child(b);b.size=Vector2(400,400)
	await process_frame
	g.deploy(g.entry_cells(0)[0],0);g.deploy(g.entry_cells(1)[0],3);b.sync()
	await create_timer(1).timeout
	var info=b.minis[0];var ap: AnimationPlayer=info.ap
	b._set_gear(0,true,false);ap.play("Incoccare");await create_timer(ap.get_animation("Incoccare").length+.2).timeout
	b._set_gear(0,true,true);b._rest_pose(0,.25);await create_timer(1.0).timeout
	var mi: MeshInstance3D=info.model.find_child("FrecciaIncoccata",true,false)
	var ab=mi.get_aabb();var t=mi.global_transform
	var ax=Vector3.RIGHT if ab.size.x>=ab.size.y and ab.size.x>=ab.size.z else (Vector3.UP if ab.size.y>=ab.size.z else Vector3.BACK)
	var d=t*(ab.get_center()+ax*ab.size.dot(ax)*.5)-t*(ab.get_center()-ax*ab.size.dot(ax)*.5)
	var fwd=info.pivot.global_transform.basis.z
	print("FRECCIA rispetto al fronte: %.0f°  rot modello %.0f°  clip %s"%[rad_to_deg(fwd.signed_angle_to(Vector3(d.x,0,d.z),Vector3.UP)),rad_to_deg(info.model.rotation.y),ap.current_animation])
	quit()
