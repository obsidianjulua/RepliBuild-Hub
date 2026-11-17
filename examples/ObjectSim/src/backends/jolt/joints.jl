# The Jolt backend: constraints and the mouse picker.
#
#   point   PointConstraint
#   hinge   HingeConstraint (limits, velocity motor)
#   slider  SliderConstraint (limits, velocity motor)
#   fixed   FixedConstraint
#   spring  SixDOFConstraint, translation free and rotation fixed (the pull
#           is ObjectSim's own, see src/joints.jl)
#
# Each is made from its *ConstraintSettings, built as a zeroed struct with its
# vtable pointer set (see _jcsettings), then Create(body1, body2). Body 1 is
# the other body (or Body::sFixedToWorld) and body 2 is `a`, so angles,
# positions and motor speeds are a's relative to b, as with bullet3's hinge.
#
# Jolt has no break threshold: a joint with `break_impulse` is checked after
# each step against the impulse its point part applied (mTotalLambda) and
# switched off (mEnabled) when that is exceeded, which is what bullet3 does.
# Jolt has no per-joint "don't collide" either: joined bodies go into a
# GroupFilterTable with the pair turned off, unless `collide = true`.

const _J_SUBGROUPS = 4096

mutable struct JoltJoint
    phys::JoltPhysics
    ptr::Ptr{Cvoid}                 # the TwoBodyConstraint (the PhysicsSystem holds the reference)
    T::DataType                     # its Julia layout (J.HingeConstraint, …)
end
_jj(j::Joint) = j.h::JoltJoint

# A *ConstraintSettings object, zeroed in C memory (calloc: 16-byte aligned),
# with the ConstraintSettings defaults that matter (enabled, world space) and
# its class's vtable pointer: the wrapper calls Create through the vtable
# (`jlcs.vcall`), as C++ does through a settings pointer. Itanium ABI: the
# vptr points 16 bytes into the vtable, past offset-to-top and the typeinfo.
const _J_VTABLES = Dict{DataType,Ptr{Cvoid}}()
function _jvtable(T::DataType)
    get!(_J_VTABLES, T) do
        name = String(nameof(T))
        sym = Symbol("_ZTVN3JPH", length(name), name, "E")
        Libdl.dlsym(Libdl.dlopen(J.LIBRARY_PATH), sym) + 16
    end
end
function _jcsettings(T::DataType)
    p = Libc.calloc(1, sizeof(T))
    unsafe_store!(Ptr{Ptr{Cvoid}}(p), _jvtable(T))
    _jpoke!(p, T, :mEnabled, true)
    _jpoke!(p, T, :mDrawConstraintSize, 1f0)
    _jpoke!(p, T, :mSpace, J.EConstraintSpace(1))         # WorldSpace
    return p
end

function _jperp(axis)
    a = vunit(axis)
    return vunit(vcross(a, abs(a[2]) < 0.9f0 ? (0f0, 1f0, 0f0) : (1f0, 0f0, 0f0)))
end

# Velocity motor settings: the torque (hinge) or force (slider) limit.
function _jmotor(limit::Float32)
    big = floatmax(Float32)
    spring = J.SpringSettings(J.ESpringMode(0x00), (0x00, 0x00, 0x00),
                              J.SpringSettings_anon1(reinterpret(NTuple{4,UInt8}, 2f0)), 1f0)   # frequency 2 Hz, damping 1
    return J.MotorSettings(spring, -limit, limit, -limit, limit)
end

function _be_add_joint!(P::JoltPhysics, w::World, s::JointSpec, j::Joint)
    a, b = j.a, j.b
    body1 = b === nothing ? _jfixed_to_world() : Ptr{J.Body}(_jh(b).ptr)
    body2 = Ptr{J.Body}(_jh(a).ptr)
    pivot = _jv(s.pivot)
    X = _jv((1, 0, 0)); Y = _jv((0, 1, 0))
    local T, settings, create
    if s.kind == :point
        T = J.PointConstraintSettings; settings = _jcsettings(T)
        _jpoke!(settings, T, :mPoint1, pivot); _jpoke!(settings, T, :mPoint2, pivot)
        create = J.JPH_PointConstraintSettings_Create
    elseif s.kind == :hinge
        T = J.HingeConstraintSettings; settings = _jcsettings(T)
        ax = _jv(s.axis); nrm = _jv(_jperp(s.axis))
        for f in (:mPoint1, :mPoint2); _jpoke!(settings, T, f, pivot); end
        for f in (:mHingeAxis1, :mHingeAxis2); _jpoke!(settings, T, f, ax); end
        for f in (:mNormalAxis1, :mNormalAxis2); _jpoke!(settings, T, f, nrm); end
        lo, hi = s.limit === nothing ? (-Float32(π), Float32(π)) : Float32.(deg2rad.(s.limit))
        _jpoke!(settings, T, :mLimitsMin, lo); _jpoke!(settings, T, :mLimitsMax, hi)
        # bullet3's motor strength is an impulse per step: as a torque, ÷ dt
        _jpoke!(settings, T, :mMotorSettings, _jmotor(s.motor === nothing ? 0f0 : Float32(s.motor[2] / w.dt)))
        create = J.JPH_HingeConstraintSettings_Create
    elseif s.kind == :slider
        T = J.SliderConstraintSettings; settings = _jcsettings(T)
        ax = _jv(s.axis); nrm = _jv(_jperp(s.axis))
        for f in (:mPoint1, :mPoint2); _jpoke!(settings, T, f, pivot); end
        for f in (:mSliderAxis1, :mSliderAxis2); _jpoke!(settings, T, f, ax); end
        for f in (:mNormalAxis1, :mNormalAxis2); _jpoke!(settings, T, f, nrm); end
        lo, hi = s.limit === nothing ? (-floatmax(Float32), floatmax(Float32)) : Float32.(s.limit)
        _jpoke!(settings, T, :mLimitsMin, lo); _jpoke!(settings, T, :mLimitsMax, hi)
        _jpoke!(settings, T, :mMotorSettings, _jmotor(s.motor === nothing ? 0f0 : Float32(s.motor[2])))
        create = J.JPH_SliderConstraintSettings_Create
    elseif s.kind == :fixed
        T = J.FixedConstraintSettings; settings = _jcsettings(T)
        for f in (:mPoint1, :mPoint2); _jpoke!(settings, T, f, pivot); end
        for f in (:mAxisX1, :mAxisX2); _jpoke!(settings, T, f, X); end
        for f in (:mAxisY1, :mAxisY2); _jpoke!(settings, T, f, Y); end
        create = J.JPH_FixedConstraintSettings_Create
    elseif s.kind == :spring
        T = J.SixDOFConstraintSettings; settings = _jcsettings(T)
        for f in (:mPosition1, :mPosition2); _jpoke!(settings, T, f, pivot); end
        for f in (:mAxisX1, :mAxisX2); _jpoke!(settings, T, f, X); end
        for f in (:mAxisY1, :mAxisY2); _jpoke!(settings, T, f, Y); end
        for ax in 0:2; J.JPH_SixDOFConstraintSettings_MakeFreeAxis(settings, J.EAxis(UInt32(ax))); end
        for ax in 3:5; J.JPH_SixDOFConstraintSettings_MakeFixedAxis(settings, J.EAxis(UInt32(ax))); end
        create = J.JPH_SixDOFConstraintSettings_Create
    else
        error("ObjectSim: unknown joint type $(s.kind)")
    end
    c = try
        Ptr{Cvoid}(create(settings, body1, body2))
    finally
        Libc.free(settings)
    end
    c == C_NULL && error("ObjectSim: Jolt could not make joint '$(s.name)'")
    J.JPH_PhysicsSystem_AddConstraint(P.ps, c)
    if s.motor !== nothing
        if s.kind == :hinge
            J.JPH_HingeConstraint_SetMotorState(c, J.EMotorState(1))              # Velocity
            J.JPH_HingeConstraint_SetTargetAngularVelocity(c, Float32(deg2rad(s.motor[1])))
        elseif s.kind == :slider
            J.JPH_SliderConstraint_SetMotorState(c, J.EMotorState(1))
            J.JPH_SliderConstraint_SetTargetVelocity(c, Float32(s.motor[1]))
        end
    end
    s.collide || b === nothing || _jno_collide!(P, a, b)
    layout = Dict(:point => J.PointConstraint, :hinge => J.HingeConstraint, :slider => J.SliderConstraint,
                  :fixed => J.FixedConstraint, :spring => J.SixDOFConstraint)[s.kind]
    return JoltJoint(P, c, layout)
end

# ── joined bodies that should not collide ───────────────────────────────────

const _J_GROUPS = IdDict{JoltPhysics,Any}()      # P → (table, Dict{Body,UInt32})

function _jno_collide!(P::JoltPhysics, a::Body, b::Body)
    (isstatic(a) && isstatic(b)) && return
    table, sub = get!(_J_GROUPS, P) do
        t = _jnew(:GroupFilterTable, J.JPH_GroupFilterTable_GroupFilterTable, _J_SUBGROUPS)
        rc = Ptr{UInt32}(Ptr{UInt8}(t) + _joff(J.GroupFilterTable, :mRefCount))
        unsafe_store!(rc, UInt32(1))                 # ours: bodies come and go, the table stays
        (Ptr{Cvoid}(t), IdDict{Body,UInt32}())
    end
    for x in (a, b)
        haskey(sub, x) && continue
        length(sub) < _J_SUBGROUPS || error("ObjectSim: too many jointed bodies for the Jolt backend ($_J_SUBGROUPS)")
        sub[x] = UInt32(length(sub))
        group = J.CollisionGroup(J.RefConst_JPH_GroupFilter(Ptr{J.GroupFilter}(table)), UInt32(0), sub[x])
        J.JPH_BodyInterface_SetCollisionGroup(P.bi, Ref(_jh(x).id), Ref(group))
    end
    J.JPH_GroupFilterTable_DisableCollision(table, sub[a], sub[b])
end

function _jfree_groups!(P::JoltPhysics)
    g = pop!(_J_GROUPS, P, nothing)
    g === nothing && return
    _jdelete(:GroupFilterTable, g[1])                # bodies are gone: ours was the last reference
end

# ── after each step: breakable joints ───────────────────────────────────────

const _J_ENABLED = _joff(J.Constraint, :mEnabled)

function _jbreak_joints!(P::JoltPhysics, w::World)
    for j in w.joints
        j = j::Joint
        (j.h === nothing || !isfinite(j.break_impulse)) && continue
        h = _jj(j)
        hasfield(h.T, :mPointConstraintPart) || continue
        unsafe_load(Ptr{Bool}(h.ptr + _J_ENABLED)) || continue
        λ = _jxyz(h.ptr + _joff(h.T, :mPointConstraintPart) + _joff(J.PointConstraintPart, :mTotalLambda))
        vnorm(λ) > j.break_impulse && unsafe_store!(Ptr{Bool}(h.ptr + _J_ENABLED), false)
    end
end

function _be_free_joint!(P::JoltPhysics, w::World, j::Joint)
    J.JPH_PhysicsSystem_RemoveConstraint(P.ps, _jj(j).ptr)   # drops the last reference: freed
    _jj(j).ptr = C_NULL
end

_be_broken(::JoltPhysics, j::Joint) = !unsafe_load(Ptr{Bool}(_jj(j).ptr + _J_ENABLED))

function _be_set_motor!(::JoltPhysics, j::Joint, factor)
    if j.kind == :hinge
        J.JPH_HingeConstraint_SetTargetAngularVelocity(_jj(j).ptr, Float32(deg2rad(j.motor[1]) * factor))
    elseif j.kind == :slider
        J.JPH_SliderConstraint_SetTargetVelocity(_jj(j).ptr, Float32(j.motor[1] * factor))
    end
end

# ── picking: Jolt's own way, a point constraint to the world ────────────────
# Body 1 is Body::sFixedToWorld, whose frame is the world's, so the
# constraint's first anchor is a world point; dragging moves it there and
# Jolt's position solver pulls the held point after it.

const _J_PICK_ANCHOR = _joff(J.PointConstraint, :mLocalSpacePosition1)

function _be_grab!(P::JoltPhysics, w::World, b::Body, local_point, world_point)
    T = J.PointConstraintSettings
    settings = _jcsettings(T)
    _jpoke!(settings, T, :mPoint1, _jv(world_point)); _jpoke!(settings, T, :mPoint2, _jv(world_point))
    c = try
        Ptr{Cvoid}(J.JPH_PointConstraintSettings_Create(settings, _jfixed_to_world(), Ptr{J.Body}(_jh(b).ptr)))
    finally
        Libc.free(settings)
    end
    J.JPH_PhysicsSystem_AddConstraint(P.ps, c)
    return c
end

function _be_drag!(P::JoltPhysics, w::World, p, point)
    unsafe_store!(Ptr{J.Vec3}(p.h + _J_PICK_ANCHOR), _jv(point))
    _be_wake!(P, p.body)
end

_be_release!(P::JoltPhysics, w::World, p) = J.JPH_PhysicsSystem_RemoveConstraint(P.ps, p.h)
