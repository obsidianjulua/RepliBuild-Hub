// Instantiation shim for Boost.Math (header-only).
//
// Boost.Math ships no compiled C++ library: every function is a template that
// exists only once something names it. This TU names the surface the Julia
// wrapper should see, as explicit instantiation definitions. Each one emits a
// weak_odr symbol plus its DWARF subprogram, so the ordinary DWARF → wrapper
// path picks it up under Boost's own mangled name. No forwarding functions:
// the wrapped symbol IS the Boost template.
//
// The package builds with [compile] visibility = "hidden", and every line here
// carries RB_API. Instantiating one public function implicitly instantiates
// dozens of Boost internals (detail::erf_imp, tools::toms748_solve, lanczos
// tables, ...). Hidden visibility keeps those out of the dynamic table, so the
// .so's API is exactly this file.
//
// Default policy throughout: a domain/pole/overflow error throws
// (std::domain_error, std::overflow_error, ...), so every call is Tier 2 and
// a bad argument comes back to Julia as an error, not a NaN.

#include <boost/math/special_functions/gamma.hpp>
#include <boost/math/special_functions/digamma.hpp>
#include <boost/math/special_functions/beta.hpp>
#include <boost/math/special_functions/erf.hpp>
#include <boost/math/special_functions/bessel.hpp>
#include <boost/math/special_functions/legendre.hpp>
#include <boost/math/special_functions/zeta.hpp>
#include <boost/math/special_functions/expint.hpp>
#include <boost/math/special_functions/lambert_w.hpp>
#include <boost/math/special_functions/factorials.hpp>
#include <boost/math/special_functions/binomial.hpp>
#include <boost/math/special_functions/ellint_1.hpp>
#include <boost/math/special_functions/airy.hpp>
#include <boost/math/special_functions/log1p.hpp>
#include <boost/math/special_functions/expm1.hpp>

#include <boost/math/distributions/normal.hpp>
#include <boost/math/distributions/students_t.hpp>
#include <boost/math/distributions/chi_squared.hpp>
#include <boost/math/distributions/poisson.hpp>
#include <boost/math/distributions/binomial.hpp>

#include <boost/math/quadrature/gauss_kronrod.hpp>

#include <boost/math/tools/minima.hpp>
#include <boost/math/tools/roots.hpp>
#include <boost/math/tools/toms748_solve.hpp>

#define RB_API __attribute__((visibility("default")))

namespace bm = boost::math;
using Pol = bm::policies::policy<>;
using RealFn = double (*)(double);

// ── Special functions, default policy ──────────────────────────────────────
// float and double only. `long double` (x87 80-bit) has no Julia ccall type,
// so a long double instantiation is wrapped as an ABI trap: dead weight.
template RB_API double bm::tgamma<double>(double);
template RB_API float  bm::tgamma<float>(float);
template RB_API double bm::lgamma<double>(double);
template RB_API double bm::digamma<double>(double);
template RB_API double bm::erf<double>(double);
template RB_API float  bm::erf<float>(float);
template RB_API double bm::erfc<double>(double);
template RB_API double bm::erf_inv<double>(double);
template RB_API double bm::log1p<double>(double);
template RB_API double bm::expm1<double>(double);
template RB_API double bm::zeta<double>(double);
template RB_API double bm::airy_ai<double>(double);
template RB_API double bm::airy_bi<double>(double);
template RB_API double bm::ellint_1<double>(double);
template RB_API double bm::lambert_w0<double>(double);
template RB_API double bm::expint<double>(double);

template RB_API double bm::beta<double, double>(double, double);
template RB_API double bm::gamma_p<double, double>(double, double);
template RB_API double bm::gamma_q<double, double>(double, double);
template RB_API double bm::cyl_bessel_j<double, double>(double, double);
template RB_API double bm::cyl_bessel_k<double, double>(double, double);
template RB_API double bm::cyl_neumann<double, double>(double, double);
template RB_API double bm::legendre_p<double>(int, double);

// Explicit return type: T is not deducible from (unsigned, unsigned).
template RB_API double bm::factorial<double>(unsigned);
template RB_API double bm::binomial_coefficient<double>(unsigned, unsigned);

// ── Distributions: the class plus its non-member accessors ─────────────────
// The class instantiation gives the constructor and member accessors
// (normal::mean(), students_t::degrees_of_freedom(), ...). pdf/cdf/quantile
// are free function templates taking the distribution by const reference.
// No `variance`: normal's comes from the generic derived_accessors template,
// not a per-distribution overload, so one spelling doesn't fit all five.
template class RB_API bm::normal_distribution<double, Pol>;
template class RB_API bm::students_t_distribution<double, Pol>;
template class RB_API bm::chi_squared_distribution<double, Pol>;
template class RB_API bm::poisson_distribution<double, Pol>;
template class RB_API bm::binomial_distribution<double, Pol>;

#define RB_DIST_ACCESSORS(D)                                                               \
    template RB_API double bm::pdf<double, Pol>(const D<double, Pol>&, const double&);      \
    template RB_API double bm::cdf<double, Pol>(const D<double, Pol>&, const double&);      \
    template RB_API double bm::quantile<double, Pol>(const D<double, Pol>&, const double&); \
    template RB_API double bm::mean<double, Pol>(const D<double, Pol>&);

RB_DIST_ACCESSORS(bm::normal_distribution)
RB_DIST_ACCESSORS(bm::students_t_distribution)
RB_DIST_ACCESSORS(bm::chi_squared_distribution)
RB_DIST_ACCESSORS(bm::poisson_distribution)
RB_DIST_ACCESSORS(bm::binomial_distribution)
#undef RB_DIST_ACCESSORS

// ── Callables: a C function pointer is the F Julia can supply (@cfunction) ─
// The class itself is instantiated RB_API because a member's visibility is
// clamped to its class's: without that line, integrate<RealFn> stays hidden.
// That also exports the class's private recursive helpers. replibuild.toml
// excludes them from the wrapper.
template class RB_API bm::quadrature::gauss_kronrod<double, 15>;
template RB_API double bm::quadrature::gauss_kronrod<double, 15>::integrate<RealFn>(
    RealFn, double, double, unsigned, double, double*, double*);

// ── Minimisation and root bracketing: std::pair<T, T> by value ─────────────
// Each returns a std::pair (boost::math::pair is `using ::std::pair` outside
// CUDA). Before RepliBuild kept the layout of a toolchain record the library
// passes by value (2026-11-08), the wrapper could only trap these, so they
// were left out. eps_tolerance<double> is instantiated RB_API for its
// constructors; Julia can also build it from its one field, `eps`.
using Tol = bm::tools::eps_tolerance<double>;
template class RB_API bm::tools::eps_tolerance<double>;
template RB_API std::pair<double, double> bm::tools::brent_find_minima<RealFn, double>(
    RealFn, double, double, int);
template RB_API std::pair<double, double> bm::tools::bisect<RealFn, double, Tol>(
    RealFn, double, double, Tol, std::uintmax_t&);
template RB_API std::pair<double, double> bm::tools::toms748_solve<RealFn, double, Tol>(
    RealFn, const double&, const double&, Tol, std::uintmax_t&);
