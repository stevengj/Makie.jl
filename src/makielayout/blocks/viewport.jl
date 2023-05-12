# Forwarded from Camera pr

struct Ray
    origin::Point3f
    direction::Vec3f
end


################################################################################



# Mesh generation
function Rhombicuboctahedron(; center = Point3f(0), radius = 1f0)
    o = 1 / (1 + sqrt(2))
    ps = radius .* Point3f[
        (-o, -o, -1), (-o, o, -1), (o, o, -1), (o, -o, -1),
        (-1, o, -o), (-o, 1, -o), (o, 1, -o), (1, o, -o), 
            (1, -o, -o), (o, -1, -o), (-o, -1, -o), (-1, -o, -o),
        (-1, o, o), (-o, 1, o), (o, 1, o), (1, o, o), 
            (1, -o, o), (o, -1, o), (-o, -1, o), (-1, -o, o),
        (-o, -o, 1), (-o, o, 1), (o, o, 1), (o, -o, 1),
    ] .+ (center,)
    QF = QuadFace
    TF = TriangleFace
    faces = [
        # bottom quad
        QF(1, 2, 3, 4), 
    
        # bottom triangles
        TF(2, 5, 6), TF(3, 7, 8), TF(4, 9, 10), TF(1, 11, 12),
    
        # bottom diag quads
        QF(3, 2, 6, 7), QF(4, 3, 8, 9), QF(1, 4, 10, 11), QF(2, 1, 12, 5), 
            
        # quad ring
        QF(13, 14, 6, 5), QF(14, 15, 7, 6), QF(15, 16, 8, 7), QF(16, 17, 9, 8),
        QF(17, 18, 10, 9), QF(18, 19, 11, 10), QF(19, 20, 12, 11), QF(20, 13, 5, 12),
    
        # top diag quads
        QF(22, 23, 15, 14), QF(21, 22, 13, 20), QF(24, 21, 19, 18), QF(23, 24, 17, 16), 
    
        # top triangles
        TF(21, 20, 19), TF(24, 18, 17), TF(23, 16, 15), TF(22, 14, 13),
    
        # top
        QF(21, 24, 23, 22)
    ]
    
    remapped_ps = Point3f[]
    remapped_fs = AbstractFace[]
    remapped_cs = RGBf[]
    remapped_index = Int[]
    for (idx, f) in enumerate(faces)
        i = length(remapped_ps)
        append!(remapped_ps, ps[f])
        push!(remapped_fs, length(f) == 3 ? TF(i+1, i+2, i+3) : QF(i+1, i+2, i+3, i+4))
        c = RGBf(abs.(mean(ps[f]))...)
        append!(remapped_cs, (c for _ in f))
        append!(remapped_index, [idx for _ in f])
    end
    
    _faces = decompose(GLTriangleFace, remapped_fs)
    return GeometryBasics.Mesh(
        meta(
            remapped_ps; 
            normals = normals(remapped_ps, _faces), 
            color = remapped_cs,
            index = remapped_index
        ), 
        _faces
    )
end


################################################################################
### Camera setup
################################################################################


# Simplified/Modified from Camera3D to make sure updates work correctly
struct ViewportControllerCamera <: AbstractCamera
    phi::Observable{Float32}
    theta::Observable{Float32}
    attributes::Attributes
end

function ViewportControllerCamera(scene::Scene, axis; kwargs...)
    kwdict = Dict(kwargs)
    attr = Attributes(
        fov = 45.0,
        projectiontype = Makie.Perspective,
        rotationspeed = 1.0,
        click_timeout = 0.3,
        selected = false,
        # step = 2pi / 16
        step = get(kwdict, :step, 2pi/16)
        # phi_steps = 16,
        # theta_steps = 16
    )
    # merge!(attr, Attributes(kwargs)) # doesn't replace?

    if axis isa Axis3
        cam = ViewportControllerCamera(
            Observable{Float32}(axis.azimuth[]), 
            Observable{Float32}(axis.elevation[]),
            attr
        )
    else
        cam = ViewportControllerCamera(
            Observable{Float32}(pi/4), 
            Observable{Float32}(0.61547977f0),
            attr
        )
    end

    disconnect!(camera(scene))

    # de/select plot on click outside/inside
    # also deselect other cameras
    deselect_all_cameras!(root(scene))
    on(camera(scene), events(scene).mousebutton, priority = 100) do event
        if event.action == Mouse.press
            attr.selected[] = is_mouseinside(scene)
        end
        return Consume(false)
    end

    # Mouse controls
    add_rotation!(scene, cam, axis)

    # add camera controls to scene
    cameracontrols!(scene, cam)

    # Trigger updates on scene resize and settings change
    # scene.px_area, 
    on(camera(scene), scene.px_area, attr[:fov], attr[:projectiontype]) do _, _, _
        update_cam!(scene, cam)
    end

    notify(attr.fov)

    connect_camera!(axis, scene)

    cam
end
deselect_camera!(cam::ViewportControllerCamera) = cam.attributes.selected[] = false

function add_rotation!(scene, cam::ViewportControllerCamera, axis)
    @extract cam.attributes (rotationspeed, click_timeout, step)
    drag_state = RefValue((false, Vec2f(0), time()))
    e = events(scene)

    # drag start/stop
    on(camera(scene), e.mousebutton) do event
        if event.button == Mouse.left
            active, last_mousepos, last_time = drag_state[]
            if event.action == Mouse.press && is_mouseinside(scene) # && !active
                drag_state[] = (true, mouseposition_px(scene), time())
                return Consume(true)
            elseif event.action == Mouse.release && active
                dt = time() - last_time
                if dt < click_timeout[]
                    # do click stuff
                    p, idx = Makie.pick(scene)
                    if p isa Mesh
                        ray = ray_at_cursor(scene, cam)
                        # ray = p + tv, Sphere: x² + y² + z² = r²
                        # Solve resulting quadratic equation
                        a = dot(ray.direction, ray.direction)
                        b = 2 * dot(ray.origin, ray.direction)
                        c = dot(ray.origin, ray.origin) - 1 # radius 1
                        # @info a, b, c
                        t1 = (-b + sqrt(b*b - 4*a*c)) / (2*a)
                        t2 = (-b - sqrt(b*b - 4*a*c)) / (2*a) # <- this one, always
                        # @info t1, t2
                        p = ray.origin + t2 * ray.direction

                        # to spherical
                        theta = asin(p[3]) 
                        if abs(p[3]) > 0.999
                            phi = 0.0
                        else
                            p = p[Vec(1,2)]
                            p = p / norm(p)
                            phi = mod(2pi + atan(p[2], p[1]), 2pi)
                        end

                        # snapping
                        phi   = step[] * round(phi / step[])
                        theta = step[] * round(theta / step[])

                        update_cam!(scene, cam, phi, theta)
                        update_camera!(axis, cam.phi[], cam.theta[])
                    end
                    # if p isa Text
                    #     phi, theta = [
                    #         (pi, 0), (pi, 0), (0, 0), 
                    #         (-pi/2, 0), (-pi/2, 0), (pi/2, 0), 
                    #         (cam.phi[], -pi/2), (cam.phi[], -pi/2), (cam.phi[], pi/2)
                    #     ][idx]
                    #     update_cam!(scene, cam, phi, theta)
                    #     update_camera!(axis, cam.phi[], cam.theta[])
                    # elseif p isa Mesh
                    #     face_idx = p[1][].index[idx]
                    #     phi, theta = [
                    #         (cam.phi[], -pi/2),
                    #         (3pi/4, -pi/4), (1pi/4, -pi/4), (7pi/4, -pi/4), (5pi/4, -pi/4),
                    #         (pi/2, -pi/4), (0, -pi/4), (-pi/2, -pi/4), (-pi, -pi/4),
                    #         (3pi/4, 0), (2pi/4, 0), (pi/4, 0), (0, 0), 
                    #         (7pi/4, 0), (6pi/4, 0), (5pi/4, 0), (pi, 0),
                    #         (pi/2, pi/4), (pi, pi/4), (3pi/2, pi/4), (0, pi/4),
                    #         (5pi/4, pi/4), (7pi/4, pi/4), (pi/4, pi/4), (3pi/4, pi/4),
                    #         (cam.phi[], pi/2)
                    #     ][face_idx]
                    #     @info "From Click: $phi, $theta"
                    #     update_cam!(scene, cam, phi, theta)
                    #     update_camera!(axis, cam.phi[], cam.theta[])
                    # end
                else
                    # do drag stuff
                    mousepos = mouseposition_px(scene)
                    rot_scaling = rotationspeed[] * (e.window_dpi[] * 0.005)
                    mp = (last_mousepos .- mousepos) .* 0.01f0 .* rot_scaling
                    rotate_cam!(scene, cam, mp[1], mp[2], axis)
                end
                drag_state[] = (false, Vec2f(0), time())
                println()

                return Consume(true)
            end
        end

        return Consume(false)
    end

    # in drag
    on(camera(scene), e.mouseposition) do mp
        active, last_mousepos, last_time = drag_state[]
        if active && ispressed(scene, Mouse.left)
            mousepos = screen_relative(scene, mp)
            rot_scaling = rotationspeed[] * (e.window_dpi[] * 0.005)
            mp = (last_mousepos .- mousepos) * 0.01f0 * rot_scaling
            rotate_cam!(scene, cam, mp[1], mp[2], axis)
            drag_state[] = (active, mousepos, last_time)
            println()
            return Consume(true)
        end

        return Consume(false)
    end
end

# function rotate_cam!(scene, cam::ViewportControllerCamera, angles::VecTypes, axis)
function rotate_cam!(scene, cam::ViewportControllerCamera, dphi::Real, dtheta::Real, axis)
    @info dphi, dtheta
    cam.theta[] = mod(cam.theta[] + dtheta, 2pi)
    reverse = ifelse(pi/2 <= cam.theta[] <= 3pi/2, -1, 1)
    cam.phi[] = mod(cam.phi[] + reverse * dphi, 2pi)

    update_cam!(scene, cam)    
    update_camera!(axis, cam.phi[], cam.theta[])

    return
end

# Update camera matrices
function update_cam!(scene::Scene, cam::ViewportControllerCamera, phi::Real, theta::Real)
    dphi = mod(2pi + cam.phi[] - phi, 2pi)
    print(dphi, " -> ")
    dphi = ifelse(dphi > pi, dphi - 2pi, dphi)
    println(dphi)
    if !(-1.1pi/2 <= dphi <= 1.1pi/2)
        cam.phi[]   = mod(phi + pi, 2pi)
        cam.theta[] = mod(pi - theta, 2pi)
    else
        cam.phi[] = phi
        cam.theta[] = theta
    end
    return update_cam!(scene, cam)
end

function update_cam!(scene::Scene, cam::ViewportControllerCamera)
    # @extractvalue cam (lookat, eyeposition, upvector)
    fov = cam.attributes.fov[]

    phi = cam.phi[]; theta = cam.theta[]
    @info "update mat: $phi, $theta"
    eyeposition = 3f0 * Vec3f(cos(theta) * cos(phi), cos(theta) * sin(phi), sin(theta))
    lookat = Vec3f(0)
    theta += pi/2
    upvector = Vec3f(cos(theta) * cos(phi), cos(theta) * sin(phi), sin(theta))

    view = Makie.lookat(eyeposition, lookat, upvector)

    aspect = Float32((/)(widths(scene.px_area[])...))
    if cam.attributes.projectiontype[] == Makie.Perspective
        view_norm = norm(eyeposition - lookat)
        proj = Makie.perspectiveprojection(Float32(fov), aspect, view_norm * 0.1f0, view_norm * 2f0)
    else
        h = norm(eyeposition - lookat); w = h * aspect
        proj = Makie.orthographicprojection(-w, w, -h, h, h * 0.1f0, h * 2f0)
    end

    Makie.set_proj_view!(camera(scene), proj, view)
    scene.camera.eyeposition[] = eyeposition

    return
end

# update controller based on axis
function connect_camera!(ax::Axis3, scene::Scene)
    cam = cameracontrols(scene)
    onany(ax.elevation, ax.azimuth) do theta, phi
        update_cam!(scene, cam, phi, theta)
        return
    end
    notify(ax.elevation)
    return
end

function connect_camera!(lscene::LScene, scene::Scene)
    cam = cameracontrols(lscene.scene)
    onany(camera(lscene.scene).view) do _
        @extractvalue cam (lookat, eyeposition, upvector)

        dir = normalize(eyeposition - lookat)
        theta = asin(dir[3]) 
        theta = mod(2pi + ifelse(upvector[3] > 0, theta, pi - theta), 2pi)
        if abs(dir[3]) > 0.9
            right = cross(upvector, dir)
            p = right[Vec(1,2)]
            p = p / norm(p)
            phi = mod(3pi/2 + atan(p[2], p[1]), 2pi)
        else
            p = dir[Vec(1,2)]
            p = p / norm(p)
            phi = mod(2pi + atan(p[2], p[1]) + ifelse(pi/2 <= theta <= 3pi/2, pi, 0), 2pi)
        end
        @info "from other: $phi, $theta"
        update_cam!(scene, scene.camera_controls, phi, theta)
        return
    end
    notify(camera(lscene.scene).view)
    return
end

# Update axis based on controller 
function update_camera!(ax::Axis3, phi, theta)
    ax.azimuth[] = phi
    ax.elevation[] = theta
    return
end

function update_camera!(lscene::LScene, phi, theta)
    cam = cameracontrols(lscene.scene)
    dir = Vec3f(cos(theta) * cos(phi), cos(theta) * sin(phi), sin(theta))
    viewdir = cam.eyeposition[] - cam.lookat[]
    theta += pi/2
    upvector = Vec3f(cos(theta) * cos(phi), cos(theta) * sin(phi), sin(theta))
    eyepos = cam.lookat[] + norm(viewdir) * dir
    update_cam!(lscene.scene, cam, eyepos, cam.lookat[], upvector)
    return
end

function spherical_to_cartesian(phi, theta, radius = 1f0)
    return radius * Vec3f(cos(theta) * cos(phi), cos(theta) * sin(phi), sin(theta))
end

function cartesian_to_spherical(v::Vec3f)

end

################################################################################


function ray_at_cursor(scene::Scene, cam::ViewportControllerCamera)
    phi = cam.phi[]; theta = cam.theta[]
    viewdir = - Vec3f(cos(theta) * cos(phi), cos(theta) * sin(phi), sin(theta))
    eyepos = - 3f0 * viewdir
    theta += pi/2
    up = Vec3f(cos(theta) * cos(phi), cos(theta) * sin(phi), sin(theta))

    u_z = normalize(viewdir)
    u_x = normalize(cross(u_z, up))
    u_y = normalize(cross(u_x, u_z))
    
    px_width, px_height = widths(scene.px_area[])
    aspect = px_width / px_height
    rel_pos = 2 .* mouseposition_px(scene) ./ (px_width, px_height) .- 1

    if cam.attributes.projectiontype[] === Perspective
        dir = (rel_pos[1] * aspect * u_x + rel_pos[2] * u_y) * 
                tand(0.5 * cam.attributes.fov[]) + u_z
        return Ray(eyepos, normalize(dir))
    else
        # Orthographic has consistent direction, but not starting point
        origin = norm(viewdir) * (rel_pos[1] * aspect * u_x + rel_pos[2] * u_y)
        return Ray(origin, normalize(viewdir))
    end
end



################################################################################
### Create Block
################################################################################


# Create Controller
Viewport3DController(x, axis::Union{LScene, Axis3}; kwargs...) = Viewport3DController(x; axis = axis, kwargs...)

function initialize_block!(controller::Viewport3DController; axis)
    blockscene = controller.blockscene

    scene_region = map(blockscene, controller.layoutobservables.computedbbox) do bb
        mini = minimum(bb); ws = widths(bb)
        center = mini + 0.5 * ws
        w = min(ws[1], ws[2])
        return round_to_IRect2D(Rect2(center .- 0.5 * w, Vec2(w)))
    end

    scene = Scene(
        blockscene, 
        px_area = scene_region, 
        # backgroundcolor = (:yellow, 0.3),
        clear = true
    )

    # m = Rhombicuboctahedron()
    texture = let
        url = "https://raw.githubusercontent.com/linuxgurugamer/NavBallTextureChanger/master/GameData/NavBallTextureChanger/PluginData/Skins/Trekky0623_DIF.png"
        FileIO.load(Base.download(url))
    end

    m = uv_normal_mesh(Tesselation(Sphere(Point3f(0), 1f0), 50))
    @info length(coordinates(m))
    mp = mesh!(scene, m, color = texture, transparency = false)
    rotate!(mp, Vec3f(0, 0, 1), pi)

    step_choices = (4, 6, 8, 9, 10, 12, 16, 18, 24, 36, 72)
    step_index = Observable(3)
    cam = ViewportControllerCamera(
        scene, axis, step = map(i -> 2pi / step_choices[i], step_index)
    )

    # mark center
    scatter!(
        scene, Point3f(0, 0, -1), space = :clip,
        marker = '⊹', markersize = 50, color = :black,
        # marker = '⌖', markersize = 30, color = :black,
        # marker = Rect, markersize = 20, color = :transparent,
        # strokewidth = 4, strokecolor = :black
    )

    # info on step size
    text!(
        scene, 
        Point2f(0.9), space = :clip, align = (:right, :top),
        text = map(i -> "Steps:\n$(step_choices[i])\n$(360/step_choices[i])°", step_index),
    )

    on(scene, events(scene).scroll) do e
        if is_mouseinside(scene)
            idx = trunc(Int, step_index[] - sign(e[2]))
            if 0 < idx <= length(step_choices) && (idx != step_index[])
                step_index[] = idx
            end
        end
    end

    return
end