# Auto-generated Julia wrapper for box2d
# Generated: 2026-07-19 12:49:54
# Generator: RepliBuild Wrapper (Introspective: DWARF metadata)
# Library: libbox2d.so
# Metadata: compilation_metadata.json

module Box2d

const Cintptr_t = Int
const Cuintptr_t = UInt

using Libdl
import RepliBuild
import Base: unsafe_convert

# Resolve the library next to this file first: build artifacts travel as a
# unit (wrapper + .so side by side, e.g. in ~/.replibuild/builds/<hash>/),
# so the sibling copy is the one that belongs to this wrapper. The
# generation-time absolute path is only a fallback — shared dirs like
# ~/.replibuild/registry/julia/ get overwritten by later builds, stranding
# any wrapper that baked them in.
const LIBRARY_PATH = let baked = "/home/john/Desktop/Projects/RepliBuild-Hub/packages/box2d/julia/libbox2d.so"
    sibling = joinpath(@__DIR__, basename(baked))
    isfile(sibling) ? sibling : baked
end
const THUNKS_LIBRARY_PATH = let baked = ""
    sibling = isempty(baked) ? "" : joinpath(@__DIR__, basename(baked))
    !isempty(sibling) && isfile(sibling) ? sibling : baked
end

# Verify library exists
if !isfile(LIBRARY_PATH)
    error("Library not found: $LIBRARY_PATH (no sibling copy in $(@__DIR__) either)")
end

# Flush C stdout so printf output appears immediately in the Julia REPL
@inline _flush_cstdout() = ccall(:fflush, Cint, (Ptr{Cvoid},), C_NULL)

function __init__()
    # Initialize this library's JIT engine (one engine per binary)
    RepliBuild.JITManager.initialize_global_jit(LIBRARY_PATH)
# Unbuffer C stdout so printf output appears immediately in the REPL
let c_stdout = unsafe_load(cglobal(:stdout, Ptr{Cvoid}))
    ccall(:setvbuf, Cint, (Ptr{Cvoid}, Ptr{Cvoid}, Cint, Csize_t), c_stdout, C_NULL, 2, 0)
end
end
# =============================================================================
# Compilation Metadata
# =============================================================================

const METADATA = Dict(
    "llvm_version" => "22.1.6",
    "clang_version" => "clang version 22.1.6",
    "optimization" => "2",
    "target_triple" => "x86_64-pc-linux-gnu",
    "function_count" => 518,
    "generated_at" => "2026-07-17T21:40:33.994"
)

const LTO_IR = ""  # LTO disabled for this build
const THUNKS_LTO_IR = ""

# =============================================================================
# Enum Definitions (from DWARF debug info)
# =============================================================================

# C++ enum: State (underlying type: unsigned int)
@enum State::Cuint begin
    e_unknown = 0
    e_failed = 1
    e_overlapped = 2
    e_touching = 3
    e_separated = 4
end

# C++ enum: c_Type (underlying type: unsigned int)
@enum c_Type::Cuint begin
    e_circle = 0
    e_edge = 1
    e_polygon = 2
    e_chain = 3
    e_typeCount = 4
end

# C++ enum: b2BendingModel (underlying type: unsigned int)
@enum b2BendingModel::Cuint begin
    b2_springAngleBendingModel = 0
    b2_pbdAngleBendingModel = 1
    b2_xpbdAngleBendingModel = 2
    b2_pbdDistanceBendingModel = 3
    b2_pbdHeightBendingModel = 4
    b2_pbdTriangleBendingModel = 5
end

# C++ enum: b2BodyType (underlying type: unsigned int)
@enum b2BodyType::Cuint begin
    b2_staticBody = 0
    b2_kinematicBody = 1
    b2_dynamicBody = 2
end

# C++ enum: b2JointType (underlying type: unsigned int)
@enum b2JointType::Cuint begin
    e_unknownJoint = 0
    e_revoluteJoint = 1
    e_prismaticJoint = 2
    e_distanceJoint = 3
    e_pulleyJoint = 4
    e_mouseJoint = 5
    e_gearJoint = 6
    e_wheelJoint = 7
    e_weldJoint = 8
    e_frictionJoint = 9
    e_ropeJoint = 10
    e_motorJoint = 11
end

# C++ enum: b2PointState (underlying type: unsigned int)
@enum b2PointState::Cuint begin
    b2_nullState = 0
    b2_addState = 1
    b2_persistState = 2
    b2_removeState = 3
end

# C++ enum: b2StretchingModel (underlying type: unsigned int)
@enum b2StretchingModel::Cuint begin
    b2_pbdStretchingModel = 0
    b2_xpbdStretchingModel = 1
end


# =============================================================================
# Forward Declarations (Opaque + Ptr-referenced types)
# =============================================================================

struct Ptr_b2Block end
struct c_Type end
struct b2ChainAndCircleContact end
struct b2ChainAndPolygonContact end
struct b2CircleContact end
struct b2EdgeAndCircleContact end
struct b2EdgeAndPolygonContact end
struct b2PolygonAndCircleContact end
struct b2PolygonContact end

# =============================================================================
# Struct Definitions (from DWARF debug info)
# =============================================================================

# C++ struct: b2Block (1 members)
struct b2Block
    next::Ptr{b2Block}
end

# Zero-initializer for b2Block
function b2Block()
    ref = Ref{b2Block}()
    GC.@preserve ref begin
        ccall(:memset, Ptr{Cvoid}, (Ptr{Cvoid}, Cint, Csize_t), Base.unsafe_convert(Ptr{Cvoid}, ref), 0, sizeof(b2Block))
    end
    return ref[]
end

# C++ struct: b2BodyUserData (1 members)
struct b2BodyUserData
    pointer::Cuintptr_t
end

# Zero-initializer for b2BodyUserData
function b2BodyUserData()
    ref = Ref{b2BodyUserData}()
    GC.@preserve ref begin
        ccall(:memset, Ptr{Cvoid}, (Ptr{Cvoid}, Cint, Csize_t), Base.unsafe_convert(Ptr{Cvoid}, ref), 0, sizeof(b2BodyUserData))
    end
    return ref[]
end

# C++ struct: b2Color (4 members)
struct b2Color
    r::Cfloat
    g::Cfloat
    b::Cfloat
    a::Cfloat
end

# Zero-initializer for b2Color
function b2Color()
    ref = Ref{b2Color}()
    GC.@preserve ref begin
        ccall(:memset, Ptr{Cvoid}, (Ptr{Cvoid}, Cint, Csize_t), Base.unsafe_convert(Ptr{Cvoid}, ref), 0, sizeof(b2Color))
    end
    return ref[]
end

# C++ struct: b2ContactFeature (4 members)
struct b2ContactFeature
    indexA::UInt8
    indexB::UInt8
    typeA::UInt8
    typeB::UInt8
end

# Zero-initializer for b2ContactFeature
function b2ContactFeature()
    ref = Ref{b2ContactFeature}()
    GC.@preserve ref begin
        ccall(:memset, Ptr{Cvoid}, (Ptr{Cvoid}, Cint, Csize_t), Base.unsafe_convert(Ptr{Cvoid}, ref), 0, sizeof(b2ContactFeature))
    end
    return ref[]
end

# C++ struct: b2ContactFilter (1 members)
struct b2ContactFilter
    _vptr_b2ContactFilter::Ptr{Cvoid}
end

# Zero-initializer for b2ContactFilter
function b2ContactFilter()
    ref = Ref{b2ContactFilter}()
    GC.@preserve ref begin
        ccall(:memset, Ptr{Cvoid}, (Ptr{Cvoid}, Cint, Csize_t), Base.unsafe_convert(Ptr{Cvoid}, ref), 0, sizeof(b2ContactFilter))
    end
    return ref[]
end

# C++ struct: b2ContactImpulse (3 members, byte blob for ABI safety)
struct b2ContactImpulse
    _data::NTuple{20, UInt8}
end

# Zero-initializer for b2ContactImpulse
function b2ContactImpulse()
    return b2ContactImpulse(ntuple(i -> 0x00, 20))
end

function Base.getproperty(x::b2ContactImpulse, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :count
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 16))
end
    error("type b2ContactImpulse has no field $s")
end

# C++ struct: b2ContactListener (1 members)
struct b2ContactListener
    _vptr_b2ContactListener::Ptr{Cvoid}
end

# Zero-initializer for b2ContactListener
function b2ContactListener()
    ref = Ref{b2ContactListener}()
    GC.@preserve ref begin
        ccall(:memset, Ptr{Cvoid}, (Ptr{Cvoid}, Cint, Csize_t), Base.unsafe_convert(Ptr{Cvoid}, ref), 0, sizeof(b2ContactListener))
    end
    return ref[]
end

# C++ struct: b2ContactRegister (3 members)
struct b2ContactRegister
    createFcn::Ptr{Cvoid}
    destroyFcn::Ptr{Cvoid}
    primary::Bool
    _pad_tail::NTuple{7, UInt8}
end

# Zero-initializer for b2ContactRegister
function b2ContactRegister()
    ref = Ref{b2ContactRegister}()
    GC.@preserve ref begin
        ccall(:memset, Ptr{Cvoid}, (Ptr{Cvoid}, Cint, Csize_t), Base.unsafe_convert(Ptr{Cvoid}, ref), 0, sizeof(b2ContactRegister))
    end
    return ref[]
end

# C++ struct: b2DestructionListener (1 members)
struct b2DestructionListener
    _vptr_b2DestructionListener::Ptr{Cvoid}
end

# Zero-initializer for b2DestructionListener
function b2DestructionListener()
    ref = Ref{b2DestructionListener}()
    GC.@preserve ref begin
        ccall(:memset, Ptr{Cvoid}, (Ptr{Cvoid}, Cint, Csize_t), Base.unsafe_convert(Ptr{Cvoid}, ref), 0, sizeof(b2DestructionListener))
    end
    return ref[]
end

# C++ struct: b2Draw (2 members)
struct b2Draw
    _vptr_b2Draw::Ptr{Cvoid}
    m_drawFlags::Cuint
    _pad_tail::NTuple{4, UInt8}
end

# Zero-initializer for b2Draw
function b2Draw()
    ref = Ref{b2Draw}()
    GC.@preserve ref begin
        ccall(:memset, Ptr{Cvoid}, (Ptr{Cvoid}, Cint, Csize_t), Base.unsafe_convert(Ptr{Cvoid}, ref), 0, sizeof(b2Draw))
    end
    return ref[]
end

# C++ struct: b2Filter (3 members)
struct b2Filter
    categoryBits::Cushort
    maskBits::Cushort
    groupIndex::Cshort
end

# Zero-initializer for b2Filter
function b2Filter()
    ref = Ref{b2Filter}()
    GC.@preserve ref begin
        ccall(:memset, Ptr{Cvoid}, (Ptr{Cvoid}, Cint, Csize_t), Base.unsafe_convert(Ptr{Cvoid}, ref), 0, sizeof(b2Filter))
    end
    return ref[]
end

# C++ struct: b2FixtureUserData (1 members)
struct b2FixtureUserData
    pointer::Cuintptr_t
end

# Zero-initializer for b2FixtureUserData
function b2FixtureUserData()
    ref = Ref{b2FixtureUserData}()
    GC.@preserve ref begin
        ccall(:memset, Ptr{Cvoid}, (Ptr{Cvoid}, Cint, Csize_t), Base.unsafe_convert(Ptr{Cvoid}, ref), 0, sizeof(b2FixtureUserData))
    end
    return ref[]
end

# C++ struct: b2GrowableStack<int, 256> (4 members, byte blob for ABI safety)
struct b2GrowableStack_int_256
    _data::NTuple{1040, UInt8}
end

# Zero-initializer for b2GrowableStack_int_256
function b2GrowableStack_int_256()
    return b2GrowableStack_int_256(ntuple(i -> 0x00, 1040))
end

function Base.getproperty(x::b2GrowableStack_int_256, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :m_stack
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 0))
end
if s === :m_count
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 1032))
end
if s === :m_capacity
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 1036))
end
    error("type b2GrowableStack_int_256 has no field $s")
end

# C++ struct: b2JointUserData (1 members)
struct b2JointUserData
    pointer::Cuintptr_t
end

# Zero-initializer for b2JointUserData
function b2JointUserData()
    ref = Ref{b2JointUserData}()
    GC.@preserve ref begin
        ccall(:memset, Ptr{Cvoid}, (Ptr{Cvoid}, Cint, Csize_t), Base.unsafe_convert(Ptr{Cvoid}, ref), 0, sizeof(b2JointUserData))
    end
    return ref[]
end

# C++ struct: b2Pair (2 members)
struct b2Pair
    proxyIdA::Cint
    proxyIdB::Cint
end

# Zero-initializer for b2Pair
function b2Pair()
    ref = Ref{b2Pair}()
    GC.@preserve ref begin
        ccall(:memset, Ptr{Cvoid}, (Ptr{Cvoid}, Cint, Csize_t), Base.unsafe_convert(Ptr{Cvoid}, ref), 0, sizeof(b2Pair))
    end
    return ref[]
end

# C++ struct: b2Profile (8 members)
struct b2Profile
    step::Cfloat
    collide::Cfloat
    solve::Cfloat
    solveInit::Cfloat
    solveVelocity::Cfloat
    solvePosition::Cfloat
    broadphase::Cfloat
    solveTOI::Cfloat
end

# Zero-initializer for b2Profile
function b2Profile()
    ref = Ref{b2Profile}()
    GC.@preserve ref begin
        ccall(:memset, Ptr{Cvoid}, (Ptr{Cvoid}, Cint, Csize_t), Base.unsafe_convert(Ptr{Cvoid}, ref), 0, sizeof(b2Profile))
    end
    return ref[]
end

# C++ struct: b2QueryCallback (1 members)
struct b2QueryCallback
    _vptr_b2QueryCallback::Ptr{Cvoid}
end

# Zero-initializer for b2QueryCallback
function b2QueryCallback()
    ref = Ref{b2QueryCallback}()
    GC.@preserve ref begin
        ccall(:memset, Ptr{Cvoid}, (Ptr{Cvoid}, Cint, Csize_t), Base.unsafe_convert(Ptr{Cvoid}, ref), 0, sizeof(b2QueryCallback))
    end
    return ref[]
end

# C++ struct: b2RayCastCallback (1 members)
struct b2RayCastCallback
    _vptr_b2RayCastCallback::Ptr{Cvoid}
end

# Zero-initializer for b2RayCastCallback
function b2RayCastCallback()
    ref = Ref{b2RayCastCallback}()
    GC.@preserve ref begin
        ccall(:memset, Ptr{Cvoid}, (Ptr{Cvoid}, Cint, Csize_t), Base.unsafe_convert(Ptr{Cvoid}, ref), 0, sizeof(b2RayCastCallback))
    end
    return ref[]
end

# C++ struct: b2RopeBend (14 members)
struct b2RopeBend
    i1::Cint
    i2::Cint
    i3::Cint
    invMass1::Cfloat
    invMass2::Cfloat
    invMass3::Cfloat
    invEffectiveMass::Cfloat
    lambda::Cfloat
    L1::Cfloat
    L2::Cfloat
    alpha1::Cfloat
    alpha2::Cfloat
    spring::Cfloat
    damper::Cfloat
end

# Zero-initializer for b2RopeBend
function b2RopeBend()
    ref = Ref{b2RopeBend}()
    GC.@preserve ref begin
        ccall(:memset, Ptr{Cvoid}, (Ptr{Cvoid}, Cint, Csize_t), Base.unsafe_convert(Ptr{Cvoid}, ref), 0, sizeof(b2RopeBend))
    end
    return ref[]
end

# C++ struct: b2RopeStretch (8 members)
struct b2RopeStretch
    i1::Cint
    i2::Cint
    invMass1::Cfloat
    invMass2::Cfloat
    L::Cfloat
    lambda::Cfloat
    spring::Cfloat
    damper::Cfloat
end

# Zero-initializer for b2RopeStretch
function b2RopeStretch()
    ref = Ref{b2RopeStretch}()
    GC.@preserve ref begin
        ccall(:memset, Ptr{Cvoid}, (Ptr{Cvoid}, Cint, Csize_t), Base.unsafe_convert(Ptr{Cvoid}, ref), 0, sizeof(b2RopeStretch))
    end
    return ref[]
end

# C++ struct: b2RopeTuning (12 members, byte blob for ABI safety)
struct b2RopeTuning
    _data::NTuple{40, UInt8}
end

# Zero-initializer for b2RopeTuning
function b2RopeTuning()
    return b2RopeTuning(ntuple(i -> 0x00, 40))
end

function Base.getproperty(x::b2RopeTuning, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :damping
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 8))
end
if s === :stretchStiffness
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 12))
end
if s === :stretchHertz
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 16))
end
if s === :stretchDamping
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 20))
end
if s === :bendStiffness
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 24))
end
if s === :bendHertz
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 28))
end
if s === :bendDamping
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 32))
end
if s === :isometric
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 36))
end
if s === :fixedEffectiveMass
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 37))
end
if s === :warmStart
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 38))
end
    error("type b2RopeTuning has no field $s")
end

# C++ struct: b2Rot (2 members)
struct b2Rot
    s::Cfloat
    c::Cfloat
end

# Zero-initializer for b2Rot
function b2Rot()
    ref = Ref{b2Rot}()
    GC.@preserve ref begin
        ccall(:memset, Ptr{Cvoid}, (Ptr{Cvoid}, Cint, Csize_t), Base.unsafe_convert(Ptr{Cvoid}, ref), 0, sizeof(b2Rot))
    end
    return ref[]
end

# C++ struct: b2Shape (3 members, byte blob for ABI safety)
struct b2Shape
    _data::NTuple{16, UInt8}
end

# Zero-initializer for b2Shape
function b2Shape()
    return b2Shape(ntuple(i -> 0x00, 16))
end

function Base.getproperty(x::b2Shape, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :_vptr$b2Shape
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 0))
end
if s === :m_radius
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 12))
end
    error("type b2Shape has no field $s")
end

# C++ struct: b2SimplexCache (4 members, byte blob for ABI safety)
struct b2SimplexCache
    _data::NTuple{12, UInt8}
end

# Zero-initializer for b2SimplexCache
function b2SimplexCache()
    return b2SimplexCache(ntuple(i -> 0x00, 12))
end

function Base.getproperty(x::b2SimplexCache, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :metric
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 0))
end
if s === :count
    return GC.@preserve x unsafe_load(Ptr{Cushort}(pointer_from_objref(Ref(x._data)) + 4))
end
    error("type b2SimplexCache has no field $s")
end

# C++ struct: b2SizeMap (1 members, byte blob for ABI safety)
struct b2SizeMap
    _data::NTuple{641, UInt8}
end

# Zero-initializer for b2SizeMap
function b2SizeMap()
    return b2SizeMap(ntuple(i -> 0x00, 641))
end

# C++ struct: b2StackEntry (3 members)
struct b2StackEntry
    data::Ptr{UInt8}
    size::Cint
    usedMalloc::Bool
    _pad_tail::NTuple{3, UInt8}
end

# Zero-initializer for b2StackEntry
function b2StackEntry()
    ref = Ref{b2StackEntry}()
    GC.@preserve ref begin
        ccall(:memset, Ptr{Cvoid}, (Ptr{Cvoid}, Cint, Csize_t), Base.unsafe_convert(Ptr{Cvoid}, ref), 0, sizeof(b2StackEntry))
    end
    return ref[]
end

# C++ struct: b2TOIOutput (2 members, byte blob for ABI safety)
struct b2TOIOutput
    _data::NTuple{8, UInt8}
end

# Zero-initializer for b2TOIOutput
function b2TOIOutput()
    return b2TOIOutput(ntuple(i -> 0x00, 8))
end

function Base.getproperty(x::b2TOIOutput, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :t
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 4))
end
    error("type b2TOIOutput has no field $s")
end

# C++ struct: b2TimeStep (6 members)
struct b2TimeStep
    dt::Cfloat
    inv_dt::Cfloat
    dtRatio::Cfloat
    velocityIterations::Cint
    positionIterations::Cint
    warmStarting::Bool
    _pad_tail::NTuple{3, UInt8}
end

# Zero-initializer for b2TimeStep
function b2TimeStep()
    ref = Ref{b2TimeStep}()
    GC.@preserve ref begin
        ccall(:memset, Ptr{Cvoid}, (Ptr{Cvoid}, Cint, Csize_t), Base.unsafe_convert(Ptr{Cvoid}, ref), 0, sizeof(b2TimeStep))
    end
    return ref[]
end

# C++ struct: b2Timer (2 members)
struct b2Timer
    m_start_sec::Culonglong
    m_start_usec::Culonglong
end

# Zero-initializer for b2Timer
function b2Timer()
    ref = Ref{b2Timer}()
    GC.@preserve ref begin
        ccall(:memset, Ptr{Cvoid}, (Ptr{Cvoid}, Cint, Csize_t), Base.unsafe_convert(Ptr{Cvoid}, ref), 0, sizeof(b2Timer))
    end
    return ref[]
end

# C++ struct: b2Vec2 (2 members)
struct b2Vec2
    x::Cfloat
    y::Cfloat
end

# Zero-initializer for b2Vec2
function b2Vec2()
    ref = Ref{b2Vec2}()
    GC.@preserve ref begin
        ccall(:memset, Ptr{Cvoid}, (Ptr{Cvoid}, Cint, Csize_t), Base.unsafe_convert(Ptr{Cvoid}, ref), 0, sizeof(b2Vec2))
    end
    return ref[]
end

# C++ struct: b2Vec3 (3 members)
struct b2Vec3
    x::Cfloat
    y::Cfloat
    z::Cfloat
end

# Zero-initializer for b2Vec3
function b2Vec3()
    ref = Ref{b2Vec3}()
    GC.@preserve ref begin
        ccall(:memset, Ptr{Cvoid}, (Ptr{Cvoid}, Cint, Csize_t), Base.unsafe_convert(Ptr{Cvoid}, ref), 0, sizeof(b2Vec3))
    end
    return ref[]
end

# C++ struct: b2Version (3 members)
struct b2Version
    major::Cint
    minor::Cint
    revision::Cint
end

# Zero-initializer for b2Version
function b2Version()
    ref = Ref{b2Version}()
    GC.@preserve ref begin
        ccall(:memset, Ptr{Cvoid}, (Ptr{Cvoid}, Cint, Csize_t), Base.unsafe_convert(Ptr{Cvoid}, ref), 0, sizeof(b2Version))
    end
    return ref[]
end

# C++ struct: timeval (2 members)
struct timeval
    tv_sec::Clong
    tv_usec::Clong
end

# Zero-initializer for timeval
function timeval()
    ref = Ref{timeval}()
    GC.@preserve ref begin
        ccall(:memset, Ptr{Cvoid}, (Ptr{Cvoid}, Cint, Csize_t), Base.unsafe_convert(Ptr{Cvoid}, ref), 0, sizeof(timeval))
    end
    return ref[]
end

# C++ struct: b2AABB (2 members, byte blob for ABI safety)
struct b2AABB
    _data::NTuple{16, UInt8}
end

# Zero-initializer for b2AABB
function b2AABB()
    return b2AABB(ntuple(i -> 0x00, 16))
end

# C++ struct: b2BodyDef (14 members, byte blob for ABI safety)
struct b2BodyDef
    _data::NTuple{64, UInt8}
end

# Zero-initializer for b2BodyDef
function b2BodyDef()
    return b2BodyDef(ntuple(i -> 0x00, 64))
end

function Base.getproperty(x::b2BodyDef, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :angle
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 12))
end
if s === :angularVelocity
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 24))
end
if s === :linearDamping
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 28))
end
if s === :angularDamping
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 32))
end
if s === :allowSleep
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 36))
end
if s === :awake
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 37))
end
if s === :fixedRotation
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 38))
end
if s === :bullet
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 39))
end
if s === :enabled
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 40))
end
if s === :gravityScale
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 56))
end
    error("type b2BodyDef has no field $s")
end

# C++ struct: b2ChainShape (7 members, byte blob for ABI safety)
struct b2ChainShape
    _data::NTuple{48, UInt8}
end

# Zero-initializer for b2ChainShape
function b2ChainShape()
    return b2ChainShape(ntuple(i -> 0x00, 48))
end

function Base.getproperty(x::b2ChainShape, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :_vptr$b2Shape
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 0))
end
if s === :m_radius
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 12))
end
if s === :m_vertices
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 16))
end
if s === :m_count
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 24))
end
    error("type b2ChainShape has no field $s")
end

# C++ struct: b2Chunk (2 members)
struct b2Chunk
    blockSize::Cint
    _pad_0::NTuple{4, UInt8}
    blocks::Ptr{b2Block}
end

# Zero-initializer for b2Chunk
function b2Chunk()
    ref = Ref{b2Chunk}()
    GC.@preserve ref begin
        ccall(:memset, Ptr{Cvoid}, (Ptr{Cvoid}, Cint, Csize_t), Base.unsafe_convert(Ptr{Cvoid}, ref), 0, sizeof(b2Chunk))
    end
    return ref[]
end

# C++ struct: b2CircleShape (4 members, byte blob for ABI safety)
struct b2CircleShape
    _data::NTuple{24, UInt8}
end

# Zero-initializer for b2CircleShape
function b2CircleShape()
    return b2CircleShape(ntuple(i -> 0x00, 24))
end

function Base.getproperty(x::b2CircleShape, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :_vptr$b2Shape
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 0))
end
if s === :m_radius
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 12))
end
    error("type b2CircleShape has no field $s")
end

# C++ struct: b2ClipVertex (2 members, byte blob for ABI safety)
struct b2ClipVertex
    _data::NTuple{12, UInt8}
end

# Zero-initializer for b2ClipVertex
function b2ClipVertex()
    return b2ClipVertex(ntuple(i -> 0x00, 12))
end

# C union: b2ContactID (size 4 bytes)
mutable struct b2ContactID
    data::NTuple{4, UInt8}
end
b2ContactID() = b2ContactID(ntuple(i -> 0x00, 4))

# C++ struct: b2ContactPositionConstraint (15 members, byte blob for ABI safety)
struct b2ContactPositionConstraint
    _data::NTuple{88, UInt8}
end

# Zero-initializer for b2ContactPositionConstraint
function b2ContactPositionConstraint()
    return b2ContactPositionConstraint(ntuple(i -> 0x00, 88))
end

function Base.getproperty(x::b2ContactPositionConstraint, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :indexA
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 32))
end
if s === :indexB
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 36))
end
if s === :invMassA
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 40))
end
if s === :invMassB
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 44))
end
if s === :invIA
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 64))
end
if s === :invIB
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 68))
end
if s === :radiusA
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 76))
end
if s === :radiusB
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 80))
end
if s === :pointCount
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 84))
end
    error("type b2ContactPositionConstraint has no field $s")
end

# C++ struct: b2DistanceJoint (38 members, byte blob for ABI safety)
struct b2DistanceJoint
    _data::NTuple{264, UInt8}
end

# Zero-initializer for b2DistanceJoint
function b2DistanceJoint()
    return b2DistanceJoint(ntuple(i -> 0x00, 264))
end

function Base.getproperty(x::b2DistanceJoint, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :_vptr$b2Joint
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 0))
end
if s === :m_prev
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 16))
end
if s === :m_next
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 24))
end
if s === :m_bodyA
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 96))
end
if s === :m_bodyB
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 104))
end
if s === :m_index
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 112))
end
if s === :m_islandFlag
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 116))
end
if s === :m_collideConnected
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 117))
end
if s === :m_stiffness
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 128))
end
if s === :m_damping
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 132))
end
if s === :m_bias
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 136))
end
if s === :m_length
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 140))
end
if s === :m_minLength
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 144))
end
if s === :m_maxLength
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 148))
end
if s === :m_gamma
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 168))
end
if s === :m_impulse
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 172))
end
if s === :m_lowerImpulse
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 176))
end
if s === :m_upperImpulse
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 180))
end
if s === :m_indexA
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 184))
end
if s === :m_indexB
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 188))
end
if s === :m_currentLength
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 232))
end
if s === :m_invMassA
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 236))
end
if s === :m_invMassB
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 240))
end
if s === :m_invIA
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 244))
end
if s === :m_invIB
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 248))
end
if s === :m_softMass
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 252))
end
if s === :m_mass
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 256))
end
    error("type b2DistanceJoint has no field $s")
end

# C++ struct: b2DistanceJointDef (12 members, byte blob for ABI safety)
struct b2DistanceJointDef
    _data::NTuple{72, UInt8}
end

# Zero-initializer for b2DistanceJointDef
function b2DistanceJointDef()
    return b2DistanceJointDef(ntuple(i -> 0x00, 72))
end

function Base.getproperty(x::b2DistanceJointDef, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :bodyA
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 16))
end
if s === :bodyB
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 24))
end
if s === :collideConnected
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 32))
end
if s === :length
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 52))
end
if s === :minLength
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 56))
end
if s === :maxLength
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 60))
end
if s === :stiffness
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 64))
end
if s === :damping
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 68))
end
    error("type b2DistanceJointDef has no field $s")
end

# C++ struct: b2DistanceOutput (4 members, byte blob for ABI safety)
struct b2DistanceOutput
    _data::NTuple{24, UInt8}
end

# Zero-initializer for b2DistanceOutput
function b2DistanceOutput()
    return b2DistanceOutput(ntuple(i -> 0x00, 24))
end

function Base.getproperty(x::b2DistanceOutput, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :distance
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 16))
end
if s === :iterations
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 20))
end
    error("type b2DistanceOutput has no field $s")
end

# C++ struct: b2DistanceProxy (4 members, byte blob for ABI safety)
struct b2DistanceProxy
    _data::NTuple{32, UInt8}
end

# Zero-initializer for b2DistanceProxy
function b2DistanceProxy()
    return b2DistanceProxy(ntuple(i -> 0x00, 32))
end

function Base.getproperty(x::b2DistanceProxy, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :m_vertices
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 16))
end
if s === :m_count
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 24))
end
if s === :m_radius
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 28))
end
    error("type b2DistanceProxy has no field $s")
end

# C++ struct: b2EPAxis (4 members, byte blob for ABI safety)
struct b2EPAxis
    _data::NTuple{20, UInt8}
end

# Zero-initializer for b2EPAxis
function b2EPAxis()
    return b2EPAxis(ntuple(i -> 0x00, 20))
end

function Base.getproperty(x::b2EPAxis, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :index
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 12))
end
if s === :separation
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 16))
end
    error("type b2EPAxis has no field $s")
end

# C++ struct: b2EdgeShape (8 members, byte blob for ABI safety)
struct b2EdgeShape
    _data::NTuple{56, UInt8}
end

# Zero-initializer for b2EdgeShape
function b2EdgeShape()
    return b2EdgeShape(ntuple(i -> 0x00, 56))
end

function Base.getproperty(x::b2EdgeShape, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :_vptr$b2Shape
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 0))
end
if s === :m_radius
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 12))
end
if s === :m_oneSided
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 48))
end
    error("type b2EdgeShape has no field $s")
end

# C++ struct: b2FixtureDef (8 members, byte blob for ABI safety)
struct b2FixtureDef
    _data::NTuple{40, UInt8}
end

# Zero-initializer for b2FixtureDef
function b2FixtureDef()
    return b2FixtureDef(ntuple(i -> 0x00, 40))
end

function Base.getproperty(x::b2FixtureDef, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :shape
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 0))
end
if s === :friction
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 16))
end
if s === :restitution
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 20))
end
if s === :restitutionThreshold
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 24))
end
if s === :density
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 28))
end
if s === :isSensor
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 32))
end
    error("type b2FixtureDef has no field $s")
end

# C++ struct: b2FrictionJointDef (9 members, byte blob for ABI safety)
struct b2FrictionJointDef
    _data::NTuple{64, UInt8}
end

# Zero-initializer for b2FrictionJointDef
function b2FrictionJointDef()
    return b2FrictionJointDef(ntuple(i -> 0x00, 64))
end

function Base.getproperty(x::b2FrictionJointDef, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :bodyA
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 16))
end
if s === :bodyB
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 24))
end
if s === :collideConnected
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 32))
end
if s === :maxForce
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 52))
end
if s === :maxTorque
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 56))
end
    error("type b2FrictionJointDef has no field $s")
end

# C++ struct: b2ManifoldPoint (4 members, byte blob for ABI safety)
struct b2ManifoldPoint
    _data::NTuple{20, UInt8}
end

# Zero-initializer for b2ManifoldPoint
function b2ManifoldPoint()
    return b2ManifoldPoint(ntuple(i -> 0x00, 20))
end

function Base.getproperty(x::b2ManifoldPoint, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :normalImpulse
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 8))
end
if s === :tangentImpulse
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 12))
end
    error("type b2ManifoldPoint has no field $s")
end

# C++ struct: b2MassData (3 members, byte blob for ABI safety)
struct b2MassData
    _data::NTuple{16, UInt8}
end

# Zero-initializer for b2MassData
function b2MassData()
    return b2MassData(ntuple(i -> 0x00, 16))
end

function Base.getproperty(x::b2MassData, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :mass
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 0))
end
if s === :I
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 12))
end
    error("type b2MassData has no field $s")
end

# C++ struct: b2Mat22 (2 members, byte blob for ABI safety)
struct b2Mat22
    _data::NTuple{16, UInt8}
end

# Zero-initializer for b2Mat22
function b2Mat22()
    return b2Mat22(ntuple(i -> 0x00, 16))
end

# C++ struct: b2Mat33 (3 members, byte blob for ABI safety)
struct b2Mat33
    _data::NTuple{36, UInt8}
end

# Zero-initializer for b2Mat33
function b2Mat33()
    return b2Mat33(ntuple(i -> 0x00, 36))
end

# C++ struct: b2MotorJointDef (10 members, byte blob for ABI safety)
struct b2MotorJointDef
    _data::NTuple{64, UInt8}
end

# Zero-initializer for b2MotorJointDef
function b2MotorJointDef()
    return b2MotorJointDef(ntuple(i -> 0x00, 64))
end

function Base.getproperty(x::b2MotorJointDef, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :bodyA
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 16))
end
if s === :bodyB
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 24))
end
if s === :collideConnected
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 32))
end
if s === :angularOffset
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 44))
end
if s === :maxForce
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 48))
end
if s === :maxTorque
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 52))
end
if s === :correctionFactor
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 56))
end
    error("type b2MotorJointDef has no field $s")
end

# C++ struct: b2MouseJointDef (9 members, byte blob for ABI safety)
struct b2MouseJointDef
    _data::NTuple{56, UInt8}
end

# Zero-initializer for b2MouseJointDef
function b2MouseJointDef()
    return b2MouseJointDef(ntuple(i -> 0x00, 56))
end

function Base.getproperty(x::b2MouseJointDef, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :bodyA
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 16))
end
if s === :bodyB
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 24))
end
if s === :collideConnected
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 32))
end
if s === :maxForce
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 44))
end
if s === :stiffness
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 48))
end
if s === :damping
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 52))
end
    error("type b2MouseJointDef has no field $s")
end

# C++ struct: b2PolygonShape (7 members, byte blob for ABI safety)
struct b2PolygonShape
    _data::NTuple{160, UInt8}
end

# Zero-initializer for b2PolygonShape
function b2PolygonShape()
    return b2PolygonShape(ntuple(i -> 0x00, 160))
end

function Base.getproperty(x::b2PolygonShape, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :_vptr$b2Shape
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 0))
end
if s === :m_radius
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 12))
end
if s === :m_count
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 152))
end
    error("type b2PolygonShape has no field $s")
end

# C++ struct: b2Position (2 members, byte blob for ABI safety)
struct b2Position
    _data::NTuple{12, UInt8}
end

# Zero-initializer for b2Position
function b2Position()
    return b2Position(ntuple(i -> 0x00, 12))
end

function Base.getproperty(x::b2Position, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :a
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 8))
end
    error("type b2Position has no field $s")
end

# C++ struct: b2PositionSolverManifold (3 members, byte blob for ABI safety)
struct b2PositionSolverManifold
    _data::NTuple{20, UInt8}
end

# Zero-initializer for b2PositionSolverManifold
function b2PositionSolverManifold()
    return b2PositionSolverManifold(ntuple(i -> 0x00, 20))
end

function Base.getproperty(x::b2PositionSolverManifold, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :separation
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 16))
end
    error("type b2PositionSolverManifold has no field $s")
end

# C++ struct: b2PrismaticJointDef (15 members, byte blob for ABI safety)
struct b2PrismaticJointDef
    _data::NTuple{88, UInt8}
end

# Zero-initializer for b2PrismaticJointDef
function b2PrismaticJointDef()
    return b2PrismaticJointDef(ntuple(i -> 0x00, 88))
end

function Base.getproperty(x::b2PrismaticJointDef, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :bodyA
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 16))
end
if s === :bodyB
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 24))
end
if s === :collideConnected
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 32))
end
if s === :referenceAngle
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 60))
end
if s === :enableLimit
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 64))
end
if s === :lowerTranslation
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 68))
end
if s === :upperTranslation
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 72))
end
if s === :enableMotor
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 76))
end
if s === :maxMotorForce
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 80))
end
if s === :motorSpeed
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 84))
end
    error("type b2PrismaticJointDef has no field $s")
end

# C++ struct: b2PulleyJoint (34 members, byte blob for ABI safety)
struct b2PulleyJoint
    _data::NTuple{256, UInt8}
end

# Zero-initializer for b2PulleyJoint
function b2PulleyJoint()
    return b2PulleyJoint(ntuple(i -> 0x00, 256))
end

function Base.getproperty(x::b2PulleyJoint, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :_vptr$b2Joint
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 0))
end
if s === :m_prev
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 16))
end
if s === :m_next
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 24))
end
if s === :m_bodyA
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 96))
end
if s === :m_bodyB
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 104))
end
if s === :m_index
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 112))
end
if s === :m_islandFlag
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 116))
end
if s === :m_collideConnected
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 117))
end
if s === :m_lengthA
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 144))
end
if s === :m_lengthB
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 148))
end
if s === :m_constant
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 168))
end
if s === :m_ratio
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 172))
end
if s === :m_impulse
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 176))
end
if s === :m_indexA
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 180))
end
if s === :m_indexB
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 184))
end
if s === :m_invMassA
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 236))
end
if s === :m_invMassB
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 240))
end
if s === :m_invIA
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 244))
end
if s === :m_invIB
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 248))
end
if s === :m_mass
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 252))
end
    error("type b2PulleyJoint has no field $s")
end

# C++ struct: b2PulleyJointDef (12 members, byte blob for ABI safety)
struct b2PulleyJointDef
    _data::NTuple{80, UInt8}
end

# Zero-initializer for b2PulleyJointDef
function b2PulleyJointDef()
    return b2PulleyJointDef(ntuple(i -> 0x00, 80))
end

function Base.getproperty(x::b2PulleyJointDef, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :bodyA
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 16))
end
if s === :bodyB
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 24))
end
if s === :collideConnected
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 32))
end
if s === :lengthA
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 68))
end
if s === :lengthB
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 72))
end
if s === :ratio
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 76))
end
    error("type b2PulleyJointDef has no field $s")
end

# C++ struct: b2RayCastInput (3 members, byte blob for ABI safety)
struct b2RayCastInput
    _data::NTuple{20, UInt8}
end

# Zero-initializer for b2RayCastInput
function b2RayCastInput()
    return b2RayCastInput(ntuple(i -> 0x00, 20))
end

function Base.getproperty(x::b2RayCastInput, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :maxFraction
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 16))
end
    error("type b2RayCastInput has no field $s")
end

# C++ struct: b2RayCastOutput (2 members, byte blob for ABI safety)
struct b2RayCastOutput
    _data::NTuple{12, UInt8}
end

# Zero-initializer for b2RayCastOutput
function b2RayCastOutput()
    return b2RayCastOutput(ntuple(i -> 0x00, 12))
end

function Base.getproperty(x::b2RayCastOutput, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :fraction
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 8))
end
    error("type b2RayCastOutput has no field $s")
end

# C++ struct: b2ReferenceFace (9 members, byte blob for ABI safety)
struct b2ReferenceFace
    _data::NTuple{56, UInt8}
end

# Zero-initializer for b2ReferenceFace
function b2ReferenceFace()
    return b2ReferenceFace(ntuple(i -> 0x00, 56))
end

function Base.getproperty(x::b2ReferenceFace, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :i1
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 0))
end
if s === :i2
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 4))
end
if s === :sideOffset1
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 40))
end
if s === :sideOffset2
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 52))
end
    error("type b2ReferenceFace has no field $s")
end

# C++ struct: b2RevoluteJointDef (14 members, byte blob for ABI safety)
struct b2RevoluteJointDef
    _data::NTuple{80, UInt8}
end

# Zero-initializer for b2RevoluteJointDef
function b2RevoluteJointDef()
    return b2RevoluteJointDef(ntuple(i -> 0x00, 80))
end

function Base.getproperty(x::b2RevoluteJointDef, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :bodyA
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 16))
end
if s === :bodyB
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 24))
end
if s === :collideConnected
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 32))
end
if s === :referenceAngle
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 52))
end
if s === :enableLimit
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 56))
end
if s === :lowerAngle
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 60))
end
if s === :upperAngle
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 64))
end
if s === :enableMotor
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 68))
end
if s === :motorSpeed
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 72))
end
if s === :maxMotorTorque
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 76))
end
    error("type b2RevoluteJointDef has no field $s")
end

# C++ struct: b2Rope (13 members, byte blob for ABI safety)
struct b2Rope
    _data::NTuple{128, UInt8}
end

# Zero-initializer for b2Rope
function b2Rope()
    return b2Rope(ntuple(i -> 0x00, 128))
end

function Base.getproperty(x::b2Rope, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :m_count
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 8))
end
if s === :m_stretchCount
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 12))
end
if s === :m_bendCount
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 16))
end
if s === :m_stretchConstraints
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 24))
end
if s === :m_bendConstraints
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 32))
end
if s === :m_bindPositions
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 40))
end
if s === :m_ps
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 48))
end
if s === :m_p0s
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 56))
end
if s === :m_vs
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 64))
end
if s === :m_invMasses
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 72))
end
    error("type b2Rope has no field $s")
end

# C++ struct: b2RopeDef (6 members, byte blob for ABI safety)
struct b2RopeDef
    _data::NTuple{80, UInt8}
end

# Zero-initializer for b2RopeDef
function b2RopeDef()
    return b2RopeDef(ntuple(i -> 0x00, 80))
end

function Base.getproperty(x::b2RopeDef, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :vertices
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 8))
end
if s === :count
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 16))
end
if s === :masses
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 24))
end
    error("type b2RopeDef has no field $s")
end

# C++ struct: b2ShapeCastOutput (4 members, byte blob for ABI safety)
struct b2ShapeCastOutput
    _data::NTuple{24, UInt8}
end

# Zero-initializer for b2ShapeCastOutput
function b2ShapeCastOutput()
    return b2ShapeCastOutput(ntuple(i -> 0x00, 24))
end

function Base.getproperty(x::b2ShapeCastOutput, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :lambda
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 16))
end
if s === :iterations
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 20))
end
    error("type b2ShapeCastOutput has no field $s")
end

# C++ struct: b2SimplexVertex (6 members, byte blob for ABI safety)
struct b2SimplexVertex
    _data::NTuple{36, UInt8}
end

# Zero-initializer for b2SimplexVertex
function b2SimplexVertex()
    return b2SimplexVertex(ntuple(i -> 0x00, 36))
end

function Base.getproperty(x::b2SimplexVertex, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :a
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 24))
end
if s === :indexA
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 28))
end
if s === :indexB
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 32))
end
    error("type b2SimplexVertex has no field $s")
end

# C++ struct: b2StackAllocator (6 members, byte blob for ABI safety)
struct b2StackAllocator
    _data::NTuple{102936, UInt8}
end

# Zero-initializer for b2StackAllocator
function b2StackAllocator()
    return b2StackAllocator(ntuple(i -> 0x00, 102936))
end

function Base.getproperty(x::b2StackAllocator, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :m_index
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 102400))
end
if s === :m_allocation
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 102404))
end
if s === :m_maxAllocation
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 102408))
end
if s === :m_entryCount
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 102928))
end
    error("type b2StackAllocator has no field $s")
end

# C++ struct: b2Sweep (6 members, byte blob for ABI safety)
struct b2Sweep
    _data::NTuple{36, UInt8}
end

# Zero-initializer for b2Sweep
function b2Sweep()
    return b2Sweep(ntuple(i -> 0x00, 36))
end

function Base.getproperty(x::b2Sweep, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :a0
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 24))
end
if s === :a
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 28))
end
if s === :alpha0
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 32))
end
    error("type b2Sweep has no field $s")
end

# C++ struct: b2TempPolygon (3 members, byte blob for ABI safety)
struct b2TempPolygon
    _data::NTuple{132, UInt8}
end

# Zero-initializer for b2TempPolygon
function b2TempPolygon()
    return b2TempPolygon(ntuple(i -> 0x00, 132))
end

function Base.getproperty(x::b2TempPolygon, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :count
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 128))
end
    error("type b2TempPolygon has no field $s")
end

# C++ struct: b2Transform (2 members, byte blob for ABI safety)
struct b2Transform
    _data::NTuple{16, UInt8}
end

# Zero-initializer for b2Transform
function b2Transform()
    return b2Transform(ntuple(i -> 0x00, 16))
end

# C++ struct: b2Velocity (2 members, byte blob for ABI safety)
struct b2Velocity
    _data::NTuple{12, UInt8}
end

# Zero-initializer for b2Velocity
function b2Velocity()
    return b2Velocity(ntuple(i -> 0x00, 12))
end

function Base.getproperty(x::b2Velocity, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :w
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 8))
end
    error("type b2Velocity has no field $s")
end

# C++ struct: b2VelocityConstraintPoint (7 members, byte blob for ABI safety)
struct b2VelocityConstraintPoint
    _data::NTuple{36, UInt8}
end

# Zero-initializer for b2VelocityConstraintPoint
function b2VelocityConstraintPoint()
    return b2VelocityConstraintPoint(ntuple(i -> 0x00, 36))
end

function Base.getproperty(x::b2VelocityConstraintPoint, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :normalImpulse
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 16))
end
if s === :tangentImpulse
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 20))
end
if s === :normalMass
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 24))
end
if s === :tangentMass
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 28))
end
if s === :velocityBias
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 32))
end
    error("type b2VelocityConstraintPoint has no field $s")
end

# C++ struct: b2WeldJointDef (10 members, byte blob for ABI safety)
struct b2WeldJointDef
    _data::NTuple{64, UInt8}
end

# Zero-initializer for b2WeldJointDef
function b2WeldJointDef()
    return b2WeldJointDef(ntuple(i -> 0x00, 64))
end

function Base.getproperty(x::b2WeldJointDef, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :bodyA
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 16))
end
if s === :bodyB
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 24))
end
if s === :collideConnected
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 32))
end
if s === :referenceAngle
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 52))
end
if s === :stiffness
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 56))
end
if s === :damping
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 60))
end
    error("type b2WeldJointDef has no field $s")
end

# C++ struct: b2WheelJoint (50 members, byte blob for ABI safety)
struct b2WheelJoint
    _data::NTuple{312, UInt8}
end

# Zero-initializer for b2WheelJoint
function b2WheelJoint()
    return b2WheelJoint(ntuple(i -> 0x00, 312))
end

function Base.getproperty(x::b2WheelJoint, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :_vptr$b2Joint
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 0))
end
if s === :m_prev
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 16))
end
if s === :m_next
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 24))
end
if s === :m_bodyA
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 96))
end
if s === :m_bodyB
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 104))
end
if s === :m_index
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 112))
end
if s === :m_islandFlag
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 116))
end
if s === :m_collideConnected
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 117))
end
if s === :m_impulse
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 160))
end
if s === :m_motorImpulse
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 164))
end
if s === :m_springImpulse
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 168))
end
if s === :m_lowerImpulse
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 172))
end
if s === :m_upperImpulse
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 176))
end
if s === :m_translation
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 180))
end
if s === :m_lowerTranslation
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 184))
end
if s === :m_upperTranslation
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 188))
end
if s === :m_maxMotorTorque
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 192))
end
if s === :m_motorSpeed
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 196))
end
if s === :m_enableLimit
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 200))
end
if s === :m_enableMotor
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 201))
end
if s === :m_stiffness
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 204))
end
if s === :m_damping
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 208))
end
if s === :m_indexA
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 212))
end
if s === :m_indexB
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 216))
end
if s === :m_invMassA
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 236))
end
if s === :m_invMassB
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 240))
end
if s === :m_invIA
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 244))
end
if s === :m_invIB
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 248))
end
if s === :m_sAx
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 268))
end
if s === :m_sBx
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 272))
end
if s === :m_sAy
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 276))
end
if s === :m_sBy
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 280))
end
if s === :m_mass
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 284))
end
if s === :m_motorMass
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 288))
end
if s === :m_axialMass
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 292))
end
if s === :m_springMass
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 296))
end
if s === :m_bias
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 300))
end
if s === :m_gamma
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 304))
end
    error("type b2WheelJoint has no field $s")
end

# C++ struct: b2WheelJointDef (16 members, byte blob for ABI safety)
struct b2WheelJointDef
    _data::NTuple{96, UInt8}
end

# Zero-initializer for b2WheelJointDef
function b2WheelJointDef()
    return b2WheelJointDef(ntuple(i -> 0x00, 96))
end

function Base.getproperty(x::b2WheelJointDef, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :bodyA
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 16))
end
if s === :bodyB
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 24))
end
if s === :collideConnected
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 32))
end
if s === :enableLimit
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 60))
end
if s === :lowerTranslation
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 64))
end
if s === :upperTranslation
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 68))
end
if s === :enableMotor
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 72))
end
if s === :maxMotorTorque
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 76))
end
if s === :motorSpeed
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 80))
end
if s === :stiffness
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 84))
end
if s === :damping
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 88))
end
    error("type b2WheelJointDef has no field $s")
end

# C++ struct: b2WorldManifold (3 members, byte blob for ABI safety)
struct b2WorldManifold
    _data::NTuple{32, UInt8}
end

# Zero-initializer for b2WorldManifold
function b2WorldManifold()
    return b2WorldManifold(ntuple(i -> 0x00, 32))
end

# C++ struct: b2BlockAllocator (4 members, byte blob for ABI safety)
struct b2BlockAllocator
    _data::NTuple{128, UInt8}
end

# Zero-initializer for b2BlockAllocator
function b2BlockAllocator()
    return b2BlockAllocator(ntuple(i -> 0x00, 128))
end

function Base.getproperty(x::b2BlockAllocator, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :m_chunks
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 0))
end
if s === :m_chunkCount
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 8))
end
if s === :m_chunkSpace
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 12))
end
    error("type b2BlockAllocator has no field $s")
end

# C++ struct: b2ContactSolverDef (6 members, byte blob for ABI safety)
struct b2ContactSolverDef
    _data::NTuple{64, UInt8}
end

# Zero-initializer for b2ContactSolverDef
function b2ContactSolverDef()
    return b2ContactSolverDef(ntuple(i -> 0x00, 64))
end

function Base.getproperty(x::b2ContactSolverDef, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :contacts
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 24))
end
if s === :count
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 32))
end
if s === :positions
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 40))
end
if s === :velocities
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 48))
end
if s === :allocator
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 56))
end
    error("type b2ContactSolverDef has no field $s")
end

# C++ struct: b2ContactVelocityConstraint (16 members, byte blob for ABI safety)
struct b2ContactVelocityConstraint
    _data::NTuple{160, UInt8}
end

# Zero-initializer for b2ContactVelocityConstraint
function b2ContactVelocityConstraint()
    return b2ContactVelocityConstraint(ntuple(i -> 0x00, 160))
end

function Base.getproperty(x::b2ContactVelocityConstraint, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :indexA
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 112))
end
if s === :indexB
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 116))
end
if s === :invMassA
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 120))
end
if s === :invMassB
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 124))
end
if s === :invIA
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 128))
end
if s === :invIB
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 132))
end
if s === :friction
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 136))
end
if s === :restitution
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 140))
end
if s === :threshold
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 144))
end
if s === :tangentSpeed
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 148))
end
if s === :pointCount
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 152))
end
if s === :contactIndex
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 156))
end
    error("type b2ContactVelocityConstraint has no field $s")
end

# C++ struct: b2DistanceInput (5 members, byte blob for ABI safety)
struct b2DistanceInput
    _data::NTuple{104, UInt8}
end

# Zero-initializer for b2DistanceInput
function b2DistanceInput()
    return b2DistanceInput(ntuple(i -> 0x00, 104))
end

function Base.getproperty(x::b2DistanceInput, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :useRadii
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 96))
end
    error("type b2DistanceInput has no field $s")
end

# C++ struct: b2FrictionJoint (30 members, byte blob for ABI safety)
struct b2FrictionJoint
    _data::NTuple{240, UInt8}
end

# Zero-initializer for b2FrictionJoint
function b2FrictionJoint()
    return b2FrictionJoint(ntuple(i -> 0x00, 240))
end

function Base.getproperty(x::b2FrictionJoint, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :_vptr$b2Joint
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 0))
end
if s === :m_prev
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 16))
end
if s === :m_next
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 24))
end
if s === :m_bodyA
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 96))
end
if s === :m_bodyB
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 104))
end
if s === :m_index
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 112))
end
if s === :m_islandFlag
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 116))
end
if s === :m_collideConnected
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 117))
end
if s === :m_angularImpulse
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 152))
end
if s === :m_maxForce
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 156))
end
if s === :m_maxTorque
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 160))
end
if s === :m_indexA
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 164))
end
if s === :m_indexB
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 168))
end
if s === :m_invMassA
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 204))
end
if s === :m_invMassB
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 208))
end
if s === :m_invIA
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 212))
end
if s === :m_invIB
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 216))
end
if s === :m_angularMass
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 236))
end
    error("type b2FrictionJoint has no field $s")
end

# C++ struct: b2Island (13 members)
struct b2Island
    m_allocator::Ptr{b2StackAllocator}
    m_listener::Ptr{b2ContactListener}
    m_bodies::Ptr{Ptr{Cvoid}}
    m_contacts::Ptr{Ptr{Cvoid}}
    m_joints::Ptr{Ptr{Cvoid}}
    m_positions::Ptr{b2Position}
    m_velocities::Ptr{b2Velocity}
    m_bodyCount::Cint
    m_jointCount::Cint
    m_contactCount::Cint
    m_bodyCapacity::Cint
    m_contactCapacity::Cint
    m_jointCapacity::Cint
end

# Zero-initializer for b2Island
function b2Island()
    ref = Ref{b2Island}()
    GC.@preserve ref begin
        ccall(:memset, Ptr{Cvoid}, (Ptr{Cvoid}, Cint, Csize_t), Base.unsafe_convert(Ptr{Cvoid}, ref), 0, sizeof(b2Island))
    end
    return ref[]
end

# C++ struct: b2Manifold (5 members, byte blob for ABI safety)
struct b2Manifold
    _data::NTuple{64, UInt8}
end

# Zero-initializer for b2Manifold
function b2Manifold()
    return b2Manifold(ntuple(i -> 0x00, 64))
end

function Base.getproperty(x::b2Manifold, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :pointCount
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 60))
end
    error("type b2Manifold has no field $s")
end

# C++ struct: b2MotorJoint (33 members, byte blob for ABI safety)
struct b2MotorJoint
    _data::NTuple{256, UInt8}
end

# Zero-initializer for b2MotorJoint
function b2MotorJoint()
    return b2MotorJoint(ntuple(i -> 0x00, 256))
end

function Base.getproperty(x::b2MotorJoint, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :_vptr$b2Joint
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 0))
end
if s === :m_prev
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 16))
end
if s === :m_next
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 24))
end
if s === :m_bodyA
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 96))
end
if s === :m_bodyB
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 104))
end
if s === :m_index
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 112))
end
if s === :m_islandFlag
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 116))
end
if s === :m_collideConnected
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 117))
end
if s === :m_angularOffset
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 136))
end
if s === :m_angularImpulse
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 148))
end
if s === :m_maxForce
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 152))
end
if s === :m_maxTorque
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 156))
end
if s === :m_correctionFactor
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 160))
end
if s === :m_indexA
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 164))
end
if s === :m_indexB
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 168))
end
if s === :m_angularError
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 212))
end
if s === :m_invMassA
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 216))
end
if s === :m_invMassB
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 220))
end
if s === :m_invIA
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 224))
end
if s === :m_invIB
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 228))
end
if s === :m_angularMass
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 248))
end
    error("type b2MotorJoint has no field $s")
end

# C++ struct: b2MouseJoint (28 members, byte blob for ABI safety)
struct b2MouseJoint
    _data::NTuple{232, UInt8}
end

# Zero-initializer for b2MouseJoint
function b2MouseJoint()
    return b2MouseJoint(ntuple(i -> 0x00, 232))
end

function Base.getproperty(x::b2MouseJoint, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :_vptr$b2Joint
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 0))
end
if s === :m_prev
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 16))
end
if s === :m_next
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 24))
end
if s === :m_bodyA
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 96))
end
if s === :m_bodyB
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 104))
end
if s === :m_index
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 112))
end
if s === :m_islandFlag
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 116))
end
if s === :m_collideConnected
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 117))
end
if s === :m_stiffness
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 144))
end
if s === :m_damping
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 148))
end
if s === :m_beta
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 152))
end
if s === :m_maxForce
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 164))
end
if s === :m_gamma
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 168))
end
if s === :m_indexA
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 172))
end
if s === :m_indexB
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 176))
end
if s === :m_invMassB
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 196))
end
if s === :m_invIB
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 200))
end
    error("type b2MouseJoint has no field $s")
end

# C++ struct: b2PrismaticJoint (44 members, byte blob for ABI safety)
struct b2PrismaticJoint
    _data::NTuple{304, UInt8}
end

# Zero-initializer for b2PrismaticJoint
function b2PrismaticJoint()
    return b2PrismaticJoint(ntuple(i -> 0x00, 304))
end

function Base.getproperty(x::b2PrismaticJoint, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :_vptr$b2Joint
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 0))
end
if s === :m_prev
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 16))
end
if s === :m_next
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 24))
end
if s === :m_bodyA
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 96))
end
if s === :m_bodyB
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 104))
end
if s === :m_index
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 112))
end
if s === :m_islandFlag
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 116))
end
if s === :m_collideConnected
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 117))
end
if s === :m_referenceAngle
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 160))
end
if s === :m_motorImpulse
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 172))
end
if s === :m_lowerImpulse
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 176))
end
if s === :m_upperImpulse
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 180))
end
if s === :m_lowerTranslation
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 184))
end
if s === :m_upperTranslation
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 188))
end
if s === :m_maxMotorForce
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 192))
end
if s === :m_motorSpeed
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 196))
end
if s === :m_enableLimit
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 200))
end
if s === :m_enableMotor
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 201))
end
if s === :m_indexA
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 204))
end
if s === :m_indexB
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 208))
end
if s === :m_invMassA
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 228))
end
if s === :m_invMassB
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 232))
end
if s === :m_invIA
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 236))
end
if s === :m_invIB
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 240))
end
if s === :m_s1
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 260))
end
if s === :m_s2
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 264))
end
if s === :m_a1
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 268))
end
if s === :m_a2
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 272))
end
if s === :m_translation
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 292))
end
if s === :m_axialMass
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 296))
end
    error("type b2PrismaticJoint has no field $s")
end

# C++ struct: b2RevoluteJoint (38 members, byte blob for ABI safety)
struct b2RevoluteJoint
    _data::NTuple{272, UInt8}
end

# Zero-initializer for b2RevoluteJoint
function b2RevoluteJoint()
    return b2RevoluteJoint(ntuple(i -> 0x00, 272))
end

function Base.getproperty(x::b2RevoluteJoint, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :_vptr$b2Joint
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 0))
end
if s === :m_prev
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 16))
end
if s === :m_next
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 24))
end
if s === :m_bodyA
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 96))
end
if s === :m_bodyB
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 104))
end
if s === :m_index
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 112))
end
if s === :m_islandFlag
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 116))
end
if s === :m_collideConnected
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 117))
end
if s === :m_motorImpulse
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 152))
end
if s === :m_lowerImpulse
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 156))
end
if s === :m_upperImpulse
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 160))
end
if s === :m_enableMotor
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 164))
end
if s === :m_maxMotorTorque
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 168))
end
if s === :m_motorSpeed
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 172))
end
if s === :m_enableLimit
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 176))
end
if s === :m_referenceAngle
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 180))
end
if s === :m_lowerAngle
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 184))
end
if s === :m_upperAngle
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 188))
end
if s === :m_indexA
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 192))
end
if s === :m_indexB
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 196))
end
if s === :m_invMassA
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 232))
end
if s === :m_invMassB
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 236))
end
if s === :m_invIA
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 240))
end
if s === :m_invIB
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 244))
end
if s === :m_angle
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 264))
end
if s === :m_axialMass
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 268))
end
    error("type b2RevoluteJoint has no field $s")
end

# C++ struct: b2SeparationFunction (7 members, byte blob for ABI safety)
struct b2SeparationFunction
    _data::NTuple{112, UInt8}
end

# Zero-initializer for b2SeparationFunction
function b2SeparationFunction()
    return b2SeparationFunction(ntuple(i -> 0x00, 112))
end

function Base.getproperty(x::b2SeparationFunction, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :m_proxyA
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 0))
end
if s === :m_proxyB
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 8))
end
    error("type b2SeparationFunction has no field $s")
end

# C++ struct: b2ShapeCastInput (5 members, byte blob for ABI safety)
struct b2ShapeCastInput
    _data::NTuple{104, UInt8}
end

# Zero-initializer for b2ShapeCastInput
function b2ShapeCastInput()
    return b2ShapeCastInput(ntuple(i -> 0x00, 104))
end

# C++ struct: b2Simplex (4 members, byte blob for ABI safety)
struct b2Simplex
    _data::NTuple{112, UInt8}
end

# Zero-initializer for b2Simplex
function b2Simplex()
    return b2Simplex(ntuple(i -> 0x00, 112))
end

function Base.getproperty(x::b2Simplex, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :m_count
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 108))
end
    error("type b2Simplex has no field $s")
end

# C++ struct: b2SolverData (3 members, byte blob for ABI safety)
struct b2SolverData
    _data::NTuple{40, UInt8}
end

# Zero-initializer for b2SolverData
function b2SolverData()
    return b2SolverData(ntuple(i -> 0x00, 40))
end

function Base.getproperty(x::b2SolverData, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :positions
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 24))
end
if s === :velocities
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 32))
end
    error("type b2SolverData has no field $s")
end

# C++ struct: b2TOIInput (5 members, byte blob for ABI safety)
struct b2TOIInput
    _data::NTuple{144, UInt8}
end

# Zero-initializer for b2TOIInput
function b2TOIInput()
    return b2TOIInput(ntuple(i -> 0x00, 144))
end

function Base.getproperty(x::b2TOIInput, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :tMax
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 136))
end
    error("type b2TOIInput has no field $s")
end

# C++ struct: b2TreeNode (6 members, byte blob for ABI safety)
struct b2TreeNode
    _data::NTuple{48, UInt8}
end

# Zero-initializer for b2TreeNode
function b2TreeNode()
    return b2TreeNode(ntuple(i -> 0x00, 48))
end

function Base.getproperty(x::b2TreeNode, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :userData
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 16))
end
if s === :child1
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 28))
end
if s === :child2
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 32))
end
if s === :height
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 36))
end
if s === :moved
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 40))
end
    error("type b2TreeNode has no field $s")
end

# C++ struct: b2WeldJoint (31 members, byte blob for ABI safety)
struct b2WeldJoint
    _data::NTuple{272, UInt8}
end

# Zero-initializer for b2WeldJoint
function b2WeldJoint()
    return b2WeldJoint(ntuple(i -> 0x00, 272))
end

function Base.getproperty(x::b2WeldJoint, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :_vptr$b2Joint
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 0))
end
if s === :m_prev
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 16))
end
if s === :m_next
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 24))
end
if s === :m_bodyA
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 96))
end
if s === :m_bodyB
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 104))
end
if s === :m_index
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 112))
end
if s === :m_islandFlag
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 116))
end
if s === :m_collideConnected
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 117))
end
if s === :m_stiffness
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 128))
end
if s === :m_damping
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 132))
end
if s === :m_bias
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 136))
end
if s === :m_referenceAngle
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 156))
end
if s === :m_gamma
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 160))
end
if s === :m_indexA
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 176))
end
if s === :m_indexB
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 180))
end
if s === :m_invMassA
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 216))
end
if s === :m_invMassB
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 220))
end
if s === :m_invIA
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 224))
end
if s === :m_invIB
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 228))
end
    error("type b2WeldJoint has no field $s")
end

# C++ struct: b2ContactSolver (8 members, byte blob for ABI safety)
struct b2ContactSolver
    _data::NTuple{80, UInt8}
end

# Zero-initializer for b2ContactSolver
function b2ContactSolver()
    return b2ContactSolver(ntuple(i -> 0x00, 80))
end

function Base.getproperty(x::b2ContactSolver, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :m_positions
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 24))
end
if s === :m_velocities
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 32))
end
if s === :m_allocator
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 40))
end
if s === :m_positionConstraints
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 48))
end
if s === :m_velocityConstraints
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 56))
end
if s === :m_contacts
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 64))
end
if s === :m_count
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 72))
end
    error("type b2ContactSolver has no field $s")
end

# C++ struct: b2DynamicTree (6 members)
struct b2DynamicTree
    m_root::Cint
    _pad_0::NTuple{4, UInt8}
    m_nodes::Ptr{b2TreeNode}
    m_nodeCount::Cint
    m_nodeCapacity::Cint
    m_freeList::Cint
    m_insertionCount::Cint
end

# Zero-initializer for b2DynamicTree
function b2DynamicTree()
    ref = Ref{b2DynamicTree}()
    GC.@preserve ref begin
        ccall(:memset, Ptr{Cvoid}, (Ptr{Cvoid}, Cint, Csize_t), Base.unsafe_convert(Ptr{Cvoid}, ref), 0, sizeof(b2DynamicTree))
    end
    return ref[]
end

# C++ struct: b2BroadPhase (9 members, byte blob for ABI safety)
struct b2BroadPhase
    _data::NTuple{80, UInt8}
end

# Zero-initializer for b2BroadPhase
function b2BroadPhase()
    return b2BroadPhase(ntuple(i -> 0x00, 80))
end

function Base.getproperty(x::b2BroadPhase, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :m_proxyCount
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 32))
end
if s === :m_moveBuffer
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 40))
end
if s === :m_moveCapacity
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 48))
end
if s === :m_moveCount
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 52))
end
if s === :m_pairBuffer
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 56))
end
if s === :m_pairCapacity
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 64))
end
if s === :m_pairCount
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 68))
end
if s === :m_queryProxyId
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 72))
end
    error("type b2BroadPhase has no field $s")
end

# C++ struct: b2WorldQueryWrapper (2 members)
struct b2WorldQueryWrapper
    broadPhase::Ptr{b2BroadPhase}
    callback::Ptr{b2QueryCallback}
end

# Zero-initializer for b2WorldQueryWrapper
function b2WorldQueryWrapper()
    ref = Ref{b2WorldQueryWrapper}()
    GC.@preserve ref begin
        ccall(:memset, Ptr{Cvoid}, (Ptr{Cvoid}, Cint, Csize_t), Base.unsafe_convert(Ptr{Cvoid}, ref), 0, sizeof(b2WorldQueryWrapper))
    end
    return ref[]
end

# C++ struct: b2WorldRayCastWrapper (2 members)
struct b2WorldRayCastWrapper
    broadPhase::Ptr{b2BroadPhase}
    callback::Ptr{b2RayCastCallback}
end

# Zero-initializer for b2WorldRayCastWrapper
function b2WorldRayCastWrapper()
    ref = Ref{b2WorldRayCastWrapper}()
    GC.@preserve ref begin
        ccall(:memset, Ptr{Cvoid}, (Ptr{Cvoid}, Cint, Csize_t), Base.unsafe_convert(Ptr{Cvoid}, ref), 0, sizeof(b2WorldRayCastWrapper))
    end
    return ref[]
end

# C++ struct: b2Body (25 members, byte blob for ABI safety)
struct b2Body
    _data::NTuple{184, UInt8}
end

# Zero-initializer for b2Body
function b2Body()
    return b2Body(ntuple(i -> 0x00, 184))
end

function Base.getproperty(x::b2Body, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :m_flags
    return GC.@preserve x unsafe_load(Ptr{Cushort}(pointer_from_objref(Ref(x._data)) + 4))
end
if s === :m_islandIndex
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 8))
end
if s === :m_angularVelocity
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 72))
end
if s === :m_torque
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 84))
end
if s === :m_world
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 88))
end
if s === :m_prev
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 96))
end
if s === :m_next
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 104))
end
if s === :m_fixtureList
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 112))
end
if s === :m_fixtureCount
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 120))
end
if s === :m_jointList
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 128))
end
if s === :m_contactList
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 136))
end
if s === :m_mass
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 144))
end
if s === :m_invMass
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 148))
end
if s === :m_I
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 152))
end
if s === :m_invI
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 156))
end
if s === :m_linearDamping
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 160))
end
if s === :m_angularDamping
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 164))
end
if s === :m_gravityScale
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 168))
end
if s === :m_sleepTime
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 172))
end
    error("type b2Body has no field $s")
end

# C++ struct: b2ContactEdge (4 members)
struct b2ContactEdge
    other::Ptr{b2Body}
    contact::Ptr{Cvoid}
    prev::Ptr{b2ContactEdge}
    next::Ptr{b2ContactEdge}
end

# Zero-initializer for b2ContactEdge
function b2ContactEdge()
    ref = Ref{b2ContactEdge}()
    GC.@preserve ref begin
        ccall(:memset, Ptr{Cvoid}, (Ptr{Cvoid}, Cint, Csize_t), Base.unsafe_convert(Ptr{Cvoid}, ref), 0, sizeof(b2ContactEdge))
    end
    return ref[]
end

# C++ struct: b2ContactManager (6 members, byte blob for ABI safety)
struct b2ContactManager
    _data::NTuple{120, UInt8}
end

# Zero-initializer for b2ContactManager
function b2ContactManager()
    return b2ContactManager(ntuple(i -> 0x00, 120))
end

function Base.getproperty(x::b2ContactManager, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :m_contactList
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 80))
end
if s === :m_contactCount
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 88))
end
if s === :m_contactFilter
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 96))
end
if s === :m_contactListener
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 104))
end
if s === :m_allocator
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 112))
end
    error("type b2ContactManager has no field $s")
end

# C++ struct: b2Fixture (12 members, byte blob for ABI safety)
struct b2Fixture
    _data::NTuple{80, UInt8}
end

# Zero-initializer for b2Fixture
function b2Fixture()
    return b2Fixture(ntuple(i -> 0x00, 80))
end

function Base.getproperty(x::b2Fixture, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :m_density
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 0))
end
if s === :m_next
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 8))
end
if s === :m_body
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 16))
end
if s === :m_shape
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 24))
end
if s === :m_friction
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 32))
end
if s === :m_restitution
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 36))
end
if s === :m_restitutionThreshold
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 40))
end
if s === :m_proxies
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 48))
end
if s === :m_proxyCount
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 56))
end
if s === :m_isSensor
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 66))
end
    error("type b2Fixture has no field $s")
end

# C++ struct: b2FixtureProxy (4 members, byte blob for ABI safety)
struct b2FixtureProxy
    _data::NTuple{32, UInt8}
end

# Zero-initializer for b2FixtureProxy
function b2FixtureProxy()
    return b2FixtureProxy(ntuple(i -> 0x00, 32))
end

function Base.getproperty(x::b2FixtureProxy, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :fixture
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 16))
end
if s === :childIndex
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 24))
end
if s === :proxyId
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 28))
end
    error("type b2FixtureProxy has no field $s")
end

# C++ struct: b2GearJoint (52 members, byte blob for ABI safety)
struct b2GearJoint
    _data::NTuple{352, UInt8}
end

# Zero-initializer for b2GearJoint
function b2GearJoint()
    return b2GearJoint(ntuple(i -> 0x00, 352))
end

function Base.getproperty(x::b2GearJoint, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :_vptr$b2Joint
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 0))
end
if s === :m_prev
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 16))
end
if s === :m_next
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 24))
end
if s === :m_bodyA
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 96))
end
if s === :m_bodyB
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 104))
end
if s === :m_index
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 112))
end
if s === :m_islandFlag
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 116))
end
if s === :m_collideConnected
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 117))
end
if s === :m_joint1
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 128))
end
if s === :m_joint2
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 136))
end
if s === :m_bodyC
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 152))
end
if s === :m_bodyD
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 160))
end
if s === :m_referenceAngleA
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 216))
end
if s === :m_referenceAngleB
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 220))
end
if s === :m_constant
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 224))
end
if s === :m_ratio
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 228))
end
if s === :m_impulse
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 232))
end
if s === :m_indexA
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 236))
end
if s === :m_indexB
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 240))
end
if s === :m_indexC
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 244))
end
if s === :m_indexD
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 248))
end
if s === :m_mA
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 284))
end
if s === :m_mB
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 288))
end
if s === :m_mC
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 292))
end
if s === :m_mD
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 296))
end
if s === :m_iA
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 300))
end
if s === :m_iB
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 304))
end
if s === :m_iC
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 308))
end
if s === :m_iD
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 312))
end
if s === :m_JwA
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 332))
end
if s === :m_JwB
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 336))
end
if s === :m_JwC
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 340))
end
if s === :m_JwD
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 344))
end
if s === :m_mass
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 348))
end
    error("type b2GearJoint has no field $s")
end

# C++ struct: b2GearJointDef (8 members, byte blob for ABI safety)
struct b2GearJointDef
    _data::NTuple{64, UInt8}
end

# Zero-initializer for b2GearJointDef
function b2GearJointDef()
    return b2GearJointDef(ntuple(i -> 0x00, 64))
end

function Base.getproperty(x::b2GearJointDef, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :bodyA
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 16))
end
if s === :bodyB
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 24))
end
if s === :collideConnected
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 32))
end
if s === :joint1
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 40))
end
if s === :joint2
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 48))
end
if s === :ratio
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 56))
end
    error("type b2GearJointDef has no field $s")
end

# C++ struct: b2JointDef (5 members, byte blob for ABI safety)
struct b2JointDef
    _data::NTuple{40, UInt8}
end

# Zero-initializer for b2JointDef
function b2JointDef()
    return b2JointDef(ntuple(i -> 0x00, 40))
end

function Base.getproperty(x::b2JointDef, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :bodyA
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 16))
end
if s === :bodyB
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 24))
end
if s === :collideConnected
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 32))
end
    error("type b2JointDef has no field $s")
end

# C++ struct: b2JointEdge (4 members)
struct b2JointEdge
    other::Ptr{b2Body}
    joint::Ptr{Cvoid}
    prev::Ptr{b2JointEdge}
    next::Ptr{b2JointEdge}
end

# Zero-initializer for b2JointEdge
function b2JointEdge()
    ref = Ref{b2JointEdge}()
    GC.@preserve ref begin
        ccall(:memset, Ptr{Cvoid}, (Ptr{Cvoid}, Cint, Csize_t), Base.unsafe_convert(Ptr{Cvoid}, ref), 0, sizeof(b2JointEdge))
    end
    return ref[]
end

# C++ struct: b2Contact (17 members, byte blob for ABI safety)
struct b2Contact
    _data::NTuple{208, UInt8}
end

# Zero-initializer for b2Contact
function b2Contact()
    return b2Contact(ntuple(i -> 0x00, 208))
end

function Base.getproperty(x::b2Contact, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :_vptr$b2Contact
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 0))
end
if s === :m_flags
    return GC.@preserve x unsafe_load(Ptr{Cuint}(pointer_from_objref(Ref(x._data)) + 8))
end
if s === :m_prev
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 16))
end
if s === :m_next
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 24))
end
if s === :m_fixtureA
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 96))
end
if s === :m_fixtureB
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 104))
end
if s === :m_indexA
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 112))
end
if s === :m_indexB
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 116))
end
if s === :m_toiCount
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 184))
end
if s === :m_toi
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 188))
end
if s === :m_friction
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 192))
end
if s === :m_restitution
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 196))
end
if s === :m_restitutionThreshold
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 200))
end
if s === :m_tangentSpeed
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 204))
end
    error("type b2Contact has no field $s")
end

# C++ struct: b2Joint (12 members, byte blob for ABI safety)
struct b2Joint
    _data::NTuple{128, UInt8}
end

# Zero-initializer for b2Joint
function b2Joint()
    return b2Joint(ntuple(i -> 0x00, 128))
end

function Base.getproperty(x::b2Joint, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :_vptr$b2Joint
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 0))
end
if s === :m_prev
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 16))
end
if s === :m_next
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 24))
end
if s === :m_bodyA
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 96))
end
if s === :m_bodyB
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 104))
end
if s === :m_index
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 112))
end
if s === :m_islandFlag
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 116))
end
if s === :m_collideConnected
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 117))
end
    error("type b2Joint has no field $s")
end

# C++ struct: b2World (20 members, byte blob for ABI safety)
struct b2World
    _data::NTuple{103288, UInt8}
end

# Zero-initializer for b2World
function b2World()
    return b2World(ntuple(i -> 0x00, 103288))
end

function Base.getproperty(x::b2World, s::Symbol)
    s === :_data && return getfield(x, :_data)
if s === :m_bodyList
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 103184))
end
if s === :m_jointList
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 103192))
end
if s === :m_bodyCount
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 103200))
end
if s === :m_jointCount
    return GC.@preserve x unsafe_load(Ptr{Cint}(pointer_from_objref(Ref(x._data)) + 103204))
end
if s === :m_allowSleep
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 103216))
end
if s === :m_destructionListener
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 103224))
end
if s === :m_debugDraw
    return GC.@preserve x unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(x._data)) + 103232))
end
if s === :m_inv_dt0
    return GC.@preserve x unsafe_load(Ptr{Cfloat}(pointer_from_objref(Ref(x._data)) + 103240))
end
if s === :m_newContacts
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 103244))
end
if s === :m_locked
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 103245))
end
if s === :m_clearForces
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 103246))
end
if s === :m_warmStarting
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 103247))
end
if s === :m_continuousPhysics
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 103248))
end
if s === :m_subStepping
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 103249))
end
if s === :m_stepComplete
    return GC.@preserve x unsafe_load(Ptr{Bool}(pointer_from_objref(Ref(x._data)) + 103250))
end
    error("type b2World has no field $s")
end


# =============================================================================
# Managed Types (Auto-Finalizers)
# =============================================================================

mutable struct Managedb2RevoluteJoint
    handle::Ptr{b2RevoluteJoint}
    
    function Managedb2RevoluteJoint(ptr::Ptr{b2RevoluteJoint})
        if ptr == C_NULL
            error("Cannot wrap NULL pointer in Managedb2RevoluteJoint")
        end
        obj = new(ptr)
        finalizer(obj) do x
            # Call deleter: _ZN15b2RevoluteJointD0Ev(x.handle)
            ccall((:_ZN15b2RevoluteJointD0Ev, LIBRARY_PATH), Cvoid, (Ptr{b2RevoluteJoint},), x.handle)
        end
        return obj
    end
end

# Allow passing Managed object to ccall expecting Ptr
unsafe_convert(::Type{Ptr{b2RevoluteJoint}}, obj::Managedb2RevoluteJoint) = obj.handle

export Managedb2RevoluteJoint

mutable struct Managedb2Body
    handle::Ptr{b2Body}
    
    function Managedb2Body(ptr::Ptr{b2Body})
        if ptr == C_NULL
            error("Cannot wrap NULL pointer in Managedb2Body")
        end
        obj = new(ptr)
        finalizer(obj) do x
            # Call deleter: _ZN6b2BodyD2Ev(x.handle)
            ccall((:_ZN6b2BodyD2Ev, LIBRARY_PATH), Cvoid, (Ptr{b2Body},), x.handle)
        end
        return obj
    end
end

# Allow passing Managed object to ccall expecting Ptr
unsafe_convert(::Type{Ptr{b2Body}}, obj::Managedb2Body) = obj.handle

export Managedb2Body

mutable struct Managedb2WheelJoint
    handle::Ptr{b2WheelJoint}
    
    function Managedb2WheelJoint(ptr::Ptr{b2WheelJoint})
        if ptr == C_NULL
            error("Cannot wrap NULL pointer in Managedb2WheelJoint")
        end
        obj = new(ptr)
        finalizer(obj) do x
            # Call deleter: _ZN12b2WheelJointD0Ev(x.handle)
            ccall((:_ZN12b2WheelJointD0Ev, LIBRARY_PATH), Cvoid, (Ptr{b2WheelJoint},), x.handle)
        end
        return obj
    end
end

# Allow passing Managed object to ccall expecting Ptr
unsafe_convert(::Type{Ptr{b2WheelJoint}}, obj::Managedb2WheelJoint) = obj.handle

export Managedb2WheelJoint

mutable struct Managedb2GearJoint
    handle::Ptr{b2GearJoint}
    
    function Managedb2GearJoint(ptr::Ptr{b2GearJoint})
        if ptr == C_NULL
            error("Cannot wrap NULL pointer in Managedb2GearJoint")
        end
        obj = new(ptr)
        finalizer(obj) do x
            # Call deleter: _ZN11b2GearJointD0Ev(x.handle)
            ccall((:_ZN11b2GearJointD0Ev, LIBRARY_PATH), Cvoid, (Ptr{b2GearJoint},), x.handle)
        end
        return obj
    end
end

# Allow passing Managed object to ccall expecting Ptr
unsafe_convert(::Type{Ptr{b2GearJoint}}, obj::Managedb2GearJoint) = obj.handle

export Managedb2GearJoint

mutable struct Managedb2Fixture
    handle::Ptr{b2Fixture}
    
    function Managedb2Fixture(ptr::Ptr{b2Fixture})
        if ptr == C_NULL
            error("Cannot wrap NULL pointer in Managedb2Fixture")
        end
        obj = new(ptr)
        finalizer(obj) do x
            # Call deleter: _ZN6b2Body14DestroyFixtureEP9b2Fixture(x.handle)
            ccall((:_ZN6b2Body14DestroyFixtureEP9b2Fixture, LIBRARY_PATH), Cvoid, (Ptr{b2Fixture},), x.handle)
        end
        return obj
    end
end

# Allow passing Managed object to ccall expecting Ptr
unsafe_convert(::Type{Ptr{b2Fixture}}, obj::Managedb2Fixture) = obj.handle

export Managedb2Fixture

mutable struct Managedb2Joint
    handle::Ptr{b2Joint}
    
    function Managedb2Joint(ptr::Ptr{b2Joint})
        if ptr == C_NULL
            error("Cannot wrap NULL pointer in Managedb2Joint")
        end
        obj = new(ptr)
        finalizer(obj) do x
            # Call deleter: _ZN7b2JointD0Ev(x.handle)
            ccall((:_ZN7b2JointD0Ev, LIBRARY_PATH), Cvoid, (Ptr{b2Joint},), x.handle)
        end
        return obj
    end
end

# Allow passing Managed object to ccall expecting Ptr
unsafe_convert(::Type{Ptr{b2Joint}}, obj::Managedb2Joint) = obj.handle

export Managedb2Joint

mutable struct Managedb2ContactFilter
    handle::Ptr{b2ContactFilter}
    
    function Managedb2ContactFilter(ptr::Ptr{b2ContactFilter})
        if ptr == C_NULL
            error("Cannot wrap NULL pointer in Managedb2ContactFilter")
        end
        obj = new(ptr)
        finalizer(obj) do x
            # Call deleter: _ZN15b2ContactFilterD0Ev(x.handle)
            ccall((:_ZN15b2ContactFilterD0Ev, LIBRARY_PATH), Cvoid, (Ptr{b2ContactFilter},), x.handle)
        end
        return obj
    end
end

# Allow passing Managed object to ccall expecting Ptr
unsafe_convert(::Type{Ptr{b2ContactFilter}}, obj::Managedb2ContactFilter) = obj.handle

export Managedb2ContactFilter

mutable struct Managedb2EdgeShape
    handle::Ptr{b2EdgeShape}
    
    function Managedb2EdgeShape(ptr::Ptr{b2EdgeShape})
        if ptr == C_NULL
            error("Cannot wrap NULL pointer in Managedb2EdgeShape")
        end
        obj = new(ptr)
        finalizer(obj) do x
            # Call deleter: _ZN11b2EdgeShapeD0Ev(x.handle)
            ccall((:_ZN11b2EdgeShapeD0Ev, LIBRARY_PATH), Cvoid, (Ptr{b2EdgeShape},), x.handle)
        end
        return obj
    end
end

# Allow passing Managed object to ccall expecting Ptr
unsafe_convert(::Type{Ptr{b2EdgeShape}}, obj::Managedb2EdgeShape) = obj.handle

export Managedb2EdgeShape

mutable struct Managedb2FrictionJoint
    handle::Ptr{b2FrictionJoint}
    
    function Managedb2FrictionJoint(ptr::Ptr{b2FrictionJoint})
        if ptr == C_NULL
            error("Cannot wrap NULL pointer in Managedb2FrictionJoint")
        end
        obj = new(ptr)
        finalizer(obj) do x
            # Call deleter: _ZN15b2FrictionJointD0Ev(x.handle)
            ccall((:_ZN15b2FrictionJointD0Ev, LIBRARY_PATH), Cvoid, (Ptr{b2FrictionJoint},), x.handle)
        end
        return obj
    end
end

# Allow passing Managed object to ccall expecting Ptr
unsafe_convert(::Type{Ptr{b2FrictionJoint}}, obj::Managedb2FrictionJoint) = obj.handle

export Managedb2FrictionJoint

mutable struct Managedb2World
    handle::Ptr{b2World}
    
    function Managedb2World(ptr::Ptr{b2World})
        if ptr == C_NULL
            error("Cannot wrap NULL pointer in Managedb2World")
        end
        obj = new(ptr)
        finalizer(obj) do x
            # Call deleter: _ZN7b2WorldD2Ev(x.handle)
            ccall((:_ZN7b2WorldD2Ev, LIBRARY_PATH), Cvoid, (Ptr{b2World},), x.handle)
        end
        return obj
    end
end

# Allow passing Managed object to ccall expecting Ptr
unsafe_convert(::Type{Ptr{b2World}}, obj::Managedb2World) = obj.handle

export Managedb2World

mutable struct Managedb2CircleShape
    handle::Ptr{b2CircleShape}
    
    function Managedb2CircleShape(ptr::Ptr{b2CircleShape})
        if ptr == C_NULL
            error("Cannot wrap NULL pointer in Managedb2CircleShape")
        end
        obj = new(ptr)
        finalizer(obj) do x
            # Call deleter: _ZN13b2CircleShapeD0Ev(x.handle)
            ccall((:_ZN13b2CircleShapeD0Ev, LIBRARY_PATH), Cvoid, (Ptr{b2CircleShape},), x.handle)
        end
        return obj
    end
end

# Allow passing Managed object to ccall expecting Ptr
unsafe_convert(::Type{Ptr{b2CircleShape}}, obj::Managedb2CircleShape) = obj.handle

export Managedb2CircleShape

mutable struct Managedb2ContactListener
    handle::Ptr{b2ContactListener}
    
    function Managedb2ContactListener(ptr::Ptr{b2ContactListener})
        if ptr == C_NULL
            error("Cannot wrap NULL pointer in Managedb2ContactListener")
        end
        obj = new(ptr)
        finalizer(obj) do x
            # Call deleter: _ZN17b2ContactListenerD0Ev(x.handle)
            ccall((:_ZN17b2ContactListenerD0Ev, LIBRARY_PATH), Cvoid, (Ptr{b2ContactListener},), x.handle)
        end
        return obj
    end
end

# Allow passing Managed object to ccall expecting Ptr
unsafe_convert(::Type{Ptr{b2ContactListener}}, obj::Managedb2ContactListener) = obj.handle

export Managedb2ContactListener

mutable struct Managedb2DynamicTree
    handle::Ptr{b2DynamicTree}
    
    function Managedb2DynamicTree(ptr::Ptr{b2DynamicTree})
        if ptr == C_NULL
            error("Cannot wrap NULL pointer in Managedb2DynamicTree")
        end
        obj = new(ptr)
        finalizer(obj) do x
            # Call deleter: _ZN13b2DynamicTreeD2Ev(x.handle)
            ccall((:_ZN13b2DynamicTreeD2Ev, LIBRARY_PATH), Cvoid, (Ptr{b2DynamicTree},), x.handle)
        end
        return obj
    end
end

# Allow passing Managed object to ccall expecting Ptr
unsafe_convert(::Type{Ptr{b2DynamicTree}}, obj::Managedb2DynamicTree) = obj.handle

export Managedb2DynamicTree

mutable struct Managedb2ContactSolver
    handle::Ptr{b2ContactSolver}
    
    function Managedb2ContactSolver(ptr::Ptr{b2ContactSolver})
        if ptr == C_NULL
            error("Cannot wrap NULL pointer in Managedb2ContactSolver")
        end
        obj = new(ptr)
        finalizer(obj) do x
            # Call deleter: _ZN15b2ContactSolverD2Ev(x.handle)
            ccall((:_ZN15b2ContactSolverD2Ev, LIBRARY_PATH), Cvoid, (Ptr{b2ContactSolver},), x.handle)
        end
        return obj
    end
end

# Allow passing Managed object to ccall expecting Ptr
unsafe_convert(::Type{Ptr{b2ContactSolver}}, obj::Managedb2ContactSolver) = obj.handle

export Managedb2ContactSolver

mutable struct Managedb2PulleyJoint
    handle::Ptr{b2PulleyJoint}
    
    function Managedb2PulleyJoint(ptr::Ptr{b2PulleyJoint})
        if ptr == C_NULL
            error("Cannot wrap NULL pointer in Managedb2PulleyJoint")
        end
        obj = new(ptr)
        finalizer(obj) do x
            # Call deleter: _ZN13b2PulleyJointD0Ev(x.handle)
            ccall((:_ZN13b2PulleyJointD0Ev, LIBRARY_PATH), Cvoid, (Ptr{b2PulleyJoint},), x.handle)
        end
        return obj
    end
end

# Allow passing Managed object to ccall expecting Ptr
unsafe_convert(::Type{Ptr{b2PulleyJoint}}, obj::Managedb2PulleyJoint) = obj.handle

export Managedb2PulleyJoint

mutable struct Managedb2MouseJoint
    handle::Ptr{b2MouseJoint}
    
    function Managedb2MouseJoint(ptr::Ptr{b2MouseJoint})
        if ptr == C_NULL
            error("Cannot wrap NULL pointer in Managedb2MouseJoint")
        end
        obj = new(ptr)
        finalizer(obj) do x
            # Call deleter: _ZN12b2MouseJointD0Ev(x.handle)
            ccall((:_ZN12b2MouseJointD0Ev, LIBRARY_PATH), Cvoid, (Ptr{b2MouseJoint},), x.handle)
        end
        return obj
    end
end

# Allow passing Managed object to ccall expecting Ptr
unsafe_convert(::Type{Ptr{b2MouseJoint}}, obj::Managedb2MouseJoint) = obj.handle

export Managedb2MouseJoint

mutable struct Managedb2WeldJoint
    handle::Ptr{b2WeldJoint}
    
    function Managedb2WeldJoint(ptr::Ptr{b2WeldJoint})
        if ptr == C_NULL
            error("Cannot wrap NULL pointer in Managedb2WeldJoint")
        end
        obj = new(ptr)
        finalizer(obj) do x
            # Call deleter: _ZN11b2WeldJointD0Ev(x.handle)
            ccall((:_ZN11b2WeldJointD0Ev, LIBRARY_PATH), Cvoid, (Ptr{b2WeldJoint},), x.handle)
        end
        return obj
    end
end

# Allow passing Managed object to ccall expecting Ptr
unsafe_convert(::Type{Ptr{b2WeldJoint}}, obj::Managedb2WeldJoint) = obj.handle

export Managedb2WeldJoint

mutable struct Managedb2Draw
    handle::Ptr{b2Draw}
    
    function Managedb2Draw(ptr::Ptr{b2Draw})
        if ptr == C_NULL
            error("Cannot wrap NULL pointer in Managedb2Draw")
        end
        obj = new(ptr)
        finalizer(obj) do x
            # Call deleter: _ZN6b2DrawD0Ev(x.handle)
            ccall((:_ZN6b2DrawD0Ev, LIBRARY_PATH), Cvoid, (Ptr{b2Draw},), x.handle)
        end
        return obj
    end
end

# Allow passing Managed object to ccall expecting Ptr
unsafe_convert(::Type{Ptr{b2Draw}}, obj::Managedb2Draw) = obj.handle

export Managedb2Draw

mutable struct Managedb2Shape
    handle::Ptr{b2Shape}
    
    function Managedb2Shape(ptr::Ptr{b2Shape})
        if ptr == C_NULL
            error("Cannot wrap NULL pointer in Managedb2Shape")
        end
        obj = new(ptr)
        finalizer(obj) do x
            # Call deleter: _ZN7b2ShapeD2Ev(x.handle)
            ccall((:_ZN7b2ShapeD2Ev, LIBRARY_PATH), Cvoid, (Ptr{b2Shape},), x.handle)
        end
        return obj
    end
end

# Allow passing Managed object to ccall expecting Ptr
unsafe_convert(::Type{Ptr{b2Shape}}, obj::Managedb2Shape) = obj.handle

export Managedb2Shape

mutable struct Managedb2BlockAllocator
    handle::Ptr{b2BlockAllocator}
    
    function Managedb2BlockAllocator(ptr::Ptr{b2BlockAllocator})
        if ptr == C_NULL
            error("Cannot wrap NULL pointer in Managedb2BlockAllocator")
        end
        obj = new(ptr)
        finalizer(obj) do x
            # Call deleter: _ZN16b2BlockAllocatorD2Ev(x.handle)
            ccall((:_ZN16b2BlockAllocatorD2Ev, LIBRARY_PATH), Cvoid, (Ptr{b2BlockAllocator},), x.handle)
        end
        return obj
    end
end

# Allow passing Managed object to ccall expecting Ptr
unsafe_convert(::Type{Ptr{b2BlockAllocator}}, obj::Managedb2BlockAllocator) = obj.handle

export Managedb2BlockAllocator

mutable struct Managedb2Island
    handle::Ptr{b2Island}
    
    function Managedb2Island(ptr::Ptr{b2Island})
        if ptr == C_NULL
            error("Cannot wrap NULL pointer in Managedb2Island")
        end
        obj = new(ptr)
        finalizer(obj) do x
            # Call deleter: _ZN8b2IslandD2Ev(x.handle)
            ccall((:_ZN8b2IslandD2Ev, LIBRARY_PATH), Cvoid, (Ptr{b2Island},), x.handle)
        end
        return obj
    end
end

# Allow passing Managed object to ccall expecting Ptr
unsafe_convert(::Type{Ptr{b2Island}}, obj::Managedb2Island) = obj.handle

export Managedb2Island

mutable struct Managedb2BroadPhase
    handle::Ptr{b2BroadPhase}
    
    function Managedb2BroadPhase(ptr::Ptr{b2BroadPhase})
        if ptr == C_NULL
            error("Cannot wrap NULL pointer in Managedb2BroadPhase")
        end
        obj = new(ptr)
        finalizer(obj) do x
            # Call deleter: _ZN12b2BroadPhaseD2Ev(x.handle)
            ccall((:_ZN12b2BroadPhaseD2Ev, LIBRARY_PATH), Cvoid, (Ptr{b2BroadPhase},), x.handle)
        end
        return obj
    end
end

# Allow passing Managed object to ccall expecting Ptr
unsafe_convert(::Type{Ptr{b2BroadPhase}}, obj::Managedb2BroadPhase) = obj.handle

export Managedb2BroadPhase

mutable struct Managedb2PolygonShape
    handle::Ptr{b2PolygonShape}
    
    function Managedb2PolygonShape(ptr::Ptr{b2PolygonShape})
        if ptr == C_NULL
            error("Cannot wrap NULL pointer in Managedb2PolygonShape")
        end
        obj = new(ptr)
        finalizer(obj) do x
            # Call deleter: _ZN14b2PolygonShapeD0Ev(x.handle)
            ccall((:_ZN14b2PolygonShapeD0Ev, LIBRARY_PATH), Cvoid, (Ptr{b2PolygonShape},), x.handle)
        end
        return obj
    end
end

# Allow passing Managed object to ccall expecting Ptr
unsafe_convert(::Type{Ptr{b2PolygonShape}}, obj::Managedb2PolygonShape) = obj.handle

export Managedb2PolygonShape

mutable struct Managedb2Rope
    handle::Ptr{b2Rope}
    
    function Managedb2Rope(ptr::Ptr{b2Rope})
        if ptr == C_NULL
            error("Cannot wrap NULL pointer in Managedb2Rope")
        end
        obj = new(ptr)
        finalizer(obj) do x
            # Call deleter: _ZN6b2RopeD2Ev(x.handle)
            ccall((:_ZN6b2RopeD2Ev, LIBRARY_PATH), Cvoid, (Ptr{b2Rope},), x.handle)
        end
        return obj
    end
end

# Allow passing Managed object to ccall expecting Ptr
unsafe_convert(::Type{Ptr{b2Rope}}, obj::Managedb2Rope) = obj.handle

export Managedb2Rope

mutable struct Managedb2DistanceJoint
    handle::Ptr{b2DistanceJoint}
    
    function Managedb2DistanceJoint(ptr::Ptr{b2DistanceJoint})
        if ptr == C_NULL
            error("Cannot wrap NULL pointer in Managedb2DistanceJoint")
        end
        obj = new(ptr)
        finalizer(obj) do x
            # Call deleter: _ZN15b2DistanceJointD0Ev(x.handle)
            ccall((:_ZN15b2DistanceJointD0Ev, LIBRARY_PATH), Cvoid, (Ptr{b2DistanceJoint},), x.handle)
        end
        return obj
    end
end

# Allow passing Managed object to ccall expecting Ptr
unsafe_convert(::Type{Ptr{b2DistanceJoint}}, obj::Managedb2DistanceJoint) = obj.handle

export Managedb2DistanceJoint

mutable struct Managedb2StackAllocator
    handle::Ptr{b2StackAllocator}
    
    function Managedb2StackAllocator(ptr::Ptr{b2StackAllocator})
        if ptr == C_NULL
            error("Cannot wrap NULL pointer in Managedb2StackAllocator")
        end
        obj = new(ptr)
        finalizer(obj) do x
            # Call deleter: _ZN16b2StackAllocatorD2Ev(x.handle)
            ccall((:_ZN16b2StackAllocatorD2Ev, LIBRARY_PATH), Cvoid, (Ptr{b2StackAllocator},), x.handle)
        end
        return obj
    end
end

# Allow passing Managed object to ccall expecting Ptr
unsafe_convert(::Type{Ptr{b2StackAllocator}}, obj::Managedb2StackAllocator) = obj.handle

export Managedb2StackAllocator

mutable struct Managedb2ChainShape
    handle::Ptr{b2ChainShape}
    
    function Managedb2ChainShape(ptr::Ptr{b2ChainShape})
        if ptr == C_NULL
            error("Cannot wrap NULL pointer in Managedb2ChainShape")
        end
        obj = new(ptr)
        finalizer(obj) do x
            # Call deleter: _ZN12b2ChainShapeD0Ev(x.handle)
            ccall((:_ZN12b2ChainShapeD0Ev, LIBRARY_PATH), Cvoid, (Ptr{b2ChainShape},), x.handle)
        end
        return obj
    end
end

# Allow passing Managed object to ccall expecting Ptr
unsafe_convert(::Type{Ptr{b2ChainShape}}, obj::Managedb2ChainShape) = obj.handle

export Managedb2ChainShape

mutable struct Managedb2MotorJoint
    handle::Ptr{b2MotorJoint}
    
    function Managedb2MotorJoint(ptr::Ptr{b2MotorJoint})
        if ptr == C_NULL
            error("Cannot wrap NULL pointer in Managedb2MotorJoint")
        end
        obj = new(ptr)
        finalizer(obj) do x
            # Call deleter: _ZN12b2MotorJointD0Ev(x.handle)
            ccall((:_ZN12b2MotorJointD0Ev, LIBRARY_PATH), Cvoid, (Ptr{b2MotorJoint},), x.handle)
        end
        return obj
    end
end

# Allow passing Managed object to ccall expecting Ptr
unsafe_convert(::Type{Ptr{b2MotorJoint}}, obj::Managedb2MotorJoint) = obj.handle

export Managedb2MotorJoint

mutable struct Managedb2Contact
    handle::Ptr{b2Contact}
    
    function Managedb2Contact(ptr::Ptr{b2Contact})
        if ptr == C_NULL
            error("Cannot wrap NULL pointer in Managedb2Contact")
        end
        obj = new(ptr)
        finalizer(obj) do x
            # Call deleter: _ZN16b2ContactManager7DestroyEP9b2Contact(x.handle)
            ccall((:_ZN16b2ContactManager7DestroyEP9b2Contact, LIBRARY_PATH), Cvoid, (Ptr{b2Contact},), x.handle)
        end
        return obj
    end
end

# Allow passing Managed object to ccall expecting Ptr
unsafe_convert(::Type{Ptr{b2Contact}}, obj::Managedb2Contact) = obj.handle

export Managedb2Contact

mutable struct Managedb2PrismaticJoint
    handle::Ptr{b2PrismaticJoint}
    
    function Managedb2PrismaticJoint(ptr::Ptr{b2PrismaticJoint})
        if ptr == C_NULL
            error("Cannot wrap NULL pointer in Managedb2PrismaticJoint")
        end
        obj = new(ptr)
        finalizer(obj) do x
            # Call deleter: _ZN16b2PrismaticJointD0Ev(x.handle)
            ccall((:_ZN16b2PrismaticJointD0Ev, LIBRARY_PATH), Cvoid, (Ptr{b2PrismaticJoint},), x.handle)
        end
        return obj
    end
end

# Allow passing Managed object to ccall expecting Ptr
unsafe_convert(::Type{Ptr{b2PrismaticJoint}}, obj::Managedb2PrismaticJoint) = obj.handle

export Managedb2PrismaticJoint

"""Get union member `cf` as `b2ContactFeature` from `b2ContactID`."""
function get_cf(u::b2ContactID)::b2ContactFeature
    return unsafe_load(Ptr{b2ContactFeature}(pointer_from_objref(u)))
end

"""Set union member `cf` as `b2ContactFeature` in `b2ContactID`."""
function set_cf!(u::b2ContactID, v::b2ContactFeature)
    unsafe_store!(Ptr{b2ContactFeature}(pointer_from_objref(u)), v)
end

"""Get union member `key` as `Cuint` from `b2ContactID`."""
function get_key(u::b2ContactID)::Cuint
    return unsafe_load(Ptr{Cuint}(pointer_from_objref(u)))
end

"""Set union member `key` as `Cuint` in `b2ContactID`."""
function set_key!(u::b2ContactID, v::Cuint)
    unsafe_store!(Ptr{Cuint}(pointer_from_objref(u)), v)
end

export get_cf, set_cf!, get_key, set_key!, b2_gjkMaxIters, b2_gjkMaxIters_ptr, b2_defaultFilter, b2_defaultFilter_ptr, b2_toiMaxTime, b2_toiMaxTime_ptr, b2_version, b2_version_ptr, b2_toiRootIters, b2_toiRootIters_ptr, b2_gjkCalls, b2_gjkCalls_ptr, b2_toiMaxRootIters, b2_toiMaxRootIters_ptr, b2_toiCalls, b2_toiCalls_ptr, b2_toiTime, b2_toiTime_ptr, b2_gjkIters, b2_gjkIters_ptr, g_blockSolve, g_blockSolve_ptr, b2_defaultListener, b2_defaultListener_ptr, b2_toiMaxIters, b2_toiMaxIters_ptr, b2Vec2_zero, b2Vec2_zero_ptr, b2_dumpFile, b2_dumpFile_ptr, b2_toiIters, b2_toiIters_ptr, b2Distance, b2OpenDump, b2CloseDump, b2ShapeCast, b2Log_Default, b2TestOverlap, b2Free_Default, b2TimeOfImpact, b2Alloc_Default, b2CollideCircles, b2GetPointStates, b2CollidePolygons, b2LinearStiffness, b2AngularStiffness, b2ClipSegmentToLine, b2_pi, b2CollideEdgeAndCircle, b2CollideEdgeAndPolygon, b2CollidePolygonAndCircle, b2_baumgarte, b2_linearSlop, b2_angularSlop, b2_maxRotation, b2_maxSubSteps, b2_timeToSleep, b2_toiBaumgarte, b2_aabbExtension, b2_polygonRadius, b2_aabbMultiplier, b2_maxTOIContacts, b2_maxTranslation, b2_maxManifoldPoints, b2_maxPolygonVertices, b2_lengthUnitsPerMeter, b2_maxLinearCorrection, b2_linearSleepTolerance, b2_maxAngularCorrection, b2_angularSleepTolerance, b2Log, b2Log_Cint, b2Log_Cdouble, b2Log_Cstring, b2Log_Cint_Cint, b2Log_Cdouble_Cdouble, b2Log_Cstring_Cint, b2Dump, b2Dump_Cint, b2Dump_Cdouble, b2Dump_Cstring, b2Dump_Cint_Cint, b2Dump_Cdouble_Cdouble, b2Dump_Cdouble_Cdouble_Cdouble, b2Dump_Cstring_Cint, b2EdgeShape_SetOneSided, b2EdgeShape_SetTwoSided, b2EdgeShape_destroy_b2EdgeShape, b2GearJoint_InitVelocityConstraints, b2GearJoint_SolvePositionConstraints, b2GearJoint_SolveVelocityConstraints, b2GearJoint_Dump, b2GearJoint_SetRatio, b2GearJoint_destroy_b2GearJoint, b2WeldJoint_InitVelocityConstraints, b2WeldJoint_SolvePositionConstraints, b2WeldJoint_SolveVelocityConstraints, b2WeldJoint_Dump, b2WeldJoint_destroy_b2WeldJoint, b2BroadPhase_BufferMove, b2BroadPhase_TouchProxy, b2BroadPhase_CreateProxy, void_b2BroadPhase_UpdatePairs_b2ContactManager, b2BroadPhase_DestroyProxy, b2BroadPhase_UnBufferMove, b2BroadPhase_QueryCallback, b2BroadPhase_MoveProxy, b2BroadPhase_destroy_b2BroadPhase, b2ChainShape_CreateLoop, b2ChainShape_CreateChain, b2ChainShape_Clear, b2ChainShape_destroy_b2ChainShape, b2MotorJoint_SetMaxForce, b2MotorJoint_SetMaxTorque, b2MotorJoint_SetLinearOffset, b2MotorJoint_SetAngularOffset, b2MotorJoint_SetCorrectionFactor, b2MotorJoint_InitVelocityConstraints, b2MotorJoint_SolvePositionConstraints, b2MotorJoint_SolveVelocityConstraints, b2MotorJoint_Dump, b2MotorJoint_destroy_b2MotorJoint, b2MouseJoint_SetMaxForce, b2MouseJoint_ShiftOrigin, b2MouseJoint_InitVelocityConstraints, b2MouseJoint_SolvePositionConstraints, b2MouseJoint_SolveVelocityConstraints, b2MouseJoint_Dump, b2MouseJoint_SetTarget, b2MouseJoint_destroy_b2MouseJoint, b2WheelJoint_SetDamping, b2WheelJoint_EnableLimit, b2WheelJoint_EnableMotor, b2WheelJoint_SetStiffness, b2WheelJoint_SetMotorSpeed, b2WheelJoint_SetMaxMotorTorque, b2WheelJoint_InitVelocityConstraints, b2WheelJoint_SolvePositionConstraints, b2WheelJoint_SolveVelocityConstraints, b2WheelJoint_Dump, b2WheelJoint_SetLimits, b2WheelJoint_destroy_b2WheelJoint, b2CircleShape_destroy_b2CircleShape, b2DynamicTree_InsertLeaf, b2DynamicTree_RemoveLeaf, b2DynamicTree_CreateProxy, b2DynamicTree_ShiftOrigin, b2DynamicTree_AllocateNode, b2DynamicTree_DestroyProxy, b2DynamicTree_RebuildBottomUp, b2DynamicTree_Balance, b2DynamicTree_FreeNode, b2DynamicTree_MoveProxy, b2DynamicTree_destroy_b2DynamicTree, b2PulleyJoint_ShiftOrigin, b2PulleyJoint_InitVelocityConstraints, b2PulleyJoint_SolvePositionConstraints, b2PulleyJoint_SolveVelocityConstraints, b2PulleyJoint_Dump, b2PulleyJoint_destroy_b2PulleyJoint, b2PolygonShape_Set, b2PolygonShape_SetAsBox, b2PolygonShape_destroy_b2PolygonShape, b2WeldJointDef_Initialize, b2CircleContact_Create, b2CircleContact_Destroy, b2CircleContact_Evaluate, b2CircleContact_destroy_b2CircleContact, b2ContactFilter_ShouldCollide, b2ContactFilter_destroy_b2ContactFilter, b2ContactSolver_StoreImpulses, b2ContactSolver_SolvePositionConstraints, b2ContactSolver_SolveVelocityConstraints, b2ContactSolver_SolveTOIPositionConstraints, b2ContactSolver_InitializeVelocityConstraints, b2ContactSolver_WarmStart, b2ContactSolver_destroy_b2ContactSolver, b2DistanceJoint_SetMaxLength, b2DistanceJoint_SetMinLength, b2DistanceJoint_InitVelocityConstraints, b2DistanceJoint_SolvePositionConstraints, b2DistanceJoint_SolveVelocityConstraints, b2DistanceJoint_Dump, b2DistanceJoint_SetLength, b2DistanceJoint_destroy_b2DistanceJoint, b2DistanceProxy_Set, b2FrictionJoint_SetMaxForce, b2FrictionJoint_SetMaxTorque, b2FrictionJoint_InitVelocityConstraints, b2FrictionJoint_SolvePositionConstraints, b2FrictionJoint_SolveVelocityConstraints, b2FrictionJoint_Dump, b2FrictionJoint_destroy_b2FrictionJoint, b2MotorJointDef_Initialize, b2RevoluteJoint_EnableLimit, b2RevoluteJoint_EnableMotor, b2RevoluteJoint_SetMotorSpeed, b2RevoluteJoint_SetMaxMotorTorque, b2RevoluteJoint_InitVelocityConstraints, b2RevoluteJoint_SolvePositionConstraints, b2RevoluteJoint_SolveVelocityConstraints, b2RevoluteJoint_Dump, b2RevoluteJoint_SetLimits, b2RevoluteJoint_destroy_b2RevoluteJoint, b2WheelJointDef_Initialize, b2WorldManifold_Initialize, b2BlockAllocator_Free, b2BlockAllocator_Clear, b2BlockAllocator_Allocate, b2BlockAllocator_destroy_b2BlockAllocator, b2ContactManager_FindNewContacts, b2ContactManager_AddPair, b2ContactManager_Collide, b2ContactManager_Destroy, b2PolygonContact_Create, b2PolygonContact_Destroy, b2PolygonContact_Evaluate, b2PolygonContact_destroy_b2PolygonContact, b2PrismaticJoint_EnableLimit, b2PrismaticJoint_EnableMotor, b2PrismaticJoint_SetMotorSpeed, b2PrismaticJoint_SetMaxMotorForce, b2PrismaticJoint_InitVelocityConstraints, b2PrismaticJoint_SolvePositionConstraints, b2PrismaticJoint_SolveVelocityConstraints, b2PrismaticJoint_Dump, b2PrismaticJoint_SetLimits, b2PrismaticJoint_destroy_b2PrismaticJoint, b2PulleyJointDef_Initialize, b2StackAllocator_Free, b2StackAllocator_Allocate, b2StackAllocator_destroy_b2StackAllocator, b2ContactListener_EndContact, b2ContactListener_BeginContact, b2ContactListener_PreSolve, b2ContactListener_PostSolve, b2ContactListener_destroy_b2ContactListener, b2DistanceJointDef_Initialize, b2FrictionJointDef_Initialize, b2RevoluteJointDef_Initialize, b2PrismaticJointDef_Initialize, b2SeparationFunction_Initialize, b2EdgeAndCircleContact_Create, b2EdgeAndCircleContact_Destroy, b2EdgeAndCircleContact_Evaluate, b2EdgeAndCircleContact_destroy_b2EdgeAndCircleContact, b2ChainAndCircleContact_Create, b2ChainAndCircleContact_Destroy, b2ChainAndCircleContact_Evaluate, b2ChainAndCircleContact_destroy_b2ChainAndCircleContact, b2EdgeAndPolygonContact_Create, b2EdgeAndPolygonContact_Destroy, b2EdgeAndPolygonContact_Evaluate, b2EdgeAndPolygonContact_destroy_b2EdgeAndPolygonContact, b2ChainAndPolygonContact_Create, b2ChainAndPolygonContact_Destroy, b2ChainAndPolygonContact_Evaluate, b2ChainAndPolygonContact_destroy_b2ChainAndPolygonContact, b2PositionSolverManifold_Initialize, b2PolygonAndCircleContact_Create, b2PolygonAndCircleContact_Destroy, b2PolygonAndCircleContact_Evaluate, b2PolygonAndCircleContact_destroy_b2PolygonAndCircleContact, b2Body_SetEnabled, b2Body_SetMassData, b2Body_SetTransform, b2Body_CreateFixture, b2Body_ResetMassData, b2Body_DestroyFixture, b2Body_SetFixedRotation, b2Body_SynchronizeFixtures, b2Body_Dump, b2Body_SetType, b2Body_destroy_b2Body, b2Draw_ClearFlags, b2Draw_AppendFlags, b2Draw_SetFlags, b2Draw_destroy_b2Draw, b2Rope_ApplyBendForces, b2Rope_SolveStretch_PBD, b2Rope_SolveStretch_XPBD, b2Rope_SolveBend_PBD_Angle, b2Rope_SolveBend_PBD_Height, b2Rope_SolveBend_XPBD_Angle, b2Rope_SolveBend_PBD_Distance, b2Rope_SolveBend_PBD_Triangle, b2Rope_Step, b2Rope_Reset, b2Rope_Create, b2Rope_SetTuning, b2Rope_destroy_b2Rope, b2Joint_ShiftOrigin, b2Joint_Dump, b2Joint_Create, b2Joint_Destroy, b2Joint_destroy_b2Joint, b2Shape_destroy_b2Shape, b2Timer_Reset, b2World_CreateBody, b2World_ClearForces, b2World_CreateJoint, b2World_DestroyBody, b2World_ShiftOrigin, b2World_DestroyJoint, b2World_SetDebugDraw, b2World_SetAllowSleeping, b2World_SetContactFilter, b2World_SetContactListener, b2World_SetDestructionListener, b2World_Dump, b2World_Step, b2World_Solve, b2World_SolveTOI, b2World_DebugDraw, b2World_DrawShape, b2World_destroy_b2World, b2Island_Solve, b2Island_Report, b2Island_SolveTOI, b2Island_destroy_b2Island, b2Contact_InitializeRegisters, b2Contact_Create, b2Contact_Update, b2Contact_AddType, b2Contact_Destroy, b2Contact_destroy_b2Contact, b2Fixture_Synchronize, b2Fixture_CreateProxies, b2Fixture_SetFilterData, b2Fixture_DestroyProxies, b2Fixture_Dump, b2Fixture_Create, b2Fixture_Destroy, b2Fixture_Refilter, b2Fixture_SetSensor, b2Simplex_Solve2, b2Simplex_Solve3, b2Simplex_ReadCache, b2EdgeShape_ComputeAABB, b2EdgeShape_ComputeMass, b2EdgeShape_GetChildCount, b2EdgeShape_Clone, b2EdgeShape_RayCast, b2EdgeShape_TestPoint, b2GearJoint_GetAnchorA, b2GearJoint_GetAnchorB, b2GearJoint_GetReactionForce, b2GearJoint_GetReactionTorque, b2GearJoint_GetRatio, b2WeldJoint_GetAnchorA, b2WeldJoint_GetAnchorB, b2WeldJoint_GetReactionForce, b2WeldJoint_GetReactionTorque, b2ChainShape_ComputeAABB, b2ChainShape_ComputeMass, b2ChainShape_GetChildEdge, b2ChainShape_GetChildCount, b2ChainShape_Clone, b2ChainShape_RayCast, b2ChainShape_TestPoint, b2MotorJoint_GetAnchorA, b2MotorJoint_GetAnchorB, b2MotorJoint_GetMaxForce, b2MotorJoint_GetMaxTorque, b2MotorJoint_GetLinearOffset, b2MotorJoint_GetAngularOffset, b2MotorJoint_GetReactionForce, b2MotorJoint_GetReactionTorque, b2MotorJoint_GetCorrectionFactor, b2MouseJoint_GetAnchorA, b2MouseJoint_GetAnchorB, b2MouseJoint_GetMaxForce, b2MouseJoint_GetReactionForce, b2MouseJoint_GetReactionTorque, b2MouseJoint_GetTarget, b2WheelJoint_GetAnchorA, b2WheelJoint_GetAnchorB, b2WheelJoint_GetDamping, b2WheelJoint_GetStiffness, b2WheelJoint_GetJointAngle, b2WheelJoint_GetLowerLimit, b2WheelJoint_GetUpperLimit, b2WheelJoint_GetMotorTorque, b2WheelJoint_IsLimitEnabled, b2WheelJoint_IsMotorEnabled, b2WheelJoint_GetReactionForce, b2WheelJoint_GetReactionTorque, b2WheelJoint_GetJointLinearSpeed, b2WheelJoint_GetJointTranslation, b2WheelJoint_GetJointAngularSpeed, b2WheelJoint_Draw, b2CircleShape_ComputeAABB, b2CircleShape_ComputeMass, b2CircleShape_GetChildCount, b2CircleShape_Clone, b2CircleShape_RayCast, b2CircleShape_TestPoint, b2DynamicTree_GetAreaRatio, b2DynamicTree_ComputeHeight, b2DynamicTree_GetMaxBalance, b2DynamicTree_ValidateMetrics, b2DynamicTree_ValidateStructure, void_b2DynamicTree_Query_b2BroadPhase, void_b2DynamicTree_Query_b2WorldQueryWrapper, void_b2DynamicTree_RayCast_b2WorldRayCastWrapper, b2DynamicTree_Validate, b2DynamicTree_GetHeight, b2PulleyJoint_GetAnchorA, b2PulleyJoint_GetAnchorB, b2PulleyJoint_GetLengthA, b2PulleyJoint_GetLengthB, b2PulleyJoint_GetGroundAnchorA, b2PulleyJoint_GetGroundAnchorB, b2PulleyJoint_GetReactionForce, b2PulleyJoint_GetCurrentLengthA, b2PulleyJoint_GetCurrentLengthB, b2PulleyJoint_GetReactionTorque, b2PulleyJoint_GetRatio, b2PolygonShape_ComputeAABB, b2PolygonShape_ComputeMass, b2PolygonShape_GetChildCount, b2PolygonShape_Clone, b2PolygonShape_RayCast, b2PolygonShape_Validate, b2PolygonShape_TestPoint, b2DistanceJoint_GetAnchorA, b2DistanceJoint_GetAnchorB, b2DistanceJoint_GetCurrentLength, b2DistanceJoint_GetReactionForce, b2DistanceJoint_GetReactionTorque, b2DistanceJoint_Draw, b2FrictionJoint_GetAnchorA, b2FrictionJoint_GetAnchorB, b2FrictionJoint_GetMaxForce, b2FrictionJoint_GetMaxTorque, b2FrictionJoint_GetReactionForce, b2FrictionJoint_GetReactionTorque, b2RevoluteJoint_GetAnchorA, b2RevoluteJoint_GetAnchorB, b2RevoluteJoint_GetJointAngle, b2RevoluteJoint_GetJointSpeed, b2RevoluteJoint_GetLowerLimit, b2RevoluteJoint_GetUpperLimit, b2RevoluteJoint_GetMotorTorque, b2RevoluteJoint_IsLimitEnabled, b2RevoluteJoint_IsMotorEnabled, b2RevoluteJoint_GetReactionForce, b2RevoluteJoint_GetReactionTorque, b2RevoluteJoint_Draw, b2PrismaticJoint_GetAnchorA, b2PrismaticJoint_GetAnchorB, b2PrismaticJoint_GetJointSpeed, b2PrismaticJoint_GetLowerLimit, b2PrismaticJoint_GetMotorForce, b2PrismaticJoint_GetUpperLimit, b2PrismaticJoint_IsLimitEnabled, b2PrismaticJoint_IsMotorEnabled, b2PrismaticJoint_GetReactionForce, b2PrismaticJoint_GetReactionTorque, b2PrismaticJoint_GetJointTranslation, b2PrismaticJoint_Draw, b2StackAllocator_GetMaxAllocation, b2SeparationFunction_FindMinSeparation, b2SeparationFunction_Evaluate, b2AABB_RayCast, b2Body_ShouldCollide, b2Draw_GetFlags, b2Rope_Draw, b2Joint_Draw, b2Joint_IsEnabled, b2Mat33_GetInverse22, b2Mat33_GetSymInverse33, b2Mat33_Solve22, b2Mat33_Solve33, b2Timer_GetMilliseconds, b2World_GetProxyCount, b2World_GetTreeHeight, b2World_GetTreeBalance, b2World_GetTreeQuality, b2World_RayCast, b2World_QueryAABB, b2Simplex_GetMetric, b2JointType, e_unknownJoint, e_revoluteJoint, e_prismaticJoint, e_distanceJoint, e_pulleyJoint, e_mouseJoint, e_gearJoint, e_wheelJoint, e_weldJoint, e_frictionJoint, e_ropeJoint, e_motorJoint, b2StretchingModel, b2_pbdStretchingModel, b2_xpbdStretchingModel, b2PointState, b2_nullState, b2_addState, b2_persistState, b2_removeState, b2BendingModel, b2_springAngleBendingModel, b2_pbdAngleBendingModel, b2_xpbdAngleBendingModel, b2_pbdDistanceBendingModel, b2_pbdHeightBendingModel, b2_pbdTriangleBendingModel, c_Type, e_circle, e_edge, e_polygon, e_chain, e_typeCount, State, e_unknown, e_failed, e_overlapped, e_touching, e_separated, b2BodyType, b2_staticBody, b2_kinematicBody, b2_dynamicBody, b2JointDef, b2RopeDef, b2QueryCallback, b2WorldRayCastWrapper, b2Timer, b2Position, b2PositionSolverManifold, b2Rot, b2RayCastOutput, b2FixtureUserData, b2ContactSolverDef, b2Profile, b2RayCastInput, b2Shape, b2TempPolygon, b2Transform, b2GearJointDef, b2ManifoldPoint, b2Mat33, b2PolygonShape, b2Mat22, b2Filter, b2StackEntry, b2WheelJointDef, b2RevoluteJoint, b2ContactEdge, b2Vec3, b2GearJoint, b2Simplex, b2Joint, b2Manifold, b2JointUserData, b2RevoluteJointDef, b2PrismaticJointDef, b2DynamicTree, b2BodyUserData, b2PulleyJoint, b2MouseJoint, b2WorldQueryWrapper, b2SimplexCache, b2RayCastCallback, b2DistanceJointDef, b2RopeBend, b2TOIInput, b2ContactVelocityConstraint, b2BroadPhase, b2ContactManager, b2StackAllocator, b2SizeMap, b2DistanceInput, b2MotorJoint, b2SimplexVertex, b2DistanceOutput, b2WheelJoint, b2TreeNode, b2DistanceProxy, b2RopeTuning, b2VelocityConstraintPoint, b2ContactFilter, b2FrictionJoint, b2PulleyJointDef, b2EdgeShape, b2ContactRegister, b2Sweep, b2World, b2CircleShape, b2RopeStretch, b2FixtureProxy, b2ContactSolver, b2Block, b2ContactID, b2Draw, b2WorldManifold, b2ContactImpulse, timeval, b2BodyDef, b2BlockAllocator, b2TOIOutput, b2ClipVertex, b2Island, b2JointEdge, b2AABB, b2SolverData, b2TimeStep, b2FixtureDef, b2DistanceJoint, b2EPAxis, b2Contact, b2Version, b2ContactFeature, b2MassData, b2Color, b2Fixture, b2MotorJointDef, b2SeparationFunction, b2ReferenceFace, b2ShapeCastOutput, b2FrictionJointDef, b2ContactListener, b2Velocity, b2DestructionListener, b2WeldJoint, b2ShapeCastInput, b2ContactPositionConstraint, b2Pair, b2GrowableStack_int_256, b2Chunk, b2Vec2, b2Rope, b2MouseJointDef, b2WeldJointDef, b2ChainShape, b2PrismaticJoint, b2Body

# =============================================================================
# Global Variables
# =============================================================================

"""
    b2_gjkMaxIters()

Get value of global variable `b2_gjkMaxIters`.
"""
function b2_gjkMaxIters()::Cint
    ptr = cglobal((:b2_gjkMaxIters, LIBRARY_PATH), Cint)
    return unsafe_load(ptr)
end

"""
    b2_gjkMaxIters_ptr()

Get pointer to global variable `b2_gjkMaxIters`.
"""
function b2_gjkMaxIters_ptr()::Ptr{Cint}
    return cglobal((:b2_gjkMaxIters, LIBRARY_PATH), Cint)
end

"""
    b2_defaultFilter()

Get value of global variable `b2_defaultFilter`.
"""
function b2_defaultFilter()::b2ContactFilter
    ptr = cglobal((:b2_defaultFilter, LIBRARY_PATH), b2ContactFilter)
    return unsafe_load(ptr)
end

"""
    b2_defaultFilter_ptr()

Get pointer to global variable `b2_defaultFilter`.
"""
function b2_defaultFilter_ptr()::Ptr{b2ContactFilter}
    return cglobal((:b2_defaultFilter, LIBRARY_PATH), b2ContactFilter)
end

"""
    b2_toiMaxTime()

Get value of global variable `b2_toiMaxTime`.
"""
function b2_toiMaxTime()::Cfloat
    ptr = cglobal((:b2_toiMaxTime, LIBRARY_PATH), Cfloat)
    return unsafe_load(ptr)
end

"""
    b2_toiMaxTime_ptr()

Get pointer to global variable `b2_toiMaxTime`.
"""
function b2_toiMaxTime_ptr()::Ptr{Cfloat}
    return cglobal((:b2_toiMaxTime, LIBRARY_PATH), Cfloat)
end

"""
    b2_version()

Get value of global variable `b2_version`.
"""
function b2_version()::b2Version
    ptr = cglobal((:b2_version, LIBRARY_PATH), b2Version)
    return unsafe_load(ptr)
end

"""
    b2_version_ptr()

Get pointer to global variable `b2_version`.
"""
function b2_version_ptr()::Ptr{b2Version}
    return cglobal((:b2_version, LIBRARY_PATH), b2Version)
end

"""
    b2_toiRootIters()

Get value of global variable `b2_toiRootIters`.
"""
function b2_toiRootIters()::Cint
    ptr = cglobal((:b2_toiRootIters, LIBRARY_PATH), Cint)
    return unsafe_load(ptr)
end

"""
    b2_toiRootIters_ptr()

Get pointer to global variable `b2_toiRootIters`.
"""
function b2_toiRootIters_ptr()::Ptr{Cint}
    return cglobal((:b2_toiRootIters, LIBRARY_PATH), Cint)
end

"""
    b2_gjkCalls()

Get value of global variable `b2_gjkCalls`.
"""
function b2_gjkCalls()::Cint
    ptr = cglobal((:b2_gjkCalls, LIBRARY_PATH), Cint)
    return unsafe_load(ptr)
end

"""
    b2_gjkCalls_ptr()

Get pointer to global variable `b2_gjkCalls`.
"""
function b2_gjkCalls_ptr()::Ptr{Cint}
    return cglobal((:b2_gjkCalls, LIBRARY_PATH), Cint)
end

"""
    b2_toiMaxRootIters()

Get value of global variable `b2_toiMaxRootIters`.
"""
function b2_toiMaxRootIters()::Cint
    ptr = cglobal((:b2_toiMaxRootIters, LIBRARY_PATH), Cint)
    return unsafe_load(ptr)
end

"""
    b2_toiMaxRootIters_ptr()

Get pointer to global variable `b2_toiMaxRootIters`.
"""
function b2_toiMaxRootIters_ptr()::Ptr{Cint}
    return cglobal((:b2_toiMaxRootIters, LIBRARY_PATH), Cint)
end

"""
    b2_toiCalls()

Get value of global variable `b2_toiCalls`.
"""
function b2_toiCalls()::Cint
    ptr = cglobal((:b2_toiCalls, LIBRARY_PATH), Cint)
    return unsafe_load(ptr)
end

"""
    b2_toiCalls_ptr()

Get pointer to global variable `b2_toiCalls`.
"""
function b2_toiCalls_ptr()::Ptr{Cint}
    return cglobal((:b2_toiCalls, LIBRARY_PATH), Cint)
end

"""
    b2_toiTime()

Get value of global variable `b2_toiTime`.
"""
function b2_toiTime()::Cfloat
    ptr = cglobal((:b2_toiTime, LIBRARY_PATH), Cfloat)
    return unsafe_load(ptr)
end

"""
    b2_toiTime_ptr()

Get pointer to global variable `b2_toiTime`.
"""
function b2_toiTime_ptr()::Ptr{Cfloat}
    return cglobal((:b2_toiTime, LIBRARY_PATH), Cfloat)
end

"""
    b2_gjkIters()

Get value of global variable `b2_gjkIters`.
"""
function b2_gjkIters()::Cint
    ptr = cglobal((:b2_gjkIters, LIBRARY_PATH), Cint)
    return unsafe_load(ptr)
end

"""
    b2_gjkIters_ptr()

Get pointer to global variable `b2_gjkIters`.
"""
function b2_gjkIters_ptr()::Ptr{Cint}
    return cglobal((:b2_gjkIters, LIBRARY_PATH), Cint)
end

"""
    g_blockSolve()

Get value of global variable `g_blockSolve`.
"""
function g_blockSolve()::Bool
    ptr = cglobal((:g_blockSolve, LIBRARY_PATH), Bool)
    return unsafe_load(ptr)
end

"""
    g_blockSolve_ptr()

Get pointer to global variable `g_blockSolve`.
"""
function g_blockSolve_ptr()::Ptr{Bool}
    return cglobal((:g_blockSolve, LIBRARY_PATH), Bool)
end

"""
    b2_defaultListener()

Get value of global variable `b2_defaultListener`.
"""
function b2_defaultListener()::b2ContactListener
    ptr = cglobal((:b2_defaultListener, LIBRARY_PATH), b2ContactListener)
    return unsafe_load(ptr)
end

"""
    b2_defaultListener_ptr()

Get pointer to global variable `b2_defaultListener`.
"""
function b2_defaultListener_ptr()::Ptr{b2ContactListener}
    return cglobal((:b2_defaultListener, LIBRARY_PATH), b2ContactListener)
end

"""
    b2_toiMaxIters()

Get value of global variable `b2_toiMaxIters`.
"""
function b2_toiMaxIters()::Cint
    ptr = cglobal((:b2_toiMaxIters, LIBRARY_PATH), Cint)
    return unsafe_load(ptr)
end

"""
    b2_toiMaxIters_ptr()

Get pointer to global variable `b2_toiMaxIters`.
"""
function b2_toiMaxIters_ptr()::Ptr{Cint}
    return cglobal((:b2_toiMaxIters, LIBRARY_PATH), Cint)
end

"""
    b2Vec2_zero()

Get value of global variable `b2Vec2_zero`.
"""
function b2Vec2_zero()::b2Vec2
    ptr = cglobal((:b2Vec2_zero, LIBRARY_PATH), b2Vec2)
    return unsafe_load(ptr)
end

"""
    b2Vec2_zero_ptr()

Get pointer to global variable `b2Vec2_zero`.
"""
function b2Vec2_zero_ptr()::Ptr{b2Vec2}
    return cglobal((:b2Vec2_zero, LIBRARY_PATH), b2Vec2)
end

"""
    b2_dumpFile()

Get value of global variable `b2_dumpFile`.
"""
function b2_dumpFile()::Ptr{_IO_FILE}
    ptr = cglobal((:b2_dumpFile, LIBRARY_PATH), Ptr{_IO_FILE})
    return unsafe_load(ptr)
end

"""
    b2_dumpFile_ptr()

Get pointer to global variable `b2_dumpFile`.
"""
function b2_dumpFile_ptr()::Ptr{Ptr{_IO_FILE}}
    return cglobal((:b2_dumpFile, LIBRARY_PATH), Ptr{_IO_FILE})
end

"""
    b2_toiIters()

Get value of global variable `b2_toiIters`.
"""
function b2_toiIters()::Cint
    ptr = cglobal((:b2_toiIters, LIBRARY_PATH), Cint)
    return unsafe_load(ptr)
end

"""
    b2_toiIters_ptr()

Get pointer to global variable `b2_toiIters`.
"""
function b2_toiIters_ptr()::Ptr{Cint}
    return cglobal((:b2_toiIters, LIBRARY_PATH), Cint)
end


"""
    b2Distance(output::Any, cache::Any, input::Any) -> Cvoid

Wrapper for `b2Distance(b2DistanceOutput*, b2SimplexCache*, b2DistanceInput const*)`

# Arguments
- `output::Ptr{b2DistanceOutput}`
- `cache::Ptr{b2SimplexCache}`
- `input::Ptr{b2DistanceInput}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_Z10b2DistanceP16b2DistanceOutputP14b2SimplexCachePK15b2DistanceInput`
"""

function b2Distance(output::Any, cache::Any, input::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__Z10b2DistanceP16b2DistanceOutputP14b2SimplexCachePK15b2DistanceInput_thunk", output, cache, input)
end
"""
    b2OpenDump(fileName::Any) -> Cvoid

Wrapper for `b2OpenDump(char const*)`

# Arguments
- `fileName::Ptr{UInt8}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_Z10b2OpenDumpPKc`
"""

function b2OpenDump(fileName::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__Z10b2OpenDumpPKc_thunk", fileName)
end
"""
    b2CloseDump() -> Cvoid

Wrapper for `b2CloseDump()`

# Arguments


# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_Z11b2CloseDumpv`
"""

function b2CloseDump()
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__Z11b2CloseDumpv_thunk")
end
"""
    b2ShapeCast(output::Any, input::Any, _debug::Any) -> Bool

Wrapper for `b2ShapeCast(b2ShapeCastOutput*, b2ShapeCastInput const*)`

# Arguments
- `output::Ptr{b2ShapeCastOutput}`
- `input::Ptr{b2ShapeCastInput}`
- `__debug::Any`

# Returns
- `Bool`

# Metadata
- Mangled symbol: `_Z11b2ShapeCastP17b2ShapeCastOutputPK16b2ShapeCastInput`
"""

function b2ShapeCast(output::Any, input::Any, _debug::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__Z11b2ShapeCastP17b2ShapeCastOutputPK16b2ShapeCastInput_thunk", Bool, output, input, _debug)
end
"""
    b2Log_Default(string::Any, args::Any) -> Cvoid

Wrapper for `b2Log_Default(char const*, __va_list_tag*)`

# Arguments
- `string::Ptr{UInt8}`
- `args::Ptr{Cvoid}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_Z13b2Log_DefaultPKcP13__va_list_tag`
"""

function b2Log_Default(string::Any, args::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__Z13b2Log_DefaultPKcP13__va_list_tag_thunk", string, args)
end
"""
    b2TestOverlap(shapeA::Any, indexA::Integer, shapeB::Any, indexB::Integer, xfA::Ref{b2Transform}, xfB::Ref{b2Transform}) -> Bool

Wrapper for `b2TestOverlap(b2Shape const*, int, b2Shape const*, int, b2Transform const&, b2Transform const&)`

# Arguments
- `shapeA::Ptr{b2Shape}`
- `indexA::Cint`
- `shapeB::Ptr{b2Shape}`
- `indexB::Cint`
- `xfA::Ref{b2Transform}`
- `xfB::Ref{b2Transform}`

# Returns
- `Bool`

# Metadata
- Mangled symbol: `_Z13b2TestOverlapPK7b2ShapeiS1_iRK11b2TransformS4_`
"""

function b2TestOverlap(shapeA::Any, indexA::Integer, shapeB::Any, indexB::Integer, xfA::Ref{b2Transform}, xfB::Ref{b2Transform})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__Z13b2TestOverlapPK7b2ShapeiS1_iRK11b2TransformS4__thunk", Bool, shapeA, indexA, shapeB, indexB, xfA, xfB)
end
"""
    b2Free_Default(mem::Any) -> Cvoid

Wrapper for `b2Free_Default(void*)`

# Arguments
- `mem::Ptr{Cvoid}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_Z14b2Free_DefaultPv`
"""

function b2Free_Default(mem::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__Z14b2Free_DefaultPv_thunk", mem)
end
"""
    b2TimeOfImpact(output::Any, input::Any) -> Cvoid

Wrapper for `b2TimeOfImpact(b2TOIOutput*, b2TOIInput const*)`

# Arguments
- `output::Ptr{b2TOIOutput}`
- `input::Ptr{b2TOIInput}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_Z14b2TimeOfImpactP11b2TOIOutputPK10b2TOIInput`
"""

function b2TimeOfImpact(output::Any, input::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__Z14b2TimeOfImpactP11b2TOIOutputPK10b2TOIInput_thunk", output, input)
end
"""
    b2Alloc_Default(size::Integer) -> Ptr{Cvoid}

Wrapper for `b2Alloc_Default(int)`

# Arguments
- `size::Cint`

# Returns
- `Ptr{Cvoid}`

# Metadata
- Mangled symbol: `_Z15b2Alloc_Defaulti`
"""

function b2Alloc_Default(size::Integer)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__Z15b2Alloc_Defaulti_thunk", Ptr{Cvoid}, size)
end
"""
    b2CollideCircles(manifold::Any, circleA::Any, xfA::Ref{b2Transform}, circleB::Any, xfB::Ref{b2Transform}) -> Cvoid

Wrapper for `b2CollideCircles(b2Manifold*, b2CircleShape const*, b2Transform const&, b2CircleShape const*, b2Transform const&)`

# Arguments
- `manifold::Ptr{b2Manifold}`
- `circleA::Ptr{b2CircleShape}`
- `xfA::Ref{b2Transform}`
- `circleB::Ptr{b2CircleShape}`
- `xfB::Ref{b2Transform}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_Z16b2CollideCirclesP10b2ManifoldPK13b2CircleShapeRK11b2TransformS3_S6_`
"""

function b2CollideCircles(manifold::Any, circleA::Any, xfA::Ref{b2Transform}, circleB::Any, xfB::Ref{b2Transform})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__Z16b2CollideCirclesP10b2ManifoldPK13b2CircleShapeRK11b2TransformS3_S6__thunk", manifold, circleA, xfA, circleB, xfB)
end
"""
    b2GetPointStates(state1::b2PointState, state2::b2PointState, manifold1::Any, manifold2::Any) -> Cvoid

Wrapper for `b2GetPointStates(b2PointState*, b2PointState*, b2Manifold const*, b2Manifold const*)`

# Arguments
- `state1::b2PointState`
- `state2::b2PointState`
- `manifold1::Ptr{b2Manifold}`
- `manifold2::Ptr{b2Manifold}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_Z16b2GetPointStatesP12b2PointStateS0_PK10b2ManifoldS3_`
"""

function b2GetPointStates(state1::b2PointState, state2::b2PointState, manifold1::Any, manifold2::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__Z16b2GetPointStatesP12b2PointStateS0_PK10b2ManifoldS3__thunk", state1, state2, manifold1, manifold2)
end
"""
    b2CollidePolygons(manifold::Any, polyA::Any, xfA::Ref{b2Transform}, polyB::Any, xfB::Ref{b2Transform}) -> Cvoid

Wrapper for `b2CollidePolygons(b2Manifold*, b2PolygonShape const*, b2Transform const&, b2PolygonShape const*, b2Transform const&)`

# Arguments
- `manifold::Ptr{b2Manifold}`
- `polyA::Ptr{b2PolygonShape}`
- `xfA::Ref{b2Transform}`
- `polyB::Ptr{b2PolygonShape}`
- `xfB::Ref{b2Transform}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_Z17b2CollidePolygonsP10b2ManifoldPK14b2PolygonShapeRK11b2TransformS3_S6_`
"""

function b2CollidePolygons(manifold::Any, polyA::Any, xfA::Ref{b2Transform}, polyB::Any, xfB::Ref{b2Transform})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__Z17b2CollidePolygonsP10b2ManifoldPK14b2PolygonShapeRK11b2TransformS3_S6__thunk", manifold, polyA, xfA, polyB, xfB)
end
"""
    b2LinearStiffness(stiffness::Ref{Cfloat}, damping::Ref{Cfloat}, frequencyHertz::Cfloat, dampingRatio::Cfloat, bodyA::Any, bodyB::Any) -> Cvoid

Wrapper for `b2LinearStiffness(float&, float&, float, float, b2Body const*, b2Body const*)`

# Arguments
- `stiffness::Ref{Cfloat}`
- `damping::Ref{Cfloat}`
- `frequencyHertz::Cfloat`
- `dampingRatio::Cfloat`
- `bodyA::Ptr{b2Body}`
- `bodyB::Ptr{b2Body}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_Z17b2LinearStiffnessRfS_ffPK6b2BodyS2_`
"""

function b2LinearStiffness(stiffness::Ref{Cfloat}, damping::Ref{Cfloat}, frequencyHertz::Cfloat, dampingRatio::Cfloat, bodyA::Any, bodyB::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__Z17b2LinearStiffnessRfS_ffPK6b2BodyS2__thunk", stiffness, damping, frequencyHertz, dampingRatio, bodyA, bodyB)
end
"""
    b2AngularStiffness(stiffness::Ref{Cfloat}, damping::Ref{Cfloat}, frequencyHertz::Cfloat, dampingRatio::Cfloat, bodyA::Any, bodyB::Any) -> Cvoid

Wrapper for `b2AngularStiffness(float&, float&, float, float, b2Body const*, b2Body const*)`

# Arguments
- `stiffness::Ref{Cfloat}`
- `damping::Ref{Cfloat}`
- `frequencyHertz::Cfloat`
- `dampingRatio::Cfloat`
- `bodyA::Ptr{b2Body}`
- `bodyB::Ptr{b2Body}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_Z18b2AngularStiffnessRfS_ffPK6b2BodyS2_`
"""

function b2AngularStiffness(stiffness::Ref{Cfloat}, damping::Ref{Cfloat}, frequencyHertz::Cfloat, dampingRatio::Cfloat, bodyA::Any, bodyB::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__Z18b2AngularStiffnessRfS_ffPK6b2BodyS2__thunk", stiffness, damping, frequencyHertz, dampingRatio, bodyA, bodyB)
end
"""
    b2ClipSegmentToLine(vOut::Any, vIn::Any, normal::Ref{b2Vec2}, offset::Cfloat, vertexIndexA::Integer) -> Cint

Wrapper for `b2ClipSegmentToLine(b2ClipVertex*, b2ClipVertex const*, b2Vec2 const&, float, int)`

# Arguments
- `vOut::Ptr{b2ClipVertex}`
- `vIn::Ptr{b2ClipVertex}`
- `normal::Ref{b2Vec2}`
- `offset::Cfloat`
- `vertexIndexA::Cint`

# Returns
- `Cint`

# Metadata
- Mangled symbol: `_Z19b2ClipSegmentToLineP12b2ClipVertexPKS_RK6b2Vec2fi`
"""

function b2ClipSegmentToLine(vOut::Any, vIn::Any, normal::Ref{b2Vec2}, offset::Cfloat, vertexIndexA::Integer)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__Z19b2ClipSegmentToLineP12b2ClipVertexPKS_RK6b2Vec2fi_thunk", Cint, vOut, vIn, normal, offset, vertexIndexA)
end
"""
    b2_pi() -> Cfloat

Wrapper for `replibuild_shim_b2_pi()`

# Arguments


# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_Z21replibuild_shim_b2_piv`
"""

function b2_pi()
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__Z21replibuild_shim_b2_piv_thunk", Cfloat)
end
"""
    b2CollideEdgeAndCircle(manifold::Any, edgeA::Any, xfA::Ref{b2Transform}, circleB::Any, xfB::Ref{b2Transform}) -> Cvoid

Wrapper for `b2CollideEdgeAndCircle(b2Manifold*, b2EdgeShape const*, b2Transform const&, b2CircleShape const*, b2Transform const&)`

# Arguments
- `manifold::Ptr{b2Manifold}`
- `edgeA::Ptr{b2EdgeShape}`
- `xfA::Ref{b2Transform}`
- `circleB::Ptr{b2CircleShape}`
- `xfB::Ref{b2Transform}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_Z22b2CollideEdgeAndCircleP10b2ManifoldPK11b2EdgeShapeRK11b2TransformPK13b2CircleShapeS6_`
"""

function b2CollideEdgeAndCircle(manifold::Any, edgeA::Any, xfA::Ref{b2Transform}, circleB::Any, xfB::Ref{b2Transform})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__Z22b2CollideEdgeAndCircleP10b2ManifoldPK11b2EdgeShapeRK11b2TransformPK13b2CircleShapeS6__thunk", manifold, edgeA, xfA, circleB, xfB)
end
"""
    b2CollideEdgeAndPolygon(manifold::Any, edgeA::Any, xfA::Ref{b2Transform}, polygonB::Any, xfB::Ref{b2Transform}) -> Cvoid

Wrapper for `b2CollideEdgeAndPolygon(b2Manifold*, b2EdgeShape const*, b2Transform const&, b2PolygonShape const*, b2Transform const&)`

# Arguments
- `manifold::Ptr{b2Manifold}`
- `edgeA::Ptr{b2EdgeShape}`
- `xfA::Ref{b2Transform}`
- `polygonB::Ptr{b2PolygonShape}`
- `xfB::Ref{b2Transform}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_Z23b2CollideEdgeAndPolygonP10b2ManifoldPK11b2EdgeShapeRK11b2TransformPK14b2PolygonShapeS6_`
"""

function b2CollideEdgeAndPolygon(manifold::Any, edgeA::Any, xfA::Ref{b2Transform}, polygonB::Any, xfB::Ref{b2Transform})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__Z23b2CollideEdgeAndPolygonP10b2ManifoldPK11b2EdgeShapeRK11b2TransformPK14b2PolygonShapeS6__thunk", manifold, edgeA, xfA, polygonB, xfB)
end
"""
    b2CollidePolygonAndCircle(manifold::Any, polygonA::Any, xfA::Ref{b2Transform}, circleB::Any, xfB::Ref{b2Transform}) -> Cvoid

Wrapper for `b2CollidePolygonAndCircle(b2Manifold*, b2PolygonShape const*, b2Transform const&, b2CircleShape const*, b2Transform const&)`

# Arguments
- `manifold::Ptr{b2Manifold}`
- `polygonA::Ptr{b2PolygonShape}`
- `xfA::Ref{b2Transform}`
- `circleB::Ptr{b2CircleShape}`
- `xfB::Ref{b2Transform}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_Z25b2CollidePolygonAndCircleP10b2ManifoldPK14b2PolygonShapeRK11b2TransformPK13b2CircleShapeS6_`
"""

function b2CollidePolygonAndCircle(manifold::Any, polygonA::Any, xfA::Ref{b2Transform}, circleB::Any, xfB::Ref{b2Transform})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__Z25b2CollidePolygonAndCircleP10b2ManifoldPK14b2PolygonShapeRK11b2TransformPK13b2CircleShapeS6__thunk", manifold, polygonA, xfA, circleB, xfB)
end
"""
    b2_baumgarte() -> Cfloat

Wrapper for `replibuild_shim_b2_baumgarte()`

# Arguments


# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_Z28replibuild_shim_b2_baumgartev`
"""

function b2_baumgarte()
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__Z28replibuild_shim_b2_baumgartev_thunk", Cfloat)
end
"""
    b2_linearSlop() -> Cfloat

Wrapper for `replibuild_shim_b2_linearSlop()`

# Arguments


# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_Z29replibuild_shim_b2_linearSlopv`
"""

function b2_linearSlop()
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__Z29replibuild_shim_b2_linearSlopv_thunk", Cfloat)
end
"""
    b2_angularSlop() -> Cfloat

Wrapper for `replibuild_shim_b2_angularSlop()`

# Arguments


# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_Z30replibuild_shim_b2_angularSlopv`
"""

function b2_angularSlop()
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__Z30replibuild_shim_b2_angularSlopv_thunk", Cfloat)
end
"""
    b2_maxRotation() -> Cfloat

Wrapper for `replibuild_shim_b2_maxRotation()`

# Arguments


# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_Z30replibuild_shim_b2_maxRotationv`
"""

function b2_maxRotation()
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__Z30replibuild_shim_b2_maxRotationv_thunk", Cfloat)
end
"""
    b2_maxSubSteps() -> Cint

Wrapper for `replibuild_shim_b2_maxSubSteps()`

# Arguments


# Returns
- `Cint`

# Metadata
- Mangled symbol: `_Z30replibuild_shim_b2_maxSubStepsv`
"""

function b2_maxSubSteps()
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__Z30replibuild_shim_b2_maxSubStepsv_thunk", Cint)
end
"""
    b2_timeToSleep() -> Cfloat

Wrapper for `replibuild_shim_b2_timeToSleep()`

# Arguments


# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_Z30replibuild_shim_b2_timeToSleepv`
"""

function b2_timeToSleep()
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__Z30replibuild_shim_b2_timeToSleepv_thunk", Cfloat)
end
"""
    b2_toiBaumgarte() -> Cfloat

Wrapper for `replibuild_shim_b2_toiBaumgarte()`

# Arguments


# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_Z31replibuild_shim_b2_toiBaumgartev`
"""

function b2_toiBaumgarte()
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__Z31replibuild_shim_b2_toiBaumgartev_thunk", Cfloat)
end
"""
    b2_aabbExtension() -> Cfloat

Wrapper for `replibuild_shim_b2_aabbExtension()`

# Arguments


# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_Z32replibuild_shim_b2_aabbExtensionv`
"""

function b2_aabbExtension()
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__Z32replibuild_shim_b2_aabbExtensionv_thunk", Cfloat)
end
"""
    b2_polygonRadius() -> Cfloat

Wrapper for `replibuild_shim_b2_polygonRadius()`

# Arguments


# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_Z32replibuild_shim_b2_polygonRadiusv`
"""

function b2_polygonRadius()
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__Z32replibuild_shim_b2_polygonRadiusv_thunk", Cfloat)
end
"""
    b2_aabbMultiplier() -> Cfloat

Wrapper for `replibuild_shim_b2_aabbMultiplier()`

# Arguments


# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_Z33replibuild_shim_b2_aabbMultiplierv`
"""

function b2_aabbMultiplier()
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__Z33replibuild_shim_b2_aabbMultiplierv_thunk", Cfloat)
end
"""
    b2_maxTOIContacts() -> Cint

Wrapper for `replibuild_shim_b2_maxTOIContacts()`

# Arguments


# Returns
- `Cint`

# Metadata
- Mangled symbol: `_Z33replibuild_shim_b2_maxTOIContactsv`
"""

function b2_maxTOIContacts()
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__Z33replibuild_shim_b2_maxTOIContactsv_thunk", Cint)
end
"""
    b2_maxTranslation() -> Cfloat

Wrapper for `replibuild_shim_b2_maxTranslation()`

# Arguments


# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_Z33replibuild_shim_b2_maxTranslationv`
"""

function b2_maxTranslation()
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__Z33replibuild_shim_b2_maxTranslationv_thunk", Cfloat)
end
"""
    b2_maxManifoldPoints() -> Cint

Wrapper for `replibuild_shim_b2_maxManifoldPoints()`

# Arguments


# Returns
- `Cint`

# Metadata
- Mangled symbol: `_Z36replibuild_shim_b2_maxManifoldPointsv`
"""

function b2_maxManifoldPoints()
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__Z36replibuild_shim_b2_maxManifoldPointsv_thunk", Cint)
end
"""
    b2_maxPolygonVertices() -> Cint

Wrapper for `replibuild_shim_b2_maxPolygonVertices()`

# Arguments


# Returns
- `Cint`

# Metadata
- Mangled symbol: `_Z37replibuild_shim_b2_maxPolygonVerticesv`
"""

function b2_maxPolygonVertices()
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__Z37replibuild_shim_b2_maxPolygonVerticesv_thunk", Cint)
end
"""
    b2_lengthUnitsPerMeter() -> Cfloat

Wrapper for `replibuild_shim_b2_lengthUnitsPerMeter()`

# Arguments


# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_Z38replibuild_shim_b2_lengthUnitsPerMeterv`
"""

function b2_lengthUnitsPerMeter()
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__Z38replibuild_shim_b2_lengthUnitsPerMeterv_thunk", Cfloat)
end
"""
    b2_maxLinearCorrection() -> Cfloat

Wrapper for `replibuild_shim_b2_maxLinearCorrection()`

# Arguments


# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_Z38replibuild_shim_b2_maxLinearCorrectionv`
"""

function b2_maxLinearCorrection()
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__Z38replibuild_shim_b2_maxLinearCorrectionv_thunk", Cfloat)
end
"""
    b2_linearSleepTolerance() -> Cfloat

Wrapper for `replibuild_shim_b2_linearSleepTolerance()`

# Arguments


# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_Z39replibuild_shim_b2_linearSleepTolerancev`
"""

function b2_linearSleepTolerance()
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__Z39replibuild_shim_b2_linearSleepTolerancev_thunk", Cfloat)
end
"""
    b2_maxAngularCorrection() -> Cfloat

Wrapper for `replibuild_shim_b2_maxAngularCorrection()`

# Arguments


# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_Z39replibuild_shim_b2_maxAngularCorrectionv`
"""

function b2_maxAngularCorrection()
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__Z39replibuild_shim_b2_maxAngularCorrectionv_thunk", Cfloat)
end
"""
    b2_angularSleepTolerance() -> Cfloat

Wrapper for `replibuild_shim_b2_angularSleepTolerance()`

# Arguments


# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_Z40replibuild_shim_b2_angularSleepTolerancev`
"""

function b2_angularSleepTolerance()
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__Z40replibuild_shim_b2_angularSleepTolerancev_thunk", Cfloat)
end
"""
    b2Log(string::Any) -> Cvoid

Wrapper for variadic C function: `b2Log(char const*, ...)` (base call with fixed args only)
"""

function b2Log(string::Any)::Cvoid
    return @ccall LIBRARY_PATH.var"_Z5b2LogPKcz"(string::Ptr{UInt8};)::Cvoid
end

"""
    b2Log_Cint(string::Any, va_1::Cint) -> Cvoid

Typed variadic overload for: `b2Log(char const*, ...)`
Variadic types: Cint
"""

function b2Log_Cint(string::Any, va_1::Cint)::Cvoid
    return @ccall LIBRARY_PATH.var"_Z5b2LogPKcz"(string::Ptr{UInt8}; va_1::Cint)::Cvoid
end

"""
    b2Log_Cdouble(string::Any, va_1::Cdouble) -> Cvoid

Typed variadic overload for: `b2Log(char const*, ...)`
Variadic types: Cdouble
"""

function b2Log_Cdouble(string::Any, va_1::Cdouble)::Cvoid
    return @ccall LIBRARY_PATH.var"_Z5b2LogPKcz"(string::Ptr{UInt8}; va_1::Cdouble)::Cvoid
end

"""
    b2Log_Cstring(string::Any, va_1::Cstring) -> Cvoid

Typed variadic overload for: `b2Log(char const*, ...)`
Variadic types: Cstring
"""

function b2Log_Cstring(string::Any, va_1::Cstring)::Cvoid
    return @ccall LIBRARY_PATH.var"_Z5b2LogPKcz"(string::Ptr{UInt8}; va_1::Cstring)::Cvoid
end

"""
    b2Log_Cint_Cint(string::Any, va_1::Cint, va_2::Cint) -> Cvoid

Typed variadic overload for: `b2Log(char const*, ...)`
Variadic types: Cint, Cint
"""

function b2Log_Cint_Cint(string::Any, va_1::Cint, va_2::Cint)::Cvoid
    return @ccall LIBRARY_PATH.var"_Z5b2LogPKcz"(string::Ptr{UInt8}; va_1::Cint, va_2::Cint)::Cvoid
end

"""
    b2Log_Cdouble_Cdouble(string::Any, va_1::Cdouble, va_2::Cdouble) -> Cvoid

Typed variadic overload for: `b2Log(char const*, ...)`
Variadic types: Cdouble, Cdouble
"""

function b2Log_Cdouble_Cdouble(string::Any, va_1::Cdouble, va_2::Cdouble)::Cvoid
    return @ccall LIBRARY_PATH.var"_Z5b2LogPKcz"(string::Ptr{UInt8}; va_1::Cdouble, va_2::Cdouble)::Cvoid
end

"""
    b2Log_Cstring_Cint(string::Any, va_1::Cstring, va_2::Cint) -> Cvoid

Typed variadic overload for: `b2Log(char const*, ...)`
Variadic types: Cstring, Cint
"""

function b2Log_Cstring_Cint(string::Any, va_1::Cstring, va_2::Cint)::Cvoid
    return @ccall LIBRARY_PATH.var"_Z5b2LogPKcz"(string::Ptr{UInt8}; va_1::Cstring, va_2::Cint)::Cvoid
end

"""
    b2Dump(string::Any) -> Cvoid

Wrapper for variadic C function: `b2Dump(char const*, ...)` (base call with fixed args only)
"""

function b2Dump(string::Any)::Cvoid
    return @ccall LIBRARY_PATH.var"_Z6b2DumpPKcz"(string::Ptr{UInt8};)::Cvoid
end

"""
    b2Dump_Cint(string::Any, va_1::Cint) -> Cvoid

Typed variadic overload for: `b2Dump(char const*, ...)`
Variadic types: Cint
"""

function b2Dump_Cint(string::Any, va_1::Cint)::Cvoid
    return @ccall LIBRARY_PATH.var"_Z6b2DumpPKcz"(string::Ptr{UInt8}; va_1::Cint)::Cvoid
end

"""
    b2Dump_Cdouble(string::Any, va_1::Cdouble) -> Cvoid

Typed variadic overload for: `b2Dump(char const*, ...)`
Variadic types: Cdouble
"""

function b2Dump_Cdouble(string::Any, va_1::Cdouble)::Cvoid
    return @ccall LIBRARY_PATH.var"_Z6b2DumpPKcz"(string::Ptr{UInt8}; va_1::Cdouble)::Cvoid
end

"""
    b2Dump_Cstring(string::Any, va_1::Cstring) -> Cvoid

Typed variadic overload for: `b2Dump(char const*, ...)`
Variadic types: Cstring
"""

function b2Dump_Cstring(string::Any, va_1::Cstring)::Cvoid
    return @ccall LIBRARY_PATH.var"_Z6b2DumpPKcz"(string::Ptr{UInt8}; va_1::Cstring)::Cvoid
end

"""
    b2Dump_Cint_Cint(string::Any, va_1::Cint, va_2::Cint) -> Cvoid

Typed variadic overload for: `b2Dump(char const*, ...)`
Variadic types: Cint, Cint
"""

function b2Dump_Cint_Cint(string::Any, va_1::Cint, va_2::Cint)::Cvoid
    return @ccall LIBRARY_PATH.var"_Z6b2DumpPKcz"(string::Ptr{UInt8}; va_1::Cint, va_2::Cint)::Cvoid
end

"""
    b2Dump_Cdouble_Cdouble(string::Any, va_1::Cdouble, va_2::Cdouble) -> Cvoid

Typed variadic overload for: `b2Dump(char const*, ...)`
Variadic types: Cdouble, Cdouble
"""

function b2Dump_Cdouble_Cdouble(string::Any, va_1::Cdouble, va_2::Cdouble)::Cvoid
    return @ccall LIBRARY_PATH.var"_Z6b2DumpPKcz"(string::Ptr{UInt8}; va_1::Cdouble, va_2::Cdouble)::Cvoid
end

"""
    b2Dump_Cdouble_Cdouble_Cdouble(string::Any, va_1::Cdouble, va_2::Cdouble, va_3::Cdouble) -> Cvoid

Typed variadic overload for: `b2Dump(char const*, ...)`
Variadic types: Cdouble, Cdouble, Cdouble
"""

function b2Dump_Cdouble_Cdouble_Cdouble(string::Any, va_1::Cdouble, va_2::Cdouble, va_3::Cdouble)::Cvoid
    return @ccall LIBRARY_PATH.var"_Z6b2DumpPKcz"(string::Ptr{UInt8}; va_1::Cdouble, va_2::Cdouble, va_3::Cdouble)::Cvoid
end

"""
    b2Dump_Cstring_Cint(string::Any, va_1::Cstring, va_2::Cint) -> Cvoid

Typed variadic overload for: `b2Dump(char const*, ...)`
Variadic types: Cstring, Cint
"""

function b2Dump_Cstring_Cint(string::Any, va_1::Cstring, va_2::Cint)::Cvoid
    return @ccall LIBRARY_PATH.var"_Z6b2DumpPKcz"(string::Ptr{UInt8}; va_1::Cstring, va_2::Cint)::Cvoid
end

"""
    b2EdgeShape_SetOneSided(this::Any, arg1::Ref{Any}, arg2::Ref{Any}, arg3::Ref{Any}, arg4::Ref{Any}) -> Cvoid

Wrapper for `b2EdgeShape::SetOneSided(b2Vec2 const&, b2Vec2 const&, b2Vec2 const&, b2Vec2 const&)`

# Arguments
- `this::Ptr{b2EdgeShape}`
- `arg1::Ref{Any}`
- `arg2::Ref{Any}`
- `arg3::Ref{Any}`
- `arg4::Ref{Any}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN11b2EdgeShape11SetOneSidedERK6b2Vec2S2_S2_S2_`
"""

function b2EdgeShape_SetOneSided(this::Any, arg1::Ref{Any}, arg2::Ref{Any}, arg3::Ref{Any}, arg4::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN11b2EdgeShape11SetOneSidedERK6b2Vec2S2_S2_S2__thunk", this, arg1, arg2, arg3, arg4)
end
"""
    b2EdgeShape_SetTwoSided(this::Any, arg1::Ref{Any}, arg2::Ref{Any}) -> Cvoid

Wrapper for `b2EdgeShape::SetTwoSided(b2Vec2 const&, b2Vec2 const&)`

# Arguments
- `this::Ptr{b2EdgeShape}`
- `arg1::Ref{Any}`
- `arg2::Ref{Any}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN11b2EdgeShape11SetTwoSidedERK6b2Vec2S2_`
"""

function b2EdgeShape_SetTwoSided(this::Any, arg1::Ref{Any}, arg2::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN11b2EdgeShape11SetTwoSidedERK6b2Vec2S2__thunk", this, arg1, arg2)
end
"""
    b2EdgeShape_destroy_b2EdgeShape(this::Any) -> Cvoid

Wrapper for `b2EdgeShape::~b2EdgeShape()`

# Arguments
- `this::Ptr{b2EdgeShape}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN11b2EdgeShapeD0Ev`
"""

function b2EdgeShape_destroy_b2EdgeShape(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN11b2EdgeShapeD0Ev_thunk", this)
end
"""
    b2GearJoint_InitVelocityConstraints(this::Any, arg1::Ref{Any}) -> Cvoid

Wrapper for `b2GearJoint::InitVelocityConstraints(b2SolverData const&)`

# Arguments
- `this::Ptr{b2GearJoint}`
- `arg1::Ref{Any}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN11b2GearJoint23InitVelocityConstraintsERK12b2SolverData`
"""

function b2GearJoint_InitVelocityConstraints(this::Any, arg1::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN11b2GearJoint23InitVelocityConstraintsERK12b2SolverData_thunk", this, arg1)
end
"""
    b2GearJoint_SolvePositionConstraints(this::Any, arg1::Ref{Any}) -> Bool

Wrapper for `b2GearJoint::SolvePositionConstraints(b2SolverData const&)`

# Arguments
- `this::Ptr{b2GearJoint}`
- `arg1::Ref{Any}`

# Returns
- `Bool`

# Metadata
- Mangled symbol: `_ZN11b2GearJoint24SolvePositionConstraintsERK12b2SolverData`
"""

function b2GearJoint_SolvePositionConstraints(this::Any, arg1::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN11b2GearJoint24SolvePositionConstraintsERK12b2SolverData_thunk", Bool, this, arg1)
end
"""
    b2GearJoint_SolveVelocityConstraints(this::Any, arg1::Ref{Any}) -> Cvoid

Wrapper for `b2GearJoint::SolveVelocityConstraints(b2SolverData const&)`

# Arguments
- `this::Ptr{b2GearJoint}`
- `arg1::Ref{Any}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN11b2GearJoint24SolveVelocityConstraintsERK12b2SolverData`
"""

function b2GearJoint_SolveVelocityConstraints(this::Any, arg1::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN11b2GearJoint24SolveVelocityConstraintsERK12b2SolverData_thunk", this, arg1)
end
"""
    b2GearJoint_Dump(this::Any) -> Cvoid

Wrapper for `b2GearJoint::Dump()`

# Arguments
- `this::Ptr{b2GearJoint}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN11b2GearJoint4DumpEv`
"""

function b2GearJoint_Dump(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN11b2GearJoint4DumpEv_thunk", this)
end
"""
    b2GearJoint_SetRatio(this::Any, arg1::Cfloat) -> Cvoid

Wrapper for `b2GearJoint::SetRatio(float)`

# Arguments
- `this::Ptr{b2GearJoint}`
- `arg1::Cfloat`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN11b2GearJoint8SetRatioEf`
"""

function b2GearJoint_SetRatio(this::Any, arg1::Cfloat)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN11b2GearJoint8SetRatioEf_thunk", this, arg1)
end
"""
    b2GearJoint_destroy_b2GearJoint(this::Any) -> Cvoid

Wrapper for `b2GearJoint::~b2GearJoint()`

# Arguments
- `this::Ptr{b2GearJoint}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN11b2GearJointD0Ev`
"""

function b2GearJoint_destroy_b2GearJoint(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN11b2GearJointD0Ev_thunk", this)
end
"""
    b2WeldJoint_InitVelocityConstraints(this::Any, arg1::Ref{Any}) -> Cvoid

Wrapper for `b2WeldJoint::InitVelocityConstraints(b2SolverData const&)`

# Arguments
- `this::Ptr{b2WeldJoint}`
- `arg1::Ref{Any}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN11b2WeldJoint23InitVelocityConstraintsERK12b2SolverData`
"""

function b2WeldJoint_InitVelocityConstraints(this::Any, arg1::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN11b2WeldJoint23InitVelocityConstraintsERK12b2SolverData_thunk", this, arg1)
end
"""
    b2WeldJoint_SolvePositionConstraints(this::Any, arg1::Ref{Any}) -> Bool

Wrapper for `b2WeldJoint::SolvePositionConstraints(b2SolverData const&)`

# Arguments
- `this::Ptr{b2WeldJoint}`
- `arg1::Ref{Any}`

# Returns
- `Bool`

# Metadata
- Mangled symbol: `_ZN11b2WeldJoint24SolvePositionConstraintsERK12b2SolverData`
"""

function b2WeldJoint_SolvePositionConstraints(this::Any, arg1::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN11b2WeldJoint24SolvePositionConstraintsERK12b2SolverData_thunk", Bool, this, arg1)
end
"""
    b2WeldJoint_SolveVelocityConstraints(this::Any, arg1::Ref{Any}) -> Cvoid

Wrapper for `b2WeldJoint::SolveVelocityConstraints(b2SolverData const&)`

# Arguments
- `this::Ptr{b2WeldJoint}`
- `arg1::Ref{Any}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN11b2WeldJoint24SolveVelocityConstraintsERK12b2SolverData`
"""

function b2WeldJoint_SolveVelocityConstraints(this::Any, arg1::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN11b2WeldJoint24SolveVelocityConstraintsERK12b2SolverData_thunk", this, arg1)
end
"""
    b2WeldJoint_Dump(this::Any) -> Cvoid

Wrapper for `b2WeldJoint::Dump()`

# Arguments
- `this::Ptr{b2WeldJoint}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN11b2WeldJoint4DumpEv`
"""

function b2WeldJoint_Dump(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN11b2WeldJoint4DumpEv_thunk", this)
end
"""
    b2WeldJoint_destroy_b2WeldJoint(this::Any) -> Cvoid

Wrapper for `b2WeldJoint::~b2WeldJoint()`

# Arguments
- `this::Ptr{b2WeldJoint}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN11b2WeldJointD0Ev`
"""

function b2WeldJoint_destroy_b2WeldJoint(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN11b2WeldJointD0Ev_thunk", this)
end
"""
    b2BroadPhase_BufferMove(this::Any, arg1::Integer) -> Cvoid

Wrapper for `b2BroadPhase::BufferMove(int)`

# Arguments
- `this::Ptr{b2BroadPhase}`
- `arg1::Cint`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN12b2BroadPhase10BufferMoveEi`
"""

function b2BroadPhase_BufferMove(this::Any, arg1::Integer)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN12b2BroadPhase10BufferMoveEi_thunk", this, arg1)
end
"""
    b2BroadPhase_TouchProxy(this::Any, arg1::Integer) -> Cvoid

Wrapper for `b2BroadPhase::TouchProxy(int)`

# Arguments
- `this::Ptr{b2BroadPhase}`
- `arg1::Cint`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN12b2BroadPhase10TouchProxyEi`
"""

function b2BroadPhase_TouchProxy(this::Any, arg1::Integer)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN12b2BroadPhase10TouchProxyEi_thunk", this, arg1)
end
"""
    b2BroadPhase_CreateProxy(this::Any, arg1::Ref{Any}, arg2::Any) -> Cint

Wrapper for `b2BroadPhase::CreateProxy(b2AABB const&, void*)`

# Arguments
- `this::Ptr{b2BroadPhase}`
- `arg1::Ref{Any}`
- `arg2::Ptr{Cvoid}`

# Returns
- `Cint`

# Metadata
- Mangled symbol: `_ZN12b2BroadPhase11CreateProxyERK6b2AABBPv`
"""

function b2BroadPhase_CreateProxy(this::Any, arg1::Ref{Any}, arg2::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN12b2BroadPhase11CreateProxyERK6b2AABBPv_thunk", Cint, this, arg1, arg2)
end
"""
    void_b2BroadPhase_UpdatePairs_b2ContactManager(e_nullProxy::b2ContactManager) -> Cvoid

Wrapper for `void b2BroadPhase::UpdatePairs<b2ContactManager>(b2ContactManager*)`

# Arguments
- `e_nullProxy::b2ContactManager`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN12b2BroadPhase11UpdatePairsI16b2ContactManagerEEvPT_`
"""

function void_b2BroadPhase_UpdatePairs_b2ContactManager(e_nullProxy::b2ContactManager)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN12b2BroadPhase11UpdatePairsI16b2ContactManagerEEvPT__thunk", e_nullProxy)
end
"""
    b2BroadPhase_DestroyProxy(this::Any, arg1::Integer) -> Cvoid

Wrapper for `b2BroadPhase::DestroyProxy(int)`

# Arguments
- `this::Ptr{b2BroadPhase}`
- `arg1::Cint`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN12b2BroadPhase12DestroyProxyEi`
"""

function b2BroadPhase_DestroyProxy(this::Any, arg1::Integer)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN12b2BroadPhase12DestroyProxyEi_thunk", this, arg1)
end
"""
    b2BroadPhase_UnBufferMove(this::Any, arg1::Integer) -> Cvoid

Wrapper for `b2BroadPhase::UnBufferMove(int)`

# Arguments
- `this::Ptr{b2BroadPhase}`
- `arg1::Cint`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN12b2BroadPhase12UnBufferMoveEi`
"""

function b2BroadPhase_UnBufferMove(this::Any, arg1::Integer)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN12b2BroadPhase12UnBufferMoveEi_thunk", this, arg1)
end
"""
    b2BroadPhase_QueryCallback(this::Any, arg1::Integer) -> Bool

Wrapper for `b2BroadPhase::QueryCallback(int)`

# Arguments
- `this::Ptr{b2BroadPhase}`
- `arg1::Cint`

# Returns
- `Bool`

# Metadata
- Mangled symbol: `_ZN12b2BroadPhase13QueryCallbackEi`
"""

function b2BroadPhase_QueryCallback(this::Any, arg1::Integer)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN12b2BroadPhase13QueryCallbackEi_thunk", Bool, this, arg1)
end
"""
    b2BroadPhase_MoveProxy(this::Any, arg1::Integer, arg2::Ref{Any}, arg3::Ref{Any}) -> Cvoid

Wrapper for `b2BroadPhase::MoveProxy(int, b2AABB const&, b2Vec2 const&)`

# Arguments
- `this::Ptr{b2BroadPhase}`
- `arg1::Cint`
- `arg2::Ref{Any}`
- `arg3::Ref{Any}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN12b2BroadPhase9MoveProxyEiRK6b2AABBRK6b2Vec2`
"""

function b2BroadPhase_MoveProxy(this::Any, arg1::Integer, arg2::Ref{Any}, arg3::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN12b2BroadPhase9MoveProxyEiRK6b2AABBRK6b2Vec2_thunk", this, arg1, arg2, arg3)
end
"""
    b2BroadPhase_destroy_b2BroadPhase(this::Any) -> Cvoid

Wrapper for `b2BroadPhase::~b2BroadPhase()`

# Arguments
- `this::Ptr{b2BroadPhase}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN12b2BroadPhaseD2Ev`
"""

function b2BroadPhase_destroy_b2BroadPhase(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN12b2BroadPhaseD2Ev_thunk", this)
end
"""
    b2ChainShape_CreateLoop(this::Any, arg1::Any, arg2::Integer) -> Cvoid

Wrapper for `b2ChainShape::CreateLoop(b2Vec2 const*, int)`

# Arguments
- `this::Ptr{b2ChainShape}`
- `arg1::Ptr{Cvoid}`
- `arg2::Cint`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN12b2ChainShape10CreateLoopEPK6b2Vec2i`
"""

function b2ChainShape_CreateLoop(this::Any, arg1::Any, arg2::Integer)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN12b2ChainShape10CreateLoopEPK6b2Vec2i_thunk", this, arg1, arg2)
end
"""
    b2ChainShape_CreateChain(this::Any, arg1::Any, arg2::Integer, arg3::Ref{Any}, arg4::Ref{Any}) -> Cvoid

Wrapper for `b2ChainShape::CreateChain(b2Vec2 const*, int, b2Vec2 const&, b2Vec2 const&)`

# Arguments
- `this::Ptr{b2ChainShape}`
- `arg1::Ptr{Cvoid}`
- `arg2::Cint`
- `arg3::Ref{Any}`
- `arg4::Ref{Any}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN12b2ChainShape11CreateChainEPK6b2Vec2iRS1_S3_`
"""

function b2ChainShape_CreateChain(this::Any, arg1::Any, arg2::Integer, arg3::Ref{Any}, arg4::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN12b2ChainShape11CreateChainEPK6b2Vec2iRS1_S3__thunk", this, arg1, arg2, arg3, arg4)
end
"""
    b2ChainShape_Clear(this::Any) -> Cvoid

Wrapper for `b2ChainShape::Clear()`

# Arguments
- `this::Ptr{b2ChainShape}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN12b2ChainShape5ClearEv`
"""

function b2ChainShape_Clear(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN12b2ChainShape5ClearEv_thunk", this)
end
"""
    b2ChainShape_destroy_b2ChainShape(this::Any) -> Cvoid

Wrapper for `b2ChainShape::~b2ChainShape()`

# Arguments
- `this::Ptr{b2ChainShape}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN12b2ChainShapeD2Ev`
"""

function b2ChainShape_destroy_b2ChainShape(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN12b2ChainShapeD2Ev_thunk", this)
end
"""
    b2MotorJoint_SetMaxForce(this::Any, arg1::Cfloat) -> Cvoid

Wrapper for `b2MotorJoint::SetMaxForce(float)`

# Arguments
- `this::Ptr{b2MotorJoint}`
- `arg1::Cfloat`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN12b2MotorJoint11SetMaxForceEf`
"""

function b2MotorJoint_SetMaxForce(this::Any, arg1::Cfloat)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN12b2MotorJoint11SetMaxForceEf_thunk", this, arg1)
end
"""
    b2MotorJoint_SetMaxTorque(this::Any, arg1::Cfloat) -> Cvoid

Wrapper for `b2MotorJoint::SetMaxTorque(float)`

# Arguments
- `this::Ptr{b2MotorJoint}`
- `arg1::Cfloat`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN12b2MotorJoint12SetMaxTorqueEf`
"""

function b2MotorJoint_SetMaxTorque(this::Any, arg1::Cfloat)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN12b2MotorJoint12SetMaxTorqueEf_thunk", this, arg1)
end
"""
    b2MotorJoint_SetLinearOffset(this::Any, arg1::Ref{Any}) -> Cvoid

Wrapper for `b2MotorJoint::SetLinearOffset(b2Vec2 const&)`

# Arguments
- `this::Ptr{b2MotorJoint}`
- `arg1::Ref{Any}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN12b2MotorJoint15SetLinearOffsetERK6b2Vec2`
"""

function b2MotorJoint_SetLinearOffset(this::Any, arg1::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN12b2MotorJoint15SetLinearOffsetERK6b2Vec2_thunk", this, arg1)
end
"""
    b2MotorJoint_SetAngularOffset(this::Any, arg1::Cfloat) -> Cvoid

Wrapper for `b2MotorJoint::SetAngularOffset(float)`

# Arguments
- `this::Ptr{b2MotorJoint}`
- `arg1::Cfloat`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN12b2MotorJoint16SetAngularOffsetEf`
"""

function b2MotorJoint_SetAngularOffset(this::Any, arg1::Cfloat)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN12b2MotorJoint16SetAngularOffsetEf_thunk", this, arg1)
end
"""
    b2MotorJoint_SetCorrectionFactor(this::Any, arg1::Cfloat) -> Cvoid

Wrapper for `b2MotorJoint::SetCorrectionFactor(float)`

# Arguments
- `this::Ptr{b2MotorJoint}`
- `arg1::Cfloat`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN12b2MotorJoint19SetCorrectionFactorEf`
"""

function b2MotorJoint_SetCorrectionFactor(this::Any, arg1::Cfloat)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN12b2MotorJoint19SetCorrectionFactorEf_thunk", this, arg1)
end
"""
    b2MotorJoint_InitVelocityConstraints(this::Any, arg1::Ref{Any}) -> Cvoid

Wrapper for `b2MotorJoint::InitVelocityConstraints(b2SolverData const&)`

# Arguments
- `this::Ptr{b2MotorJoint}`
- `arg1::Ref{Any}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN12b2MotorJoint23InitVelocityConstraintsERK12b2SolverData`
"""

function b2MotorJoint_InitVelocityConstraints(this::Any, arg1::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN12b2MotorJoint23InitVelocityConstraintsERK12b2SolverData_thunk", this, arg1)
end
"""
    b2MotorJoint_SolvePositionConstraints(this::Any, arg1::Ref{Any}) -> Bool

Wrapper for `b2MotorJoint::SolvePositionConstraints(b2SolverData const&)`

# Arguments
- `this::Ptr{b2MotorJoint}`
- `arg1::Ref{Any}`

# Returns
- `Bool`

# Metadata
- Mangled symbol: `_ZN12b2MotorJoint24SolvePositionConstraintsERK12b2SolverData`
"""

function b2MotorJoint_SolvePositionConstraints(this::Any, arg1::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN12b2MotorJoint24SolvePositionConstraintsERK12b2SolverData_thunk", Bool, this, arg1)
end
"""
    b2MotorJoint_SolveVelocityConstraints(this::Any, arg1::Ref{Any}) -> Cvoid

Wrapper for `b2MotorJoint::SolveVelocityConstraints(b2SolverData const&)`

# Arguments
- `this::Ptr{b2MotorJoint}`
- `arg1::Ref{Any}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN12b2MotorJoint24SolveVelocityConstraintsERK12b2SolverData`
"""

function b2MotorJoint_SolveVelocityConstraints(this::Any, arg1::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN12b2MotorJoint24SolveVelocityConstraintsERK12b2SolverData_thunk", this, arg1)
end
"""
    b2MotorJoint_Dump(this::Any) -> Cvoid

Wrapper for `b2MotorJoint::Dump()`

# Arguments
- `this::Ptr{b2MotorJoint}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN12b2MotorJoint4DumpEv`
"""

function b2MotorJoint_Dump(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN12b2MotorJoint4DumpEv_thunk", this)
end
"""
    b2MotorJoint_destroy_b2MotorJoint(this::Any) -> Cvoid

Wrapper for `b2MotorJoint::~b2MotorJoint()`

# Arguments
- `this::Ptr{b2MotorJoint}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN12b2MotorJointD0Ev`
"""

function b2MotorJoint_destroy_b2MotorJoint(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN12b2MotorJointD0Ev_thunk", this)
end
"""
    b2MouseJoint_SetMaxForce(this::Any, arg1::Cfloat) -> Cvoid

Wrapper for `b2MouseJoint::SetMaxForce(float)`

# Arguments
- `this::Ptr{b2MouseJoint}`
- `arg1::Cfloat`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN12b2MouseJoint11SetMaxForceEf`
"""

function b2MouseJoint_SetMaxForce(this::Any, arg1::Cfloat)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN12b2MouseJoint11SetMaxForceEf_thunk", this, arg1)
end
"""
    b2MouseJoint_ShiftOrigin(this::Any, arg1::Ref{Any}) -> Cvoid

Wrapper for `b2MouseJoint::ShiftOrigin(b2Vec2 const&)`

# Arguments
- `this::Ptr{b2MouseJoint}`
- `arg1::Ref{Any}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN12b2MouseJoint11ShiftOriginERK6b2Vec2`
"""

function b2MouseJoint_ShiftOrigin(this::Any, arg1::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN12b2MouseJoint11ShiftOriginERK6b2Vec2_thunk", this, arg1)
end
"""
    b2MouseJoint_InitVelocityConstraints(this::Any, arg1::Ref{Any}) -> Cvoid

Wrapper for `b2MouseJoint::InitVelocityConstraints(b2SolverData const&)`

# Arguments
- `this::Ptr{b2MouseJoint}`
- `arg1::Ref{Any}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN12b2MouseJoint23InitVelocityConstraintsERK12b2SolverData`
"""

function b2MouseJoint_InitVelocityConstraints(this::Any, arg1::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN12b2MouseJoint23InitVelocityConstraintsERK12b2SolverData_thunk", this, arg1)
end
"""
    b2MouseJoint_SolvePositionConstraints(this::Any, arg1::Ref{Any}) -> Bool

Wrapper for `b2MouseJoint::SolvePositionConstraints(b2SolverData const&)`

# Arguments
- `this::Ptr{b2MouseJoint}`
- `arg1::Ref{Any}`

# Returns
- `Bool`

# Metadata
- Mangled symbol: `_ZN12b2MouseJoint24SolvePositionConstraintsERK12b2SolverData`
"""

function b2MouseJoint_SolvePositionConstraints(this::Any, arg1::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN12b2MouseJoint24SolvePositionConstraintsERK12b2SolverData_thunk", Bool, this, arg1)
end
"""
    b2MouseJoint_SolveVelocityConstraints(this::Any, arg1::Ref{Any}) -> Cvoid

Wrapper for `b2MouseJoint::SolveVelocityConstraints(b2SolverData const&)`

# Arguments
- `this::Ptr{b2MouseJoint}`
- `arg1::Ref{Any}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN12b2MouseJoint24SolveVelocityConstraintsERK12b2SolverData`
"""

function b2MouseJoint_SolveVelocityConstraints(this::Any, arg1::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN12b2MouseJoint24SolveVelocityConstraintsERK12b2SolverData_thunk", this, arg1)
end
"""
    b2MouseJoint_Dump(this::Any) -> Cvoid

Wrapper for `b2MouseJoint::Dump()`

# Arguments
- `this::Ptr{b2MouseJoint}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN12b2MouseJoint4DumpEv`
"""

function b2MouseJoint_Dump(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN12b2MouseJoint4DumpEv_thunk", this)
end
"""
    b2MouseJoint_SetTarget(this::Any, arg1::Ref{Any}) -> Cvoid

Wrapper for `b2MouseJoint::SetTarget(b2Vec2 const&)`

# Arguments
- `this::Ptr{b2MouseJoint}`
- `arg1::Ref{Any}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN12b2MouseJoint9SetTargetERK6b2Vec2`
"""

function b2MouseJoint_SetTarget(this::Any, arg1::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN12b2MouseJoint9SetTargetERK6b2Vec2_thunk", this, arg1)
end
"""
    b2MouseJoint_destroy_b2MouseJoint(this::Any) -> Cvoid

Wrapper for `b2MouseJoint::~b2MouseJoint()`

# Arguments
- `this::Ptr{b2MouseJoint}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN12b2MouseJointD0Ev`
"""

function b2MouseJoint_destroy_b2MouseJoint(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN12b2MouseJointD0Ev_thunk", this)
end
"""
    b2WheelJoint_SetDamping(this::Any, arg1::Cfloat) -> Cvoid

Wrapper for `b2WheelJoint::SetDamping(float)`

# Arguments
- `this::Ptr{b2WheelJoint}`
- `arg1::Cfloat`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN12b2WheelJoint10SetDampingEf`
"""

function b2WheelJoint_SetDamping(this::Any, arg1::Cfloat)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN12b2WheelJoint10SetDampingEf_thunk", this, arg1)
end
"""
    b2WheelJoint_EnableLimit(this::Any, arg1::Bool) -> Cvoid

Wrapper for `b2WheelJoint::EnableLimit(bool)`

# Arguments
- `this::Ptr{b2WheelJoint}`
- `arg1::Bool`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN12b2WheelJoint11EnableLimitEb`
"""

function b2WheelJoint_EnableLimit(this::Any, arg1::Bool)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN12b2WheelJoint11EnableLimitEb_thunk", this, arg1)
end
"""
    b2WheelJoint_EnableMotor(this::Any, arg1::Bool) -> Cvoid

Wrapper for `b2WheelJoint::EnableMotor(bool)`

# Arguments
- `this::Ptr{b2WheelJoint}`
- `arg1::Bool`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN12b2WheelJoint11EnableMotorEb`
"""

function b2WheelJoint_EnableMotor(this::Any, arg1::Bool)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN12b2WheelJoint11EnableMotorEb_thunk", this, arg1)
end
"""
    b2WheelJoint_SetStiffness(this::Any, arg1::Cfloat) -> Cvoid

Wrapper for `b2WheelJoint::SetStiffness(float)`

# Arguments
- `this::Ptr{b2WheelJoint}`
- `arg1::Cfloat`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN12b2WheelJoint12SetStiffnessEf`
"""

function b2WheelJoint_SetStiffness(this::Any, arg1::Cfloat)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN12b2WheelJoint12SetStiffnessEf_thunk", this, arg1)
end
"""
    b2WheelJoint_SetMotorSpeed(this::Any, arg1::Cfloat) -> Cvoid

Wrapper for `b2WheelJoint::SetMotorSpeed(float)`

# Arguments
- `this::Ptr{b2WheelJoint}`
- `arg1::Cfloat`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN12b2WheelJoint13SetMotorSpeedEf`
"""

function b2WheelJoint_SetMotorSpeed(this::Any, arg1::Cfloat)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN12b2WheelJoint13SetMotorSpeedEf_thunk", this, arg1)
end
"""
    b2WheelJoint_SetMaxMotorTorque(this::Any, arg1::Cfloat) -> Cvoid

Wrapper for `b2WheelJoint::SetMaxMotorTorque(float)`

# Arguments
- `this::Ptr{b2WheelJoint}`
- `arg1::Cfloat`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN12b2WheelJoint17SetMaxMotorTorqueEf`
"""

function b2WheelJoint_SetMaxMotorTorque(this::Any, arg1::Cfloat)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN12b2WheelJoint17SetMaxMotorTorqueEf_thunk", this, arg1)
end
"""
    b2WheelJoint_InitVelocityConstraints(this::Any, arg1::Ref{Any}) -> Cvoid

Wrapper for `b2WheelJoint::InitVelocityConstraints(b2SolverData const&)`

# Arguments
- `this::Ptr{b2WheelJoint}`
- `arg1::Ref{Any}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN12b2WheelJoint23InitVelocityConstraintsERK12b2SolverData`
"""

function b2WheelJoint_InitVelocityConstraints(this::Any, arg1::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN12b2WheelJoint23InitVelocityConstraintsERK12b2SolverData_thunk", this, arg1)
end
"""
    b2WheelJoint_SolvePositionConstraints(this::Any, arg1::Ref{Any}) -> Bool

Wrapper for `b2WheelJoint::SolvePositionConstraints(b2SolverData const&)`

# Arguments
- `this::Ptr{b2WheelJoint}`
- `arg1::Ref{Any}`

# Returns
- `Bool`

# Metadata
- Mangled symbol: `_ZN12b2WheelJoint24SolvePositionConstraintsERK12b2SolverData`
"""

function b2WheelJoint_SolvePositionConstraints(this::Any, arg1::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN12b2WheelJoint24SolvePositionConstraintsERK12b2SolverData_thunk", Bool, this, arg1)
end
"""
    b2WheelJoint_SolveVelocityConstraints(this::Any, arg1::Ref{Any}) -> Cvoid

Wrapper for `b2WheelJoint::SolveVelocityConstraints(b2SolverData const&)`

# Arguments
- `this::Ptr{b2WheelJoint}`
- `arg1::Ref{Any}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN12b2WheelJoint24SolveVelocityConstraintsERK12b2SolverData`
"""

function b2WheelJoint_SolveVelocityConstraints(this::Any, arg1::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN12b2WheelJoint24SolveVelocityConstraintsERK12b2SolverData_thunk", this, arg1)
end
"""
    b2WheelJoint_Dump(this::Any) -> Cvoid

Wrapper for `b2WheelJoint::Dump()`

# Arguments
- `this::Ptr{b2WheelJoint}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN12b2WheelJoint4DumpEv`
"""

function b2WheelJoint_Dump(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN12b2WheelJoint4DumpEv_thunk", this)
end
"""
    b2WheelJoint_SetLimits(this::Any, arg1::Cfloat, arg2::Cfloat) -> Cvoid

Wrapper for `b2WheelJoint::SetLimits(float, float)`

# Arguments
- `this::Ptr{b2WheelJoint}`
- `arg1::Cfloat`
- `arg2::Cfloat`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN12b2WheelJoint9SetLimitsEff`
"""

function b2WheelJoint_SetLimits(this::Any, arg1::Cfloat, arg2::Cfloat)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN12b2WheelJoint9SetLimitsEff_thunk", this, arg1, arg2)
end
"""
    b2WheelJoint_destroy_b2WheelJoint(this::Any) -> Cvoid

Wrapper for `b2WheelJoint::~b2WheelJoint()`

# Arguments
- `this::Ptr{b2WheelJoint}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN12b2WheelJointD0Ev`
"""

function b2WheelJoint_destroy_b2WheelJoint(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN12b2WheelJointD0Ev_thunk", this)
end
"""
    b2CircleShape_destroy_b2CircleShape(this::Any) -> Cvoid

Wrapper for `b2CircleShape::~b2CircleShape()`

# Arguments
- `this::Ptr{b2CircleShape}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN13b2CircleShapeD0Ev`
"""

function b2CircleShape_destroy_b2CircleShape(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN13b2CircleShapeD0Ev_thunk", this)
end
"""
    b2DynamicTree_InsertLeaf(this::Any, arg1::Integer) -> Cvoid

Wrapper for `b2DynamicTree::InsertLeaf(int)`

# Arguments
- `this::Ptr{b2DynamicTree}`
- `arg1::Cint`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN13b2DynamicTree10InsertLeafEi`
"""

function b2DynamicTree_InsertLeaf(this::Any, arg1::Integer)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN13b2DynamicTree10InsertLeafEi_thunk", this, arg1)
end
"""
    b2DynamicTree_RemoveLeaf(this::Any, arg1::Integer) -> Cvoid

Wrapper for `b2DynamicTree::RemoveLeaf(int)`

# Arguments
- `this::Ptr{b2DynamicTree}`
- `arg1::Cint`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN13b2DynamicTree10RemoveLeafEi`
"""

function b2DynamicTree_RemoveLeaf(this::Any, arg1::Integer)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN13b2DynamicTree10RemoveLeafEi_thunk", this, arg1)
end
"""
    b2DynamicTree_CreateProxy(this::Any, arg1::Ref{Any}, arg2::Any) -> Cint

Wrapper for `b2DynamicTree::CreateProxy(b2AABB const&, void*)`

# Arguments
- `this::Ptr{b2DynamicTree}`
- `arg1::Ref{Any}`
- `arg2::Ptr{Cvoid}`

# Returns
- `Cint`

# Metadata
- Mangled symbol: `_ZN13b2DynamicTree11CreateProxyERK6b2AABBPv`
"""

function b2DynamicTree_CreateProxy(this::Any, arg1::Ref{Any}, arg2::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN13b2DynamicTree11CreateProxyERK6b2AABBPv_thunk", Cint, this, arg1, arg2)
end
"""
    b2DynamicTree_ShiftOrigin(this::Any, arg1::Ref{Any}) -> Cvoid

Wrapper for `b2DynamicTree::ShiftOrigin(b2Vec2 const&)`

# Arguments
- `this::Ptr{b2DynamicTree}`
- `arg1::Ref{Any}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN13b2DynamicTree11ShiftOriginERK6b2Vec2`
"""

function b2DynamicTree_ShiftOrigin(this::Any, arg1::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN13b2DynamicTree11ShiftOriginERK6b2Vec2_thunk", this, arg1)
end
"""
    b2DynamicTree_AllocateNode(this::Any) -> Cint

Wrapper for `b2DynamicTree::AllocateNode()`

# Arguments
- `this::Ptr{b2DynamicTree}`

# Returns
- `Cint`

# Metadata
- Mangled symbol: `_ZN13b2DynamicTree12AllocateNodeEv`
"""

function b2DynamicTree_AllocateNode(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN13b2DynamicTree12AllocateNodeEv_thunk", Cint, this)
end
"""
    b2DynamicTree_DestroyProxy(this::Any, arg1::Integer) -> Cvoid

Wrapper for `b2DynamicTree::DestroyProxy(int)`

# Arguments
- `this::Ptr{b2DynamicTree}`
- `arg1::Cint`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN13b2DynamicTree12DestroyProxyEi`
"""

function b2DynamicTree_DestroyProxy(this::Any, arg1::Integer)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN13b2DynamicTree12DestroyProxyEi_thunk", this, arg1)
end
"""
    b2DynamicTree_RebuildBottomUp(this::Any) -> Cvoid

Wrapper for `b2DynamicTree::RebuildBottomUp()`

# Arguments
- `this::Ptr{b2DynamicTree}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN13b2DynamicTree15RebuildBottomUpEv`
"""

function b2DynamicTree_RebuildBottomUp(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN13b2DynamicTree15RebuildBottomUpEv_thunk", this)
end
"""
    b2DynamicTree_Balance(this::Any, arg1::Integer) -> Cint

Wrapper for `b2DynamicTree::Balance(int)`

# Arguments
- `this::Ptr{b2DynamicTree}`
- `arg1::Cint`

# Returns
- `Cint`

# Metadata
- Mangled symbol: `_ZN13b2DynamicTree7BalanceEi`
"""

function b2DynamicTree_Balance(this::Any, arg1::Integer)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN13b2DynamicTree7BalanceEi_thunk", Cint, this, arg1)
end
"""
    b2DynamicTree_FreeNode(this::Any, arg1::Integer) -> Cvoid

Wrapper for `b2DynamicTree::FreeNode(int)`

# Arguments
- `this::Ptr{b2DynamicTree}`
- `arg1::Cint`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN13b2DynamicTree8FreeNodeEi`
"""

function b2DynamicTree_FreeNode(this::Any, arg1::Integer)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN13b2DynamicTree8FreeNodeEi_thunk", this, arg1)
end
"""
    b2DynamicTree_MoveProxy(this::Any, arg1::Integer, arg2::Ref{Any}, arg3::Ref{Any}) -> Bool

Wrapper for `b2DynamicTree::MoveProxy(int, b2AABB const&, b2Vec2 const&)`

# Arguments
- `this::Ptr{b2DynamicTree}`
- `arg1::Cint`
- `arg2::Ref{Any}`
- `arg3::Ref{Any}`

# Returns
- `Bool`

# Metadata
- Mangled symbol: `_ZN13b2DynamicTree9MoveProxyEiRK6b2AABBRK6b2Vec2`
"""

function b2DynamicTree_MoveProxy(this::Any, arg1::Integer, arg2::Ref{Any}, arg3::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN13b2DynamicTree9MoveProxyEiRK6b2AABBRK6b2Vec2_thunk", Bool, this, arg1, arg2, arg3)
end
"""
    b2DynamicTree_destroy_b2DynamicTree(this::Any) -> Cvoid

Wrapper for `b2DynamicTree::~b2DynamicTree()`

# Arguments
- `this::Ptr{b2DynamicTree}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN13b2DynamicTreeD2Ev`
"""

function b2DynamicTree_destroy_b2DynamicTree(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN13b2DynamicTreeD2Ev_thunk", this)
end
"""
    b2PulleyJoint_ShiftOrigin(this::Any, arg1::Ref{Any}) -> Cvoid

Wrapper for `b2PulleyJoint::ShiftOrigin(b2Vec2 const&)`

# Arguments
- `this::Ptr{b2PulleyJoint}`
- `arg1::Ref{Any}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN13b2PulleyJoint11ShiftOriginERK6b2Vec2`
"""

function b2PulleyJoint_ShiftOrigin(this::Any, arg1::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN13b2PulleyJoint11ShiftOriginERK6b2Vec2_thunk", this, arg1)
end
"""
    b2PulleyJoint_InitVelocityConstraints(this::Any, arg1::Ref{Any}) -> Cvoid

Wrapper for `b2PulleyJoint::InitVelocityConstraints(b2SolverData const&)`

# Arguments
- `this::Ptr{b2PulleyJoint}`
- `arg1::Ref{Any}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN13b2PulleyJoint23InitVelocityConstraintsERK12b2SolverData`
"""

function b2PulleyJoint_InitVelocityConstraints(this::Any, arg1::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN13b2PulleyJoint23InitVelocityConstraintsERK12b2SolverData_thunk", this, arg1)
end
"""
    b2PulleyJoint_SolvePositionConstraints(this::Any, arg1::Ref{Any}) -> Bool

Wrapper for `b2PulleyJoint::SolvePositionConstraints(b2SolverData const&)`

# Arguments
- `this::Ptr{b2PulleyJoint}`
- `arg1::Ref{Any}`

# Returns
- `Bool`

# Metadata
- Mangled symbol: `_ZN13b2PulleyJoint24SolvePositionConstraintsERK12b2SolverData`
"""

function b2PulleyJoint_SolvePositionConstraints(this::Any, arg1::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN13b2PulleyJoint24SolvePositionConstraintsERK12b2SolverData_thunk", Bool, this, arg1)
end
"""
    b2PulleyJoint_SolveVelocityConstraints(this::Any, arg1::Ref{Any}) -> Cvoid

Wrapper for `b2PulleyJoint::SolveVelocityConstraints(b2SolverData const&)`

# Arguments
- `this::Ptr{b2PulleyJoint}`
- `arg1::Ref{Any}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN13b2PulleyJoint24SolveVelocityConstraintsERK12b2SolverData`
"""

function b2PulleyJoint_SolveVelocityConstraints(this::Any, arg1::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN13b2PulleyJoint24SolveVelocityConstraintsERK12b2SolverData_thunk", this, arg1)
end
"""
    b2PulleyJoint_Dump(this::Any) -> Cvoid

Wrapper for `b2PulleyJoint::Dump()`

# Arguments
- `this::Ptr{b2PulleyJoint}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN13b2PulleyJoint4DumpEv`
"""

function b2PulleyJoint_Dump(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN13b2PulleyJoint4DumpEv_thunk", this)
end
"""
    b2PulleyJoint_destroy_b2PulleyJoint(this::Any) -> Cvoid

Wrapper for `b2PulleyJoint::~b2PulleyJoint()`

# Arguments
- `this::Ptr{b2PulleyJoint}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN13b2PulleyJointD0Ev`
"""

function b2PulleyJoint_destroy_b2PulleyJoint(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN13b2PulleyJointD0Ev_thunk", this)
end
"""
    b2PolygonShape_Set(this::Any, arg1::Any, arg2::Integer) -> Cvoid

Wrapper for `b2PolygonShape::Set(b2Vec2 const*, int)`

# Arguments
- `this::Ptr{b2PolygonShape}`
- `arg1::Ptr{Cvoid}`
- `arg2::Cint`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN14b2PolygonShape3SetEPK6b2Vec2i`
"""

function b2PolygonShape_Set(this::Any, arg1::Any, arg2::Integer)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN14b2PolygonShape3SetEPK6b2Vec2i_thunk", this, arg1, arg2)
end
"""
    b2PolygonShape_SetAsBox(this::Any, arg1::Cfloat, arg2::Cfloat) -> Cvoid

Wrapper for `b2PolygonShape::SetAsBox(float, float)`

# Arguments
- `this::Ptr{b2PolygonShape}`
- `arg1::Cfloat`
- `arg2::Cfloat`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN14b2PolygonShape8SetAsBoxEff`
"""

function b2PolygonShape_SetAsBox(this::Any, arg1::Cfloat, arg2::Cfloat)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN14b2PolygonShape8SetAsBoxEff_thunk", this, arg1, arg2)
end
"""
    b2PolygonShape_SetAsBox(this::Any, arg1::Cfloat, arg2::Cfloat, arg3::Ref{Any}, arg4::Cfloat) -> Cvoid

Wrapper for `b2PolygonShape::SetAsBox(float, float, b2Vec2 const&, float)`

# Arguments
- `this::Ptr{b2PolygonShape}`
- `arg1::Cfloat`
- `arg2::Cfloat`
- `arg3::Ref{Any}`
- `arg4::Cfloat`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN14b2PolygonShape8SetAsBoxEffRK6b2Vec2f`
"""

function b2PolygonShape_SetAsBox(this::Any, arg1::Cfloat, arg2::Cfloat, arg3::Ref{Any}, arg4::Cfloat)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN14b2PolygonShape8SetAsBoxEffRK6b2Vec2f_thunk", this, arg1, arg2, arg3, arg4)
end
"""
    b2PolygonShape_destroy_b2PolygonShape(this::Any) -> Cvoid

Wrapper for `b2PolygonShape::~b2PolygonShape()`

# Arguments
- `this::Ptr{b2PolygonShape}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN14b2PolygonShapeD0Ev`
"""

function b2PolygonShape_destroy_b2PolygonShape(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN14b2PolygonShapeD0Ev_thunk", this)
end
"""
    b2WeldJointDef_Initialize(this::Any, arg1::Any, arg2::Any, arg3::Ref{Any}) -> Cvoid

Wrapper for `b2WeldJointDef::Initialize(b2Body*, b2Body*, b2Vec2 const&)`

# Arguments
- `this::Ptr{b2WeldJointDef}`
- `arg1::Ptr{b2Body}`
- `arg2::Ptr{b2Body}`
- `arg3::Ref{Any}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN14b2WeldJointDef10InitializeEP6b2BodyS1_RK6b2Vec2`
"""

function b2WeldJointDef_Initialize(this::Any, arg1::Any, arg2::Any, arg3::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN14b2WeldJointDef10InitializeEP6b2BodyS1_RK6b2Vec2_thunk", this, arg1, arg2, arg3)
end
"""
    b2CircleContact_Create(arg1::Any, arg2::Integer, arg3::Any, arg4::Integer, arg5::Any) -> Ptr{b2Contact}

Wrapper for `b2CircleContact::Create(b2Fixture*, int, b2Fixture*, int, b2BlockAllocator*)`

# Arguments
- `arg1::Ptr{b2Fixture}`
- `arg2::Cint`
- `arg3::Ptr{b2Fixture}`
- `arg4::Cint`
- `arg5::Ptr{b2BlockAllocator}`

# Returns
- `Ptr{b2Contact}`

# Metadata
- Mangled symbol: `_ZN15b2CircleContact6CreateEP9b2FixtureiS1_iP16b2BlockAllocator`
"""

function b2CircleContact_Create(arg1::Any, arg2::Integer, arg3::Any, arg4::Integer, arg5::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN15b2CircleContact6CreateEP9b2FixtureiS1_iP16b2BlockAllocator_thunk", Ptr{b2Contact}, arg1, arg2, arg3, arg4, arg5)
end
"""
    b2CircleContact_Destroy(arg1::Any, arg2::Any) -> Cvoid

Wrapper for `b2CircleContact::Destroy(b2Contact*, b2BlockAllocator*)`

# Arguments
- `arg1::Ptr{b2Contact}`
- `arg2::Ptr{b2BlockAllocator}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN15b2CircleContact7DestroyEP9b2ContactP16b2BlockAllocator`
"""

function b2CircleContact_Destroy(arg1::Any, arg2::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN15b2CircleContact7DestroyEP9b2ContactP16b2BlockAllocator_thunk", arg1, arg2)
end
"""
    b2CircleContact_Evaluate(arg1::Any, arg2::Ref{Any}, arg3::Ref{Any}) -> Cvoid

Wrapper for `b2CircleContact::Evaluate(b2Manifold*, b2Transform const&, b2Transform const&)`

# Arguments
- `arg1::Ptr{b2Manifold}`
- `arg2::Ref{Any}`
- `arg3::Ref{Any}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN15b2CircleContact8EvaluateEP10b2ManifoldRK11b2TransformS4_`
"""

function b2CircleContact_Evaluate(arg1::Any, arg2::Ref{Any}, arg3::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN15b2CircleContact8EvaluateEP10b2ManifoldRK11b2TransformS4__thunk", arg1, arg2, arg3)
end
"""
    b2CircleContact_destroy_b2CircleContact(this::Any) -> Cvoid

Wrapper for `b2CircleContact::~b2CircleContact()`

# Arguments
- `this::Ptr{b2CircleContact}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN15b2CircleContactD0Ev`
"""

function b2CircleContact_destroy_b2CircleContact(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN15b2CircleContactD0Ev_thunk", this)
end
"""
    b2ContactFilter_ShouldCollide(this::Any, arg1::Any, arg2::Any) -> Bool

Wrapper for `b2ContactFilter::ShouldCollide(b2Fixture*, b2Fixture*)`

# Arguments
- `this::Ptr{b2ContactFilter}`
- `arg1::Ptr{b2Fixture}`
- `arg2::Ptr{b2Fixture}`

# Returns
- `Bool`

# Metadata
- Mangled symbol: `_ZN15b2ContactFilter13ShouldCollideEP9b2FixtureS1_`
"""

function b2ContactFilter_ShouldCollide(this::Any, arg1::Any, arg2::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN15b2ContactFilter13ShouldCollideEP9b2FixtureS1__thunk", Bool, this, arg1, arg2)
end
"""
    b2ContactFilter_destroy_b2ContactFilter(this::Any) -> Cvoid

Wrapper for `b2ContactFilter::~b2ContactFilter()`

# Arguments
- `this::Ptr{b2ContactFilter}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN15b2ContactFilterD2Ev`
"""

function b2ContactFilter_destroy_b2ContactFilter(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN15b2ContactFilterD2Ev_thunk", this)
end
"""
    b2ContactSolver_StoreImpulses(this::Any) -> Cvoid

Wrapper for `b2ContactSolver::StoreImpulses()`

# Arguments
- `this::Ptr{b2ContactSolver}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN15b2ContactSolver13StoreImpulsesEv`
"""

function b2ContactSolver_StoreImpulses(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN15b2ContactSolver13StoreImpulsesEv_thunk", this)
end
"""
    b2ContactSolver_SolvePositionConstraints(this::Any) -> Bool

Wrapper for `b2ContactSolver::SolvePositionConstraints()`

# Arguments
- `this::Ptr{b2ContactSolver}`

# Returns
- `Bool`

# Metadata
- Mangled symbol: `_ZN15b2ContactSolver24SolvePositionConstraintsEv`
"""

function b2ContactSolver_SolvePositionConstraints(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN15b2ContactSolver24SolvePositionConstraintsEv_thunk", Bool, this)
end
"""
    b2ContactSolver_SolveVelocityConstraints(this::Any) -> Cvoid

Wrapper for `b2ContactSolver::SolveVelocityConstraints()`

# Arguments
- `this::Ptr{b2ContactSolver}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN15b2ContactSolver24SolveVelocityConstraintsEv`
"""

function b2ContactSolver_SolveVelocityConstraints(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN15b2ContactSolver24SolveVelocityConstraintsEv_thunk", this)
end
"""
    b2ContactSolver_SolveTOIPositionConstraints(this::Any, arg1::Integer, arg2::Integer) -> Bool

Wrapper for `b2ContactSolver::SolveTOIPositionConstraints(int, int)`

# Arguments
- `this::Ptr{b2ContactSolver}`
- `arg1::Cint`
- `arg2::Cint`

# Returns
- `Bool`

# Metadata
- Mangled symbol: `_ZN15b2ContactSolver27SolveTOIPositionConstraintsEii`
"""

function b2ContactSolver_SolveTOIPositionConstraints(this::Any, arg1::Integer, arg2::Integer)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN15b2ContactSolver27SolveTOIPositionConstraintsEii_thunk", Bool, this, arg1, arg2)
end
"""
    b2ContactSolver_InitializeVelocityConstraints(this::Any) -> Cvoid

Wrapper for `b2ContactSolver::InitializeVelocityConstraints()`

# Arguments
- `this::Ptr{b2ContactSolver}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN15b2ContactSolver29InitializeVelocityConstraintsEv`
"""

function b2ContactSolver_InitializeVelocityConstraints(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN15b2ContactSolver29InitializeVelocityConstraintsEv_thunk", this)
end
"""
    b2ContactSolver_WarmStart(this::Any) -> Cvoid

Wrapper for `b2ContactSolver::WarmStart()`

# Arguments
- `this::Ptr{b2ContactSolver}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN15b2ContactSolver9WarmStartEv`
"""

function b2ContactSolver_WarmStart(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN15b2ContactSolver9WarmStartEv_thunk", this)
end
"""
    b2ContactSolver_destroy_b2ContactSolver(this::Any) -> Cvoid

Wrapper for `b2ContactSolver::~b2ContactSolver()`

# Arguments
- `this::Ptr{b2ContactSolver}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN15b2ContactSolverD2Ev`
"""

function b2ContactSolver_destroy_b2ContactSolver(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN15b2ContactSolverD2Ev_thunk", this)
end
"""
    b2DistanceJoint_SetMaxLength(this::Any, arg1::Cfloat) -> Cfloat

Wrapper for `b2DistanceJoint::SetMaxLength(float)`

# Arguments
- `this::Ptr{b2DistanceJoint}`
- `arg1::Cfloat`

# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_ZN15b2DistanceJoint12SetMaxLengthEf`
"""

function b2DistanceJoint_SetMaxLength(this::Any, arg1::Cfloat)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN15b2DistanceJoint12SetMaxLengthEf_thunk", Cfloat, this, arg1)
end
"""
    b2DistanceJoint_SetMinLength(this::Any, arg1::Cfloat) -> Cfloat

Wrapper for `b2DistanceJoint::SetMinLength(float)`

# Arguments
- `this::Ptr{b2DistanceJoint}`
- `arg1::Cfloat`

# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_ZN15b2DistanceJoint12SetMinLengthEf`
"""

function b2DistanceJoint_SetMinLength(this::Any, arg1::Cfloat)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN15b2DistanceJoint12SetMinLengthEf_thunk", Cfloat, this, arg1)
end
"""
    b2DistanceJoint_InitVelocityConstraints(this::Any, arg1::Ref{Any}) -> Cvoid

Wrapper for `b2DistanceJoint::InitVelocityConstraints(b2SolverData const&)`

# Arguments
- `this::Ptr{b2DistanceJoint}`
- `arg1::Ref{Any}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN15b2DistanceJoint23InitVelocityConstraintsERK12b2SolverData`
"""

function b2DistanceJoint_InitVelocityConstraints(this::Any, arg1::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN15b2DistanceJoint23InitVelocityConstraintsERK12b2SolverData_thunk", this, arg1)
end
"""
    b2DistanceJoint_SolvePositionConstraints(this::Any, arg1::Ref{Any}) -> Bool

Wrapper for `b2DistanceJoint::SolvePositionConstraints(b2SolverData const&)`

# Arguments
- `this::Ptr{b2DistanceJoint}`
- `arg1::Ref{Any}`

# Returns
- `Bool`

# Metadata
- Mangled symbol: `_ZN15b2DistanceJoint24SolvePositionConstraintsERK12b2SolverData`
"""

function b2DistanceJoint_SolvePositionConstraints(this::Any, arg1::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN15b2DistanceJoint24SolvePositionConstraintsERK12b2SolverData_thunk", Bool, this, arg1)
end
"""
    b2DistanceJoint_SolveVelocityConstraints(this::Any, arg1::Ref{Any}) -> Cvoid

Wrapper for `b2DistanceJoint::SolveVelocityConstraints(b2SolverData const&)`

# Arguments
- `this::Ptr{b2DistanceJoint}`
- `arg1::Ref{Any}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN15b2DistanceJoint24SolveVelocityConstraintsERK12b2SolverData`
"""

function b2DistanceJoint_SolveVelocityConstraints(this::Any, arg1::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN15b2DistanceJoint24SolveVelocityConstraintsERK12b2SolverData_thunk", this, arg1)
end
"""
    b2DistanceJoint_Dump(this::Any) -> Cvoid

Wrapper for `b2DistanceJoint::Dump()`

# Arguments
- `this::Ptr{b2DistanceJoint}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN15b2DistanceJoint4DumpEv`
"""

function b2DistanceJoint_Dump(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN15b2DistanceJoint4DumpEv_thunk", this)
end
"""
    b2DistanceJoint_SetLength(this::Any, arg1::Cfloat) -> Cfloat

Wrapper for `b2DistanceJoint::SetLength(float)`

# Arguments
- `this::Ptr{b2DistanceJoint}`
- `arg1::Cfloat`

# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_ZN15b2DistanceJoint9SetLengthEf`
"""

function b2DistanceJoint_SetLength(this::Any, arg1::Cfloat)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN15b2DistanceJoint9SetLengthEf_thunk", Cfloat, this, arg1)
end
"""
    b2DistanceJoint_destroy_b2DistanceJoint(this::Any) -> Cvoid

Wrapper for `b2DistanceJoint::~b2DistanceJoint()`

# Arguments
- `this::Ptr{b2DistanceJoint}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN15b2DistanceJointD0Ev`
"""

function b2DistanceJoint_destroy_b2DistanceJoint(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN15b2DistanceJointD0Ev_thunk", this)
end
"""
    b2DistanceProxy_Set(this::Any, arg1::Any, arg2::Integer, arg3::Cfloat) -> Cvoid

Wrapper for `b2DistanceProxy::Set(b2Vec2 const*, int, float)`

# Arguments
- `this::Ptr{b2DistanceProxy}`
- `arg1::Ptr{Cvoid}`
- `arg2::Cint`
- `arg3::Cfloat`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN15b2DistanceProxy3SetEPK6b2Vec2if`
"""

function b2DistanceProxy_Set(this::Any, arg1::Any, arg2::Integer, arg3::Cfloat)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN15b2DistanceProxy3SetEPK6b2Vec2if_thunk", this, arg1, arg2, arg3)
end
"""
    b2DistanceProxy_Set(this::Any, arg1::Any, arg2::Integer) -> Cvoid

Wrapper for `b2DistanceProxy::Set(b2Shape const*, int)`

# Arguments
- `this::Ptr{b2DistanceProxy}`
- `arg1::Ptr{Cvoid}`
- `arg2::Cint`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN15b2DistanceProxy3SetEPK7b2Shapei`
"""

function b2DistanceProxy_Set(this::Any, arg1::Any, arg2::Integer)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN15b2DistanceProxy3SetEPK7b2Shapei_thunk", this, arg1, arg2)
end
"""
    b2FrictionJoint_SetMaxForce(this::Any, arg1::Cfloat) -> Cvoid

Wrapper for `b2FrictionJoint::SetMaxForce(float)`

# Arguments
- `this::Ptr{b2FrictionJoint}`
- `arg1::Cfloat`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN15b2FrictionJoint11SetMaxForceEf`
"""

function b2FrictionJoint_SetMaxForce(this::Any, arg1::Cfloat)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN15b2FrictionJoint11SetMaxForceEf_thunk", this, arg1)
end
"""
    b2FrictionJoint_SetMaxTorque(this::Any, arg1::Cfloat) -> Cvoid

Wrapper for `b2FrictionJoint::SetMaxTorque(float)`

# Arguments
- `this::Ptr{b2FrictionJoint}`
- `arg1::Cfloat`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN15b2FrictionJoint12SetMaxTorqueEf`
"""

function b2FrictionJoint_SetMaxTorque(this::Any, arg1::Cfloat)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN15b2FrictionJoint12SetMaxTorqueEf_thunk", this, arg1)
end
"""
    b2FrictionJoint_InitVelocityConstraints(this::Any, arg1::Ref{Any}) -> Cvoid

Wrapper for `b2FrictionJoint::InitVelocityConstraints(b2SolverData const&)`

# Arguments
- `this::Ptr{b2FrictionJoint}`
- `arg1::Ref{Any}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN15b2FrictionJoint23InitVelocityConstraintsERK12b2SolverData`
"""

function b2FrictionJoint_InitVelocityConstraints(this::Any, arg1::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN15b2FrictionJoint23InitVelocityConstraintsERK12b2SolverData_thunk", this, arg1)
end
"""
    b2FrictionJoint_SolvePositionConstraints(this::Any, arg1::Ref{Any}) -> Bool

Wrapper for `b2FrictionJoint::SolvePositionConstraints(b2SolverData const&)`

# Arguments
- `this::Ptr{b2FrictionJoint}`
- `arg1::Ref{Any}`

# Returns
- `Bool`

# Metadata
- Mangled symbol: `_ZN15b2FrictionJoint24SolvePositionConstraintsERK12b2SolverData`
"""

function b2FrictionJoint_SolvePositionConstraints(this::Any, arg1::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN15b2FrictionJoint24SolvePositionConstraintsERK12b2SolverData_thunk", Bool, this, arg1)
end
"""
    b2FrictionJoint_SolveVelocityConstraints(this::Any, arg1::Ref{Any}) -> Cvoid

Wrapper for `b2FrictionJoint::SolveVelocityConstraints(b2SolverData const&)`

# Arguments
- `this::Ptr{b2FrictionJoint}`
- `arg1::Ref{Any}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN15b2FrictionJoint24SolveVelocityConstraintsERK12b2SolverData`
"""

function b2FrictionJoint_SolveVelocityConstraints(this::Any, arg1::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN15b2FrictionJoint24SolveVelocityConstraintsERK12b2SolverData_thunk", this, arg1)
end
"""
    b2FrictionJoint_Dump(this::Any) -> Cvoid

Wrapper for `b2FrictionJoint::Dump()`

# Arguments
- `this::Ptr{b2FrictionJoint}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN15b2FrictionJoint4DumpEv`
"""

function b2FrictionJoint_Dump(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN15b2FrictionJoint4DumpEv_thunk", this)
end
"""
    b2FrictionJoint_destroy_b2FrictionJoint(this::Any) -> Cvoid

Wrapper for `b2FrictionJoint::~b2FrictionJoint()`

# Arguments
- `this::Ptr{b2FrictionJoint}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN15b2FrictionJointD0Ev`
"""

function b2FrictionJoint_destroy_b2FrictionJoint(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN15b2FrictionJointD0Ev_thunk", this)
end
"""
    b2MotorJointDef_Initialize(this::Any, arg1::Any, arg2::Any) -> Cvoid

Wrapper for `b2MotorJointDef::Initialize(b2Body*, b2Body*)`

# Arguments
- `this::Ptr{b2MotorJointDef}`
- `arg1::Ptr{b2Body}`
- `arg2::Ptr{b2Body}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN15b2MotorJointDef10InitializeEP6b2BodyS1_`
"""

function b2MotorJointDef_Initialize(this::Any, arg1::Any, arg2::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN15b2MotorJointDef10InitializeEP6b2BodyS1__thunk", this, arg1, arg2)
end
"""
    b2RevoluteJoint_EnableLimit(this::Any, arg1::Bool) -> Cvoid

Wrapper for `b2RevoluteJoint::EnableLimit(bool)`

# Arguments
- `this::Ptr{b2RevoluteJoint}`
- `arg1::Bool`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN15b2RevoluteJoint11EnableLimitEb`
"""

function b2RevoluteJoint_EnableLimit(this::Any, arg1::Bool)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN15b2RevoluteJoint11EnableLimitEb_thunk", this, arg1)
end
"""
    b2RevoluteJoint_EnableMotor(this::Any, arg1::Bool) -> Cvoid

Wrapper for `b2RevoluteJoint::EnableMotor(bool)`

# Arguments
- `this::Ptr{b2RevoluteJoint}`
- `arg1::Bool`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN15b2RevoluteJoint11EnableMotorEb`
"""

function b2RevoluteJoint_EnableMotor(this::Any, arg1::Bool)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN15b2RevoluteJoint11EnableMotorEb_thunk", this, arg1)
end
"""
    b2RevoluteJoint_SetMotorSpeed(this::Any, arg1::Cfloat) -> Cvoid

Wrapper for `b2RevoluteJoint::SetMotorSpeed(float)`

# Arguments
- `this::Ptr{b2RevoluteJoint}`
- `arg1::Cfloat`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN15b2RevoluteJoint13SetMotorSpeedEf`
"""

function b2RevoluteJoint_SetMotorSpeed(this::Any, arg1::Cfloat)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN15b2RevoluteJoint13SetMotorSpeedEf_thunk", this, arg1)
end
"""
    b2RevoluteJoint_SetMaxMotorTorque(this::Any, arg1::Cfloat) -> Cvoid

Wrapper for `b2RevoluteJoint::SetMaxMotorTorque(float)`

# Arguments
- `this::Ptr{b2RevoluteJoint}`
- `arg1::Cfloat`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN15b2RevoluteJoint17SetMaxMotorTorqueEf`
"""

function b2RevoluteJoint_SetMaxMotorTorque(this::Any, arg1::Cfloat)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN15b2RevoluteJoint17SetMaxMotorTorqueEf_thunk", this, arg1)
end
"""
    b2RevoluteJoint_InitVelocityConstraints(this::Any, arg1::Ref{Any}) -> Cvoid

Wrapper for `b2RevoluteJoint::InitVelocityConstraints(b2SolverData const&)`

# Arguments
- `this::Ptr{b2RevoluteJoint}`
- `arg1::Ref{Any}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN15b2RevoluteJoint23InitVelocityConstraintsERK12b2SolverData`
"""

function b2RevoluteJoint_InitVelocityConstraints(this::Any, arg1::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN15b2RevoluteJoint23InitVelocityConstraintsERK12b2SolverData_thunk", this, arg1)
end
"""
    b2RevoluteJoint_SolvePositionConstraints(this::Any, arg1::Ref{Any}) -> Bool

Wrapper for `b2RevoluteJoint::SolvePositionConstraints(b2SolverData const&)`

# Arguments
- `this::Ptr{b2RevoluteJoint}`
- `arg1::Ref{Any}`

# Returns
- `Bool`

# Metadata
- Mangled symbol: `_ZN15b2RevoluteJoint24SolvePositionConstraintsERK12b2SolverData`
"""

function b2RevoluteJoint_SolvePositionConstraints(this::Any, arg1::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN15b2RevoluteJoint24SolvePositionConstraintsERK12b2SolverData_thunk", Bool, this, arg1)
end
"""
    b2RevoluteJoint_SolveVelocityConstraints(this::Any, arg1::Ref{Any}) -> Cvoid

Wrapper for `b2RevoluteJoint::SolveVelocityConstraints(b2SolverData const&)`

# Arguments
- `this::Ptr{b2RevoluteJoint}`
- `arg1::Ref{Any}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN15b2RevoluteJoint24SolveVelocityConstraintsERK12b2SolverData`
"""

function b2RevoluteJoint_SolveVelocityConstraints(this::Any, arg1::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN15b2RevoluteJoint24SolveVelocityConstraintsERK12b2SolverData_thunk", this, arg1)
end
"""
    b2RevoluteJoint_Dump(this::Any) -> Cvoid

Wrapper for `b2RevoluteJoint::Dump()`

# Arguments
- `this::Ptr{b2RevoluteJoint}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN15b2RevoluteJoint4DumpEv`
"""

function b2RevoluteJoint_Dump(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN15b2RevoluteJoint4DumpEv_thunk", this)
end
"""
    b2RevoluteJoint_SetLimits(this::Any, arg1::Cfloat, arg2::Cfloat) -> Cvoid

Wrapper for `b2RevoluteJoint::SetLimits(float, float)`

# Arguments
- `this::Ptr{b2RevoluteJoint}`
- `arg1::Cfloat`
- `arg2::Cfloat`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN15b2RevoluteJoint9SetLimitsEff`
"""

function b2RevoluteJoint_SetLimits(this::Any, arg1::Cfloat, arg2::Cfloat)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN15b2RevoluteJoint9SetLimitsEff_thunk", this, arg1, arg2)
end
"""
    b2RevoluteJoint_destroy_b2RevoluteJoint(this::Any) -> Cvoid

Wrapper for `b2RevoluteJoint::~b2RevoluteJoint()`

# Arguments
- `this::Ptr{b2RevoluteJoint}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN15b2RevoluteJointD0Ev`
"""

function b2RevoluteJoint_destroy_b2RevoluteJoint(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN15b2RevoluteJointD0Ev_thunk", this)
end
"""
    b2WheelJointDef_Initialize(this::Any, arg1::Any, arg2::Any, arg3::Ref{Any}, arg4::Ref{Any}) -> Cvoid

Wrapper for `b2WheelJointDef::Initialize(b2Body*, b2Body*, b2Vec2 const&, b2Vec2 const&)`

# Arguments
- `this::Ptr{b2WheelJointDef}`
- `arg1::Ptr{b2Body}`
- `arg2::Ptr{b2Body}`
- `arg3::Ref{Any}`
- `arg4::Ref{Any}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN15b2WheelJointDef10InitializeEP6b2BodyS1_RK6b2Vec2S4_`
"""

function b2WheelJointDef_Initialize(this::Any, arg1::Any, arg2::Any, arg3::Ref{Any}, arg4::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN15b2WheelJointDef10InitializeEP6b2BodyS1_RK6b2Vec2S4__thunk", this, arg1, arg2, arg3, arg4)
end
"""
    b2WorldManifold_Initialize(this::Any, arg1::Any, arg2::Ref{Any}, arg3::Cfloat, arg4::Ref{Any}, arg5::Cfloat) -> Cvoid

Wrapper for `b2WorldManifold::Initialize(b2Manifold const*, b2Transform const&, float, b2Transform const&, float)`

# Arguments
- `this::Ptr{b2WorldManifold}`
- `arg1::Ptr{Cvoid}`
- `arg2::Ref{Any}`
- `arg3::Cfloat`
- `arg4::Ref{Any}`
- `arg5::Cfloat`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN15b2WorldManifold10InitializeEPK10b2ManifoldRK11b2TransformfS5_f`
"""

function b2WorldManifold_Initialize(this::Any, arg1::Any, arg2::Ref{Any}, arg3::Cfloat, arg4::Ref{Any}, arg5::Cfloat)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN15b2WorldManifold10InitializeEPK10b2ManifoldRK11b2TransformfS5_f_thunk", this, arg1, arg2, arg3, arg4, arg5)
end
"""
    b2BlockAllocator_Free(this::Any, arg1::Any, arg2::Integer) -> Cvoid

Wrapper for `b2BlockAllocator::Free(void*, int)`

# Arguments
- `this::Ptr{b2BlockAllocator}`
- `arg1::Ptr{Cvoid}`
- `arg2::Cint`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN16b2BlockAllocator4FreeEPvi`
"""

function b2BlockAllocator_Free(this::Any, arg1::Any, arg2::Integer)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN16b2BlockAllocator4FreeEPvi_thunk", this, arg1, arg2)
end
"""
    b2BlockAllocator_Clear(this::Any) -> Cvoid

Wrapper for `b2BlockAllocator::Clear()`

# Arguments
- `this::Ptr{b2BlockAllocator}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN16b2BlockAllocator5ClearEv`
"""

function b2BlockAllocator_Clear(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN16b2BlockAllocator5ClearEv_thunk", this)
end
"""
    b2BlockAllocator_Allocate(this::Any, arg1::Integer) -> Ptr{Cvoid}

Wrapper for `b2BlockAllocator::Allocate(int)`

# Arguments
- `this::Ptr{b2BlockAllocator}`
- `arg1::Cint`

# Returns
- `Ptr{Cvoid}`

# Metadata
- Mangled symbol: `_ZN16b2BlockAllocator8AllocateEi`
"""

function b2BlockAllocator_Allocate(this::Any, arg1::Integer)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN16b2BlockAllocator8AllocateEi_thunk", Ptr{Cvoid}, this, arg1)
end
"""
    b2BlockAllocator_destroy_b2BlockAllocator(this::Any) -> Cvoid

Wrapper for `b2BlockAllocator::~b2BlockAllocator()`

# Arguments
- `this::Ptr{b2BlockAllocator}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN16b2BlockAllocatorD2Ev`
"""

function b2BlockAllocator_destroy_b2BlockAllocator(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN16b2BlockAllocatorD2Ev_thunk", this)
end
"""
    b2ContactManager_FindNewContacts(this::Any) -> Cvoid

Wrapper for `b2ContactManager::FindNewContacts()`

# Arguments
- `this::Ptr{b2ContactManager}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN16b2ContactManager15FindNewContactsEv`
"""

function b2ContactManager_FindNewContacts(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN16b2ContactManager15FindNewContactsEv_thunk", this)
end
"""
    b2ContactManager_AddPair(this::Any, arg1::Any, arg2::Any) -> Cvoid

Wrapper for `b2ContactManager::AddPair(void*, void*)`

# Arguments
- `this::Ptr{b2ContactManager}`
- `arg1::Ptr{Cvoid}`
- `arg2::Ptr{Cvoid}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN16b2ContactManager7AddPairEPvS0_`
"""

function b2ContactManager_AddPair(this::Any, arg1::Any, arg2::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN16b2ContactManager7AddPairEPvS0__thunk", this, arg1, arg2)
end
"""
    b2ContactManager_Collide(this::Any) -> Cvoid

Wrapper for `b2ContactManager::Collide()`

# Arguments
- `this::Ptr{b2ContactManager}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN16b2ContactManager7CollideEv`
"""

function b2ContactManager_Collide(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN16b2ContactManager7CollideEv_thunk", this)
end
"""
    b2ContactManager_Destroy(this::Any, arg1::Any) -> Cvoid

Wrapper for `b2ContactManager::Destroy(b2Contact*)`

# Arguments
- `this::Ptr{b2ContactManager}`
- `arg1::Ptr{b2Contact}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN16b2ContactManager7DestroyEP9b2Contact`
"""

function b2ContactManager_Destroy(this::Any, arg1::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN16b2ContactManager7DestroyEP9b2Contact_thunk", this, arg1)
end
"""
    b2PolygonContact_Create(arg1::Any, arg2::Integer, arg3::Any, arg4::Integer, arg5::Any) -> Ptr{b2Contact}

Wrapper for `b2PolygonContact::Create(b2Fixture*, int, b2Fixture*, int, b2BlockAllocator*)`

# Arguments
- `arg1::Ptr{b2Fixture}`
- `arg2::Cint`
- `arg3::Ptr{b2Fixture}`
- `arg4::Cint`
- `arg5::Ptr{b2BlockAllocator}`

# Returns
- `Ptr{b2Contact}`

# Metadata
- Mangled symbol: `_ZN16b2PolygonContact6CreateEP9b2FixtureiS1_iP16b2BlockAllocator`
"""

function b2PolygonContact_Create(arg1::Any, arg2::Integer, arg3::Any, arg4::Integer, arg5::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN16b2PolygonContact6CreateEP9b2FixtureiS1_iP16b2BlockAllocator_thunk", Ptr{b2Contact}, arg1, arg2, arg3, arg4, arg5)
end
"""
    b2PolygonContact_Destroy(arg1::Any, arg2::Any) -> Cvoid

Wrapper for `b2PolygonContact::Destroy(b2Contact*, b2BlockAllocator*)`

# Arguments
- `arg1::Ptr{b2Contact}`
- `arg2::Ptr{b2BlockAllocator}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN16b2PolygonContact7DestroyEP9b2ContactP16b2BlockAllocator`
"""

function b2PolygonContact_Destroy(arg1::Any, arg2::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN16b2PolygonContact7DestroyEP9b2ContactP16b2BlockAllocator_thunk", arg1, arg2)
end
"""
    b2PolygonContact_Evaluate(arg1::Any, arg2::Ref{Any}, arg3::Ref{Any}) -> Cvoid

Wrapper for `b2PolygonContact::Evaluate(b2Manifold*, b2Transform const&, b2Transform const&)`

# Arguments
- `arg1::Ptr{b2Manifold}`
- `arg2::Ref{Any}`
- `arg3::Ref{Any}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN16b2PolygonContact8EvaluateEP10b2ManifoldRK11b2TransformS4_`
"""

function b2PolygonContact_Evaluate(arg1::Any, arg2::Ref{Any}, arg3::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN16b2PolygonContact8EvaluateEP10b2ManifoldRK11b2TransformS4__thunk", arg1, arg2, arg3)
end
"""
    b2PolygonContact_destroy_b2PolygonContact(this::Any) -> Cvoid

Wrapper for `b2PolygonContact::~b2PolygonContact()`

# Arguments
- `this::Ptr{b2PolygonContact}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN16b2PolygonContactD0Ev`
"""

function b2PolygonContact_destroy_b2PolygonContact(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN16b2PolygonContactD0Ev_thunk", this)
end
"""
    b2PrismaticJoint_EnableLimit(this::Any, arg1::Bool) -> Cvoid

Wrapper for `b2PrismaticJoint::EnableLimit(bool)`

# Arguments
- `this::Ptr{b2PrismaticJoint}`
- `arg1::Bool`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN16b2PrismaticJoint11EnableLimitEb`
"""

function b2PrismaticJoint_EnableLimit(this::Any, arg1::Bool)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN16b2PrismaticJoint11EnableLimitEb_thunk", this, arg1)
end
"""
    b2PrismaticJoint_EnableMotor(this::Any, arg1::Bool) -> Cvoid

Wrapper for `b2PrismaticJoint::EnableMotor(bool)`

# Arguments
- `this::Ptr{b2PrismaticJoint}`
- `arg1::Bool`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN16b2PrismaticJoint11EnableMotorEb`
"""

function b2PrismaticJoint_EnableMotor(this::Any, arg1::Bool)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN16b2PrismaticJoint11EnableMotorEb_thunk", this, arg1)
end
"""
    b2PrismaticJoint_SetMotorSpeed(this::Any, arg1::Cfloat) -> Cvoid

Wrapper for `b2PrismaticJoint::SetMotorSpeed(float)`

# Arguments
- `this::Ptr{b2PrismaticJoint}`
- `arg1::Cfloat`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN16b2PrismaticJoint13SetMotorSpeedEf`
"""

function b2PrismaticJoint_SetMotorSpeed(this::Any, arg1::Cfloat)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN16b2PrismaticJoint13SetMotorSpeedEf_thunk", this, arg1)
end
"""
    b2PrismaticJoint_SetMaxMotorForce(this::Any, arg1::Cfloat) -> Cvoid

Wrapper for `b2PrismaticJoint::SetMaxMotorForce(float)`

# Arguments
- `this::Ptr{b2PrismaticJoint}`
- `arg1::Cfloat`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN16b2PrismaticJoint16SetMaxMotorForceEf`
"""

function b2PrismaticJoint_SetMaxMotorForce(this::Any, arg1::Cfloat)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN16b2PrismaticJoint16SetMaxMotorForceEf_thunk", this, arg1)
end
"""
    b2PrismaticJoint_InitVelocityConstraints(this::Any, arg1::Ref{Any}) -> Cvoid

Wrapper for `b2PrismaticJoint::InitVelocityConstraints(b2SolverData const&)`

# Arguments
- `this::Ptr{b2PrismaticJoint}`
- `arg1::Ref{Any}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN16b2PrismaticJoint23InitVelocityConstraintsERK12b2SolverData`
"""

function b2PrismaticJoint_InitVelocityConstraints(this::Any, arg1::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN16b2PrismaticJoint23InitVelocityConstraintsERK12b2SolverData_thunk", this, arg1)
end
"""
    b2PrismaticJoint_SolvePositionConstraints(this::Any, arg1::Ref{Any}) -> Bool

Wrapper for `b2PrismaticJoint::SolvePositionConstraints(b2SolverData const&)`

# Arguments
- `this::Ptr{b2PrismaticJoint}`
- `arg1::Ref{Any}`

# Returns
- `Bool`

# Metadata
- Mangled symbol: `_ZN16b2PrismaticJoint24SolvePositionConstraintsERK12b2SolverData`
"""

function b2PrismaticJoint_SolvePositionConstraints(this::Any, arg1::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN16b2PrismaticJoint24SolvePositionConstraintsERK12b2SolverData_thunk", Bool, this, arg1)
end
"""
    b2PrismaticJoint_SolveVelocityConstraints(this::Any, arg1::Ref{Any}) -> Cvoid

Wrapper for `b2PrismaticJoint::SolveVelocityConstraints(b2SolverData const&)`

# Arguments
- `this::Ptr{b2PrismaticJoint}`
- `arg1::Ref{Any}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN16b2PrismaticJoint24SolveVelocityConstraintsERK12b2SolverData`
"""

function b2PrismaticJoint_SolveVelocityConstraints(this::Any, arg1::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN16b2PrismaticJoint24SolveVelocityConstraintsERK12b2SolverData_thunk", this, arg1)
end
"""
    b2PrismaticJoint_Dump(this::Any) -> Cvoid

Wrapper for `b2PrismaticJoint::Dump()`

# Arguments
- `this::Ptr{b2PrismaticJoint}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN16b2PrismaticJoint4DumpEv`
"""

function b2PrismaticJoint_Dump(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN16b2PrismaticJoint4DumpEv_thunk", this)
end
"""
    b2PrismaticJoint_SetLimits(this::Any, arg1::Cfloat, arg2::Cfloat) -> Cvoid

Wrapper for `b2PrismaticJoint::SetLimits(float, float)`

# Arguments
- `this::Ptr{b2PrismaticJoint}`
- `arg1::Cfloat`
- `arg2::Cfloat`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN16b2PrismaticJoint9SetLimitsEff`
"""

function b2PrismaticJoint_SetLimits(this::Any, arg1::Cfloat, arg2::Cfloat)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN16b2PrismaticJoint9SetLimitsEff_thunk", this, arg1, arg2)
end
"""
    b2PrismaticJoint_destroy_b2PrismaticJoint(this::Any) -> Cvoid

Wrapper for `b2PrismaticJoint::~b2PrismaticJoint()`

# Arguments
- `this::Ptr{b2PrismaticJoint}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN16b2PrismaticJointD0Ev`
"""

function b2PrismaticJoint_destroy_b2PrismaticJoint(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN16b2PrismaticJointD0Ev_thunk", this)
end
"""
    b2PulleyJointDef_Initialize(this::Any, arg1::Any, arg2::Any, arg3::Ref{Any}, arg4::Ref{Any}, arg5::Ref{Any}, arg6::Ref{Any}, arg7::Cfloat) -> Cvoid

Wrapper for `b2PulleyJointDef::Initialize(b2Body*, b2Body*, b2Vec2 const&, b2Vec2 const&, b2Vec2 const&, b2Vec2 const&, float)`

# Arguments
- `this::Ptr{b2PulleyJointDef}`
- `arg1::Ptr{b2Body}`
- `arg2::Ptr{b2Body}`
- `arg3::Ref{Any}`
- `arg4::Ref{Any}`
- `arg5::Ref{Any}`
- `arg6::Ref{Any}`
- `arg7::Cfloat`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN16b2PulleyJointDef10InitializeEP6b2BodyS1_RK6b2Vec2S4_S4_S4_f`
"""

function b2PulleyJointDef_Initialize(this::Any, arg1::Any, arg2::Any, arg3::Ref{Any}, arg4::Ref{Any}, arg5::Ref{Any}, arg6::Ref{Any}, arg7::Cfloat)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN16b2PulleyJointDef10InitializeEP6b2BodyS1_RK6b2Vec2S4_S4_S4_f_thunk", this, arg1, arg2, arg3, arg4, arg5, arg6, arg7)
end
"""
    b2StackAllocator_Free(this::Any, arg1::Any) -> Cvoid

Wrapper for `b2StackAllocator::Free(void*)`

# Arguments
- `this::Ptr{b2StackAllocator}`
- `arg1::Ptr{Cvoid}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN16b2StackAllocator4FreeEPv`
"""

function b2StackAllocator_Free(this::Any, arg1::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN16b2StackAllocator4FreeEPv_thunk", this, arg1)
end
"""
    b2StackAllocator_Allocate(this::Any, arg1::Integer) -> Ptr{Cvoid}

Wrapper for `b2StackAllocator::Allocate(int)`

# Arguments
- `this::Ptr{b2StackAllocator}`
- `arg1::Cint`

# Returns
- `Ptr{Cvoid}`

# Metadata
- Mangled symbol: `_ZN16b2StackAllocator8AllocateEi`
"""

function b2StackAllocator_Allocate(this::Any, arg1::Integer)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN16b2StackAllocator8AllocateEi_thunk", Ptr{Cvoid}, this, arg1)
end
"""
    b2StackAllocator_destroy_b2StackAllocator(this::Any) -> Cvoid

Wrapper for `b2StackAllocator::~b2StackAllocator()`

# Arguments
- `this::Ptr{b2StackAllocator}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN16b2StackAllocatorD2Ev`
"""

function b2StackAllocator_destroy_b2StackAllocator(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN16b2StackAllocatorD2Ev_thunk", this)
end
"""
    b2ContactListener_EndContact(this::Any, arg1::Any) -> Cvoid

Wrapper for `b2ContactListener::EndContact(b2Contact*)`

# Arguments
- `this::Ptr{b2ContactListener}`
- `arg1::Ptr{b2Contact}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN17b2ContactListener10EndContactEP9b2Contact`
"""

function b2ContactListener_EndContact(this::Any, arg1::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN17b2ContactListener10EndContactEP9b2Contact_thunk", this, arg1)
end
"""
    b2ContactListener_BeginContact(this::Any, arg1::Any) -> Cvoid

Wrapper for `b2ContactListener::BeginContact(b2Contact*)`

# Arguments
- `this::Ptr{b2ContactListener}`
- `arg1::Ptr{b2Contact}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN17b2ContactListener12BeginContactEP9b2Contact`
"""

function b2ContactListener_BeginContact(this::Any, arg1::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN17b2ContactListener12BeginContactEP9b2Contact_thunk", this, arg1)
end
"""
    b2ContactListener_PreSolve(this::Any, arg1::Any, arg2::Any) -> Cvoid

Wrapper for `b2ContactListener::PreSolve(b2Contact*, b2Manifold const*)`

# Arguments
- `this::Ptr{b2ContactListener}`
- `arg1::Ptr{b2Contact}`
- `arg2::Ptr{Cvoid}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN17b2ContactListener8PreSolveEP9b2ContactPK10b2Manifold`
"""

function b2ContactListener_PreSolve(this::Any, arg1::Any, arg2::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN17b2ContactListener8PreSolveEP9b2ContactPK10b2Manifold_thunk", this, arg1, arg2)
end
"""
    b2ContactListener_PostSolve(this::Any, arg1::Any, arg2::Any) -> Cvoid

Wrapper for `b2ContactListener::PostSolve(b2Contact*, b2ContactImpulse const*)`

# Arguments
- `this::Ptr{b2ContactListener}`
- `arg1::Ptr{b2Contact}`
- `arg2::Ptr{Cvoid}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN17b2ContactListener9PostSolveEP9b2ContactPK16b2ContactImpulse`
"""

function b2ContactListener_PostSolve(this::Any, arg1::Any, arg2::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN17b2ContactListener9PostSolveEP9b2ContactPK16b2ContactImpulse_thunk", this, arg1, arg2)
end
"""
    b2ContactListener_destroy_b2ContactListener(this::Any) -> Cvoid

Wrapper for `b2ContactListener::~b2ContactListener()`

# Arguments
- `this::Ptr{b2ContactListener}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN17b2ContactListenerD2Ev`
"""

function b2ContactListener_destroy_b2ContactListener(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN17b2ContactListenerD2Ev_thunk", this)
end
"""
    b2DistanceJointDef_Initialize(this::Any, arg1::Any, arg2::Any, arg3::Ref{Any}, arg4::Ref{Any}) -> Cvoid

Wrapper for `b2DistanceJointDef::Initialize(b2Body*, b2Body*, b2Vec2 const&, b2Vec2 const&)`

# Arguments
- `this::Ptr{b2DistanceJointDef}`
- `arg1::Ptr{b2Body}`
- `arg2::Ptr{b2Body}`
- `arg3::Ref{Any}`
- `arg4::Ref{Any}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN18b2DistanceJointDef10InitializeEP6b2BodyS1_RK6b2Vec2S4_`
"""

function b2DistanceJointDef_Initialize(this::Any, arg1::Any, arg2::Any, arg3::Ref{Any}, arg4::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN18b2DistanceJointDef10InitializeEP6b2BodyS1_RK6b2Vec2S4__thunk", this, arg1, arg2, arg3, arg4)
end
"""
    b2FrictionJointDef_Initialize(this::Any, arg1::Any, arg2::Any, arg3::Ref{Any}) -> Cvoid

Wrapper for `b2FrictionJointDef::Initialize(b2Body*, b2Body*, b2Vec2 const&)`

# Arguments
- `this::Ptr{b2FrictionJointDef}`
- `arg1::Ptr{b2Body}`
- `arg2::Ptr{b2Body}`
- `arg3::Ref{Any}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN18b2FrictionJointDef10InitializeEP6b2BodyS1_RK6b2Vec2`
"""

function b2FrictionJointDef_Initialize(this::Any, arg1::Any, arg2::Any, arg3::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN18b2FrictionJointDef10InitializeEP6b2BodyS1_RK6b2Vec2_thunk", this, arg1, arg2, arg3)
end
"""
    b2RevoluteJointDef_Initialize(this::Any, arg1::Any, arg2::Any, arg3::Ref{Any}) -> Cvoid

Wrapper for `b2RevoluteJointDef::Initialize(b2Body*, b2Body*, b2Vec2 const&)`

# Arguments
- `this::Ptr{b2RevoluteJointDef}`
- `arg1::Ptr{b2Body}`
- `arg2::Ptr{b2Body}`
- `arg3::Ref{Any}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN18b2RevoluteJointDef10InitializeEP6b2BodyS1_RK6b2Vec2`
"""

function b2RevoluteJointDef_Initialize(this::Any, arg1::Any, arg2::Any, arg3::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN18b2RevoluteJointDef10InitializeEP6b2BodyS1_RK6b2Vec2_thunk", this, arg1, arg2, arg3)
end
"""
    b2PrismaticJointDef_Initialize(this::Any, arg1::Any, arg2::Any, arg3::Ref{Any}, arg4::Ref{Any}) -> Cvoid

Wrapper for `b2PrismaticJointDef::Initialize(b2Body*, b2Body*, b2Vec2 const&, b2Vec2 const&)`

# Arguments
- `this::Ptr{b2PrismaticJointDef}`
- `arg1::Ptr{b2Body}`
- `arg2::Ptr{b2Body}`
- `arg3::Ref{Any}`
- `arg4::Ref{Any}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN19b2PrismaticJointDef10InitializeEP6b2BodyS1_RK6b2Vec2S4_`
"""

function b2PrismaticJointDef_Initialize(this::Any, arg1::Any, arg2::Any, arg3::Ref{Any}, arg4::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN19b2PrismaticJointDef10InitializeEP6b2BodyS1_RK6b2Vec2S4__thunk", this, arg1, arg2, arg3, arg4)
end
"""
    b2SeparationFunction_Initialize(this::Any, arg1::Any, arg2::Any, arg3::Ref{Any}, arg4::Any, arg5::Ref{Any}, arg6::Cfloat) -> Cfloat

Wrapper for `b2SeparationFunction::Initialize(b2SimplexCache const*, b2DistanceProxy const*, b2Sweep const&, b2DistanceProxy const*, b2Sweep const&, float)`

# Arguments
- `this::Ptr{b2SeparationFunction}`
- `arg1::Ptr{Cvoid}`
- `arg2::Ptr{Cvoid}`
- `arg3::Ref{Any}`
- `arg4::Ptr{Cvoid}`
- `arg5::Ref{Any}`
- `arg6::Cfloat`

# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_ZN20b2SeparationFunction10InitializeEPK14b2SimplexCachePK15b2DistanceProxyRK7b2SweepS5_S8_f`
"""

function b2SeparationFunction_Initialize(this::Any, arg1::Any, arg2::Any, arg3::Ref{Any}, arg4::Any, arg5::Ref{Any}, arg6::Cfloat)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN20b2SeparationFunction10InitializeEPK14b2SimplexCachePK15b2DistanceProxyRK7b2SweepS5_S8_f_thunk", Cfloat, this, arg1, arg2, arg3, arg4, arg5, arg6)
end
"""
    b2EdgeAndCircleContact_Create(arg1::Any, arg2::Integer, arg3::Any, arg4::Integer, arg5::Any) -> Ptr{b2Contact}

Wrapper for `b2EdgeAndCircleContact::Create(b2Fixture*, int, b2Fixture*, int, b2BlockAllocator*)`

# Arguments
- `arg1::Ptr{b2Fixture}`
- `arg2::Cint`
- `arg3::Ptr{b2Fixture}`
- `arg4::Cint`
- `arg5::Ptr{b2BlockAllocator}`

# Returns
- `Ptr{b2Contact}`

# Metadata
- Mangled symbol: `_ZN22b2EdgeAndCircleContact6CreateEP9b2FixtureiS1_iP16b2BlockAllocator`
"""

function b2EdgeAndCircleContact_Create(arg1::Any, arg2::Integer, arg3::Any, arg4::Integer, arg5::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN22b2EdgeAndCircleContact6CreateEP9b2FixtureiS1_iP16b2BlockAllocator_thunk", Ptr{b2Contact}, arg1, arg2, arg3, arg4, arg5)
end
"""
    b2EdgeAndCircleContact_Destroy(arg1::Any, arg2::Any) -> Cvoid

Wrapper for `b2EdgeAndCircleContact::Destroy(b2Contact*, b2BlockAllocator*)`

# Arguments
- `arg1::Ptr{b2Contact}`
- `arg2::Ptr{b2BlockAllocator}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN22b2EdgeAndCircleContact7DestroyEP9b2ContactP16b2BlockAllocator`
"""

function b2EdgeAndCircleContact_Destroy(arg1::Any, arg2::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN22b2EdgeAndCircleContact7DestroyEP9b2ContactP16b2BlockAllocator_thunk", arg1, arg2)
end
"""
    b2EdgeAndCircleContact_Evaluate(arg1::Any, arg2::Ref{Any}, arg3::Ref{Any}) -> Cvoid

Wrapper for `b2EdgeAndCircleContact::Evaluate(b2Manifold*, b2Transform const&, b2Transform const&)`

# Arguments
- `arg1::Ptr{b2Manifold}`
- `arg2::Ref{Any}`
- `arg3::Ref{Any}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN22b2EdgeAndCircleContact8EvaluateEP10b2ManifoldRK11b2TransformS4_`
"""

function b2EdgeAndCircleContact_Evaluate(arg1::Any, arg2::Ref{Any}, arg3::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN22b2EdgeAndCircleContact8EvaluateEP10b2ManifoldRK11b2TransformS4__thunk", arg1, arg2, arg3)
end
"""
    b2EdgeAndCircleContact_destroy_b2EdgeAndCircleContact(this::Any) -> Cvoid

Wrapper for `b2EdgeAndCircleContact::~b2EdgeAndCircleContact()`

# Arguments
- `this::Ptr{b2EdgeAndCircleContact}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN22b2EdgeAndCircleContactD0Ev`
"""

function b2EdgeAndCircleContact_destroy_b2EdgeAndCircleContact(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN22b2EdgeAndCircleContactD0Ev_thunk", this)
end
"""
    b2ChainAndCircleContact_Create(arg1::Any, arg2::Integer, arg3::Any, arg4::Integer, arg5::Any) -> Ptr{b2Contact}

Wrapper for `b2ChainAndCircleContact::Create(b2Fixture*, int, b2Fixture*, int, b2BlockAllocator*)`

# Arguments
- `arg1::Ptr{b2Fixture}`
- `arg2::Cint`
- `arg3::Ptr{b2Fixture}`
- `arg4::Cint`
- `arg5::Ptr{b2BlockAllocator}`

# Returns
- `Ptr{b2Contact}`

# Metadata
- Mangled symbol: `_ZN23b2ChainAndCircleContact6CreateEP9b2FixtureiS1_iP16b2BlockAllocator`
"""

function b2ChainAndCircleContact_Create(arg1::Any, arg2::Integer, arg3::Any, arg4::Integer, arg5::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN23b2ChainAndCircleContact6CreateEP9b2FixtureiS1_iP16b2BlockAllocator_thunk", Ptr{b2Contact}, arg1, arg2, arg3, arg4, arg5)
end
"""
    b2ChainAndCircleContact_Destroy(arg1::Any, arg2::Any) -> Cvoid

Wrapper for `b2ChainAndCircleContact::Destroy(b2Contact*, b2BlockAllocator*)`

# Arguments
- `arg1::Ptr{b2Contact}`
- `arg2::Ptr{b2BlockAllocator}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN23b2ChainAndCircleContact7DestroyEP9b2ContactP16b2BlockAllocator`
"""

function b2ChainAndCircleContact_Destroy(arg1::Any, arg2::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN23b2ChainAndCircleContact7DestroyEP9b2ContactP16b2BlockAllocator_thunk", arg1, arg2)
end
"""
    b2ChainAndCircleContact_Evaluate(arg1::Any, arg2::Ref{Any}, arg3::Ref{Any}) -> Cvoid

Wrapper for `b2ChainAndCircleContact::Evaluate(b2Manifold*, b2Transform const&, b2Transform const&)`

# Arguments
- `arg1::Ptr{b2Manifold}`
- `arg2::Ref{Any}`
- `arg3::Ref{Any}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN23b2ChainAndCircleContact8EvaluateEP10b2ManifoldRK11b2TransformS4_`
"""

function b2ChainAndCircleContact_Evaluate(arg1::Any, arg2::Ref{Any}, arg3::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN23b2ChainAndCircleContact8EvaluateEP10b2ManifoldRK11b2TransformS4__thunk", arg1, arg2, arg3)
end
"""
    b2ChainAndCircleContact_destroy_b2ChainAndCircleContact(this::Any) -> Cvoid

Wrapper for `b2ChainAndCircleContact::~b2ChainAndCircleContact()`

# Arguments
- `this::Ptr{b2ChainAndCircleContact}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN23b2ChainAndCircleContactD0Ev`
"""

function b2ChainAndCircleContact_destroy_b2ChainAndCircleContact(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN23b2ChainAndCircleContactD0Ev_thunk", this)
end
"""
    b2EdgeAndPolygonContact_Create(arg1::Any, arg2::Integer, arg3::Any, arg4::Integer, arg5::Any) -> Ptr{b2Contact}

Wrapper for `b2EdgeAndPolygonContact::Create(b2Fixture*, int, b2Fixture*, int, b2BlockAllocator*)`

# Arguments
- `arg1::Ptr{b2Fixture}`
- `arg2::Cint`
- `arg3::Ptr{b2Fixture}`
- `arg4::Cint`
- `arg5::Ptr{b2BlockAllocator}`

# Returns
- `Ptr{b2Contact}`

# Metadata
- Mangled symbol: `_ZN23b2EdgeAndPolygonContact6CreateEP9b2FixtureiS1_iP16b2BlockAllocator`
"""

function b2EdgeAndPolygonContact_Create(arg1::Any, arg2::Integer, arg3::Any, arg4::Integer, arg5::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN23b2EdgeAndPolygonContact6CreateEP9b2FixtureiS1_iP16b2BlockAllocator_thunk", Ptr{b2Contact}, arg1, arg2, arg3, arg4, arg5)
end
"""
    b2EdgeAndPolygonContact_Destroy(arg1::Any, arg2::Any) -> Cvoid

Wrapper for `b2EdgeAndPolygonContact::Destroy(b2Contact*, b2BlockAllocator*)`

# Arguments
- `arg1::Ptr{b2Contact}`
- `arg2::Ptr{b2BlockAllocator}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN23b2EdgeAndPolygonContact7DestroyEP9b2ContactP16b2BlockAllocator`
"""

function b2EdgeAndPolygonContact_Destroy(arg1::Any, arg2::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN23b2EdgeAndPolygonContact7DestroyEP9b2ContactP16b2BlockAllocator_thunk", arg1, arg2)
end
"""
    b2EdgeAndPolygonContact_Evaluate(arg1::Any, arg2::Ref{Any}, arg3::Ref{Any}) -> Cvoid

Wrapper for `b2EdgeAndPolygonContact::Evaluate(b2Manifold*, b2Transform const&, b2Transform const&)`

# Arguments
- `arg1::Ptr{b2Manifold}`
- `arg2::Ref{Any}`
- `arg3::Ref{Any}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN23b2EdgeAndPolygonContact8EvaluateEP10b2ManifoldRK11b2TransformS4_`
"""

function b2EdgeAndPolygonContact_Evaluate(arg1::Any, arg2::Ref{Any}, arg3::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN23b2EdgeAndPolygonContact8EvaluateEP10b2ManifoldRK11b2TransformS4__thunk", arg1, arg2, arg3)
end
"""
    b2EdgeAndPolygonContact_destroy_b2EdgeAndPolygonContact(this::Any) -> Cvoid

Wrapper for `b2EdgeAndPolygonContact::~b2EdgeAndPolygonContact()`

# Arguments
- `this::Ptr{b2EdgeAndPolygonContact}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN23b2EdgeAndPolygonContactD0Ev`
"""

function b2EdgeAndPolygonContact_destroy_b2EdgeAndPolygonContact(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN23b2EdgeAndPolygonContactD0Ev_thunk", this)
end
"""
    b2ChainAndPolygonContact_Create(arg1::Any, arg2::Integer, arg3::Any, arg4::Integer, arg5::Any) -> Ptr{b2Contact}

Wrapper for `b2ChainAndPolygonContact::Create(b2Fixture*, int, b2Fixture*, int, b2BlockAllocator*)`

# Arguments
- `arg1::Ptr{b2Fixture}`
- `arg2::Cint`
- `arg3::Ptr{b2Fixture}`
- `arg4::Cint`
- `arg5::Ptr{b2BlockAllocator}`

# Returns
- `Ptr{b2Contact}`

# Metadata
- Mangled symbol: `_ZN24b2ChainAndPolygonContact6CreateEP9b2FixtureiS1_iP16b2BlockAllocator`
"""

function b2ChainAndPolygonContact_Create(arg1::Any, arg2::Integer, arg3::Any, arg4::Integer, arg5::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN24b2ChainAndPolygonContact6CreateEP9b2FixtureiS1_iP16b2BlockAllocator_thunk", Ptr{b2Contact}, arg1, arg2, arg3, arg4, arg5)
end
"""
    b2ChainAndPolygonContact_Destroy(arg1::Any, arg2::Any) -> Cvoid

Wrapper for `b2ChainAndPolygonContact::Destroy(b2Contact*, b2BlockAllocator*)`

# Arguments
- `arg1::Ptr{b2Contact}`
- `arg2::Ptr{b2BlockAllocator}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN24b2ChainAndPolygonContact7DestroyEP9b2ContactP16b2BlockAllocator`
"""

function b2ChainAndPolygonContact_Destroy(arg1::Any, arg2::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN24b2ChainAndPolygonContact7DestroyEP9b2ContactP16b2BlockAllocator_thunk", arg1, arg2)
end
"""
    b2ChainAndPolygonContact_Evaluate(arg1::Any, arg2::Ref{Any}, arg3::Ref{Any}) -> Cvoid

Wrapper for `b2ChainAndPolygonContact::Evaluate(b2Manifold*, b2Transform const&, b2Transform const&)`

# Arguments
- `arg1::Ptr{b2Manifold}`
- `arg2::Ref{Any}`
- `arg3::Ref{Any}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN24b2ChainAndPolygonContact8EvaluateEP10b2ManifoldRK11b2TransformS4_`
"""

function b2ChainAndPolygonContact_Evaluate(arg1::Any, arg2::Ref{Any}, arg3::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN24b2ChainAndPolygonContact8EvaluateEP10b2ManifoldRK11b2TransformS4__thunk", arg1, arg2, arg3)
end
"""
    b2ChainAndPolygonContact_destroy_b2ChainAndPolygonContact(this::Any) -> Cvoid

Wrapper for `b2ChainAndPolygonContact::~b2ChainAndPolygonContact()`

# Arguments
- `this::Ptr{b2ChainAndPolygonContact}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN24b2ChainAndPolygonContactD0Ev`
"""

function b2ChainAndPolygonContact_destroy_b2ChainAndPolygonContact(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN24b2ChainAndPolygonContactD0Ev_thunk", this)
end
"""
    b2PositionSolverManifold_Initialize(this::Any, arg1::Any, arg2::Ref{Any}, arg3::Ref{Any}, arg4::Integer) -> Cvoid

Wrapper for `b2PositionSolverManifold::Initialize(b2ContactPositionConstraint*, b2Transform const&, b2Transform const&, int)`

# Arguments
- `this::Ptr{b2PositionSolverManifold}`
- `arg1::Ptr{b2ContactPositionConstraint}`
- `arg2::Ref{Any}`
- `arg3::Ref{Any}`
- `arg4::Cint`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN24b2PositionSolverManifold10InitializeEP27b2ContactPositionConstraintRK11b2TransformS4_i`
"""

function b2PositionSolverManifold_Initialize(this::Any, arg1::Any, arg2::Ref{Any}, arg3::Ref{Any}, arg4::Integer)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN24b2PositionSolverManifold10InitializeEP27b2ContactPositionConstraintRK11b2TransformS4_i_thunk", this, arg1, arg2, arg3, arg4)
end
"""
    b2PolygonAndCircleContact_Create(arg1::Any, arg2::Integer, arg3::Any, arg4::Integer, arg5::Any) -> Ptr{b2Contact}

Wrapper for `b2PolygonAndCircleContact::Create(b2Fixture*, int, b2Fixture*, int, b2BlockAllocator*)`

# Arguments
- `arg1::Ptr{b2Fixture}`
- `arg2::Cint`
- `arg3::Ptr{b2Fixture}`
- `arg4::Cint`
- `arg5::Ptr{b2BlockAllocator}`

# Returns
- `Ptr{b2Contact}`

# Metadata
- Mangled symbol: `_ZN25b2PolygonAndCircleContact6CreateEP9b2FixtureiS1_iP16b2BlockAllocator`
"""

function b2PolygonAndCircleContact_Create(arg1::Any, arg2::Integer, arg3::Any, arg4::Integer, arg5::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN25b2PolygonAndCircleContact6CreateEP9b2FixtureiS1_iP16b2BlockAllocator_thunk", Ptr{b2Contact}, arg1, arg2, arg3, arg4, arg5)
end
"""
    b2PolygonAndCircleContact_Destroy(arg1::Any, arg2::Any) -> Cvoid

Wrapper for `b2PolygonAndCircleContact::Destroy(b2Contact*, b2BlockAllocator*)`

# Arguments
- `arg1::Ptr{b2Contact}`
- `arg2::Ptr{b2BlockAllocator}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN25b2PolygonAndCircleContact7DestroyEP9b2ContactP16b2BlockAllocator`
"""

function b2PolygonAndCircleContact_Destroy(arg1::Any, arg2::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN25b2PolygonAndCircleContact7DestroyEP9b2ContactP16b2BlockAllocator_thunk", arg1, arg2)
end
"""
    b2PolygonAndCircleContact_Evaluate(arg1::Any, arg2::Ref{Any}, arg3::Ref{Any}) -> Cvoid

Wrapper for `b2PolygonAndCircleContact::Evaluate(b2Manifold*, b2Transform const&, b2Transform const&)`

# Arguments
- `arg1::Ptr{b2Manifold}`
- `arg2::Ref{Any}`
- `arg3::Ref{Any}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN25b2PolygonAndCircleContact8EvaluateEP10b2ManifoldRK11b2TransformS4_`
"""

function b2PolygonAndCircleContact_Evaluate(arg1::Any, arg2::Ref{Any}, arg3::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN25b2PolygonAndCircleContact8EvaluateEP10b2ManifoldRK11b2TransformS4__thunk", arg1, arg2, arg3)
end
"""
    b2PolygonAndCircleContact_destroy_b2PolygonAndCircleContact(this::Any) -> Cvoid

Wrapper for `b2PolygonAndCircleContact::~b2PolygonAndCircleContact()`

# Arguments
- `this::Ptr{b2PolygonAndCircleContact}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN25b2PolygonAndCircleContactD0Ev`
"""

function b2PolygonAndCircleContact_destroy_b2PolygonAndCircleContact(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN25b2PolygonAndCircleContactD0Ev_thunk", this)
end
"""
    b2Body_SetEnabled(this::Any, arg1::Bool) -> Cvoid

Wrapper for `b2Body::SetEnabled(bool)`

# Arguments
- `this::Ptr{b2Body}`
- `arg1::Bool`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN6b2Body10SetEnabledEb`
"""

function b2Body_SetEnabled(this::Any, arg1::Bool)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN6b2Body10SetEnabledEb_thunk", this, arg1)
end
"""
    b2Body_SetMassData(this::Any, arg1::Any) -> Cvoid

Wrapper for `b2Body::SetMassData(b2MassData const*)`

# Arguments
- `this::Ptr{b2Body}`
- `arg1::Ptr{Cvoid}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN6b2Body11SetMassDataEPK10b2MassData`
"""

function b2Body_SetMassData(this::Any, arg1::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN6b2Body11SetMassDataEPK10b2MassData_thunk", this, arg1)
end
"""
    b2Body_SetTransform(this::Any, arg1::Ref{Any}, arg2::Cfloat) -> Cvoid

Wrapper for `b2Body::SetTransform(b2Vec2 const&, float)`

# Arguments
- `this::Ptr{b2Body}`
- `arg1::Ref{Any}`
- `arg2::Cfloat`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN6b2Body12SetTransformERK6b2Vec2f`
"""

function b2Body_SetTransform(this::Any, arg1::Ref{Any}, arg2::Cfloat)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN6b2Body12SetTransformERK6b2Vec2f_thunk", this, arg1, arg2)
end
"""
    b2Body_CreateFixture(this::Any, arg1::Any) -> Ptr{b2Fixture}

Wrapper for `b2Body::CreateFixture(b2FixtureDef const*)`

# Arguments
- `this::Ptr{b2Body}`
- `arg1::Ptr{Cvoid}`

# Returns
- `Ptr{b2Fixture}`

# Metadata
- Mangled symbol: `_ZN6b2Body13CreateFixtureEPK12b2FixtureDef`
"""

function b2Body_CreateFixture(this::Any, arg1::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN6b2Body13CreateFixtureEPK12b2FixtureDef_thunk", Ptr{b2Fixture}, this, arg1)
end
"""
    b2Body_CreateFixture(this::Any, arg1::Any, arg2::Cfloat) -> Ptr{b2Fixture}

Wrapper for `b2Body::CreateFixture(b2Shape const*, float)`

# Arguments
- `this::Ptr{b2Body}`
- `arg1::Ptr{Cvoid}`
- `arg2::Cfloat`

# Returns
- `Ptr{b2Fixture}`

# Metadata
- Mangled symbol: `_ZN6b2Body13CreateFixtureEPK7b2Shapef`
"""

function b2Body_CreateFixture(this::Any, arg1::Any, arg2::Cfloat)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN6b2Body13CreateFixtureEPK7b2Shapef_thunk", Ptr{b2Fixture}, this, arg1, arg2)
end
"""
    b2Body_ResetMassData(this::Any) -> Cvoid

Wrapper for `b2Body::ResetMassData()`

# Arguments
- `this::Ptr{b2Body}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN6b2Body13ResetMassDataEv`
"""

function b2Body_ResetMassData(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN6b2Body13ResetMassDataEv_thunk", this)
end
"""
    b2Body_DestroyFixture(this::Any, arg1::Any) -> Cvoid

Wrapper for `b2Body::DestroyFixture(b2Fixture*)`

# Arguments
- `this::Ptr{b2Body}`
- `arg1::Ptr{b2Fixture}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN6b2Body14DestroyFixtureEP9b2Fixture`
"""

function b2Body_DestroyFixture(this::Any, arg1::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN6b2Body14DestroyFixtureEP9b2Fixture_thunk", this, arg1)
end
"""
    b2Body_SetFixedRotation(this::Any, arg1::Bool) -> Cvoid

Wrapper for `b2Body::SetFixedRotation(bool)`

# Arguments
- `this::Ptr{b2Body}`
- `arg1::Bool`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN6b2Body16SetFixedRotationEb`
"""

function b2Body_SetFixedRotation(this::Any, arg1::Bool)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN6b2Body16SetFixedRotationEb_thunk", this, arg1)
end
"""
    b2Body_SynchronizeFixtures(this::Any) -> Cvoid

Wrapper for `b2Body::SynchronizeFixtures()`

# Arguments
- `this::Ptr{b2Body}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN6b2Body19SynchronizeFixturesEv`
"""

function b2Body_SynchronizeFixtures(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN6b2Body19SynchronizeFixturesEv_thunk", this)
end
"""
    b2Body_Dump(this::Any) -> Cvoid

Wrapper for `b2Body::Dump()`

# Arguments
- `this::Ptr{b2Body}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN6b2Body4DumpEv`
"""

function b2Body_Dump(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN6b2Body4DumpEv_thunk", this)
end
"""
    b2Body_SetType(this::Any, arg1::b2BodyType) -> Cvoid

Wrapper for `b2Body::SetType(b2BodyType)`

# Arguments
- `this::Ptr{b2Body}`
- `arg1::b2BodyType`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN6b2Body7SetTypeE10b2BodyType`
"""

function b2Body_SetType(this::Any, arg1::b2BodyType)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN6b2Body7SetTypeE10b2BodyType_thunk", this, arg1)
end
"""
    b2Body_destroy_b2Body(this::Any) -> Cvoid

Wrapper for `b2Body::~b2Body()`

# Arguments
- `this::Ptr{b2Body}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN6b2BodyD2Ev`
"""

function b2Body_destroy_b2Body(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN6b2BodyD2Ev_thunk", this)
end
"""
    b2Draw_ClearFlags(this::Any, arg1::Integer) -> Cvoid

Wrapper for `b2Draw::ClearFlags(unsigned int)`

# Arguments
- `this::Ptr{b2Draw}`
- `arg1::Cuint`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN6b2Draw10ClearFlagsEj`
"""

function b2Draw_ClearFlags(this::Any, arg1::Integer)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN6b2Draw10ClearFlagsEj_thunk", this, arg1)
end
"""
    b2Draw_AppendFlags(this::Any, arg1::Integer) -> Cvoid

Wrapper for `b2Draw::AppendFlags(unsigned int)`

# Arguments
- `this::Ptr{b2Draw}`
- `arg1::Cuint`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN6b2Draw11AppendFlagsEj`
"""

function b2Draw_AppendFlags(this::Any, arg1::Integer)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN6b2Draw11AppendFlagsEj_thunk", this, arg1)
end
"""
    b2Draw_SetFlags(this::Any, arg1::Integer) -> Cvoid

Wrapper for `b2Draw::SetFlags(unsigned int)`

# Arguments
- `this::Ptr{b2Draw}`
- `arg1::Cuint`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN6b2Draw8SetFlagsEj`
"""

function b2Draw_SetFlags(this::Any, arg1::Integer)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN6b2Draw8SetFlagsEj_thunk", this, arg1)
end
"""
    b2Draw_destroy_b2Draw(this::Any) -> Cvoid

Wrapper for `b2Draw::~b2Draw()`

# Arguments
- `this::Ptr{b2Draw}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN6b2DrawD2Ev`
"""

function b2Draw_destroy_b2Draw(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN6b2DrawD2Ev_thunk", this)
end
"""
    b2Rope_ApplyBendForces(this::Any, arg1::Cfloat) -> Cvoid

Wrapper for `b2Rope::ApplyBendForces(float)`

# Arguments
- `this::Ptr{b2Rope}`
- `arg1::Cfloat`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN6b2Rope15ApplyBendForcesEf`
"""

function b2Rope_ApplyBendForces(this::Any, arg1::Cfloat)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN6b2Rope15ApplyBendForcesEf_thunk", this, arg1)
end
"""
    b2Rope_SolveStretch_PBD(this::Any) -> Cvoid

Wrapper for `b2Rope::SolveStretch_PBD()`

# Arguments
- `this::Ptr{b2Rope}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN6b2Rope16SolveStretch_PBDEv`
"""

function b2Rope_SolveStretch_PBD(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN6b2Rope16SolveStretch_PBDEv_thunk", this)
end
"""
    b2Rope_SolveStretch_XPBD(this::Any, arg1::Cfloat) -> Cvoid

Wrapper for `b2Rope::SolveStretch_XPBD(float)`

# Arguments
- `this::Ptr{b2Rope}`
- `arg1::Cfloat`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN6b2Rope17SolveStretch_XPBDEf`
"""

function b2Rope_SolveStretch_XPBD(this::Any, arg1::Cfloat)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN6b2Rope17SolveStretch_XPBDEf_thunk", this, arg1)
end
"""
    b2Rope_SolveBend_PBD_Angle(this::Any) -> Cvoid

Wrapper for `b2Rope::SolveBend_PBD_Angle()`

# Arguments
- `this::Ptr{b2Rope}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN6b2Rope19SolveBend_PBD_AngleEv`
"""

function b2Rope_SolveBend_PBD_Angle(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN6b2Rope19SolveBend_PBD_AngleEv_thunk", this)
end
"""
    b2Rope_SolveBend_PBD_Height(this::Any) -> Cvoid

Wrapper for `b2Rope::SolveBend_PBD_Height()`

# Arguments
- `this::Ptr{b2Rope}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN6b2Rope20SolveBend_PBD_HeightEv`
"""

function b2Rope_SolveBend_PBD_Height(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN6b2Rope20SolveBend_PBD_HeightEv_thunk", this)
end
"""
    b2Rope_SolveBend_XPBD_Angle(this::Any, arg1::Cfloat) -> Cvoid

Wrapper for `b2Rope::SolveBend_XPBD_Angle(float)`

# Arguments
- `this::Ptr{b2Rope}`
- `arg1::Cfloat`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN6b2Rope20SolveBend_XPBD_AngleEf`
"""

function b2Rope_SolveBend_XPBD_Angle(this::Any, arg1::Cfloat)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN6b2Rope20SolveBend_XPBD_AngleEf_thunk", this, arg1)
end
"""
    b2Rope_SolveBend_PBD_Distance(this::Any) -> Cvoid

Wrapper for `b2Rope::SolveBend_PBD_Distance()`

# Arguments
- `this::Ptr{b2Rope}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN6b2Rope22SolveBend_PBD_DistanceEv`
"""

function b2Rope_SolveBend_PBD_Distance(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN6b2Rope22SolveBend_PBD_DistanceEv_thunk", this)
end
"""
    b2Rope_SolveBend_PBD_Triangle(this::Any) -> Cvoid

Wrapper for `b2Rope::SolveBend_PBD_Triangle()`

# Arguments
- `this::Ptr{b2Rope}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN6b2Rope22SolveBend_PBD_TriangleEv`
"""

function b2Rope_SolveBend_PBD_Triangle(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN6b2Rope22SolveBend_PBD_TriangleEv_thunk", this)
end
"""
    b2Rope_Step(this::Any, arg1::Cfloat, arg2::Integer, arg3::Ref{Any}) -> Cvoid

Wrapper for `b2Rope::Step(float, int, b2Vec2 const&)`

# Arguments
- `this::Ptr{b2Rope}`
- `arg1::Cfloat`
- `arg2::Cint`
- `arg3::Ref{Any}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN6b2Rope4StepEfiRK6b2Vec2`
"""

function b2Rope_Step(this::Any, arg1::Cfloat, arg2::Integer, arg3::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN6b2Rope4StepEfiRK6b2Vec2_thunk", this, arg1, arg2, arg3)
end
"""
    b2Rope_Reset(this::Any, arg1::Ref{Any}) -> Cvoid

Wrapper for `b2Rope::Reset(b2Vec2 const&)`

# Arguments
- `this::Ptr{b2Rope}`
- `arg1::Ref{Any}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN6b2Rope5ResetERK6b2Vec2`
"""

function b2Rope_Reset(this::Any, arg1::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN6b2Rope5ResetERK6b2Vec2_thunk", this, arg1)
end
"""
    b2Rope_Create(this::Any, arg1::Ref{Any}) -> Cvoid

Wrapper for `b2Rope::Create(b2RopeDef const&)`

# Arguments
- `this::Ptr{b2Rope}`
- `arg1::Ref{Any}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN6b2Rope6CreateERK9b2RopeDef`
"""

function b2Rope_Create(this::Any, arg1::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN6b2Rope6CreateERK9b2RopeDef_thunk", this, arg1)
end
"""
    b2Rope_SetTuning(this::Any, arg1::Ref{Any}) -> Cvoid

Wrapper for `b2Rope::SetTuning(b2RopeTuning const&)`

# Arguments
- `this::Ptr{b2Rope}`
- `arg1::Ref{Any}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN6b2Rope9SetTuningERK12b2RopeTuning`
"""

function b2Rope_SetTuning(this::Any, arg1::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN6b2Rope9SetTuningERK12b2RopeTuning_thunk", this, arg1)
end
"""
    b2Rope_destroy_b2Rope(this::Any) -> Cvoid

Wrapper for `b2Rope::~b2Rope()`

# Arguments
- `this::Ptr{b2Rope}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN6b2RopeD2Ev`
"""

function b2Rope_destroy_b2Rope(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN6b2RopeD2Ev_thunk", this)
end
"""
    b2Joint_ShiftOrigin(this::Any, arg1::Ref{Any}) -> Cvoid

Wrapper for `b2Joint::ShiftOrigin(b2Vec2 const&)`

# Arguments
- `this::Ptr{b2Joint}`
- `arg1::Ref{Any}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN7b2Joint11ShiftOriginERK6b2Vec2`
"""

function b2Joint_ShiftOrigin(this::Any, arg1::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN7b2Joint11ShiftOriginERK6b2Vec2_thunk", this, arg1)
end
"""
    b2Joint_Dump(this::Any) -> Cvoid

Wrapper for `b2Joint::Dump()`

# Arguments
- `this::Ptr{b2Joint}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN7b2Joint4DumpEv`
"""

function b2Joint_Dump(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN7b2Joint4DumpEv_thunk", this)
end
"""
    b2Joint_Create(this::Any, arg1::Any, arg2::Any) -> Ptr{b2Joint}

Wrapper for `b2Joint::Create(b2JointDef const*, b2BlockAllocator*)`

# Arguments
- `this::Ptr{b2Joint}`
- `arg1::Ptr{Cvoid}`
- `arg2::Ptr{b2BlockAllocator}`

# Returns
- `Ptr{b2Joint}`

# Metadata
- Mangled symbol: `_ZN7b2Joint6CreateEPK10b2JointDefP16b2BlockAllocator`
"""

function b2Joint_Create(this::Any, arg1::Any, arg2::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN7b2Joint6CreateEPK10b2JointDefP16b2BlockAllocator_thunk", Ptr{b2Joint}, this, arg1, arg2)
end
"""
    b2Joint_Destroy(this::Any, arg1::Any, arg2::Any) -> Cvoid

Wrapper for `b2Joint::Destroy(b2Joint*, b2BlockAllocator*)`

# Arguments
- `this::Ptr{b2Joint}`
- `arg1::Ptr{b2Joint}`
- `arg2::Ptr{b2BlockAllocator}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN7b2Joint7DestroyEPS_P16b2BlockAllocator`
"""

function b2Joint_Destroy(this::Any, arg1::Any, arg2::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN7b2Joint7DestroyEPS_P16b2BlockAllocator_thunk", this, arg1, arg2)
end
"""
    b2Joint_destroy_b2Joint(this::Any) -> Cvoid

Wrapper for `b2Joint::~b2Joint()`

# Arguments
- `this::Ptr{b2Joint}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN7b2JointD2Ev`
"""

function b2Joint_destroy_b2Joint(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN7b2JointD2Ev_thunk", this)
end
"""
    b2Shape_destroy_b2Shape(this::Any) -> Cvoid

Wrapper for `b2Shape::~b2Shape()`

# Arguments
- `this::Ptr{b2Shape}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN7b2ShapeD2Ev`
"""

function b2Shape_destroy_b2Shape(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN7b2ShapeD2Ev_thunk", this)
end
"""
    b2Timer_Reset(this::Any) -> Cvoid

Wrapper for `b2Timer::Reset()`

# Arguments
- `this::Ptr{b2Timer}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN7b2Timer5ResetEv`
"""

function b2Timer_Reset(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN7b2Timer5ResetEv_thunk", this)
end
"""
    b2World_CreateBody(this::Any, arg1::Any) -> Ptr{b2Body}

Wrapper for `b2World::CreateBody(b2BodyDef const*)`

# Arguments
- `this::Ptr{b2World}`
- `arg1::Ptr{Cvoid}`

# Returns
- `Ptr{b2Body}`

# Metadata
- Mangled symbol: `_ZN7b2World10CreateBodyEPK9b2BodyDef`
"""

function b2World_CreateBody(this::Any, arg1::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN7b2World10CreateBodyEPK9b2BodyDef_thunk", Ptr{b2Body}, this, arg1)
end
"""
    b2World_ClearForces(this::Any) -> Cvoid

Wrapper for `b2World::ClearForces()`

# Arguments
- `this::Ptr{b2World}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN7b2World11ClearForcesEv`
"""

function b2World_ClearForces(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN7b2World11ClearForcesEv_thunk", this)
end
"""
    b2World_CreateJoint(this::Any, arg1::Any) -> Ptr{b2Joint}

Wrapper for `b2World::CreateJoint(b2JointDef const*)`

# Arguments
- `this::Ptr{b2World}`
- `arg1::Ptr{Cvoid}`

# Returns
- `Ptr{b2Joint}`

# Metadata
- Mangled symbol: `_ZN7b2World11CreateJointEPK10b2JointDef`
"""

function b2World_CreateJoint(this::Any, arg1::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN7b2World11CreateJointEPK10b2JointDef_thunk", Ptr{b2Joint}, this, arg1)
end
"""
    b2World_DestroyBody(this::Any, arg1::Any) -> Cvoid

Wrapper for `b2World::DestroyBody(b2Body*)`

# Arguments
- `this::Ptr{b2World}`
- `arg1::Ptr{b2Body}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN7b2World11DestroyBodyEP6b2Body`
"""

function b2World_DestroyBody(this::Any, arg1::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN7b2World11DestroyBodyEP6b2Body_thunk", this, arg1)
end
"""
    b2World_ShiftOrigin(this::Any, arg1::Ref{Any}) -> Cvoid

Wrapper for `b2World::ShiftOrigin(b2Vec2 const&)`

# Arguments
- `this::Ptr{b2World}`
- `arg1::Ref{Any}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN7b2World11ShiftOriginERK6b2Vec2`
"""

function b2World_ShiftOrigin(this::Any, arg1::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN7b2World11ShiftOriginERK6b2Vec2_thunk", this, arg1)
end
"""
    b2World_DestroyJoint(this::Any, arg1::Any) -> Cvoid

Wrapper for `b2World::DestroyJoint(b2Joint*)`

# Arguments
- `this::Ptr{b2World}`
- `arg1::Ptr{b2Joint}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN7b2World12DestroyJointEP7b2Joint`
"""

function b2World_DestroyJoint(this::Any, arg1::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN7b2World12DestroyJointEP7b2Joint_thunk", this, arg1)
end
"""
    b2World_SetDebugDraw(this::Any, arg1::Any) -> Cvoid

Wrapper for `b2World::SetDebugDraw(b2Draw*)`

# Arguments
- `this::Ptr{b2World}`
- `arg1::Ptr{b2Draw}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN7b2World12SetDebugDrawEP6b2Draw`
"""

function b2World_SetDebugDraw(this::Any, arg1::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN7b2World12SetDebugDrawEP6b2Draw_thunk", this, arg1)
end
"""
    b2World_SetAllowSleeping(this::Any, arg1::Bool) -> Cvoid

Wrapper for `b2World::SetAllowSleeping(bool)`

# Arguments
- `this::Ptr{b2World}`
- `arg1::Bool`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN7b2World16SetAllowSleepingEb`
"""

function b2World_SetAllowSleeping(this::Any, arg1::Bool)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN7b2World16SetAllowSleepingEb_thunk", this, arg1)
end
"""
    b2World_SetContactFilter(this::Any, arg1::Any) -> Cvoid

Wrapper for `b2World::SetContactFilter(b2ContactFilter*)`

# Arguments
- `this::Ptr{b2World}`
- `arg1::Ptr{b2ContactFilter}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN7b2World16SetContactFilterEP15b2ContactFilter`
"""

function b2World_SetContactFilter(this::Any, arg1::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN7b2World16SetContactFilterEP15b2ContactFilter_thunk", this, arg1)
end
"""
    b2World_SetContactListener(this::Any, arg1::Any) -> Cvoid

Wrapper for `b2World::SetContactListener(b2ContactListener*)`

# Arguments
- `this::Ptr{b2World}`
- `arg1::Ptr{b2ContactListener}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN7b2World18SetContactListenerEP17b2ContactListener`
"""

function b2World_SetContactListener(this::Any, arg1::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN7b2World18SetContactListenerEP17b2ContactListener_thunk", this, arg1)
end
"""
    b2World_SetDestructionListener(this::Any, arg1::Any) -> Cvoid

Wrapper for `b2World::SetDestructionListener(b2DestructionListener*)`

# Arguments
- `this::Ptr{b2World}`
- `arg1::Ptr{b2DestructionListener}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN7b2World22SetDestructionListenerEP21b2DestructionListener`
"""

function b2World_SetDestructionListener(this::Any, arg1::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN7b2World22SetDestructionListenerEP21b2DestructionListener_thunk", this, arg1)
end
"""
    b2World_Dump(this::Any) -> Cvoid

Wrapper for `b2World::Dump()`

# Arguments
- `this::Ptr{b2World}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN7b2World4DumpEv`
"""

function b2World_Dump(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN7b2World4DumpEv_thunk", this)
end
"""
    b2World_Step(this::Any, arg1::Cfloat, arg2::Integer, arg3::Integer) -> Cvoid

Wrapper for `b2World::Step(float, int, int)`

# Arguments
- `this::Ptr{b2World}`
- `arg1::Cfloat`
- `arg2::Cint`
- `arg3::Cint`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN7b2World4StepEfii`
"""

function b2World_Step(this::Any, arg1::Cfloat, arg2::Integer, arg3::Integer)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN7b2World4StepEfii_thunk", this, arg1, arg2, arg3)
end
"""
    b2World_Solve(this::Any, arg1::Ref{Any}) -> Cvoid

Wrapper for `b2World::Solve(b2TimeStep const&)`

# Arguments
- `this::Ptr{b2World}`
- `arg1::Ref{Any}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN7b2World5SolveERK10b2TimeStep`
"""

function b2World_Solve(this::Any, arg1::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN7b2World5SolveERK10b2TimeStep_thunk", this, arg1)
end
"""
    b2World_SolveTOI(this::Any, arg1::Ref{Any}) -> Cvoid

Wrapper for `b2World::SolveTOI(b2TimeStep const&)`

# Arguments
- `this::Ptr{b2World}`
- `arg1::Ref{Any}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN7b2World8SolveTOIERK10b2TimeStep`
"""

function b2World_SolveTOI(this::Any, arg1::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN7b2World8SolveTOIERK10b2TimeStep_thunk", this, arg1)
end
"""
    b2World_DebugDraw(this::Any) -> Cvoid

Wrapper for `b2World::DebugDraw()`

# Arguments
- `this::Ptr{b2World}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN7b2World9DebugDrawEv`
"""

function b2World_DebugDraw(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN7b2World9DebugDrawEv_thunk", this)
end
"""
    b2World_DrawShape(this::Any, arg1::Any, arg2::Ref{Any}, arg3::Ref{Any}) -> Cvoid

Wrapper for `b2World::DrawShape(b2Fixture*, b2Transform const&, b2Color const&)`

# Arguments
- `this::Ptr{b2World}`
- `arg1::Ptr{b2Fixture}`
- `arg2::Ref{Any}`
- `arg3::Ref{Any}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN7b2World9DrawShapeEP9b2FixtureRK11b2TransformRK7b2Color`
"""

function b2World_DrawShape(this::Any, arg1::Any, arg2::Ref{Any}, arg3::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN7b2World9DrawShapeEP9b2FixtureRK11b2TransformRK7b2Color_thunk", this, arg1, arg2, arg3)
end
"""
    b2World_destroy_b2World(this::Any) -> Cvoid

Wrapper for `b2World::~b2World()`

# Arguments
- `this::Ptr{b2World}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN7b2WorldD2Ev`
"""

function b2World_destroy_b2World(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN7b2WorldD2Ev_thunk", this)
end
"""
    b2Island_Solve(this::Any, arg1::Any, arg2::Ref{Any}, arg3::Ref{Any}, arg4::Bool) -> Cvoid

Wrapper for `b2Island::Solve(b2Profile*, b2TimeStep const&, b2Vec2 const&, bool)`

# Arguments
- `this::Ptr{b2Island}`
- `arg1::Ptr{b2Profile}`
- `arg2::Ref{Any}`
- `arg3::Ref{Any}`
- `arg4::Bool`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN8b2Island5SolveEP9b2ProfileRK10b2TimeStepRK6b2Vec2b`
"""

function b2Island_Solve(this::Any, arg1::Any, arg2::Ref{Any}, arg3::Ref{Any}, arg4::Bool)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN8b2Island5SolveEP9b2ProfileRK10b2TimeStepRK6b2Vec2b_thunk", this, arg1, arg2, arg3, arg4)
end
"""
    b2Island_Report(this::Any, arg1::Any) -> Cvoid

Wrapper for `b2Island::Report(b2ContactVelocityConstraint const*)`

# Arguments
- `this::Ptr{b2Island}`
- `arg1::Ptr{Cvoid}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN8b2Island6ReportEPK27b2ContactVelocityConstraint`
"""

function b2Island_Report(this::Any, arg1::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN8b2Island6ReportEPK27b2ContactVelocityConstraint_thunk", this, arg1)
end
"""
    b2Island_SolveTOI(this::Any, arg1::Ref{Any}, arg2::Integer, arg3::Integer) -> Cvoid

Wrapper for `b2Island::SolveTOI(b2TimeStep const&, int, int)`

# Arguments
- `this::Ptr{b2Island}`
- `arg1::Ref{Any}`
- `arg2::Cint`
- `arg3::Cint`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN8b2Island8SolveTOIERK10b2TimeStepii`
"""

function b2Island_SolveTOI(this::Any, arg1::Ref{Any}, arg2::Integer, arg3::Integer)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN8b2Island8SolveTOIERK10b2TimeStepii_thunk", this, arg1, arg2, arg3)
end
"""
    b2Island_destroy_b2Island(this::Any) -> Cvoid

Wrapper for `b2Island::~b2Island()`

# Arguments
- `this::Ptr{b2Island}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN8b2IslandD2Ev`
"""

function b2Island_destroy_b2Island(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN8b2IslandD2Ev_thunk", this)
end
"""
    b2Contact_InitializeRegisters(this::Any) -> Cvoid

Wrapper for `b2Contact::InitializeRegisters()`

# Arguments
- `this::Ptr{b2Contact}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN9b2Contact19InitializeRegistersEv`
"""

function b2Contact_InitializeRegisters(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN9b2Contact19InitializeRegistersEv_thunk", this)
end
"""
    b2Contact_Create(this::Any, arg1::Any, arg2::Integer, arg3::Any, arg4::Integer, arg5::Any) -> Ptr{b2Contact}

Wrapper for `b2Contact::Create(b2Fixture*, int, b2Fixture*, int, b2BlockAllocator*)`

# Arguments
- `this::Ptr{b2Contact}`
- `arg1::Ptr{b2Fixture}`
- `arg2::Cint`
- `arg3::Ptr{b2Fixture}`
- `arg4::Cint`
- `arg5::Ptr{b2BlockAllocator}`

# Returns
- `Ptr{b2Contact}`

# Metadata
- Mangled symbol: `_ZN9b2Contact6CreateEP9b2FixtureiS1_iP16b2BlockAllocator`
"""

function b2Contact_Create(this::Any, arg1::Any, arg2::Integer, arg3::Any, arg4::Integer, arg5::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN9b2Contact6CreateEP9b2FixtureiS1_iP16b2BlockAllocator_thunk", Ptr{b2Contact}, this, arg1, arg2, arg3, arg4, arg5)
end
"""
    b2Contact_Update(this::Any, arg1::Any) -> Cvoid

Wrapper for `b2Contact::Update(b2ContactListener*)`

# Arguments
- `this::Ptr{b2Contact}`
- `arg1::Ptr{b2ContactListener}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN9b2Contact6UpdateEP17b2ContactListener`
"""

function b2Contact_Update(this::Any, arg1::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN9b2Contact6UpdateEP17b2ContactListener_thunk", this, arg1)
end
"""
    b2Contact_AddType(this::Any, arg1::Any, arg2::Integer, arg3::Any, arg4::Integer, arg5::Any, arg6::Any, arg7::Any, arg8::Any, arg9::Any) -> Cvoid

Wrapper for `b2Contact::AddType(b2Contact* (*)(b2Fixture*, int, b2Fixture*, int, b2BlockAllocator*), void (*)(b2Contact*, b2BlockAllocator*), b2Shape::Type, b2Shape::Type)`

# Arguments
- `this::Ptr{b2Contact}`
- `arg1::Ptr{Cvoid}` - Callback function (signature unknown)
- `arg2::Cint`
- `arg3::Ptr{b2Fixture}`
- `arg4::Cint`
- `arg5::Any`
- `arg6::Ptr{Cvoid}` - Callback function (signature unknown)
- `arg7::Any`
- `arg8::Any`
- `arg9::Any`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN9b2Contact7AddTypeEPFPS_P9b2FixtureiS2_iP16b2BlockAllocatorEPFvS0_S4_EN7b2Shape4TypeESA_`
"""

function b2Contact_AddType(this::Any, arg1::Any, arg2::Integer, arg3::Any, arg4::Integer, arg5::Any, arg6::Any, arg7::Any, arg8::Any, arg9::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN9b2Contact7AddTypeEPFPS_P9b2FixtureiS2_iP16b2BlockAllocatorEPFvS0_S4_EN7b2Shape4TypeESA__thunk", this, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9)
end
"""
    b2Contact_Destroy(this::Any, arg1::Any, arg2::Any) -> Cvoid

Wrapper for `b2Contact::Destroy(b2Contact*, b2BlockAllocator*)`

# Arguments
- `this::Ptr{b2Contact}`
- `arg1::Ptr{b2Contact}`
- `arg2::Ptr{b2BlockAllocator}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN9b2Contact7DestroyEPS_P16b2BlockAllocator`
"""

function b2Contact_Destroy(this::Any, arg1::Any, arg2::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN9b2Contact7DestroyEPS_P16b2BlockAllocator_thunk", this, arg1, arg2)
end
"""
    b2Contact_destroy_b2Contact(this::Any) -> Cvoid

Wrapper for `b2Contact::~b2Contact()`

# Arguments
- `this::Ptr{b2Contact}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN9b2ContactD2Ev`
"""

function b2Contact_destroy_b2Contact(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN9b2ContactD2Ev_thunk", this)
end
"""
    b2Fixture_Synchronize(this::Any, arg1::Any, arg2::Ref{Any}, arg3::Ref{Any}) -> Cvoid

Wrapper for `b2Fixture::Synchronize(b2BroadPhase*, b2Transform const&, b2Transform const&)`

# Arguments
- `this::Ptr{b2Fixture}`
- `arg1::Ptr{b2BroadPhase}`
- `arg2::Ref{Any}`
- `arg3::Ref{Any}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN9b2Fixture11SynchronizeEP12b2BroadPhaseRK11b2TransformS4_`
"""

function b2Fixture_Synchronize(this::Any, arg1::Any, arg2::Ref{Any}, arg3::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN9b2Fixture11SynchronizeEP12b2BroadPhaseRK11b2TransformS4__thunk", this, arg1, arg2, arg3)
end
"""
    b2Fixture_CreateProxies(this::Any, arg1::Any, arg2::Ref{Any}) -> Cvoid

Wrapper for `b2Fixture::CreateProxies(b2BroadPhase*, b2Transform const&)`

# Arguments
- `this::Ptr{b2Fixture}`
- `arg1::Ptr{b2BroadPhase}`
- `arg2::Ref{Any}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN9b2Fixture13CreateProxiesEP12b2BroadPhaseRK11b2Transform`
"""

function b2Fixture_CreateProxies(this::Any, arg1::Any, arg2::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN9b2Fixture13CreateProxiesEP12b2BroadPhaseRK11b2Transform_thunk", this, arg1, arg2)
end
"""
    b2Fixture_SetFilterData(this::Any, arg1::Ref{Any}) -> Cvoid

Wrapper for `b2Fixture::SetFilterData(b2Filter const&)`

# Arguments
- `this::Ptr{b2Fixture}`
- `arg1::Ref{Any}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN9b2Fixture13SetFilterDataERK8b2Filter`
"""

function b2Fixture_SetFilterData(this::Any, arg1::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN9b2Fixture13SetFilterDataERK8b2Filter_thunk", this, arg1)
end
"""
    b2Fixture_DestroyProxies(this::Any, arg1::Any) -> Cvoid

Wrapper for `b2Fixture::DestroyProxies(b2BroadPhase*)`

# Arguments
- `this::Ptr{b2Fixture}`
- `arg1::Ptr{b2BroadPhase}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN9b2Fixture14DestroyProxiesEP12b2BroadPhase`
"""

function b2Fixture_DestroyProxies(this::Any, arg1::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN9b2Fixture14DestroyProxiesEP12b2BroadPhase_thunk", this, arg1)
end
"""
    b2Fixture_Dump(this::Any, arg1::Integer) -> Cvoid

Wrapper for `b2Fixture::Dump(int)`

# Arguments
- `this::Ptr{b2Fixture}`
- `arg1::Cint`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN9b2Fixture4DumpEi`
"""

function b2Fixture_Dump(this::Any, arg1::Integer)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN9b2Fixture4DumpEi_thunk", this, arg1)
end
"""
    b2Fixture_Create(this::Any, arg1::Any, arg2::Any, arg3::Any) -> Cvoid

Wrapper for `b2Fixture::Create(b2BlockAllocator*, b2Body*, b2FixtureDef const*)`

# Arguments
- `this::Ptr{b2Fixture}`
- `arg1::Ptr{b2BlockAllocator}`
- `arg2::Ptr{b2Body}`
- `arg3::Ptr{Cvoid}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN9b2Fixture6CreateEP16b2BlockAllocatorP6b2BodyPK12b2FixtureDef`
"""

function b2Fixture_Create(this::Any, arg1::Any, arg2::Any, arg3::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN9b2Fixture6CreateEP16b2BlockAllocatorP6b2BodyPK12b2FixtureDef_thunk", this, arg1, arg2, arg3)
end
"""
    b2Fixture_Destroy(this::Any, arg1::Any) -> Cvoid

Wrapper for `b2Fixture::Destroy(b2BlockAllocator*)`

# Arguments
- `this::Ptr{b2Fixture}`
- `arg1::Ptr{b2BlockAllocator}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN9b2Fixture7DestroyEP16b2BlockAllocator`
"""

function b2Fixture_Destroy(this::Any, arg1::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN9b2Fixture7DestroyEP16b2BlockAllocator_thunk", this, arg1)
end
"""
    b2Fixture_Refilter(this::Any) -> Cvoid

Wrapper for `b2Fixture::Refilter()`

# Arguments
- `this::Ptr{b2Fixture}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN9b2Fixture8RefilterEv`
"""

function b2Fixture_Refilter(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN9b2Fixture8RefilterEv_thunk", this)
end
"""
    b2Fixture_SetSensor(this::Any, arg1::Bool) -> Cvoid

Wrapper for `b2Fixture::SetSensor(bool)`

# Arguments
- `this::Ptr{b2Fixture}`
- `arg1::Bool`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN9b2Fixture9SetSensorEb`
"""

function b2Fixture_SetSensor(this::Any, arg1::Bool)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN9b2Fixture9SetSensorEb_thunk", this, arg1)
end
"""
    b2Simplex_Solve2(this::Any) -> Cvoid

Wrapper for `b2Simplex::Solve2()`

# Arguments
- `this::Ptr{b2Simplex}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN9b2Simplex6Solve2Ev`
"""

function b2Simplex_Solve2(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN9b2Simplex6Solve2Ev_thunk", this)
end
"""
    b2Simplex_Solve3(this::Any) -> Cvoid

Wrapper for `b2Simplex::Solve3()`

# Arguments
- `this::Ptr{b2Simplex}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN9b2Simplex6Solve3Ev`
"""

function b2Simplex_Solve3(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN9b2Simplex6Solve3Ev_thunk", this)
end
"""
    b2Simplex_ReadCache(this::Any, arg1::Any, arg2::Any, arg3::Ref{Any}, arg4::Any, arg5::Ref{Any}) -> Cvoid

Wrapper for `b2Simplex::ReadCache(b2SimplexCache const*, b2DistanceProxy const*, b2Transform const&, b2DistanceProxy const*, b2Transform const&)`

# Arguments
- `this::Ptr{b2Simplex}`
- `arg1::Ptr{Cvoid}`
- `arg2::Ptr{Cvoid}`
- `arg3::Ref{Any}`
- `arg4::Ptr{Cvoid}`
- `arg5::Ref{Any}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZN9b2Simplex9ReadCacheEPK14b2SimplexCachePK15b2DistanceProxyRK11b2TransformS5_S8_`
"""

function b2Simplex_ReadCache(this::Any, arg1::Any, arg2::Any, arg3::Ref{Any}, arg4::Any, arg5::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZN9b2Simplex9ReadCacheEPK14b2SimplexCachePK15b2DistanceProxyRK11b2TransformS5_S8__thunk", this, arg1, arg2, arg3, arg4, arg5)
end
"""
    b2EdgeShape_ComputeAABB(this::Any, arg1::Any, arg2::Ref{Any}, arg3::Integer) -> Cvoid

Wrapper for `b2EdgeShape::ComputeAABB(b2AABB*, b2Transform const&, int) const`

# Arguments
- `this::Ptr{b2EdgeShape}`
- `arg1::Ptr{b2AABB}`
- `arg2::Ref{Any}`
- `arg3::Cint`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZNK11b2EdgeShape11ComputeAABBEP6b2AABBRK11b2Transformi`
"""

function b2EdgeShape_ComputeAABB(this::Any, arg1::Any, arg2::Ref{Any}, arg3::Integer)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK11b2EdgeShape11ComputeAABBEP6b2AABBRK11b2Transformi_thunk", this, arg1, arg2, arg3)
end
"""
    b2EdgeShape_ComputeMass(this::Any, arg1::Any, arg2::Cfloat) -> Cvoid

Wrapper for `b2EdgeShape::ComputeMass(b2MassData*, float) const`

# Arguments
- `this::Ptr{b2EdgeShape}`
- `arg1::Ptr{b2MassData}`
- `arg2::Cfloat`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZNK11b2EdgeShape11ComputeMassEP10b2MassDataf`
"""

function b2EdgeShape_ComputeMass(this::Any, arg1::Any, arg2::Cfloat)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK11b2EdgeShape11ComputeMassEP10b2MassDataf_thunk", this, arg1, arg2)
end
"""
    b2EdgeShape_GetChildCount(this::Any) -> Cint

Wrapper for `b2EdgeShape::GetChildCount() const`

# Arguments
- `this::Ptr{b2EdgeShape}`

# Returns
- `Cint`

# Metadata
- Mangled symbol: `_ZNK11b2EdgeShape13GetChildCountEv`
"""

function b2EdgeShape_GetChildCount(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK11b2EdgeShape13GetChildCountEv_thunk", Cint, this)
end
"""
    b2EdgeShape_Clone(this::Any, arg1::Any) -> Ptr{b2Shape}

Wrapper for `b2EdgeShape::Clone(b2BlockAllocator*) const`

# Arguments
- `this::Ptr{b2EdgeShape}`
- `arg1::Ptr{b2BlockAllocator}`

# Returns
- `Ptr{b2Shape}`

# Metadata
- Mangled symbol: `_ZNK11b2EdgeShape5CloneEP16b2BlockAllocator`
"""

function b2EdgeShape_Clone(this::Any, arg1::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK11b2EdgeShape5CloneEP16b2BlockAllocator_thunk", Ptr{b2Shape}, this, arg1)
end
"""
    b2EdgeShape_RayCast(this::Any, arg1::Any, arg2::Ref{Any}, arg3::Ref{Any}, arg4::Integer) -> Bool

Wrapper for `b2EdgeShape::RayCast(b2RayCastOutput*, b2RayCastInput const&, b2Transform const&, int) const`

# Arguments
- `this::Ptr{b2EdgeShape}`
- `arg1::Ptr{b2RayCastOutput}`
- `arg2::Ref{Any}`
- `arg3::Ref{Any}`
- `arg4::Cint`

# Returns
- `Bool`

# Metadata
- Mangled symbol: `_ZNK11b2EdgeShape7RayCastEP15b2RayCastOutputRK14b2RayCastInputRK11b2Transformi`
"""

function b2EdgeShape_RayCast(this::Any, arg1::Any, arg2::Ref{Any}, arg3::Ref{Any}, arg4::Integer)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK11b2EdgeShape7RayCastEP15b2RayCastOutputRK14b2RayCastInputRK11b2Transformi_thunk", Bool, this, arg1, arg2, arg3, arg4)
end
"""
    b2EdgeShape_TestPoint(this::Any, arg1::Ref{Any}, arg2::Ref{Any}) -> Bool

Wrapper for `b2EdgeShape::TestPoint(b2Transform const&, b2Vec2 const&) const`

# Arguments
- `this::Ptr{b2EdgeShape}`
- `arg1::Ref{Any}`
- `arg2::Ref{Any}`

# Returns
- `Bool`

# Metadata
- Mangled symbol: `_ZNK11b2EdgeShape9TestPointERK11b2TransformRK6b2Vec2`
"""

function b2EdgeShape_TestPoint(this::Any, arg1::Ref{Any}, arg2::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK11b2EdgeShape9TestPointERK11b2TransformRK6b2Vec2_thunk", Bool, this, arg1, arg2)
end
"""
    b2GearJoint_GetAnchorA(this::Any) -> b2Vec2

Wrapper for `b2GearJoint::GetAnchorA() const`

# Arguments
- `this::Ptr{b2GearJoint}`

# Returns
- `b2Vec2`

# Metadata
- Mangled symbol: `_ZNK11b2GearJoint10GetAnchorAEv`
"""

function b2GearJoint_GetAnchorA(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK11b2GearJoint10GetAnchorAEv_thunk", b2Vec2, this)
end
"""
    b2GearJoint_GetAnchorB(this::Any) -> b2Vec2

Wrapper for `b2GearJoint::GetAnchorB() const`

# Arguments
- `this::Ptr{b2GearJoint}`

# Returns
- `b2Vec2`

# Metadata
- Mangled symbol: `_ZNK11b2GearJoint10GetAnchorBEv`
"""

function b2GearJoint_GetAnchorB(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK11b2GearJoint10GetAnchorBEv_thunk", b2Vec2, this)
end
"""
    b2GearJoint_GetReactionForce(this::Any, arg1::Cfloat) -> b2Vec2

Wrapper for `b2GearJoint::GetReactionForce(float) const`

# Arguments
- `this::Ptr{b2GearJoint}`
- `arg1::Cfloat`

# Returns
- `b2Vec2`

# Metadata
- Mangled symbol: `_ZNK11b2GearJoint16GetReactionForceEf`
"""

function b2GearJoint_GetReactionForce(this::Any, arg1::Cfloat)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK11b2GearJoint16GetReactionForceEf_thunk", b2Vec2, this, arg1)
end
"""
    b2GearJoint_GetReactionTorque(this::Any, arg1::Cfloat) -> Cfloat

Wrapper for `b2GearJoint::GetReactionTorque(float) const`

# Arguments
- `this::Ptr{b2GearJoint}`
- `arg1::Cfloat`

# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_ZNK11b2GearJoint17GetReactionTorqueEf`
"""

function b2GearJoint_GetReactionTorque(this::Any, arg1::Cfloat)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK11b2GearJoint17GetReactionTorqueEf_thunk", Cfloat, this, arg1)
end
"""
    b2GearJoint_GetRatio(this::Any) -> Cfloat

Wrapper for `b2GearJoint::GetRatio() const`

# Arguments
- `this::Ptr{b2GearJoint}`

# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_ZNK11b2GearJoint8GetRatioEv`
"""

function b2GearJoint_GetRatio(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK11b2GearJoint8GetRatioEv_thunk", Cfloat, this)
end
"""
    b2WeldJoint_GetAnchorA(this::Any) -> b2Vec2

Wrapper for `b2WeldJoint::GetAnchorA() const`

# Arguments
- `this::Ptr{b2WeldJoint}`

# Returns
- `b2Vec2`

# Metadata
- Mangled symbol: `_ZNK11b2WeldJoint10GetAnchorAEv`
"""

function b2WeldJoint_GetAnchorA(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK11b2WeldJoint10GetAnchorAEv_thunk", b2Vec2, this)
end
"""
    b2WeldJoint_GetAnchorB(this::Any) -> b2Vec2

Wrapper for `b2WeldJoint::GetAnchorB() const`

# Arguments
- `this::Ptr{b2WeldJoint}`

# Returns
- `b2Vec2`

# Metadata
- Mangled symbol: `_ZNK11b2WeldJoint10GetAnchorBEv`
"""

function b2WeldJoint_GetAnchorB(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK11b2WeldJoint10GetAnchorBEv_thunk", b2Vec2, this)
end
"""
    b2WeldJoint_GetReactionForce(this::Any, arg1::Cfloat) -> b2Vec2

Wrapper for `b2WeldJoint::GetReactionForce(float) const`

# Arguments
- `this::Ptr{b2WeldJoint}`
- `arg1::Cfloat`

# Returns
- `b2Vec2`

# Metadata
- Mangled symbol: `_ZNK11b2WeldJoint16GetReactionForceEf`
"""

function b2WeldJoint_GetReactionForce(this::Any, arg1::Cfloat)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK11b2WeldJoint16GetReactionForceEf_thunk", b2Vec2, this, arg1)
end
"""
    b2WeldJoint_GetReactionTorque(this::Any, arg1::Cfloat) -> Cfloat

Wrapper for `b2WeldJoint::GetReactionTorque(float) const`

# Arguments
- `this::Ptr{b2WeldJoint}`
- `arg1::Cfloat`

# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_ZNK11b2WeldJoint17GetReactionTorqueEf`
"""

function b2WeldJoint_GetReactionTorque(this::Any, arg1::Cfloat)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK11b2WeldJoint17GetReactionTorqueEf_thunk", Cfloat, this, arg1)
end
"""
    b2ChainShape_ComputeAABB(this::Any, arg1::Any, arg2::Ref{Any}, arg3::Integer) -> Cvoid

Wrapper for `b2ChainShape::ComputeAABB(b2AABB*, b2Transform const&, int) const`

# Arguments
- `this::Ptr{b2ChainShape}`
- `arg1::Ptr{b2AABB}`
- `arg2::Ref{Any}`
- `arg3::Cint`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZNK12b2ChainShape11ComputeAABBEP6b2AABBRK11b2Transformi`
"""

function b2ChainShape_ComputeAABB(this::Any, arg1::Any, arg2::Ref{Any}, arg3::Integer)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK12b2ChainShape11ComputeAABBEP6b2AABBRK11b2Transformi_thunk", this, arg1, arg2, arg3)
end
"""
    b2ChainShape_ComputeMass(this::Any, arg1::Any, arg2::Cfloat) -> Cvoid

Wrapper for `b2ChainShape::ComputeMass(b2MassData*, float) const`

# Arguments
- `this::Ptr{b2ChainShape}`
- `arg1::Ptr{b2MassData}`
- `arg2::Cfloat`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZNK12b2ChainShape11ComputeMassEP10b2MassDataf`
"""

function b2ChainShape_ComputeMass(this::Any, arg1::Any, arg2::Cfloat)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK12b2ChainShape11ComputeMassEP10b2MassDataf_thunk", this, arg1, arg2)
end
"""
    b2ChainShape_GetChildEdge(this::Any, arg1::Any, arg2::Integer) -> Cvoid

Wrapper for `b2ChainShape::GetChildEdge(b2EdgeShape*, int) const`

# Arguments
- `this::Ptr{b2ChainShape}`
- `arg1::Ptr{b2EdgeShape}`
- `arg2::Cint`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZNK12b2ChainShape12GetChildEdgeEP11b2EdgeShapei`
"""

function b2ChainShape_GetChildEdge(this::Any, arg1::Any, arg2::Integer)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK12b2ChainShape12GetChildEdgeEP11b2EdgeShapei_thunk", this, arg1, arg2)
end
"""
    b2ChainShape_GetChildCount(this::Any) -> Cint

Wrapper for `b2ChainShape::GetChildCount() const`

# Arguments
- `this::Ptr{b2ChainShape}`

# Returns
- `Cint`

# Metadata
- Mangled symbol: `_ZNK12b2ChainShape13GetChildCountEv`
"""

function b2ChainShape_GetChildCount(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK12b2ChainShape13GetChildCountEv_thunk", Cint, this)
end
"""
    b2ChainShape_Clone(this::Any, arg1::Any) -> Ptr{b2Shape}

Wrapper for `b2ChainShape::Clone(b2BlockAllocator*) const`

# Arguments
- `this::Ptr{b2ChainShape}`
- `arg1::Ptr{b2BlockAllocator}`

# Returns
- `Ptr{b2Shape}`

# Metadata
- Mangled symbol: `_ZNK12b2ChainShape5CloneEP16b2BlockAllocator`
"""

function b2ChainShape_Clone(this::Any, arg1::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK12b2ChainShape5CloneEP16b2BlockAllocator_thunk", Ptr{b2Shape}, this, arg1)
end
"""
    b2ChainShape_RayCast(this::Any, arg1::Any, arg2::Ref{Any}, arg3::Ref{Any}, arg4::Integer) -> Bool

Wrapper for `b2ChainShape::RayCast(b2RayCastOutput*, b2RayCastInput const&, b2Transform const&, int) const`

# Arguments
- `this::Ptr{b2ChainShape}`
- `arg1::Ptr{b2RayCastOutput}`
- `arg2::Ref{Any}`
- `arg3::Ref{Any}`
- `arg4::Cint`

# Returns
- `Bool`

# Metadata
- Mangled symbol: `_ZNK12b2ChainShape7RayCastEP15b2RayCastOutputRK14b2RayCastInputRK11b2Transformi`
"""

function b2ChainShape_RayCast(this::Any, arg1::Any, arg2::Ref{Any}, arg3::Ref{Any}, arg4::Integer)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK12b2ChainShape7RayCastEP15b2RayCastOutputRK14b2RayCastInputRK11b2Transformi_thunk", Bool, this, arg1, arg2, arg3, arg4)
end
"""
    b2ChainShape_TestPoint(this::Any, arg1::Ref{Any}, arg2::Ref{Any}) -> Bool

Wrapper for `b2ChainShape::TestPoint(b2Transform const&, b2Vec2 const&) const`

# Arguments
- `this::Ptr{b2ChainShape}`
- `arg1::Ref{Any}`
- `arg2::Ref{Any}`

# Returns
- `Bool`

# Metadata
- Mangled symbol: `_ZNK12b2ChainShape9TestPointERK11b2TransformRK6b2Vec2`
"""

function b2ChainShape_TestPoint(this::Any, arg1::Ref{Any}, arg2::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK12b2ChainShape9TestPointERK11b2TransformRK6b2Vec2_thunk", Bool, this, arg1, arg2)
end
"""
    b2MotorJoint_GetAnchorA(this::Any) -> b2Vec2

Wrapper for `b2MotorJoint::GetAnchorA() const`

# Arguments
- `this::Ptr{b2MotorJoint}`

# Returns
- `b2Vec2`

# Metadata
- Mangled symbol: `_ZNK12b2MotorJoint10GetAnchorAEv`
"""

function b2MotorJoint_GetAnchorA(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK12b2MotorJoint10GetAnchorAEv_thunk", b2Vec2, this)
end
"""
    b2MotorJoint_GetAnchorB(this::Any) -> b2Vec2

Wrapper for `b2MotorJoint::GetAnchorB() const`

# Arguments
- `this::Ptr{b2MotorJoint}`

# Returns
- `b2Vec2`

# Metadata
- Mangled symbol: `_ZNK12b2MotorJoint10GetAnchorBEv`
"""

function b2MotorJoint_GetAnchorB(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK12b2MotorJoint10GetAnchorBEv_thunk", b2Vec2, this)
end
"""
    b2MotorJoint_GetMaxForce(this::Any) -> Cfloat

Wrapper for `b2MotorJoint::GetMaxForce() const`

# Arguments
- `this::Ptr{b2MotorJoint}`

# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_ZNK12b2MotorJoint11GetMaxForceEv`
"""

function b2MotorJoint_GetMaxForce(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK12b2MotorJoint11GetMaxForceEv_thunk", Cfloat, this)
end
"""
    b2MotorJoint_GetMaxTorque(this::Any) -> Cfloat

Wrapper for `b2MotorJoint::GetMaxTorque() const`

# Arguments
- `this::Ptr{b2MotorJoint}`

# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_ZNK12b2MotorJoint12GetMaxTorqueEv`
"""

function b2MotorJoint_GetMaxTorque(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK12b2MotorJoint12GetMaxTorqueEv_thunk", Cfloat, this)
end
"""
    b2MotorJoint_GetLinearOffset(this::Any) -> Ref{Cvoid}

Wrapper for `b2MotorJoint::GetLinearOffset() const`

# Arguments
- `this::Ptr{b2MotorJoint}`

# Returns
- `Ref{Cvoid}`

# Metadata
- Mangled symbol: `_ZNK12b2MotorJoint15GetLinearOffsetEv`
"""

function b2MotorJoint_GetLinearOffset(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK12b2MotorJoint15GetLinearOffsetEv_thunk", Ref{Cvoid}, this)
end
"""
    b2MotorJoint_GetAngularOffset(this::Any) -> Cfloat

Wrapper for `b2MotorJoint::GetAngularOffset() const`

# Arguments
- `this::Ptr{b2MotorJoint}`

# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_ZNK12b2MotorJoint16GetAngularOffsetEv`
"""

function b2MotorJoint_GetAngularOffset(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK12b2MotorJoint16GetAngularOffsetEv_thunk", Cfloat, this)
end
"""
    b2MotorJoint_GetReactionForce(this::Any, arg1::Cfloat) -> b2Vec2

Wrapper for `b2MotorJoint::GetReactionForce(float) const`

# Arguments
- `this::Ptr{b2MotorJoint}`
- `arg1::Cfloat`

# Returns
- `b2Vec2`

# Metadata
- Mangled symbol: `_ZNK12b2MotorJoint16GetReactionForceEf`
"""

function b2MotorJoint_GetReactionForce(this::Any, arg1::Cfloat)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK12b2MotorJoint16GetReactionForceEf_thunk", b2Vec2, this, arg1)
end
"""
    b2MotorJoint_GetReactionTorque(this::Any, arg1::Cfloat) -> Cfloat

Wrapper for `b2MotorJoint::GetReactionTorque(float) const`

# Arguments
- `this::Ptr{b2MotorJoint}`
- `arg1::Cfloat`

# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_ZNK12b2MotorJoint17GetReactionTorqueEf`
"""

function b2MotorJoint_GetReactionTorque(this::Any, arg1::Cfloat)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK12b2MotorJoint17GetReactionTorqueEf_thunk", Cfloat, this, arg1)
end
"""
    b2MotorJoint_GetCorrectionFactor(this::Any) -> Cfloat

Wrapper for `b2MotorJoint::GetCorrectionFactor() const`

# Arguments
- `this::Ptr{b2MotorJoint}`

# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_ZNK12b2MotorJoint19GetCorrectionFactorEv`
"""

function b2MotorJoint_GetCorrectionFactor(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK12b2MotorJoint19GetCorrectionFactorEv_thunk", Cfloat, this)
end
"""
    b2MouseJoint_GetAnchorA(this::Any) -> b2Vec2

Wrapper for `b2MouseJoint::GetAnchorA() const`

# Arguments
- `this::Ptr{b2MouseJoint}`

# Returns
- `b2Vec2`

# Metadata
- Mangled symbol: `_ZNK12b2MouseJoint10GetAnchorAEv`
"""

function b2MouseJoint_GetAnchorA(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK12b2MouseJoint10GetAnchorAEv_thunk", b2Vec2, this)
end
"""
    b2MouseJoint_GetAnchorB(this::Any) -> b2Vec2

Wrapper for `b2MouseJoint::GetAnchorB() const`

# Arguments
- `this::Ptr{b2MouseJoint}`

# Returns
- `b2Vec2`

# Metadata
- Mangled symbol: `_ZNK12b2MouseJoint10GetAnchorBEv`
"""

function b2MouseJoint_GetAnchorB(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK12b2MouseJoint10GetAnchorBEv_thunk", b2Vec2, this)
end
"""
    b2MouseJoint_GetMaxForce(this::Any) -> Cfloat

Wrapper for `b2MouseJoint::GetMaxForce() const`

# Arguments
- `this::Ptr{b2MouseJoint}`

# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_ZNK12b2MouseJoint11GetMaxForceEv`
"""

function b2MouseJoint_GetMaxForce(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK12b2MouseJoint11GetMaxForceEv_thunk", Cfloat, this)
end
"""
    b2MouseJoint_GetReactionForce(this::Any, arg1::Cfloat) -> b2Vec2

Wrapper for `b2MouseJoint::GetReactionForce(float) const`

# Arguments
- `this::Ptr{b2MouseJoint}`
- `arg1::Cfloat`

# Returns
- `b2Vec2`

# Metadata
- Mangled symbol: `_ZNK12b2MouseJoint16GetReactionForceEf`
"""

function b2MouseJoint_GetReactionForce(this::Any, arg1::Cfloat)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK12b2MouseJoint16GetReactionForceEf_thunk", b2Vec2, this, arg1)
end
"""
    b2MouseJoint_GetReactionTorque(this::Any, arg1::Cfloat) -> Cfloat

Wrapper for `b2MouseJoint::GetReactionTorque(float) const`

# Arguments
- `this::Ptr{b2MouseJoint}`
- `arg1::Cfloat`

# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_ZNK12b2MouseJoint17GetReactionTorqueEf`
"""

function b2MouseJoint_GetReactionTorque(this::Any, arg1::Cfloat)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK12b2MouseJoint17GetReactionTorqueEf_thunk", Cfloat, this, arg1)
end
"""
    b2MouseJoint_GetTarget(this::Any) -> Ref{Cvoid}

Wrapper for `b2MouseJoint::GetTarget() const`

# Arguments
- `this::Ptr{b2MouseJoint}`

# Returns
- `Ref{Cvoid}`

# Metadata
- Mangled symbol: `_ZNK12b2MouseJoint9GetTargetEv`
"""

function b2MouseJoint_GetTarget(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK12b2MouseJoint9GetTargetEv_thunk", Ref{Cvoid}, this)
end
"""
    b2WheelJoint_GetAnchorA(this::Any) -> b2Vec2

Wrapper for `b2WheelJoint::GetAnchorA() const`

# Arguments
- `this::Ptr{b2WheelJoint}`

# Returns
- `b2Vec2`

# Metadata
- Mangled symbol: `_ZNK12b2WheelJoint10GetAnchorAEv`
"""

function b2WheelJoint_GetAnchorA(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK12b2WheelJoint10GetAnchorAEv_thunk", b2Vec2, this)
end
"""
    b2WheelJoint_GetAnchorB(this::Any) -> b2Vec2

Wrapper for `b2WheelJoint::GetAnchorB() const`

# Arguments
- `this::Ptr{b2WheelJoint}`

# Returns
- `b2Vec2`

# Metadata
- Mangled symbol: `_ZNK12b2WheelJoint10GetAnchorBEv`
"""

function b2WheelJoint_GetAnchorB(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK12b2WheelJoint10GetAnchorBEv_thunk", b2Vec2, this)
end
"""
    b2WheelJoint_GetDamping(this::Any) -> Cfloat

Wrapper for `b2WheelJoint::GetDamping() const`

# Arguments
- `this::Ptr{b2WheelJoint}`

# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_ZNK12b2WheelJoint10GetDampingEv`
"""

function b2WheelJoint_GetDamping(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK12b2WheelJoint10GetDampingEv_thunk", Cfloat, this)
end
"""
    b2WheelJoint_GetStiffness(this::Any) -> Cfloat

Wrapper for `b2WheelJoint::GetStiffness() const`

# Arguments
- `this::Ptr{b2WheelJoint}`

# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_ZNK12b2WheelJoint12GetStiffnessEv`
"""

function b2WheelJoint_GetStiffness(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK12b2WheelJoint12GetStiffnessEv_thunk", Cfloat, this)
end
"""
    b2WheelJoint_GetJointAngle(this::Any) -> Cfloat

Wrapper for `b2WheelJoint::GetJointAngle() const`

# Arguments
- `this::Ptr{b2WheelJoint}`

# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_ZNK12b2WheelJoint13GetJointAngleEv`
"""

function b2WheelJoint_GetJointAngle(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK12b2WheelJoint13GetJointAngleEv_thunk", Cfloat, this)
end
"""
    b2WheelJoint_GetLowerLimit(this::Any) -> Cfloat

Wrapper for `b2WheelJoint::GetLowerLimit() const`

# Arguments
- `this::Ptr{b2WheelJoint}`

# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_ZNK12b2WheelJoint13GetLowerLimitEv`
"""

function b2WheelJoint_GetLowerLimit(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK12b2WheelJoint13GetLowerLimitEv_thunk", Cfloat, this)
end
"""
    b2WheelJoint_GetUpperLimit(this::Any) -> Cfloat

Wrapper for `b2WheelJoint::GetUpperLimit() const`

# Arguments
- `this::Ptr{b2WheelJoint}`

# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_ZNK12b2WheelJoint13GetUpperLimitEv`
"""

function b2WheelJoint_GetUpperLimit(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK12b2WheelJoint13GetUpperLimitEv_thunk", Cfloat, this)
end
"""
    b2WheelJoint_GetMotorTorque(this::Any, arg1::Cfloat) -> Cfloat

Wrapper for `b2WheelJoint::GetMotorTorque(float) const`

# Arguments
- `this::Ptr{b2WheelJoint}`
- `arg1::Cfloat`

# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_ZNK12b2WheelJoint14GetMotorTorqueEf`
"""

function b2WheelJoint_GetMotorTorque(this::Any, arg1::Cfloat)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK12b2WheelJoint14GetMotorTorqueEf_thunk", Cfloat, this, arg1)
end
"""
    b2WheelJoint_IsLimitEnabled(this::Any) -> Bool

Wrapper for `b2WheelJoint::IsLimitEnabled() const`

# Arguments
- `this::Ptr{b2WheelJoint}`

# Returns
- `Bool`

# Metadata
- Mangled symbol: `_ZNK12b2WheelJoint14IsLimitEnabledEv`
"""

function b2WheelJoint_IsLimitEnabled(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK12b2WheelJoint14IsLimitEnabledEv_thunk", Bool, this)
end
"""
    b2WheelJoint_IsMotorEnabled(this::Any) -> Bool

Wrapper for `b2WheelJoint::IsMotorEnabled() const`

# Arguments
- `this::Ptr{b2WheelJoint}`

# Returns
- `Bool`

# Metadata
- Mangled symbol: `_ZNK12b2WheelJoint14IsMotorEnabledEv`
"""

function b2WheelJoint_IsMotorEnabled(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK12b2WheelJoint14IsMotorEnabledEv_thunk", Bool, this)
end
"""
    b2WheelJoint_GetReactionForce(this::Any, arg1::Cfloat) -> b2Vec2

Wrapper for `b2WheelJoint::GetReactionForce(float) const`

# Arguments
- `this::Ptr{b2WheelJoint}`
- `arg1::Cfloat`

# Returns
- `b2Vec2`

# Metadata
- Mangled symbol: `_ZNK12b2WheelJoint16GetReactionForceEf`
"""

function b2WheelJoint_GetReactionForce(this::Any, arg1::Cfloat)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK12b2WheelJoint16GetReactionForceEf_thunk", b2Vec2, this, arg1)
end
"""
    b2WheelJoint_GetReactionTorque(this::Any, arg1::Cfloat) -> Cfloat

Wrapper for `b2WheelJoint::GetReactionTorque(float) const`

# Arguments
- `this::Ptr{b2WheelJoint}`
- `arg1::Cfloat`

# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_ZNK12b2WheelJoint17GetReactionTorqueEf`
"""

function b2WheelJoint_GetReactionTorque(this::Any, arg1::Cfloat)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK12b2WheelJoint17GetReactionTorqueEf_thunk", Cfloat, this, arg1)
end
"""
    b2WheelJoint_GetJointLinearSpeed(this::Any) -> Cfloat

Wrapper for `b2WheelJoint::GetJointLinearSpeed() const`

# Arguments
- `this::Ptr{b2WheelJoint}`

# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_ZNK12b2WheelJoint19GetJointLinearSpeedEv`
"""

function b2WheelJoint_GetJointLinearSpeed(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK12b2WheelJoint19GetJointLinearSpeedEv_thunk", Cfloat, this)
end
"""
    b2WheelJoint_GetJointTranslation(this::Any) -> Cfloat

Wrapper for `b2WheelJoint::GetJointTranslation() const`

# Arguments
- `this::Ptr{b2WheelJoint}`

# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_ZNK12b2WheelJoint19GetJointTranslationEv`
"""

function b2WheelJoint_GetJointTranslation(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK12b2WheelJoint19GetJointTranslationEv_thunk", Cfloat, this)
end
"""
    b2WheelJoint_GetJointAngularSpeed(this::Any) -> Cfloat

Wrapper for `b2WheelJoint::GetJointAngularSpeed() const`

# Arguments
- `this::Ptr{b2WheelJoint}`

# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_ZNK12b2WheelJoint20GetJointAngularSpeedEv`
"""

function b2WheelJoint_GetJointAngularSpeed(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK12b2WheelJoint20GetJointAngularSpeedEv_thunk", Cfloat, this)
end
"""
    b2WheelJoint_Draw(this::Any, arg1::Any) -> Cvoid

Wrapper for `b2WheelJoint::Draw(b2Draw*) const`

# Arguments
- `this::Ptr{b2WheelJoint}`
- `arg1::Ptr{b2Draw}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZNK12b2WheelJoint4DrawEP6b2Draw`
"""

function b2WheelJoint_Draw(this::Any, arg1::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK12b2WheelJoint4DrawEP6b2Draw_thunk", this, arg1)
end
"""
    b2CircleShape_ComputeAABB(this::Any, arg1::Any, arg2::Ref{Any}, arg3::Integer) -> Cvoid

Wrapper for `b2CircleShape::ComputeAABB(b2AABB*, b2Transform const&, int) const`

# Arguments
- `this::Ptr{b2CircleShape}`
- `arg1::Ptr{b2AABB}`
- `arg2::Ref{Any}`
- `arg3::Cint`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZNK13b2CircleShape11ComputeAABBEP6b2AABBRK11b2Transformi`
"""

function b2CircleShape_ComputeAABB(this::Any, arg1::Any, arg2::Ref{Any}, arg3::Integer)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK13b2CircleShape11ComputeAABBEP6b2AABBRK11b2Transformi_thunk", this, arg1, arg2, arg3)
end
"""
    b2CircleShape_ComputeMass(this::Any, arg1::Any, arg2::Cfloat) -> Cvoid

Wrapper for `b2CircleShape::ComputeMass(b2MassData*, float) const`

# Arguments
- `this::Ptr{b2CircleShape}`
- `arg1::Ptr{b2MassData}`
- `arg2::Cfloat`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZNK13b2CircleShape11ComputeMassEP10b2MassDataf`
"""

function b2CircleShape_ComputeMass(this::Any, arg1::Any, arg2::Cfloat)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK13b2CircleShape11ComputeMassEP10b2MassDataf_thunk", this, arg1, arg2)
end
"""
    b2CircleShape_GetChildCount(this::Any) -> Cint

Wrapper for `b2CircleShape::GetChildCount() const`

# Arguments
- `this::Ptr{b2CircleShape}`

# Returns
- `Cint`

# Metadata
- Mangled symbol: `_ZNK13b2CircleShape13GetChildCountEv`
"""

function b2CircleShape_GetChildCount(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK13b2CircleShape13GetChildCountEv_thunk", Cint, this)
end
"""
    b2CircleShape_Clone(this::Any, arg1::Any) -> Ptr{b2Shape}

Wrapper for `b2CircleShape::Clone(b2BlockAllocator*) const`

# Arguments
- `this::Ptr{b2CircleShape}`
- `arg1::Ptr{b2BlockAllocator}`

# Returns
- `Ptr{b2Shape}`

# Metadata
- Mangled symbol: `_ZNK13b2CircleShape5CloneEP16b2BlockAllocator`
"""

function b2CircleShape_Clone(this::Any, arg1::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK13b2CircleShape5CloneEP16b2BlockAllocator_thunk", Ptr{b2Shape}, this, arg1)
end
"""
    b2CircleShape_RayCast(this::Any, arg1::Any, arg2::Ref{Any}, arg3::Ref{Any}, arg4::Integer) -> Bool

Wrapper for `b2CircleShape::RayCast(b2RayCastOutput*, b2RayCastInput const&, b2Transform const&, int) const`

# Arguments
- `this::Ptr{b2CircleShape}`
- `arg1::Ptr{b2RayCastOutput}`
- `arg2::Ref{Any}`
- `arg3::Ref{Any}`
- `arg4::Cint`

# Returns
- `Bool`

# Metadata
- Mangled symbol: `_ZNK13b2CircleShape7RayCastEP15b2RayCastOutputRK14b2RayCastInputRK11b2Transformi`
"""

function b2CircleShape_RayCast(this::Any, arg1::Any, arg2::Ref{Any}, arg3::Ref{Any}, arg4::Integer)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK13b2CircleShape7RayCastEP15b2RayCastOutputRK14b2RayCastInputRK11b2Transformi_thunk", Bool, this, arg1, arg2, arg3, arg4)
end
"""
    b2CircleShape_TestPoint(this::Any, arg1::Ref{Any}, arg2::Ref{Any}) -> Bool

Wrapper for `b2CircleShape::TestPoint(b2Transform const&, b2Vec2 const&) const`

# Arguments
- `this::Ptr{b2CircleShape}`
- `arg1::Ref{Any}`
- `arg2::Ref{Any}`

# Returns
- `Bool`

# Metadata
- Mangled symbol: `_ZNK13b2CircleShape9TestPointERK11b2TransformRK6b2Vec2`
"""

function b2CircleShape_TestPoint(this::Any, arg1::Ref{Any}, arg2::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK13b2CircleShape9TestPointERK11b2TransformRK6b2Vec2_thunk", Bool, this, arg1, arg2)
end
"""
    b2DynamicTree_GetAreaRatio(this::Any) -> Cfloat

Wrapper for `b2DynamicTree::GetAreaRatio() const`

# Arguments
- `this::Ptr{b2DynamicTree}`

# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_ZNK13b2DynamicTree12GetAreaRatioEv`
"""

function b2DynamicTree_GetAreaRatio(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK13b2DynamicTree12GetAreaRatioEv_thunk", Cfloat, this)
end
"""
    b2DynamicTree_ComputeHeight(this::Any, arg1::Integer) -> Cint

Wrapper for `b2DynamicTree::ComputeHeight(int) const`

# Arguments
- `this::Ptr{b2DynamicTree}`
- `arg1::Cint`

# Returns
- `Cint`

# Metadata
- Mangled symbol: `_ZNK13b2DynamicTree13ComputeHeightEi`
"""

function b2DynamicTree_ComputeHeight(this::Any, arg1::Integer)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK13b2DynamicTree13ComputeHeightEi_thunk", Cint, this, arg1)
end
"""
    b2DynamicTree_ComputeHeight(this::Any) -> Cint

Wrapper for `b2DynamicTree::ComputeHeight() const`

# Arguments
- `this::Ptr{b2DynamicTree}`

# Returns
- `Cint`

# Metadata
- Mangled symbol: `_ZNK13b2DynamicTree13ComputeHeightEv`
"""

function b2DynamicTree_ComputeHeight(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK13b2DynamicTree13ComputeHeightEv_thunk", Cint, this)
end
"""
    b2DynamicTree_GetMaxBalance(this::Any) -> Cint

Wrapper for `b2DynamicTree::GetMaxBalance() const`

# Arguments
- `this::Ptr{b2DynamicTree}`

# Returns
- `Cint`

# Metadata
- Mangled symbol: `_ZNK13b2DynamicTree13GetMaxBalanceEv`
"""

function b2DynamicTree_GetMaxBalance(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK13b2DynamicTree13GetMaxBalanceEv_thunk", Cint, this)
end
"""
    b2DynamicTree_ValidateMetrics(this::Any, arg1::Integer) -> Cvoid

Wrapper for `b2DynamicTree::ValidateMetrics(int) const`

# Arguments
- `this::Ptr{b2DynamicTree}`
- `arg1::Cint`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZNK13b2DynamicTree15ValidateMetricsEi`
"""

function b2DynamicTree_ValidateMetrics(this::Any, arg1::Integer)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK13b2DynamicTree15ValidateMetricsEi_thunk", this, arg1)
end
"""
    b2DynamicTree_ValidateStructure(this::Any, arg1::Integer) -> Cvoid

Wrapper for `b2DynamicTree::ValidateStructure(int) const`

# Arguments
- `this::Ptr{b2DynamicTree}`
- `arg1::Cint`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZNK13b2DynamicTree17ValidateStructureEi`
"""

function b2DynamicTree_ValidateStructure(this::Any, arg1::Integer)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK13b2DynamicTree17ValidateStructureEi_thunk", this, arg1)
end
"""
    void_b2DynamicTree_Query_b2BroadPhase(arg1::Any, arg2::Ref{Any}) -> Cvoid

Wrapper for `void b2DynamicTree::Query<b2BroadPhase>(b2BroadPhase*, b2AABB const&) const`

# Arguments
- `arg1::Ptr{b2BroadPhase}`
- `arg2::Ref{Any}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZNK13b2DynamicTree5QueryI12b2BroadPhaseEEvPT_RK6b2AABB`
"""

function void_b2DynamicTree_Query_b2BroadPhase(arg1::Any, arg2::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK13b2DynamicTree5QueryI12b2BroadPhaseEEvPT_RK6b2AABB_thunk", arg1, arg2)
end
"""
    void_b2DynamicTree_Query_b2WorldQueryWrapper(arg1::Any, arg2::Ref{Any}) -> Cvoid

Wrapper for `void b2DynamicTree::Query<b2WorldQueryWrapper>(b2WorldQueryWrapper*, b2AABB const&) const`

# Arguments
- `arg1::Ptr{b2WorldQueryWrapper}`
- `arg2::Ref{Any}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZNK13b2DynamicTree5QueryI19b2WorldQueryWrapperEEvPT_RK6b2AABB`
"""

function void_b2DynamicTree_Query_b2WorldQueryWrapper(arg1::Any, arg2::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK13b2DynamicTree5QueryI19b2WorldQueryWrapperEEvPT_RK6b2AABB_thunk", arg1, arg2)
end
"""
    void_b2DynamicTree_RayCast_b2WorldRayCastWrapper(parent::Integer) -> Cvoid

Wrapper for `void b2DynamicTree::RayCast<b2WorldRayCastWrapper>(b2WorldRayCastWrapper*, b2RayCastInput const&) const`

# Arguments
- `parent::Cint`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZNK13b2DynamicTree7RayCastI21b2WorldRayCastWrapperEEvPT_RK14b2RayCastInput`
"""

function void_b2DynamicTree_RayCast_b2WorldRayCastWrapper(parent::Integer)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK13b2DynamicTree7RayCastI21b2WorldRayCastWrapperEEvPT_RK14b2RayCastInput_thunk", parent)
end
"""
    b2DynamicTree_Validate(this::Any) -> Cvoid

Wrapper for `b2DynamicTree::Validate() const`

# Arguments
- `this::Ptr{b2DynamicTree}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZNK13b2DynamicTree8ValidateEv`
"""

function b2DynamicTree_Validate(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK13b2DynamicTree8ValidateEv_thunk", this)
end
"""
    b2DynamicTree_GetHeight(this::Any) -> Cint

Wrapper for `b2DynamicTree::GetHeight() const`

# Arguments
- `this::Ptr{b2DynamicTree}`

# Returns
- `Cint`

# Metadata
- Mangled symbol: `_ZNK13b2DynamicTree9GetHeightEv`
"""

function b2DynamicTree_GetHeight(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK13b2DynamicTree9GetHeightEv_thunk", Cint, this)
end
"""
    b2PulleyJoint_GetAnchorA(this::Any) -> b2Vec2

Wrapper for `b2PulleyJoint::GetAnchorA() const`

# Arguments
- `this::Ptr{b2PulleyJoint}`

# Returns
- `b2Vec2`

# Metadata
- Mangled symbol: `_ZNK13b2PulleyJoint10GetAnchorAEv`
"""

function b2PulleyJoint_GetAnchorA(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK13b2PulleyJoint10GetAnchorAEv_thunk", b2Vec2, this)
end
"""
    b2PulleyJoint_GetAnchorB(this::Any) -> b2Vec2

Wrapper for `b2PulleyJoint::GetAnchorB() const`

# Arguments
- `this::Ptr{b2PulleyJoint}`

# Returns
- `b2Vec2`

# Metadata
- Mangled symbol: `_ZNK13b2PulleyJoint10GetAnchorBEv`
"""

function b2PulleyJoint_GetAnchorB(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK13b2PulleyJoint10GetAnchorBEv_thunk", b2Vec2, this)
end
"""
    b2PulleyJoint_GetLengthA(this::Any) -> Cfloat

Wrapper for `b2PulleyJoint::GetLengthA() const`

# Arguments
- `this::Ptr{b2PulleyJoint}`

# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_ZNK13b2PulleyJoint10GetLengthAEv`
"""

function b2PulleyJoint_GetLengthA(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK13b2PulleyJoint10GetLengthAEv_thunk", Cfloat, this)
end
"""
    b2PulleyJoint_GetLengthB(this::Any) -> Cfloat

Wrapper for `b2PulleyJoint::GetLengthB() const`

# Arguments
- `this::Ptr{b2PulleyJoint}`

# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_ZNK13b2PulleyJoint10GetLengthBEv`
"""

function b2PulleyJoint_GetLengthB(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK13b2PulleyJoint10GetLengthBEv_thunk", Cfloat, this)
end
"""
    b2PulleyJoint_GetGroundAnchorA(this::Any) -> b2Vec2

Wrapper for `b2PulleyJoint::GetGroundAnchorA() const`

# Arguments
- `this::Ptr{b2PulleyJoint}`

# Returns
- `b2Vec2`

# Metadata
- Mangled symbol: `_ZNK13b2PulleyJoint16GetGroundAnchorAEv`
"""

function b2PulleyJoint_GetGroundAnchorA(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK13b2PulleyJoint16GetGroundAnchorAEv_thunk", b2Vec2, this)
end
"""
    b2PulleyJoint_GetGroundAnchorB(this::Any) -> b2Vec2

Wrapper for `b2PulleyJoint::GetGroundAnchorB() const`

# Arguments
- `this::Ptr{b2PulleyJoint}`

# Returns
- `b2Vec2`

# Metadata
- Mangled symbol: `_ZNK13b2PulleyJoint16GetGroundAnchorBEv`
"""

function b2PulleyJoint_GetGroundAnchorB(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK13b2PulleyJoint16GetGroundAnchorBEv_thunk", b2Vec2, this)
end
"""
    b2PulleyJoint_GetReactionForce(this::Any, arg1::Cfloat) -> b2Vec2

Wrapper for `b2PulleyJoint::GetReactionForce(float) const`

# Arguments
- `this::Ptr{b2PulleyJoint}`
- `arg1::Cfloat`

# Returns
- `b2Vec2`

# Metadata
- Mangled symbol: `_ZNK13b2PulleyJoint16GetReactionForceEf`
"""

function b2PulleyJoint_GetReactionForce(this::Any, arg1::Cfloat)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK13b2PulleyJoint16GetReactionForceEf_thunk", b2Vec2, this, arg1)
end
"""
    b2PulleyJoint_GetCurrentLengthA(this::Any) -> Cfloat

Wrapper for `b2PulleyJoint::GetCurrentLengthA() const`

# Arguments
- `this::Ptr{b2PulleyJoint}`

# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_ZNK13b2PulleyJoint17GetCurrentLengthAEv`
"""

function b2PulleyJoint_GetCurrentLengthA(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK13b2PulleyJoint17GetCurrentLengthAEv_thunk", Cfloat, this)
end
"""
    b2PulleyJoint_GetCurrentLengthB(this::Any) -> Cfloat

Wrapper for `b2PulleyJoint::GetCurrentLengthB() const`

# Arguments
- `this::Ptr{b2PulleyJoint}`

# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_ZNK13b2PulleyJoint17GetCurrentLengthBEv`
"""

function b2PulleyJoint_GetCurrentLengthB(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK13b2PulleyJoint17GetCurrentLengthBEv_thunk", Cfloat, this)
end
"""
    b2PulleyJoint_GetReactionTorque(this::Any, arg1::Cfloat) -> Cfloat

Wrapper for `b2PulleyJoint::GetReactionTorque(float) const`

# Arguments
- `this::Ptr{b2PulleyJoint}`
- `arg1::Cfloat`

# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_ZNK13b2PulleyJoint17GetReactionTorqueEf`
"""

function b2PulleyJoint_GetReactionTorque(this::Any, arg1::Cfloat)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK13b2PulleyJoint17GetReactionTorqueEf_thunk", Cfloat, this, arg1)
end
"""
    b2PulleyJoint_GetRatio(this::Any) -> Cfloat

Wrapper for `b2PulleyJoint::GetRatio() const`

# Arguments
- `this::Ptr{b2PulleyJoint}`

# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_ZNK13b2PulleyJoint8GetRatioEv`
"""

function b2PulleyJoint_GetRatio(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK13b2PulleyJoint8GetRatioEv_thunk", Cfloat, this)
end
"""
    b2PolygonShape_ComputeAABB(this::Any, arg1::Any, arg2::Ref{Any}, arg3::Integer) -> Cvoid

Wrapper for `b2PolygonShape::ComputeAABB(b2AABB*, b2Transform const&, int) const`

# Arguments
- `this::Ptr{b2PolygonShape}`
- `arg1::Ptr{b2AABB}`
- `arg2::Ref{Any}`
- `arg3::Cint`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZNK14b2PolygonShape11ComputeAABBEP6b2AABBRK11b2Transformi`
"""

function b2PolygonShape_ComputeAABB(this::Any, arg1::Any, arg2::Ref{Any}, arg3::Integer)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK14b2PolygonShape11ComputeAABBEP6b2AABBRK11b2Transformi_thunk", this, arg1, arg2, arg3)
end
"""
    b2PolygonShape_ComputeMass(this::Any, arg1::Any, arg2::Cfloat) -> Cvoid

Wrapper for `b2PolygonShape::ComputeMass(b2MassData*, float) const`

# Arguments
- `this::Ptr{b2PolygonShape}`
- `arg1::Ptr{b2MassData}`
- `arg2::Cfloat`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZNK14b2PolygonShape11ComputeMassEP10b2MassDataf`
"""

function b2PolygonShape_ComputeMass(this::Any, arg1::Any, arg2::Cfloat)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK14b2PolygonShape11ComputeMassEP10b2MassDataf_thunk", this, arg1, arg2)
end
"""
    b2PolygonShape_GetChildCount(this::Any) -> Cint

Wrapper for `b2PolygonShape::GetChildCount() const`

# Arguments
- `this::Ptr{b2PolygonShape}`

# Returns
- `Cint`

# Metadata
- Mangled symbol: `_ZNK14b2PolygonShape13GetChildCountEv`
"""

function b2PolygonShape_GetChildCount(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK14b2PolygonShape13GetChildCountEv_thunk", Cint, this)
end
"""
    b2PolygonShape_Clone(this::Any, arg1::Any) -> Ptr{b2Shape}

Wrapper for `b2PolygonShape::Clone(b2BlockAllocator*) const`

# Arguments
- `this::Ptr{b2PolygonShape}`
- `arg1::Ptr{b2BlockAllocator}`

# Returns
- `Ptr{b2Shape}`

# Metadata
- Mangled symbol: `_ZNK14b2PolygonShape5CloneEP16b2BlockAllocator`
"""

function b2PolygonShape_Clone(this::Any, arg1::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK14b2PolygonShape5CloneEP16b2BlockAllocator_thunk", Ptr{b2Shape}, this, arg1)
end
"""
    b2PolygonShape_RayCast(this::Any, arg1::Any, arg2::Ref{Any}, arg3::Ref{Any}, arg4::Integer) -> Bool

Wrapper for `b2PolygonShape::RayCast(b2RayCastOutput*, b2RayCastInput const&, b2Transform const&, int) const`

# Arguments
- `this::Ptr{b2PolygonShape}`
- `arg1::Ptr{b2RayCastOutput}`
- `arg2::Ref{Any}`
- `arg3::Ref{Any}`
- `arg4::Cint`

# Returns
- `Bool`

# Metadata
- Mangled symbol: `_ZNK14b2PolygonShape7RayCastEP15b2RayCastOutputRK14b2RayCastInputRK11b2Transformi`
"""

function b2PolygonShape_RayCast(this::Any, arg1::Any, arg2::Ref{Any}, arg3::Ref{Any}, arg4::Integer)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK14b2PolygonShape7RayCastEP15b2RayCastOutputRK14b2RayCastInputRK11b2Transformi_thunk", Bool, this, arg1, arg2, arg3, arg4)
end
"""
    b2PolygonShape_Validate(this::Any) -> Bool

Wrapper for `b2PolygonShape::Validate() const`

# Arguments
- `this::Ptr{b2PolygonShape}`

# Returns
- `Bool`

# Metadata
- Mangled symbol: `_ZNK14b2PolygonShape8ValidateEv`
"""

function b2PolygonShape_Validate(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK14b2PolygonShape8ValidateEv_thunk", Bool, this)
end
"""
    b2PolygonShape_TestPoint(this::Any, arg1::Ref{Any}, arg2::Ref{Any}) -> Bool

Wrapper for `b2PolygonShape::TestPoint(b2Transform const&, b2Vec2 const&) const`

# Arguments
- `this::Ptr{b2PolygonShape}`
- `arg1::Ref{Any}`
- `arg2::Ref{Any}`

# Returns
- `Bool`

# Metadata
- Mangled symbol: `_ZNK14b2PolygonShape9TestPointERK11b2TransformRK6b2Vec2`
"""

function b2PolygonShape_TestPoint(this::Any, arg1::Ref{Any}, arg2::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK14b2PolygonShape9TestPointERK11b2TransformRK6b2Vec2_thunk", Bool, this, arg1, arg2)
end
"""
    b2DistanceJoint_GetAnchorA(this::Any) -> b2Vec2

Wrapper for `b2DistanceJoint::GetAnchorA() const`

# Arguments
- `this::Ptr{b2DistanceJoint}`

# Returns
- `b2Vec2`

# Metadata
- Mangled symbol: `_ZNK15b2DistanceJoint10GetAnchorAEv`
"""

function b2DistanceJoint_GetAnchorA(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK15b2DistanceJoint10GetAnchorAEv_thunk", b2Vec2, this)
end
"""
    b2DistanceJoint_GetAnchorB(this::Any) -> b2Vec2

Wrapper for `b2DistanceJoint::GetAnchorB() const`

# Arguments
- `this::Ptr{b2DistanceJoint}`

# Returns
- `b2Vec2`

# Metadata
- Mangled symbol: `_ZNK15b2DistanceJoint10GetAnchorBEv`
"""

function b2DistanceJoint_GetAnchorB(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK15b2DistanceJoint10GetAnchorBEv_thunk", b2Vec2, this)
end
"""
    b2DistanceJoint_GetCurrentLength(this::Any) -> Cfloat

Wrapper for `b2DistanceJoint::GetCurrentLength() const`

# Arguments
- `this::Ptr{b2DistanceJoint}`

# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_ZNK15b2DistanceJoint16GetCurrentLengthEv`
"""

function b2DistanceJoint_GetCurrentLength(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK15b2DistanceJoint16GetCurrentLengthEv_thunk", Cfloat, this)
end
"""
    b2DistanceJoint_GetReactionForce(this::Any, arg1::Cfloat) -> b2Vec2

Wrapper for `b2DistanceJoint::GetReactionForce(float) const`

# Arguments
- `this::Ptr{b2DistanceJoint}`
- `arg1::Cfloat`

# Returns
- `b2Vec2`

# Metadata
- Mangled symbol: `_ZNK15b2DistanceJoint16GetReactionForceEf`
"""

function b2DistanceJoint_GetReactionForce(this::Any, arg1::Cfloat)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK15b2DistanceJoint16GetReactionForceEf_thunk", b2Vec2, this, arg1)
end
"""
    b2DistanceJoint_GetReactionTorque(this::Any, arg1::Cfloat) -> Cfloat

Wrapper for `b2DistanceJoint::GetReactionTorque(float) const`

# Arguments
- `this::Ptr{b2DistanceJoint}`
- `arg1::Cfloat`

# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_ZNK15b2DistanceJoint17GetReactionTorqueEf`
"""

function b2DistanceJoint_GetReactionTorque(this::Any, arg1::Cfloat)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK15b2DistanceJoint17GetReactionTorqueEf_thunk", Cfloat, this, arg1)
end
"""
    b2DistanceJoint_Draw(this::Any, arg1::Any) -> Cvoid

Wrapper for `b2DistanceJoint::Draw(b2Draw*) const`

# Arguments
- `this::Ptr{b2DistanceJoint}`
- `arg1::Ptr{b2Draw}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZNK15b2DistanceJoint4DrawEP6b2Draw`
"""

function b2DistanceJoint_Draw(this::Any, arg1::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK15b2DistanceJoint4DrawEP6b2Draw_thunk", this, arg1)
end
"""
    b2FrictionJoint_GetAnchorA(this::Any) -> b2Vec2

Wrapper for `b2FrictionJoint::GetAnchorA() const`

# Arguments
- `this::Ptr{b2FrictionJoint}`

# Returns
- `b2Vec2`

# Metadata
- Mangled symbol: `_ZNK15b2FrictionJoint10GetAnchorAEv`
"""

function b2FrictionJoint_GetAnchorA(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK15b2FrictionJoint10GetAnchorAEv_thunk", b2Vec2, this)
end
"""
    b2FrictionJoint_GetAnchorB(this::Any) -> b2Vec2

Wrapper for `b2FrictionJoint::GetAnchorB() const`

# Arguments
- `this::Ptr{b2FrictionJoint}`

# Returns
- `b2Vec2`

# Metadata
- Mangled symbol: `_ZNK15b2FrictionJoint10GetAnchorBEv`
"""

function b2FrictionJoint_GetAnchorB(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK15b2FrictionJoint10GetAnchorBEv_thunk", b2Vec2, this)
end
"""
    b2FrictionJoint_GetMaxForce(this::Any) -> Cfloat

Wrapper for `b2FrictionJoint::GetMaxForce() const`

# Arguments
- `this::Ptr{b2FrictionJoint}`

# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_ZNK15b2FrictionJoint11GetMaxForceEv`
"""

function b2FrictionJoint_GetMaxForce(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK15b2FrictionJoint11GetMaxForceEv_thunk", Cfloat, this)
end
"""
    b2FrictionJoint_GetMaxTorque(this::Any) -> Cfloat

Wrapper for `b2FrictionJoint::GetMaxTorque() const`

# Arguments
- `this::Ptr{b2FrictionJoint}`

# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_ZNK15b2FrictionJoint12GetMaxTorqueEv`
"""

function b2FrictionJoint_GetMaxTorque(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK15b2FrictionJoint12GetMaxTorqueEv_thunk", Cfloat, this)
end
"""
    b2FrictionJoint_GetReactionForce(this::Any, arg1::Cfloat) -> b2Vec2

Wrapper for `b2FrictionJoint::GetReactionForce(float) const`

# Arguments
- `this::Ptr{b2FrictionJoint}`
- `arg1::Cfloat`

# Returns
- `b2Vec2`

# Metadata
- Mangled symbol: `_ZNK15b2FrictionJoint16GetReactionForceEf`
"""

function b2FrictionJoint_GetReactionForce(this::Any, arg1::Cfloat)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK15b2FrictionJoint16GetReactionForceEf_thunk", b2Vec2, this, arg1)
end
"""
    b2FrictionJoint_GetReactionTorque(this::Any, arg1::Cfloat) -> Cfloat

Wrapper for `b2FrictionJoint::GetReactionTorque(float) const`

# Arguments
- `this::Ptr{b2FrictionJoint}`
- `arg1::Cfloat`

# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_ZNK15b2FrictionJoint17GetReactionTorqueEf`
"""

function b2FrictionJoint_GetReactionTorque(this::Any, arg1::Cfloat)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK15b2FrictionJoint17GetReactionTorqueEf_thunk", Cfloat, this, arg1)
end
"""
    b2RevoluteJoint_GetAnchorA(this::Any) -> b2Vec2

Wrapper for `b2RevoluteJoint::GetAnchorA() const`

# Arguments
- `this::Ptr{b2RevoluteJoint}`

# Returns
- `b2Vec2`

# Metadata
- Mangled symbol: `_ZNK15b2RevoluteJoint10GetAnchorAEv`
"""

function b2RevoluteJoint_GetAnchorA(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK15b2RevoluteJoint10GetAnchorAEv_thunk", b2Vec2, this)
end
"""
    b2RevoluteJoint_GetAnchorB(this::Any) -> b2Vec2

Wrapper for `b2RevoluteJoint::GetAnchorB() const`

# Arguments
- `this::Ptr{b2RevoluteJoint}`

# Returns
- `b2Vec2`

# Metadata
- Mangled symbol: `_ZNK15b2RevoluteJoint10GetAnchorBEv`
"""

function b2RevoluteJoint_GetAnchorB(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK15b2RevoluteJoint10GetAnchorBEv_thunk", b2Vec2, this)
end
"""
    b2RevoluteJoint_GetJointAngle(this::Any) -> Cfloat

Wrapper for `b2RevoluteJoint::GetJointAngle() const`

# Arguments
- `this::Ptr{b2RevoluteJoint}`

# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_ZNK15b2RevoluteJoint13GetJointAngleEv`
"""

function b2RevoluteJoint_GetJointAngle(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK15b2RevoluteJoint13GetJointAngleEv_thunk", Cfloat, this)
end
"""
    b2RevoluteJoint_GetJointSpeed(this::Any) -> Cfloat

Wrapper for `b2RevoluteJoint::GetJointSpeed() const`

# Arguments
- `this::Ptr{b2RevoluteJoint}`

# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_ZNK15b2RevoluteJoint13GetJointSpeedEv`
"""

function b2RevoluteJoint_GetJointSpeed(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK15b2RevoluteJoint13GetJointSpeedEv_thunk", Cfloat, this)
end
"""
    b2RevoluteJoint_GetLowerLimit(this::Any) -> Cfloat

Wrapper for `b2RevoluteJoint::GetLowerLimit() const`

# Arguments
- `this::Ptr{b2RevoluteJoint}`

# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_ZNK15b2RevoluteJoint13GetLowerLimitEv`
"""

function b2RevoluteJoint_GetLowerLimit(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK15b2RevoluteJoint13GetLowerLimitEv_thunk", Cfloat, this)
end
"""
    b2RevoluteJoint_GetUpperLimit(this::Any) -> Cfloat

Wrapper for `b2RevoluteJoint::GetUpperLimit() const`

# Arguments
- `this::Ptr{b2RevoluteJoint}`

# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_ZNK15b2RevoluteJoint13GetUpperLimitEv`
"""

function b2RevoluteJoint_GetUpperLimit(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK15b2RevoluteJoint13GetUpperLimitEv_thunk", Cfloat, this)
end
"""
    b2RevoluteJoint_GetMotorTorque(this::Any, arg1::Cfloat) -> Cfloat

Wrapper for `b2RevoluteJoint::GetMotorTorque(float) const`

# Arguments
- `this::Ptr{b2RevoluteJoint}`
- `arg1::Cfloat`

# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_ZNK15b2RevoluteJoint14GetMotorTorqueEf`
"""

function b2RevoluteJoint_GetMotorTorque(this::Any, arg1::Cfloat)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK15b2RevoluteJoint14GetMotorTorqueEf_thunk", Cfloat, this, arg1)
end
"""
    b2RevoluteJoint_IsLimitEnabled(this::Any) -> Bool

Wrapper for `b2RevoluteJoint::IsLimitEnabled() const`

# Arguments
- `this::Ptr{b2RevoluteJoint}`

# Returns
- `Bool`

# Metadata
- Mangled symbol: `_ZNK15b2RevoluteJoint14IsLimitEnabledEv`
"""

function b2RevoluteJoint_IsLimitEnabled(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK15b2RevoluteJoint14IsLimitEnabledEv_thunk", Bool, this)
end
"""
    b2RevoluteJoint_IsMotorEnabled(this::Any) -> Bool

Wrapper for `b2RevoluteJoint::IsMotorEnabled() const`

# Arguments
- `this::Ptr{b2RevoluteJoint}`

# Returns
- `Bool`

# Metadata
- Mangled symbol: `_ZNK15b2RevoluteJoint14IsMotorEnabledEv`
"""

function b2RevoluteJoint_IsMotorEnabled(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK15b2RevoluteJoint14IsMotorEnabledEv_thunk", Bool, this)
end
"""
    b2RevoluteJoint_GetReactionForce(this::Any, arg1::Cfloat) -> b2Vec2

Wrapper for `b2RevoluteJoint::GetReactionForce(float) const`

# Arguments
- `this::Ptr{b2RevoluteJoint}`
- `arg1::Cfloat`

# Returns
- `b2Vec2`

# Metadata
- Mangled symbol: `_ZNK15b2RevoluteJoint16GetReactionForceEf`
"""

function b2RevoluteJoint_GetReactionForce(this::Any, arg1::Cfloat)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK15b2RevoluteJoint16GetReactionForceEf_thunk", b2Vec2, this, arg1)
end
"""
    b2RevoluteJoint_GetReactionTorque(this::Any, arg1::Cfloat) -> Cfloat

Wrapper for `b2RevoluteJoint::GetReactionTorque(float) const`

# Arguments
- `this::Ptr{b2RevoluteJoint}`
- `arg1::Cfloat`

# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_ZNK15b2RevoluteJoint17GetReactionTorqueEf`
"""

function b2RevoluteJoint_GetReactionTorque(this::Any, arg1::Cfloat)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK15b2RevoluteJoint17GetReactionTorqueEf_thunk", Cfloat, this, arg1)
end
"""
    b2RevoluteJoint_Draw(this::Any, arg1::Any) -> Cvoid

Wrapper for `b2RevoluteJoint::Draw(b2Draw*) const`

# Arguments
- `this::Ptr{b2RevoluteJoint}`
- `arg1::Ptr{b2Draw}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZNK15b2RevoluteJoint4DrawEP6b2Draw`
"""

function b2RevoluteJoint_Draw(this::Any, arg1::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK15b2RevoluteJoint4DrawEP6b2Draw_thunk", this, arg1)
end
"""
    b2PrismaticJoint_GetAnchorA(this::Any) -> b2Vec2

Wrapper for `b2PrismaticJoint::GetAnchorA() const`

# Arguments
- `this::Ptr{b2PrismaticJoint}`

# Returns
- `b2Vec2`

# Metadata
- Mangled symbol: `_ZNK16b2PrismaticJoint10GetAnchorAEv`
"""

function b2PrismaticJoint_GetAnchorA(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK16b2PrismaticJoint10GetAnchorAEv_thunk", b2Vec2, this)
end
"""
    b2PrismaticJoint_GetAnchorB(this::Any) -> b2Vec2

Wrapper for `b2PrismaticJoint::GetAnchorB() const`

# Arguments
- `this::Ptr{b2PrismaticJoint}`

# Returns
- `b2Vec2`

# Metadata
- Mangled symbol: `_ZNK16b2PrismaticJoint10GetAnchorBEv`
"""

function b2PrismaticJoint_GetAnchorB(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK16b2PrismaticJoint10GetAnchorBEv_thunk", b2Vec2, this)
end
"""
    b2PrismaticJoint_GetJointSpeed(this::Any) -> Cfloat

Wrapper for `b2PrismaticJoint::GetJointSpeed() const`

# Arguments
- `this::Ptr{b2PrismaticJoint}`

# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_ZNK16b2PrismaticJoint13GetJointSpeedEv`
"""

function b2PrismaticJoint_GetJointSpeed(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK16b2PrismaticJoint13GetJointSpeedEv_thunk", Cfloat, this)
end
"""
    b2PrismaticJoint_GetLowerLimit(this::Any) -> Cfloat

Wrapper for `b2PrismaticJoint::GetLowerLimit() const`

# Arguments
- `this::Ptr{b2PrismaticJoint}`

# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_ZNK16b2PrismaticJoint13GetLowerLimitEv`
"""

function b2PrismaticJoint_GetLowerLimit(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK16b2PrismaticJoint13GetLowerLimitEv_thunk", Cfloat, this)
end
"""
    b2PrismaticJoint_GetMotorForce(this::Any, arg1::Cfloat) -> Cfloat

Wrapper for `b2PrismaticJoint::GetMotorForce(float) const`

# Arguments
- `this::Ptr{b2PrismaticJoint}`
- `arg1::Cfloat`

# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_ZNK16b2PrismaticJoint13GetMotorForceEf`
"""

function b2PrismaticJoint_GetMotorForce(this::Any, arg1::Cfloat)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK16b2PrismaticJoint13GetMotorForceEf_thunk", Cfloat, this, arg1)
end
"""
    b2PrismaticJoint_GetUpperLimit(this::Any) -> Cfloat

Wrapper for `b2PrismaticJoint::GetUpperLimit() const`

# Arguments
- `this::Ptr{b2PrismaticJoint}`

# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_ZNK16b2PrismaticJoint13GetUpperLimitEv`
"""

function b2PrismaticJoint_GetUpperLimit(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK16b2PrismaticJoint13GetUpperLimitEv_thunk", Cfloat, this)
end
"""
    b2PrismaticJoint_IsLimitEnabled(this::Any) -> Bool

Wrapper for `b2PrismaticJoint::IsLimitEnabled() const`

# Arguments
- `this::Ptr{b2PrismaticJoint}`

# Returns
- `Bool`

# Metadata
- Mangled symbol: `_ZNK16b2PrismaticJoint14IsLimitEnabledEv`
"""

function b2PrismaticJoint_IsLimitEnabled(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK16b2PrismaticJoint14IsLimitEnabledEv_thunk", Bool, this)
end
"""
    b2PrismaticJoint_IsMotorEnabled(this::Any) -> Bool

Wrapper for `b2PrismaticJoint::IsMotorEnabled() const`

# Arguments
- `this::Ptr{b2PrismaticJoint}`

# Returns
- `Bool`

# Metadata
- Mangled symbol: `_ZNK16b2PrismaticJoint14IsMotorEnabledEv`
"""

function b2PrismaticJoint_IsMotorEnabled(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK16b2PrismaticJoint14IsMotorEnabledEv_thunk", Bool, this)
end
"""
    b2PrismaticJoint_GetReactionForce(this::Any, arg1::Cfloat) -> b2Vec2

Wrapper for `b2PrismaticJoint::GetReactionForce(float) const`

# Arguments
- `this::Ptr{b2PrismaticJoint}`
- `arg1::Cfloat`

# Returns
- `b2Vec2`

# Metadata
- Mangled symbol: `_ZNK16b2PrismaticJoint16GetReactionForceEf`
"""

function b2PrismaticJoint_GetReactionForce(this::Any, arg1::Cfloat)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK16b2PrismaticJoint16GetReactionForceEf_thunk", b2Vec2, this, arg1)
end
"""
    b2PrismaticJoint_GetReactionTorque(this::Any, arg1::Cfloat) -> Cfloat

Wrapper for `b2PrismaticJoint::GetReactionTorque(float) const`

# Arguments
- `this::Ptr{b2PrismaticJoint}`
- `arg1::Cfloat`

# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_ZNK16b2PrismaticJoint17GetReactionTorqueEf`
"""

function b2PrismaticJoint_GetReactionTorque(this::Any, arg1::Cfloat)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK16b2PrismaticJoint17GetReactionTorqueEf_thunk", Cfloat, this, arg1)
end
"""
    b2PrismaticJoint_GetJointTranslation(this::Any) -> Cfloat

Wrapper for `b2PrismaticJoint::GetJointTranslation() const`

# Arguments
- `this::Ptr{b2PrismaticJoint}`

# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_ZNK16b2PrismaticJoint19GetJointTranslationEv`
"""

function b2PrismaticJoint_GetJointTranslation(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK16b2PrismaticJoint19GetJointTranslationEv_thunk", Cfloat, this)
end
"""
    b2PrismaticJoint_Draw(this::Any, arg1::Any) -> Cvoid

Wrapper for `b2PrismaticJoint::Draw(b2Draw*) const`

# Arguments
- `this::Ptr{b2PrismaticJoint}`
- `arg1::Ptr{b2Draw}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZNK16b2PrismaticJoint4DrawEP6b2Draw`
"""

function b2PrismaticJoint_Draw(this::Any, arg1::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK16b2PrismaticJoint4DrawEP6b2Draw_thunk", this, arg1)
end
"""
    b2StackAllocator_GetMaxAllocation(this::Any) -> Cint

Wrapper for `b2StackAllocator::GetMaxAllocation() const`

# Arguments
- `this::Ptr{b2StackAllocator}`

# Returns
- `Cint`

# Metadata
- Mangled symbol: `_ZNK16b2StackAllocator16GetMaxAllocationEv`
"""

function b2StackAllocator_GetMaxAllocation(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK16b2StackAllocator16GetMaxAllocationEv_thunk", Cint, this)
end
"""
    b2SeparationFunction_FindMinSeparation(this::Any, arg1::Any, arg2::Any, arg3::Cfloat) -> Cfloat

Wrapper for `b2SeparationFunction::FindMinSeparation(int*, int*, float) const`

# Arguments
- `this::Ptr{b2SeparationFunction}`
- `arg1::Ptr{Cint}`
- `arg2::Ptr{Cint}`
- `arg3::Cfloat`

# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_ZNK20b2SeparationFunction17FindMinSeparationEPiS0_f`
"""

function b2SeparationFunction_FindMinSeparation(this::Any, arg1::Any, arg2::Any, arg3::Cfloat)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK20b2SeparationFunction17FindMinSeparationEPiS0_f_thunk", Cfloat, this, arg1, arg2, arg3)
end
"""
    b2SeparationFunction_Evaluate(this::Any, arg1::Integer, arg2::Integer, arg3::Cfloat) -> Cfloat

Wrapper for `b2SeparationFunction::Evaluate(int, int, float) const`

# Arguments
- `this::Ptr{b2SeparationFunction}`
- `arg1::Cint`
- `arg2::Cint`
- `arg3::Cfloat`

# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_ZNK20b2SeparationFunction8EvaluateEiif`
"""

function b2SeparationFunction_Evaluate(this::Any, arg1::Integer, arg2::Integer, arg3::Cfloat)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK20b2SeparationFunction8EvaluateEiif_thunk", Cfloat, this, arg1, arg2, arg3)
end
"""
    b2AABB_RayCast(this::Any, arg1::Any, arg2::Ref{Any}) -> Bool

Wrapper for `b2AABB::RayCast(b2RayCastOutput*, b2RayCastInput const&) const`

# Arguments
- `this::Ptr{b2AABB}`
- `arg1::Ptr{b2RayCastOutput}`
- `arg2::Ref{Any}`

# Returns
- `Bool`

# Metadata
- Mangled symbol: `_ZNK6b2AABB7RayCastEP15b2RayCastOutputRK14b2RayCastInput`
"""

function b2AABB_RayCast(this::Any, arg1::Any, arg2::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK6b2AABB7RayCastEP15b2RayCastOutputRK14b2RayCastInput_thunk", Bool, this, arg1, arg2)
end
"""
    b2Body_ShouldCollide(this::Any, arg1::Any) -> Bool

Wrapper for `b2Body::ShouldCollide(b2Body const*) const`

# Arguments
- `this::Ptr{b2Body}`
- `arg1::Ptr{Cvoid}`

# Returns
- `Bool`

# Metadata
- Mangled symbol: `_ZNK6b2Body13ShouldCollideEPKS_`
"""

function b2Body_ShouldCollide(this::Any, arg1::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK6b2Body13ShouldCollideEPKS__thunk", Bool, this, arg1)
end
"""
    b2Draw_GetFlags(this::Any) -> Cuint

Wrapper for `b2Draw::GetFlags() const`

# Arguments
- `this::Ptr{b2Draw}`

# Returns
- `Cuint`

# Metadata
- Mangled symbol: `_ZNK6b2Draw8GetFlagsEv`
"""

function b2Draw_GetFlags(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK6b2Draw8GetFlagsEv_thunk", Cuint, this)
end
"""
    b2Rope_Draw(this::Any, arg1::Any) -> Cvoid

Wrapper for `b2Rope::Draw(b2Draw*) const`

# Arguments
- `this::Ptr{b2Rope}`
- `arg1::Ptr{b2Draw}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZNK6b2Rope4DrawEP6b2Draw`
"""

function b2Rope_Draw(this::Any, arg1::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK6b2Rope4DrawEP6b2Draw_thunk", this, arg1)
end
"""
    b2Joint_Draw(this::Any, arg1::Any) -> Cvoid

Wrapper for `b2Joint::Draw(b2Draw*) const`

# Arguments
- `this::Ptr{b2Joint}`
- `arg1::Ptr{b2Draw}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZNK7b2Joint4DrawEP6b2Draw`
"""

function b2Joint_Draw(this::Any, arg1::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK7b2Joint4DrawEP6b2Draw_thunk", this, arg1)
end
"""
    b2Joint_IsEnabled(this::Any) -> Bool

Wrapper for `b2Joint::IsEnabled() const`

# Arguments
- `this::Ptr{b2Joint}`

# Returns
- `Bool`

# Metadata
- Mangled symbol: `_ZNK7b2Joint9IsEnabledEv`
"""

function b2Joint_IsEnabled(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK7b2Joint9IsEnabledEv_thunk", Bool, this)
end
"""
    b2Mat33_GetInverse22(this::Any, arg1::Any) -> Cvoid

Wrapper for `b2Mat33::GetInverse22(b2Mat33*) const`

# Arguments
- `this::Ptr{b2Mat33}`
- `arg1::Ptr{b2Mat33}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZNK7b2Mat3312GetInverse22EPS_`
"""

function b2Mat33_GetInverse22(this::Any, arg1::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK7b2Mat3312GetInverse22EPS__thunk", this, arg1)
end
"""
    b2Mat33_GetSymInverse33(this::Any, arg1::Any) -> Cvoid

Wrapper for `b2Mat33::GetSymInverse33(b2Mat33*) const`

# Arguments
- `this::Ptr{b2Mat33}`
- `arg1::Ptr{b2Mat33}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZNK7b2Mat3315GetSymInverse33EPS_`
"""

function b2Mat33_GetSymInverse33(this::Any, arg1::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK7b2Mat3315GetSymInverse33EPS__thunk", this, arg1)
end
"""
    b2Mat33_Solve22(this::Any, arg1::Ref{Any}) -> b2Vec2

Wrapper for `b2Mat33::Solve22(b2Vec2 const&) const`

# Arguments
- `this::Ptr{b2Mat33}`
- `arg1::Ref{Any}`

# Returns
- `b2Vec2`

# Metadata
- Mangled symbol: `_ZNK7b2Mat337Solve22ERK6b2Vec2`
"""

function b2Mat33_Solve22(this::Any, arg1::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK7b2Mat337Solve22ERK6b2Vec2_thunk", b2Vec2, this, arg1)
end
"""
    b2Mat33_Solve33(this::Any, arg1::Ref{Any}) -> b2Vec3

Wrapper for `b2Mat33::Solve33(b2Vec3 const&) const`

# Arguments
- `this::Ptr{b2Mat33}`
- `arg1::Ref{Any}`

# Returns
- `b2Vec3`

# Metadata
- Mangled symbol: `_ZNK7b2Mat337Solve33ERK6b2Vec3`
"""

function b2Mat33_Solve33(this::Any, arg1::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK7b2Mat337Solve33ERK6b2Vec3_thunk", b2Vec3, this, arg1)
end
"""
    b2Timer_GetMilliseconds(this::Any) -> Cfloat

Wrapper for `b2Timer::GetMilliseconds() const`

# Arguments
- `this::Ptr{b2Timer}`

# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_ZNK7b2Timer15GetMillisecondsEv`
"""

function b2Timer_GetMilliseconds(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK7b2Timer15GetMillisecondsEv_thunk", Cfloat, this)
end
"""
    b2World_GetProxyCount(this::Any) -> Cint

Wrapper for `b2World::GetProxyCount() const`

# Arguments
- `this::Ptr{b2World}`

# Returns
- `Cint`

# Metadata
- Mangled symbol: `_ZNK7b2World13GetProxyCountEv`
"""

function b2World_GetProxyCount(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK7b2World13GetProxyCountEv_thunk", Cint, this)
end
"""
    b2World_GetTreeHeight(this::Any) -> Cint

Wrapper for `b2World::GetTreeHeight() const`

# Arguments
- `this::Ptr{b2World}`

# Returns
- `Cint`

# Metadata
- Mangled symbol: `_ZNK7b2World13GetTreeHeightEv`
"""

function b2World_GetTreeHeight(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK7b2World13GetTreeHeightEv_thunk", Cint, this)
end
"""
    b2World_GetTreeBalance(this::Any) -> Cint

Wrapper for `b2World::GetTreeBalance() const`

# Arguments
- `this::Ptr{b2World}`

# Returns
- `Cint`

# Metadata
- Mangled symbol: `_ZNK7b2World14GetTreeBalanceEv`
"""

function b2World_GetTreeBalance(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK7b2World14GetTreeBalanceEv_thunk", Cint, this)
end
"""
    b2World_GetTreeQuality(this::Any) -> Cfloat

Wrapper for `b2World::GetTreeQuality() const`

# Arguments
- `this::Ptr{b2World}`

# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_ZNK7b2World14GetTreeQualityEv`
"""

function b2World_GetTreeQuality(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK7b2World14GetTreeQualityEv_thunk", Cfloat, this)
end
"""
    b2World_RayCast(this::Any, arg1::Any, arg2::Ref{Any}, arg3::Ref{Any}) -> Cvoid

Wrapper for `b2World::RayCast(b2RayCastCallback*, b2Vec2 const&, b2Vec2 const&) const`

# Arguments
- `this::Ptr{b2World}`
- `arg1::Ptr{b2RayCastCallback}`
- `arg2::Ref{Any}`
- `arg3::Ref{Any}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZNK7b2World7RayCastEP17b2RayCastCallbackRK6b2Vec2S4_`
"""

function b2World_RayCast(this::Any, arg1::Any, arg2::Ref{Any}, arg3::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK7b2World7RayCastEP17b2RayCastCallbackRK6b2Vec2S4__thunk", this, arg1, arg2, arg3)
end
"""
    b2World_QueryAABB(this::Any, arg1::Any, arg2::Ref{Any}) -> Cvoid

Wrapper for `b2World::QueryAABB(b2QueryCallback*, b2AABB const&) const`

# Arguments
- `this::Ptr{b2World}`
- `arg1::Ptr{b2QueryCallback}`
- `arg2::Ref{Any}`

# Returns
- `Cvoid`

# Metadata
- Mangled symbol: `_ZNK7b2World9QueryAABBEP15b2QueryCallbackRK6b2AABB`
"""

function b2World_QueryAABB(this::Any, arg1::Any, arg2::Ref{Any})
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK7b2World9QueryAABBEP15b2QueryCallbackRK6b2AABB_thunk", this, arg1, arg2)
end
"""
    b2Simplex_GetMetric(this::Any) -> Cfloat

Wrapper for `b2Simplex::GetMetric() const`

# Arguments
- `this::Ptr{b2Simplex}`

# Returns
- `Cfloat`

# Metadata
- Mangled symbol: `_ZNK9b2Simplex9GetMetricEv`
"""

function b2Simplex_GetMetric(this::Any)
    # [Tier 2] Dispatch to MLIR JIT (Complex ABI / Packed / Union)
    return RepliBuild.JITManager.invoke("_mlir_ciface__ZNK9b2Simplex9GetMetricEv_thunk", Cfloat, this)
end

end # module Box2d
