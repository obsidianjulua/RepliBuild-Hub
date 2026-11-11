#!/usr/bin/env julia
# boostmath Hub package — deep verifier
#
# Assumes the wrapper is already built (test.jl rebuilds; this only verifies).
# Every assertion is a value, against a closed form or a published constant:
#   - special functions, float + double instantiations
#   - five distributions: constructor, member accessors, pdf/cdf/quantile/mean
#   - gauss_kronrod<double,15>::integrate over a Julia @cfunction
#   - brent_find_minima, bisect and toms748_solve, each returning
#     std::pair<double, double> by value, over a Julia @cfunction
#   - the error path: Boost's default policy throws, and that must come back
#     to Julia as an error, not a NaN or an abort
#
# Usage:  julia --project=/path/to/RepliBuild.jl packages/boostmath/test_deep.jl

using Test

const PKG_DIR = @__DIR__
const WRAPPER = joinpath(PKG_DIR, "julia", "Boostmath.jl")

if !isfile(WRAPPER)
    @info "Wrapper missing — building first"
    using RepliBuild
    RepliBuild.build(joinpath(PKG_DIR, "replibuild.toml"))
    RepliBuild.wrap(joinpath(PKG_DIR, "replibuild.toml"))
end

include(WRAPPER)
const B = Boostmath

# Julia names carry the full template argument list, and Boost's default
# policy<> spells out as thirteen `default_policy`s. Resolve by the readable
# head and tail and let the policy run in between, so the test reads as
# Boost's API rather than as a 700-character identifier.
const _POL = raw"(_boost_math_policies_(default_)?policy)*"
function sym(head::AbstractString, tail::AbstractString="")
    re = Regex("^" * head * _POL * tail * raw"$")
    hits = [n for n in names(B; all=true) if occursin(re, String(n))]
    length(hits) == 1 || error("sym($head, $tail): expected 1 match, got $(length(hits)): $hits")
    return getfield(B, only(hits))
end

const NormalT    = sym("normal_distribution_double")
const StudentsT  = sym("students_t_distribution_double")
const ChiSqT     = sym("chi_squared_distribution_double")
const PoissonT   = sym("poisson_distribution_double")
const BinomialT  = sym("binomial_distribution_double")

const pdf      = sym("boost_math_pdf_double")
const cdf      = sym("boost_math_cdf_double")
const quantile = sym("boost_math_quantile_double")
const dmean    = sym("boost_math_mean_double")

# Construct a distribution the C++ way: storage, then the constructor on it.
# The structs are immutable Julia mirrors, so `this` is a Ref the ctor fills.
function construct(T::Type, ctorhead::AbstractString, args...)
    r = Ref(T(ntuple(_ -> 0.0, fieldcount(T))...))
    ctor = sym(ctorhead, "_" * replace(ctorhead, r"^boost_math_(\w+?)_double$" => s"\1"))
    GC.@preserve r ctor(Base.unsafe_convert(Ptr{T}, r), Float64.(args)...)
    return r
end
normal(m, s)   = construct(NormalT,   "boost_math_normal_distribution_double", m, s)
students_t(df) = construct(StudentsT, "boost_math_students_t_distribution_double", df)
chi_sq(df)     = construct(ChiSqT,    "boost_math_chi_squared_distribution_double", df)
poisson(l)     = construct(PoissonT,  "boost_math_poisson_distribution_double", l)
binomial(n, p) = construct(BinomialT, "boost_math_binomial_distribution_double", n, p)

const EULER_GAMMA = 0.5772156649015329

@testset "Boost.Math deep" begin

@testset "build identity" begin
    @test isfile(B.LIBRARY_PATH)
    @test isfile(B.THUNKS_LIBRARY_PATH)
end

@testset "gamma family" begin
    @test B.boost_math_tgamma_double(5.0) == 24.0
    @test B.boost_math_tgamma_double(0.5) ≈ sqrt(π)
    @test B.boost_math_tgamma_float(5.0f0) === 24.0f0          # float instantiation, Cfloat in/out
    @test B.boost_math_lgamma_double(10.0) ≈ log(362880.0)
    @test B.boost_math_digamma_double(1.0) ≈ -EULER_GAMMA
    @test B.boost_math_beta_double_double(2.0, 3.0) ≈ 1 / 12
    @test B.boost_math_gamma_p_double_double(1.0, 1.0) ≈ 1 - exp(-1)
    @test B.boost_math_gamma_q_double_double(1.0, 1.0) ≈ exp(-1)
    @test B.boost_math_factorial_double(10) == 3628800.0
    @test B.boost_math_binomial_coefficient_double(10, 3) == 120.0
end

@testset "erf family" begin
    @test B.boost_math_erf_double(0.5) ≈ 0.5204998778130465
    @test B.boost_math_erf_float(0.5f0) ≈ 0.5204999f0
    @test B.boost_math_erfc_double(0.5) ≈ 1 - 0.5204998778130465
    @test B.boost_math_erf_inv_double(B.boost_math_erf_double(0.3)) ≈ 0.3
end

@testset "elementary-adjacent" begin
    # log1p/expm1 exist for the small-x regime where log(1+x) loses everything.
    @test B.boost_math_log1p_double(1e-10) ≈ 1e-10 - 5e-21 rtol=1e-15
    @test B.boost_math_expm1_double(1e-10) ≈ 1e-10 + 5e-21 rtol=1e-15
    @test B.boost_math_zeta_double(2.0) ≈ π^2 / 6
    @test B.boost_math_lambert_w0_double(exp(1)) ≈ 1.0
    @test B.boost_math_expint_double(1.0) ≈ 1.8951178163559368
    @test B.boost_math_ellint_1_double(0.0) ≈ π / 2
end

@testset "Bessel / Airy / Legendre" begin
    @test B.boost_math_cyl_bessel_j_double_double(0.0, 0.0) == 1.0
    @test abs(B.boost_math_cyl_bessel_j_double_double(0.0, 2.404825557695773)) < 1e-14  # first zero of J0
    @test B.boost_math_cyl_bessel_k_double_double(0.5, 1.0) ≈ sqrt(π / 2) * exp(-1)
    @test B.boost_math_cyl_neumann_double_double(0.0, 1.0) ≈ 0.08825696421567697
    @test B.boost_math_airy_ai_double(0.0) ≈ 0.3550280538878172
    @test B.boost_math_airy_bi_double(0.0) ≈ 0.6149266274460007
    @test B.boost_math_legendre_p_double(2, 0.5) ≈ -0.125
end

@testset "struct layout" begin
    @test sizeof(NormalT) == 16
    @test fieldnames(NormalT) == (:m_mean, :m_sd)
    @test sizeof(BinomialT) == 16
    @test sizeof(StudentsT) == 8
    @test sizeof(ChiSqT) == 8
    @test sizeof(PoissonT) == 8
end

@testset "normal distribution" begin
    n = normal(2.0, 3.0)
    @test n[].m_mean == 2.0 && n[].m_sd == 3.0          # ctor wrote the fields
    GC.@preserve n begin
        p = Base.unsafe_convert(Ptr{NormalT}, n)
        @test sym("boost_math_normal_distribution_double", "_standard_deviation")(p) == 3.0
        @test sym("boost_math_normal_distribution_double", "_location")(p) == 2.0
    end
    @test dmean(n) == 2.0

    z = normal(0.0, 1.0)
    @test pdf(z, Ref(0.0)) ≈ 1 / sqrt(2π)
    @test cdf(z, Ref(1.96)) ≈ 0.9750021048517795
    @test quantile(z, Ref(0.975)) ≈ 1.959963984540054
    @test cdf(z, Ref(quantile(z, Ref(0.3)))) ≈ 0.3
end

@testset "students_t / chi_squared / poisson / binomial" begin
    t = students_t(10.0)
    @test cdf(t, Ref(0.0)) ≈ 0.5
    @test dmean(t) == 0.0

    c = chi_sq(4.0)
    @test dmean(c) == 4.0
    @test pdf(c, Ref(2.0)) ≈ 0.5 * exp(-1)                # x e^{-x/2} / 4 at x = 2

    p = poisson(3.0)
    @test dmean(p) == 3.0
    @test pdf(p, Ref(2.0)) ≈ 4.5 * exp(-3)

    b = binomial(10.0, 0.5)
    @test dmean(b) == 5.0
    @test pdf(b, Ref(5.0)) ≈ 252 / 1024
    @test cdf(b, Ref(5.0)) ≈ 638 / 1024
end

@testset "gauss_kronrod<double,15>::integrate over a @cfunction" begin
    integrate = sym("boost_math_quadrature_gauss_kronrod_double_15u", "_integrate_double_mul_double")
    sq(x::Cdouble)::Cdouble = x * x
    f = @cfunction($sq, Cdouble, (Cdouble,))
    err = Ref(NaN)
    GC.@preserve f err begin
        q = integrate(Base.unsafe_convert(Ptr{Cvoid}, f), 0.0, 1.0, 15, sqrt(eps()),
                      Base.unsafe_convert(Ptr{Cdouble}, err), C_NULL)
        @test q ≈ 1 / 3
        @test 0.0 <= err[] < 1e-10                          # error estimate written through the pointer
    end
    # A non-polynomial integrand: ∫₀^π sin = 2.
    s(x::Cdouble)::Cdouble = sin(x)
    g = @cfunction($s, Cdouble, (Cdouble,))
    GC.@preserve g begin
        @test integrate(Base.unsafe_convert(Ptr{Cvoid}, g), 0.0, Float64(π), 15, sqrt(eps()),
                        C_NULL, C_NULL) ≈ 2.0
    end
end

@testset "minimise, and bracket a root: std::pair<double, double> by value" begin
    # brent_find_minima / bisect / toms748_solve return std::pair<T, T>
    # (boost::math::pair is `using ::std::pair`). RepliBuild keeps the layout of
    # a toolchain record the library passes by value since 2026-11-08; before
    # that these could only be ABI traps, so the shim left them out.
    PairT  = B.pair_double_double
    brent  = B.boost_math_tools_brent_find_minima_double_mul_double_double
    bisect = B.boost_math_tools_bisect_double_mul_double_double_boost_math_tools_eps_tolerance_double
    toms   = B.boost_math_tools_toms748_solve_double_mul_double_double_boost_math_tools_eps_tolerance_double
    @test fieldnames(PairT) == (:first, :second) && sizeof(PairT) == 16
    fptr(c) = Base.unsafe_convert(Ptr{Cvoid}, c)

    bowl(x::Cdouble)::Cdouble = (x - 2.0)^2 + 1.0
    sq2(x::Cdouble)::Cdouble = x * x - 2.0
    fb = @cfunction($bowl, Cdouble, (Cdouble,))
    fs = @cfunction($sq2, Cdouble, (Cdouble,))
    GC.@preserve fb fs begin
        m = brent(fptr(fb), 0.0, 5.0, 52)
        @test m isa PairT
        @test m.first ≈ 2.0 atol = 1e-7                      # where the minimum is
        @test m.second ≈ 1.0                                  # and its value

        tol = B.eps_tolerance_double(2.0^-40)                 # its one field, `eps`
        it = Ref{Culong}(200)
        r = bisect(fptr(fs), 0.0, 2.0, tol, it)
        @test r.first <= sqrt(2) <= r.second
        @test r.second - r.first < 1e-11
        @test 0 < it[] < 200                                  # the count comes back through the reference

        it748 = Ref{Culong}(200)
        t = toms(fptr(fs), Ref(0.0), Ref(2.0), tol, it748)
        @test t.first <= sqrt(2) <= t.second
        @test t.second - t.first < 1e-11
        @test 0 < it748[] < it[]                              # fewer evaluations than bisection

        # No sign change on [2, 3]: the default policy throws evaluation_error.
        @test_throws "No change of sign" bisect(fptr(fs), 2.0, 3.0, tol, Ref{Culong}(50))
    end
end

@testset "error path: default policy throws" begin
    # Each is a JITManager.CxxException carrying Boost's own what(): the
    # message is asserted so an unrelated Julia error cannot pass for it.
    # Pole at -1 → pole_error → std::domain_error. Must surface, not abort.
    @test_throws "Evaluation of tgamma at a negative integer -1" B.boost_math_tgamma_double(-1.0)
    # Probability outside [0, 1].
    z = normal(0.0, 1.0)
    @test_throws "Probability argument is 1.5" quantile(z, Ref(1.5))
    # The ctor validates sd > 0.
    @test_throws "Scale parameter is -1" normal(0.0, -1.0)
    # And the wrapper is still usable afterwards.
    @test B.boost_math_tgamma_double(4.0) == 6.0
end

end
