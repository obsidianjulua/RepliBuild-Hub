# The bullet3 backend: constraints and the mouse picker.
#
#   point   btPoint2PointConstraint
#   hinge   btHingeConstraint
#   slider  btSliderConstraint
#   fixed   btFixedConstraint
#   spring  btGeneric6DofSpring2Constraint with free translation and locked
#           turning (the pull is ObjectSim's own, see src/joints.jl)
#
# Limits, motors and break thresholds go through bullet3's own setters
# (setLimit, enableAngularMotor, setBreakingImpulseThreshold, …): inline in its
# headers, defined by the build since RepliBuild.jl #108. C++ default arguments
# do not carry over, so each call spells them out. The picking constraint's
# m_setting is a public member C++ code writes directly, and so does this.

const _OFF_P2P_SET   = B.member_offset(:btPoint2PointConstraint, :m_setting)
const _OFF_SET_TAU   = B.member_offset(:btConstraintSetting, :m_tau)
const _OFF_SET_CLAMP = B.member_offset(:btConstraintSetting, :m_impulseClamp)

const _BT_JOINT_CLASS = Dict(:point => :btPoint2PointConstraint, :hinge => :btHingeConstraint,
                             :slider => :btSliderConstraint, :fixed => :btFixedConstraint,
                             :spring => :btGeneric6DofSpring2Constraint)

"""A joint in the bullet3 backend: the btTypedConstraint and its class."""
mutable struct Bullet3Joint
    phys::Bullet3Physics
    ptr::Ptr{Cvoid}
    cls::Symbol
end

_bt_rb(b::Body) = Ptr{B.btRigidBody}(_rbp(b))
_bt_transform(rows, o) = B.btTransform(B.btMatrix3x3((_btv(rows[1]), _btv(rows[2]), _btv(rows[3]))), _btv(o))
# The world frame (rows F, origin p) expressed in body b's frame.
_bt_local_frame(b::Body, F, p) = _bt_transform(_matmul(_transpose(transform(b)[1]), F), _to_local(b, p))

function _be_add_joint!(P::Bullet3Physics, w::World, s::JointSpec, j::Joint)
    a, b, pa, pb = j.a, j.b, j.pivot_a, j.pivot_b
    cls = _BT_JOINT_CLASS[s.kind]
    c = _alloc(cls)
    if s.kind == :point
        b === nothing ? B.btPoint2PointConstraint_btPoint2PointConstraint(c, _bt_rb(a), Ref(_btv(pa))) :
            B.btPoint2PointConstraint_btPoint2PointConstraint(c, _bt_rb(a), _bt_rb(b), Ref(_btv(pa)), Ref(_btv(pb)))
    elseif s.kind == :hinge
        ax = _dir_to_local(a, s.axis)
        if b === nothing
            B.btHingeConstraint_btHingeConstraint(c, _bt_rb(a), Ref(_btv(pa)), Ref(_btv(ax)), false)
        else
            B.btHingeConstraint_btHingeConstraint(c, _bt_rb(a), _bt_rb(b), Ref(_btv(pa)), Ref(_btv(pb)),
                Ref(_btv(ax)), Ref(_btv(_dir_to_local(b, s.axis))), false)
        end
        if s.limit !== nothing      # softness 0.9, bias 0.3, relaxation 1.0: the C++ defaults
            B.btHingeConstraint_setLimit(c, deg2rad(s.limit[1]), deg2rad(s.limit[2]), 0.9f0, 0.3f0, 1.0f0)
        end
        s.motor === nothing ||
            B.btHingeConstraint_enableAngularMotor(c, true, Float32(deg2rad(s.motor[1])), Float32(s.motor[2]))
    elseif s.kind == :slider
        F = _frame_rows(s.axis)
        if b === nothing            # slides along the axis relative to the world
            B.btSliderConstraint_btSliderConstraint(c, _bt_rb(a), Ref(_bt_local_frame(a, F, s.pivot)), true)
        else
            B.btSliderConstraint_btSliderConstraint(c, _bt_rb(a), _bt_rb(b), Ref(_bt_local_frame(a, F, s.pivot)),
                Ref(_bt_local_frame(b, F, s.pivot)), true)
        end
        lo, hi = s.limit === nothing ? (1f0, -1f0) : Float32.(s.limit)   # lo > hi: free
        B.btSliderConstraint_setLowerLinLimit(c, lo)
        B.btSliderConstraint_setUpperLinLimit(c, hi)
        if s.motor !== nothing
            B.btSliderConstraint_setPoweredLinMotor(c, true)
            B.btSliderConstraint_setTargetLinMotorVelocity(c, Float32(s.motor[1]))
            B.btSliderConstraint_setMaxLinMotorForce(c, Float32(s.motor[2]))
        end
    elseif s.kind == :fixed
        F = ((1f0, 0f0, 0f0), (0f0, 1f0, 0f0), (0f0, 0f0, 1f0))
        B.btFixedConstraint_btFixedConstraint(c, _bt_rb(a), _bt_rb(b), Ref(_bt_local_frame(a, F, s.pivot)),
            Ref(_bt_local_frame(b, F, s.pivot)))
    elseif s.kind == :spring
        F = ((1f0, 0f0, 0f0), (0f0, 1f0, 0f0), (0f0, 0f0, 1f0))
        if b === nothing
            B.btGeneric6DofSpring2Constraint_btGeneric6DofSpring2Constraint(c, _bt_rb(a),
                Ref(_bt_local_frame(a, F, s.pivot)), B.RO_XYZ)
        else
            B.btGeneric6DofSpring2Constraint_btGeneric6DofSpring2Constraint(c, _bt_rb(a), _bt_rb(b),
                Ref(_bt_local_frame(a, F, s.pivot)), Ref(_bt_local_frame(b, F, s.pivot)), B.RO_XYZ)
        end
        # Free translation (lower > upper) and locked turning.
        B.btGeneric6DofSpring2Constraint_setLinearLowerLimit(c, Ref(_btv((1, 1, 1))))
        B.btGeneric6DofSpring2Constraint_setLinearUpperLimit(c, Ref(_btv((-1, -1, -1))))
    end
    isfinite(s.break_impulse) && B.btTypedConstraint_setBreakingImpulseThreshold(c, s.break_impulse)
    B.btDiscreteDynamicsWorld_addConstraint(P.world, c, !s.collide)
    return Bullet3Joint(P, c, cls)
end

function _be_free_joint!(P::Bullet3Physics, w::World, j::Joint)
    B.btDiscreteDynamicsWorld_removeConstraint(P.world, (j.h::Bullet3Joint).ptr)
    _delete((j.h::Bullet3Joint).cls, (j.h::Bullet3Joint).ptr)          # deleting destructor: frees too
    (j.h::Bullet3Joint).ptr = C_NULL
end

_be_broken(::Bullet3Physics, j::Joint) = !B.btTypedConstraint_isEnabled((j.h::Bullet3Joint).ptr)

function _be_set_motor!(::Bullet3Physics, j::Joint, factor)
    if j.kind == :hinge
        B.btHingeConstraint_enableAngularMotor((j.h::Bullet3Joint).ptr, true, Float32(deg2rad(j.motor[1]) * factor), j.motor[2])
    elseif j.kind == :slider
        B.btSliderConstraint_setTargetLinMotorVelocity((j.h::Bullet3Joint).ptr, Float32(j.motor[1] * factor))
    end
end

# ── picking: a point-to-point constraint to the world, its pivot B moved ─────

function _be_grab!(P::Bullet3Physics, w::World, b::Body, local_point, world_point)
    c = _alloc(:btPoint2PointConstraint)
    B.btPoint2PointConstraint_btPoint2PointConstraint(c, _bt_rb(b), Ref(_btv(local_point)))
    # Bullet's demo values: a firm pull with the impulse per step capped, so a
    # held body can still be blocked by heavy things instead of tunnelling.
    unsafe_store!(Ptr{Float32}(c + _OFF_P2P_SET + _OFF_SET_TAU), 0.6f0)
    unsafe_store!(Ptr{Float32}(c + _OFF_P2P_SET + _OFF_SET_CLAMP), 30f0 * max(1f0, mass(b)))
    B.btDiscreteDynamicsWorld_addConstraint(P.world, c, true)
    return c
end

_be_drag!(::Bullet3Physics, w::World, p, point) = B.btPoint2PointConstraint_setPivotB(p.h, Ref(_btv(point)))

function _be_release!(P::Bullet3Physics, w::World, p)
    B.btDiscreteDynamicsWorld_removeConstraint(P.world, p.h)
    _delete(:btPoint2PointConstraint, p.h)
end
