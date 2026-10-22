// =============================================================================
//  toon_outline.gdshader —— 反向外壳描边（Inverted Hull）
//
//  做法：把同一个网格沿**平滑法线**向外膨胀一点点，只渲染背面（cull_front），
//  涂成近黑色，于是物体外围多出一圈手办线稿。挂在材质的 `next_pass` 上，
//  不需要复制节点、不需要第二个 MeshInstance3D，与主 pass 共享同一份几何与实例数据。
//
//  为什么必须用**平滑法线**（而不是面着色用的平面法线）：
//  膨胀方向一旦按面法线走，相邻三角形各往各的方向推开，外壳会裂成一片「碎片」，
//  描边就变成毛刺。本工程的网格本来就带平滑法线（面着色是在片元里用导数做的），
//  所以这里天然拿得到连续的法线 —— 这也是「地形在片元里临时拍平」的另一个好处。
//
//  宽度单位是**世界米**（不是像素）：正交等距下缩放不改变透视，1 像素 ≈ 0.12 m
//  （1600×900、默认 size≈107 m），所以 0.10~0.18 m 就是 1~1.5 像素的线。
//  非等比缩放的模型（GLB 建筑按目标尺寸缩放）要除掉缩放，否则线会跟着模型变粗。
// =============================================================================
shader_type spatial;
render_mode cull_front, unshaded, shadows_disabled, depth_draw_opaque;

uniform vec4 outline_color : source_color = vec4(0.075, 0.062, 0.105, 1.0);
// 世界米：0.05 接近看不见，0.30 已经是粗墨线
uniform float outline_width = 0.12;

void vertex() {
	// 模型缩放：GLB 建筑按 target_m 缩放过，直接按局部法线膨胀会让线粗得不一致
	mat4 m = MODEL_MATRIX;
	vec3 s = vec3(
		max(length(m[0].xyz), 1e-4),
		max(length(m[1].xyz), 1e-4),
		max(length(m[2].xyz), 1e-4));
	// 法线先归一：GLB 的法线长度未必恰好是 1
	VERTEX += normalize(NORMAL + vec3(1e-9)) * outline_width / max(max(s.x, s.y), max(s.z, 1e-4));
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
