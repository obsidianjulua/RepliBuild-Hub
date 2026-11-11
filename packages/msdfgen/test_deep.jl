#!/usr/bin/env julia
# msdfgen — deep verifier. Exercises an ALREADY-BUILT wrapper; builds nothing.
# (`test.jl` is the cold rebuild driver and then runs this file.)
#
#   julia --project=<RepliBuild.jl> packages/msdfgen/test_deep.jl
#
# The reference is the library itself, called natively: a small C++ program is
# compiled against the SAME julia/libmsdfgen.so at test time and dumps what it
# computes. Every wrapper result is compared against that dump, so the expected
# values cannot drift from the library the way hand-written constants would.
#
# What this leans on — Tier 2 end to end, on real geometry:
#   * class construction into Julia-owned storage, std::vector growth inside Shape
#   * virtual classes (EdgeSegment hierarchy) read back through their vtables
#   * by-value Vector2 / Range arguments and by-value SignedDistance / Vector2 returns
#   * SDF / PSDF / MSDF generation (768 floats through MSDF error correction)
#
# Asserted positively (each was pinned here first):
#   * EdgeSegment::create is static. A phantom `this` used to take the first
#     register, so the colour argument never landed at offset 8.
#   * constructors join their DWARF (C4/D4 ↔ C1/C2/D0-2), so by-value Vector2
#     constructor arguments marshal correctly (2026-09-26)
#   * `T&&` parameters are typed (`Contour::addEdge(EdgeHolder&&)`)

using Test
using JSON        # RepliBuild dependency; available under --project=<RepliBuild.jl>

const PKG = @__DIR__
include(joinpath(PKG, "julia", "Msdfgen.jl"))
import .Msdfgen as M         # never `using` a C++ wrapper — see the Hub notes

# EdgeColor's underlying type is Cuint. The static create() and the
# LinearSegment constructor both take that enum, not a phantom this plus Any.
const WHITE = M.WHITE

# ── the native oracle ────────────────────────────────────────────────────────
const ORACLE_SRC = raw"""
#include "msdfgen.h"
#include <cstdio>
#include <cstring>
using namespace msdfgen;
static void build(Shape &shape) {
    Contour &c = shape.addContour();
    c.addEdge(EdgeHolder(Point2(1,1), Point2(7,1)));
    c.addEdge(EdgeHolder(Point2(7,1), Point2(7,7)));
    c.addEdge(EdgeHolder(Point2(7,7), Point2(1,7)));
    c.addEdge(EdgeHolder(Point2(1,7), Point2(1,1)));
    Contour &h = shape.addContour();
    h.addEdge(EdgeHolder(Point2(3,3), Point2(4,5)));
    h.addEdge(EdgeHolder(Point2(4,5), Point2(5,3)));
    h.addEdge(EdgeHolder(Point2(5,3), Point2(3,3)));
    shape.normalize();
}
static void dump(FILE *f, const char *tag, const float *p, int n) {
    fprintf(f, "%s", tag); for (int i=0;i<n;i++) fprintf(f, " %.9g", p[i]); fprintf(f, "\n"); }
int main(int argc, char **argv) {
    FILE *f = fopen(argv[1], "w");
    fprintf(f, "sizeof %zu %zu %zu %zu %zu %zu %zu %zu %zu\n", sizeof(Shape), sizeof(Contour),
            sizeof(EdgeHolder), sizeof(LinearSegment), sizeof(Range), sizeof(SDFTransformation),
            sizeof(MSDFGeneratorConfig), sizeof(ErrorCorrectionConfig), sizeof(SignedDistance));
    LinearSegment seg(Point2(0,0), Point2(4,0));
    Point2 mid = seg.point(0.5);
    double param; SignedDistance sd = seg.signedDistance(Point2(2,-1), param);
    fprintf(f, "point %.17g %.17g\nsigned %.17g %.17g %.17g\n", mid.x, mid.y, sd.distance, sd.dot, param);
    Shape shape; build(shape);
    fprintf(f, "validate %d\nedgeCount %d\nwinding %d %d\n", shape.validate(), shape.edgeCount(),
            shape.contours[0].winding(), shape.contours[1].winding());
    edgeColoringSimple(shape, 3.0, 0);
    fprintf(f, "colors");
    for (int ci=0; ci<2; ci++) for (size_t e=0; e<shape.contours[ci].edges.size(); e++)
        fprintf(f, " %d", (int) shape.contours[ci].edges[e]->color);
    fprintf(f, "\n");
    const int W = 16;
    Bitmap<float,1> a(W,W), b(W,W), p(W,W); Bitmap<float,3> m(W,W);
    SDFTransformation tf(Projection(Vector2(2.0), Vector2(0.0)), Range(4.0));
    generateSDF(a, shape, tf);                                     dump(f, "sdf_tf", (const float*) a, W*W);
    generateSDF(b, shape, Range(4.0), Vector2(2.0), Vector2(0.0)); dump(f, "sdf_range", (const float*) b, W*W);
    generatePSDF(p, shape, tf);                                    dump(f, "psdf_tf", (const float*) p, W*W);
    MSDFGeneratorConfig cfg;
    generateMSDF(m, shape, tf, cfg);                               dump(f, "msdf_tf", (const float*) m, 3*W*W);
    ErrorCorrectionConfig ec; unsigned char buf[sizeof ec]; memcpy(buf, &ec, sizeof ec);
    fprintf(f, "eccbytes"); for (size_t i=0;i<sizeof ec;i++) fprintf(f, " %d", buf[i]); fprintf(f, "\n");
    fclose(f); return 0;
}
"""

function run_oracle()
    dir = mktempdir()
    src = joinpath(dir, "oracle.cpp"); exe = joinpath(dir, "oracle"); out = joinpath(dir, "oracle.txt")
    write(src, ORACLE_SRC)
    libdir = joinpath(PKG, "julia")
    inc = joinpath(PKG, ".replibuild_cache", "deps", "msdfgen")
    # Same defines the package compiles with, or the oracle sees a different ABI.
    run(`clang++ -std=c++17 -O1 -DMSDFGEN_PUBLIC= -DMSDFGEN_USE_CPP11 -I$inc $src
         -L$libdir -lmsdfgen -Wl,-rpath,$libdir -o $exe`)
    run(`$exe $out`)
    d = Dict{String,Vector{Float64}}()
    for l in eachline(out)
        parts = split(l)
        d[parts[1]] = parse.(Float64, parts[2:end])
    end
    return d
end

close_to(got, want; tol=1e-5) =
    length(got) == length(want) && maximum(abs.(Float64.(collect(got)) .- want); init=0.0) < tol

"LinearSegment constructed in malloc'd storage through the real constructor thunk."
function linseg(x0, y0, x1, y1)
    seg = Libc.malloc(sizeof(M.LinearSegment))
    M.msdfgen_LinearSegment_LinearSegment(Ptr{M.LinearSegment}(seg), M.Vector2(x0, y0), M.Vector2(x1, y1), WHITE)
    return seg
end

"BitmapSection<float, ch> over a Julia array (pixels@0, width@8, height@12, rowStride@16, yOrientation@20)."
function section(ch, W)
    pix = zeros(Float32, ch * W * W)
    blob = zeros(UInt8, 24)
    GC.@preserve pix blob begin
        unsafe_store!(Ptr{Ptr{Float32}}(pointer(blob)), pointer(pix))
        unsafe_store!(Ptr{Cint}(pointer(blob) + 8), W)
        unsafe_store!(Ptr{Cint}(pointer(blob) + 12), W)
        unsafe_store!(Ptr{Cint}(pointer(blob) + 16), ch * W)
        unsafe_store!(Ptr{Cint}(pointer(blob) + 20), 0)
    end
    return (pix, blob)
end

@testset "msdfgen (deep)" begin
    O = run_oracle()

    @testset "layouts agree with the C++ compiler" begin
        s = O["sizeof"]
        @test sizeof(M.Shape) == s[1]
        @test sizeof(M.Contour) == s[2]
        @test sizeof(M.EdgeHolder) == s[3]
        @test sizeof(M.LinearSegment) == s[4]
        @test sizeof(M.Range) == s[5]              # needs -fstandalone-debug (see toml)
        @test sizeof(M.SDFTransformation) == s[6]
        @test sizeof(M.MSDFGeneratorConfig) == s[7]
        @test sizeof(M.ErrorCorrectionConfig) == s[8]
        @test sizeof(M.SignedDistance) == s[9]
    end

    @testset "virtual segment methods: Vector2 in, struct out" begin
        seg = linseg(0.0, 0.0, 4.0, 0.0)
        p = M.msdfgen_LinearSegment_point(Ptr{M.LinearSegment}(seg), 0.5)
        @test close_to((p.x, p.y), O["point"])
        param = Ref(0.0)
        sd = M.msdfgen_LinearSegment_signedDistance(Ptr{M.LinearSegment}(seg), M.Vector2(2.0, -1.0), param)
        @test close_to((sd.distance, sd.dot, param[]), O["signed"])
        Libc.free(seg)
    end

    # Build the oracle's shape through the wrapper.
    shape = Ptr{M.Shape}(Libc.malloc(sizeof(M.Shape)))
    M.msdfgen_Shape_Shape(shape)
    for poly in ([(1.,1.),(7.,1.),(7.,7.),(1.,7.)], [(3.,3.),(4.,5.),(5.,3.)])
        c = Ptr{M.Contour}(M.msdfgen_Shape_addContour(shape))
        for k in eachindex(poly)
            (a, b) = (poly[k], poly[mod1(k + 1, length(poly))])
            seg = linseg(a..., b...)
            h = Ref(M.EdgeHolder(Ptr{M.EdgeSegment}(seg)))
            GC.@preserve h M.msdfgen_Contour_addEdge(c, h)   # const& overload clones
            Libc.free(seg)
        end
    end
    M.msdfgen_Shape_normalize(shape)
    # addContour may have reallocated Shape::contours — take addresses afterwards.
    cbeg = unsafe_load(Ptr{Ptr{UInt8}}(shape))
    contours = [Ptr{M.Contour}(cbeg + sizeof(M.Contour) * (i - 1)) for i in 1:2]

    @testset "shape topology" begin
        @test M.msdfgen_Shape_validate(shape) == Bool(O["validate"][1])
        @test M.msdfgen_Shape_edgeCount(shape) == O["edgeCount"][1]
        @test [M.msdfgen_Contour_winding(c) for c in contours] == O["winding"]
        l = Ref(Inf); b = Ref(Inf); r = Ref(-Inf); t = Ref(-Inf)   # bound() expands the box it is given
        M.msdfgen_Shape_bound(shape, l, b, r, t)
        @test (l[], b[], r[], t[]) == (1.0, 1.0, 7.0, 7.0)
    end

    @testset "edge colouring (reads back through EdgeHolder → vtable'd segment)" begin
        M.msdfgen_edgeColoringSimple(shape, 3.0, 0)
        cols = Float64[]
        for (ci, c) in enumerate(contours), e in 1:(ci == 1 ? 4 : 3)
            edges = unsafe_load(Ptr{Ptr{Ptr{Cvoid}}}(c))
            push!(cols, unsafe_load(Ptr{Cint}(unsafe_load(edges, e) + 8)))
        end
        @test cols == O["colors"]
    end

    W = 16
    tf  = Ref(M.SDFTransformation(M.Vector2(2.0, 2.0), M.Vector2(0.0, 0.0), M.DistanceMapping(1 / 4.0, 2.0)))
    cfg = Ref(M.GeneratorConfig(true))

    @testset "distance fields match the native library" begin
        (a, ab) = section(1, W)
        GC.@preserve a ab M.msdfgen_generateSDF(Ptr{M.BitmapSection_float_1}(pointer(ab)), shape, tf, cfg)
        @test close_to(a, O["sdf_tf"])

        (b, bb) = section(1, W)       # Range passed BY VALUE
        GC.@preserve b bb M.msdfgen_generateSDF(Ptr{M.BitmapSection_float_1}(pointer(bb)), shape,
                                                M.Range(-2.0, 2.0), Ref(M.Vector2(2.0, 2.0)),
                                                Ref(M.Vector2(0.0, 0.0)), true)
        @test close_to(b, O["sdf_range"])

        (p, pb) = section(1, W)
        GC.@preserve p pb M.msdfgen_generatePSDF(Ptr{M.BitmapSection_float_1}(pointer(pb)), shape, tf, cfg)
        @test close_to(p, O["psdf_tf"])

        # RepliBuild 4.4 wraps ErrorCorrectionConfig as its five members (it was
        # a 32-byte blob before); the oracle still hands over the native bytes of
        # a default-constructed one, so read them back as the struct.
        eccbytes = UInt8.(O["eccbytes"])
        @test length(eccbytes) == sizeof(M.ErrorCorrectionConfig)
        ecc  = let r = Ref{M.ErrorCorrectionConfig}()
            GC.@preserve r eccbytes unsafe_copyto!(Ptr{UInt8}(Base.unsafe_convert(Ptr{Cvoid}, r)),
                                                   pointer(eccbytes), length(eccbytes))
            r[]
        end
        mcfg = Ref(M.MSDFGeneratorConfig(true, ntuple(_ -> 0x00, 7), ecc))
        (m, mb) = section(3, W)
        GC.@preserve m mb M.msdfgen_generateMSDF(Ptr{M.BitmapSection_float_3}(pointer(mb)), shape, tf, mcfg)
        @test close_to(m, O["msdf_tf"])
    end

    @testset "constructor arguments marshal (C4/D4 DWARF join)" begin
        # Was @test_broken until 2026-09-26: the constructor's signature came from
        # the demangled string, both Vector2 arguments were `Any`, and the thunk
        # stored p0=(1,3) plus garbage.
        seg = Libc.malloc(48)
        M.msdfgen_LinearSegment_LinearSegment(Ptr{M.LinearSegment}(seg), M.Vector2(1.0, 2.0), M.Vector2(3.0, 4.0), M.EdgeColor(5))
        got = (unsafe_load(Ptr{Cint}(seg + 8)), [unsafe_load(Ptr{Float64}(seg + 16 + 8k)) for k in 0:3]...)
        @test got == (Cint(5), 1.0, 2.0, 3.0, 4.0)
        Libc.free(seg)
    end

    @testset "static EdgeSegment::create and rvalue references" begin

        # No receiver. The colour is the third argument and is stored at +8.
        e = M.msdfgen_EdgeSegment_create(M.Vector2(0.0, 0.0), M.Vector2(1.0, 1.0), WHITE)
        @test e != C_NULL
        @test unsafe_load(Ptr{Cuint}(e + 8)) == Cuint(WHITE)

        # Rvalue references (fixed 2026-09-26, was pinned here): typed, and one Ref.
        meta = JSON.parsefile(joinpath(PKG, "julia", "compilation_metadata.json"); use_mmap=false)
        rv = only(f for f in meta["functions"] if f["mangled"] == "_ZN7msdfgen7Contour7addEdgeEONS_10EdgeHolderE")
        @test rv["parameters"][2]["c_type"] == "EdgeHolder&&"
        @test rv["parameters"][2]["julia_type"] == "Ref{EdgeHolder}"
    end

    # Shape's destructor is implicit (not exported); the vectors inside are leaked
    # deliberately rather than freed with the wrong deallocator.
    Libc.free(shape)
end
