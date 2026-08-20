#!/usr/bin/env julia
# SQLite Hub package — deep integration test
#
# Assumes the wrapper is already built (test.jl rebuilds; this only verifies).
# SQL itself is the oracle here: every assertion is a statement whose result is
# fixed by the SQL standard or by SQLite's documented semantics, so agreement
# is evidence about the wrapped engine rather than about the wrapper's opinion.
#   - prepared statements: bind/step/column across every storage class,
#     including blobs, NULs inside TEXT, and 64-bit integer edges
#   - the SQLITE_STATIC vs SQLITE_TRANSIENT lifetime contract, which is the
#     easiest way to get a use-after-free out of this API
#   - Julia @cfunction callbacks driven BY C: exec row callbacks, a
#     user-defined SQL function, a busy handler
#   - transactions, rollback, constraint violation and error reporting
#   - sqlite3_mprintf ownership (owned char* copied and freed via sqlite3_free)
#   - Tier-1 liveness and churn under GC pressure
#
# Usage:  julia --project=/path/to/RepliBuild.jl packages/sqlite/test_deep.jl

using Test
using InteractiveUtils: code_typed

const PKG_DIR = @__DIR__
const WRAPPER = joinpath(PKG_DIR, "julia", "Sqlite.jl")

if !isfile(WRAPPER)
    @info "Wrapper missing — building first"
    using RepliBuild
    RepliBuild.build(joinpath(PKG_DIR, "replibuild.toml"))
    RepliBuild.wrap(joinpath(PKG_DIR, "replibuild.toml"))
end

include(WRAPPER)

const S = Sqlite

# ── Helpers ──────────────────────────────────────────────────────────────────

"Open an in-memory database, run `f(db)`, always close."
function withdb(f)
    pdb = Ref{Ptr{S.sqlite3}}(C_NULL)
    rc = S.sqlite3_open(":memory:", pdb)
    rc == S.SQLITE_OK() || error("open failed: $rc")
    db = pdb[]
    try
        return f(db)
    finally
        S.sqlite3_close(db)
    end
end

"Run SQL with no result rows; raise with the engine's own message on failure."
function exec!(db, sql)
    rc = S.sqlite3_exec(db, sql, C_NULL, C_NULL, C_NULL)
    rc == S.SQLITE_OK() || error("exec failed ($rc): $(S.sqlite3_errmsg(db)) — $sql")
    return rc
end

"Prepare `sql`, run `f(stmt)`, always finalize."
function withstmt(f, db, sql)
    pstmt = Ref{Ptr{S.sqlite3_stmt}}(C_NULL)
    rc = S.sqlite3_prepare_v2(db, sql, -1, pstmt, C_NULL)
    rc == S.SQLITE_OK() || error("prepare failed ($rc): $(S.sqlite3_errmsg(db)) — $sql")
    stmt = pstmt[]
    try
        return f(stmt)
    finally
        S.sqlite3_finalize(stmt)
    end
end

coltext(stmt, i) = (p = S.sqlite3_column_text(stmt, i);
                    p == C_NULL ? nothing : unsafe_string(Ptr{UInt8}(p)))

"Collect a single-column query as a Vector."
function query1(db, sql, get = (st) -> S.sqlite3_column_int64(st, 0))
    out = []
    withstmt(db, sql) do st
        while S.sqlite3_step(st) == S.SQLITE_ROW()
            push!(out, get(st))
        end
    end
    return out
end

# ── C callbacks (must be top-level, non-closure, for @cfunction) ─────────────

const EXEC_ROWS = Vector{Vector{Union{String,Nothing}}}()

# sqlite3_exec callback: (void*, int ncol, char** values, char** names) -> int
function exec_cb(::Ptr{Cvoid}, ncol::Cint, vals::Ptr{Ptr{UInt8}}, ::Ptr{Ptr{UInt8}})::Cint
    row = Union{String,Nothing}[]
    for i in 1:ncol
        p = unsafe_load(vals, i)
        push!(row, p == C_NULL ? nothing : unsafe_string(p))
    end
    push!(EXEC_ROWS, row)
    return Cint(0)
end

# An exec callback that aborts the query by returning non-zero.
const ABORT_AFTER = Ref(2)
const ABORT_SEEN = Ref(0)
function exec_abort_cb(::Ptr{Cvoid}, ::Cint, ::Ptr{Ptr{UInt8}}, ::Ptr{Ptr{UInt8}})::Cint
    ABORT_SEEN[] += 1
    return Cint(ABORT_SEEN[] >= ABORT_AFTER[] ? 1 : 0)
end

# User-defined SQL function: triple(x) -> 3x
function sql_triple(ctx::Ptr{Cvoid}, argc::Cint, argv::Ptr{Ptr{Cvoid}})::Cvoid
    if argc == 1
        v = unsafe_load(argv, 1)
        S.sqlite3_result_int(ctx, 3 * S.sqlite3_value_int(v))
    end
    return nothing
end

# Busy handler: refuse to retry, and count invocations.
const BUSY_CALLS = Ref(0)
function busy_cb(::Ptr{Cvoid}, ::Cint)::Cint
    BUSY_CALLS[] += 1
    return Cint(0)
end

@testset "SQLite Deep Tests" begin

@testset "Library identity and value macros" begin
    @test S.sqlite3_libversion() == "3.53.3"

    @test S.SQLITE_OK() == 0
    @test S.SQLITE_ERROR() == 1
    @test S.SQLITE_BUSY() == 5
    @test S.SQLITE_MISUSE() == 21
    @test S.SQLITE_ROW() == 100
    @test S.SQLITE_DONE() == 101
    @test S.SQLITE_CONSTRAINT() == 19
    @test S.SQLITE_ABORT() == 4
    @test S.SQLITE_NOMEM() == 7

    @test S.SQLITE_INTEGER() == 1
    @test S.SQLITE_FLOAT() == 2
    @test S.SQLITE_TEXT() == 3
    @test S.SQLITE_BLOB() == 4
    @test S.SQLITE_NULL() == 5

    @test S.SQLITE_OPEN_READONLY() == 0x01
    @test S.SQLITE_OPEN_READWRITE() == 0x02
    @test S.SQLITE_OPEN_CREATE() == 0x04
    @test S.SQLITE_UTF8() == 1

    # The two destructor sentinels are pointer-valued macros, not ints.
    @test S.SQLITE_STATIC() == Ptr{Cvoid}(0)
    @test S.SQLITE_TRANSIENT() == Ptr{Cvoid}(-1)
end

@testset "Tier-1 slicing is live" begin
    @test !isempty(S.TIER1_FUNCTIONS)
    slices_dir = joinpath(PKG_DIR, "julia", "slices")
    @test isdir(slices_dir)
    lls = filter(f -> endswith(f, ".ll"), readdir(slices_dir))
    @test length(lls) == length(S.TIER1_FUNCTIONS)
    @test length(lls) > 200

    @test S.dispatch_tier(:sqlite3_column_count) === :tier1
    @test S.dispatch_tier(:sqlite3_bind_int) === :tier1
    @test S.dispatch_tier(:sqlite3_bind_int64) === :tier1

    # Cstring returns can never be Tier 1, so errmsg/libversion stay ccall —
    # every test below is therefore a mixed-tier run.
    @test !("sqlite3_errmsg" in S.TIER1_FUNCTIONS)
    @test !("sqlite3_libversion" in S.TIER1_FUNCTIONS)
end

@testset "Basic DDL/DML and row counts" begin
    withdb() do db
        exec!(db, "CREATE TABLE t(id INTEGER PRIMARY KEY, name TEXT, score REAL)")
        exec!(db, "INSERT INTO t(name, score) VALUES ('alice', 1.5)")
        @test S.sqlite3_changes(db) == 1
        @test S.sqlite3_last_insert_rowid(db) == 1

        exec!(db, "INSERT INTO t(name, score) VALUES ('bob', 2.5), ('carol', 3.5)")
        @test S.sqlite3_changes(db) == 2
        @test S.sqlite3_last_insert_rowid(db) == 3
        @test S.sqlite3_total_changes(db) == 3

        @test query1(db, "SELECT COUNT(*) FROM t") == [3]
        @test query1(db, "SELECT id FROM t ORDER BY id") == [1, 2, 3]

        exec!(db, "UPDATE t SET score = score * 2")
        @test S.sqlite3_changes(db) == 3
        @test query1(db, "SELECT CAST(SUM(score) AS INTEGER) FROM t") == [15]

        exec!(db, "DELETE FROM t WHERE name = 'bob'")
        @test S.sqlite3_changes(db) == 1
        @test query1(db, "SELECT COUNT(*) FROM t") == [2]
    end
end

@testset "Prepared statements: bind, step, column, reset" begin
    withdb() do db
        exec!(db, "CREATE TABLE v(i INTEGER, r REAL, s TEXT, b BLOB, n)")

        blob = UInt8[0x00, 0xff, 0x10, 0x00, 0x7f]
        withstmt(db, "INSERT INTO v VALUES (?, ?, ?, ?, ?)") do st
            @test S.sqlite3_bind_parameter_count(st) == 5

            @test S.sqlite3_bind_int64(st, 1, typemax(Int64)) == S.SQLITE_OK()
            @test S.sqlite3_bind_double(st, 2, 2.5) == S.SQLITE_OK()
            @test S.sqlite3_bind_text(st, 3, "héllo", -1, S.SQLITE_TRANSIENT()) == S.SQLITE_OK()
            @test S.sqlite3_bind_blob(st, 4, blob, length(blob), S.SQLITE_TRANSIENT()) == S.SQLITE_OK()
            @test S.sqlite3_bind_null(st, 5) == S.SQLITE_OK()

            @test S.sqlite3_step(st) == S.SQLITE_DONE()
            @test S.sqlite3_reset(st) == S.SQLITE_OK()

            # Reset keeps bindings; clear_bindings drops them to NULL.
            @test S.sqlite3_clear_bindings(st) == S.SQLITE_OK()
            @test S.sqlite3_step(st) == S.SQLITE_DONE()
        end

        withstmt(db, "SELECT i, r, s, b, n FROM v ORDER BY rowid") do st
            @test S.sqlite3_column_count(st) == 5
            @test S.sqlite3_column_name(st, 0) == "i"
            @test S.sqlite3_column_name(st, 4) == "n"
            @test S.sqlite3_column_decltype(st, 0) == "INTEGER"
            @test S.sqlite3_column_decltype(st, 4) === nothing   # no declared type

            @test S.sqlite3_step(st) == S.SQLITE_ROW()
            @test S.sqlite3_column_type(st, 0) == S.SQLITE_INTEGER()
            @test S.sqlite3_column_int64(st, 0) == typemax(Int64)
            @test S.sqlite3_column_type(st, 1) == S.SQLITE_FLOAT()
            @test S.sqlite3_column_double(st, 1) == 2.5
            @test S.sqlite3_column_type(st, 2) == S.SQLITE_TEXT()
            @test coltext(st, 2) == "héllo"
            @test S.sqlite3_column_bytes(st, 2) == ncodeunits("héllo")

            @test S.sqlite3_column_type(st, 3) == S.SQLITE_BLOB()
            n = S.sqlite3_column_bytes(st, 3)
            @test n == length(blob)
            p = S.sqlite3_column_blob(st, 3)
            @test p != C_NULL
            @test copy(unsafe_wrap(Vector{UInt8}, Ptr{UInt8}(p), n; own = false)) == blob

            @test S.sqlite3_column_type(st, 4) == S.SQLITE_NULL()

            # The second row was inserted after clear_bindings: all NULL.
            @test S.sqlite3_step(st) == S.SQLITE_ROW()
            for c in 0:4
                @test S.sqlite3_column_type(st, c) == S.SQLITE_NULL()
            end
            @test S.sqlite3_step(st) == S.SQLITE_DONE()
        end
    end
end

@testset "Named parameters" begin
    withdb() do db
        exec!(db, "CREATE TABLE p(a, b)")
        withstmt(db, "INSERT INTO p VALUES (:alpha, \$beta)") do st
            @test S.sqlite3_bind_parameter_count(st) == 2
            ia = S.sqlite3_bind_parameter_index(st, ":alpha")
            ib = S.sqlite3_bind_parameter_index(st, "\$beta")
            @test ia == 1 && ib == 2
            @test S.sqlite3_bind_parameter_name(st, 1) == ":alpha"
            @test S.sqlite3_bind_parameter_name(st, 2) == "\$beta"
            @test S.sqlite3_bind_parameter_index(st, ":missing") == 0

            S.sqlite3_bind_int(st, ia, 11)
            S.sqlite3_bind_int(st, ib, 22)
            @test S.sqlite3_step(st) == S.SQLITE_DONE()
        end
        @test query1(db, "SELECT a FROM p") == [11]
        @test query1(db, "SELECT b FROM p") == [22]
    end
end

@testset "SQLITE_STATIC vs SQLITE_TRANSIENT lifetime contract" begin
    withdb() do db
        exec!(db, "CREATE TABLE life(s TEXT)")

        # TRANSIENT tells SQLite to copy immediately, so the source buffer may
        # die right after the bind. This is the safe default from Julia, where
        # we cannot promise a GC-managed buffer outlives the statement.
        withstmt(db, "INSERT INTO life VALUES (?)") do st
            let tmp = collect(codeunits("copied at bind time"))
                GC.@preserve tmp begin
                    S.sqlite3_bind_text(st, 1, pointer(tmp), length(tmp), S.SQLITE_TRANSIENT())
                end
                S.sqlite3_step(st)
            end
        end
        GC.gc(); GC.gc()
        @test query1(db, "SELECT s FROM life", st -> coltext(st, 0)) == ["copied at bind time"]

        # STATIC promises the buffer outlives the statement — legal only while
        # we keep it alive ourselves, which GC.@preserve across the whole
        # bind/step/finalize window does.
        held = collect(codeunits("borrowed, not copied"))
        GC.@preserve held begin
            withstmt(db, "INSERT INTO life VALUES (?)") do st
                S.sqlite3_bind_text(st, 1, pointer(held), length(held), S.SQLITE_STATIC())
                @test S.sqlite3_step(st) == S.SQLITE_DONE()
            end
        end
        GC.gc()
        @test sort(query1(db, "SELECT s FROM life ORDER BY rowid", st -> coltext(st, 0))) ==
              ["borrowed, not copied", "copied at bind time"]
    end
end

@testset "Text with embedded NULs and explicit lengths" begin
    withdb() do db
        exec!(db, "CREATE TABLE n(s TEXT)")
        payload = UInt8[UInt8('a'), 0x00, UInt8('b')]
        withstmt(db, "INSERT INTO n VALUES (?)") do st
            GC.@preserve payload begin
                # Passing an explicit length is what makes the NUL data rather
                # than a terminator.
                S.sqlite3_bind_text(st, 1, pointer(payload), length(payload), S.SQLITE_TRANSIENT())
            end
            @test S.sqlite3_step(st) == S.SQLITE_DONE()
        end
        withstmt(db, "SELECT s, length(s) FROM n") do st
            @test S.sqlite3_step(st) == S.SQLITE_ROW()
            @test S.sqlite3_column_bytes(st, 0) == 3
            p = S.sqlite3_column_text(st, 0)
            bytes = copy(unsafe_wrap(Vector{UInt8}, Ptr{UInt8}(p), 3; own = false))
            @test bytes == payload
        end
    end
end

@testset "Integer and float edge cases" begin
    withdb() do db
        exec!(db, "CREATE TABLE e(v)")
        vals = Int64[0, -1, 1, typemax(Int64), typemin(Int64), 2^53, -(2^53)]
        withstmt(db, "INSERT INTO e VALUES (?)") do st
            for v in vals
                S.sqlite3_bind_int64(st, 1, v)
                @test S.sqlite3_step(st) == S.SQLITE_DONE()
                S.sqlite3_reset(st)
            end
        end
        @test query1(db, "SELECT v FROM e ORDER BY rowid") == vals

        exec!(db, "CREATE TABLE f(v REAL)")
        fvals = [0.0, -0.0, 1.5, -2.25, 1e300, 1e-300]
        withstmt(db, "INSERT INTO f VALUES (?)") do st
            for v in fvals
                S.sqlite3_bind_double(st, 1, v)
                S.sqlite3_step(st); S.sqlite3_reset(st)
            end
        end
        got = query1(db, "SELECT v FROM f ORDER BY rowid", st -> S.sqlite3_column_double(st, 0))
        @test got == fvals
    end
end

@testset "Transactions, rollback, constraints" begin
    withdb() do db
        exec!(db, "CREATE TABLE tx(id INTEGER PRIMARY KEY, u TEXT UNIQUE NOT NULL)")
        exec!(db, "INSERT INTO tx(u) VALUES ('one')")

        exec!(db, "BEGIN")
        exec!(db, "INSERT INTO tx(u) VALUES ('two')")
        @test query1(db, "SELECT COUNT(*) FROM tx") == [2]
        exec!(db, "ROLLBACK")
        @test query1(db, "SELECT COUNT(*) FROM tx") == [1]

        exec!(db, "BEGIN")
        exec!(db, "INSERT INTO tx(u) VALUES ('three')")
        exec!(db, "COMMIT")
        @test query1(db, "SELECT COUNT(*) FROM tx") == [2]

        # UNIQUE violation is reported, not silently dropped.
        rc = S.sqlite3_exec(db, "INSERT INTO tx(u) VALUES ('one')", C_NULL, C_NULL, C_NULL)
        @test rc == S.SQLITE_CONSTRAINT()
        @test occursin("UNIQUE", S.sqlite3_errmsg(db))
        @test query1(db, "SELECT COUNT(*) FROM tx") == [2]

        # NOT NULL violation likewise.
        rc2 = S.sqlite3_exec(db, "INSERT INTO tx(u) VALUES (NULL)", C_NULL, C_NULL, C_NULL)
        @test rc2 == S.SQLITE_CONSTRAINT()
        @test occursin("NOT NULL", S.sqlite3_errmsg(db))
    end
end

@testset "Errors and misuse" begin
    withdb() do db
        # A syntax error surfaces at prepare time with a real message.
        pstmt = Ref{Ptr{S.sqlite3_stmt}}(C_NULL)
        rc = S.sqlite3_prepare_v2(db, "SELECT FROM WHERE", -1, pstmt, C_NULL)
        @test rc != S.SQLITE_OK()
        @test occursin("syntax error", S.sqlite3_errmsg(db))

        # An unknown table is an error, and errmsg names it.
        rc2 = S.sqlite3_exec(db, "SELECT * FROM nonexistent", C_NULL, C_NULL, C_NULL)
        @test rc2 == S.SQLITE_ERROR()
        @test occursin("nonexistent", S.sqlite3_errmsg(db))

        # pzTail reports where a multi-statement string stopped.
        tail = Ref{Ptr{UInt8}}(C_NULL)
        sql = "SELECT 1; SELECT 2;"
        p2 = Ref{Ptr{S.sqlite3_stmt}}(C_NULL)
        GC.@preserve sql begin
            @test S.sqlite3_prepare_v2(db, sql, -1, p2, tail) == S.SQLITE_OK()
            @test tail[] != C_NULL
            @test strip(unsafe_string(tail[])) == "SELECT 2;"
        end
        S.sqlite3_finalize(p2[])
    end
end

@testset "Julia @cfunction callbacks driven by SQLite" begin
    withdb() do db
        exec!(db, "CREATE TABLE cb(a INTEGER, b TEXT)")
        exec!(db, "INSERT INTO cb VALUES (1,'one'),(2,'two'),(3,NULL)")

        # exec row callback
        empty!(EXEC_ROWS)
        cf = @cfunction(exec_cb, Cint, (Ptr{Cvoid}, Cint, Ptr{Ptr{UInt8}}, Ptr{Ptr{UInt8}}))
        @test S.sqlite3_exec(db, "SELECT a, b FROM cb ORDER BY a", cf, C_NULL, C_NULL) ==
              S.SQLITE_OK()
        @test length(EXEC_ROWS) == 3
        @test EXEC_ROWS[1] == ["1", "one"]
        @test EXEC_ROWS[3] == ["3", nothing]      # NULL arrives as a NULL pointer

        # A callback returning non-zero aborts the query with SQLITE_ABORT.
        ABORT_SEEN[] = 0
        acf = @cfunction(exec_abort_cb, Cint, (Ptr{Cvoid}, Cint, Ptr{Ptr{UInt8}}, Ptr{Ptr{UInt8}}))
        rc = S.sqlite3_exec(db, "SELECT a FROM cb ORDER BY a", acf, C_NULL, C_NULL)
        @test rc == S.SQLITE_ABORT()
        @test ABORT_SEEN[] == 2

        # A user-defined SQL function implemented in Julia.
        fcf = @cfunction(sql_triple, Cvoid, (Ptr{Cvoid}, Cint, Ptr{Ptr{Cvoid}}))
        @test S.sqlite3_create_function(db, "triple", 1,
                                        S.SQLITE_UTF8() | S.SQLITE_DETERMINISTIC(),
                                        C_NULL, fcf, C_NULL, C_NULL) == S.SQLITE_OK()
        @test query1(db, "SELECT triple(7)") == [21]
        @test query1(db, "SELECT triple(a) FROM cb ORDER BY a") == [3, 6, 9]
        # ...and it composes inside real SQL.
        @test query1(db, "SELECT SUM(triple(a)) FROM cb") == [18]

        # A busy handler can be installed and removed without upsetting anything.
        BUSY_CALLS[] = 0
        bcf = @cfunction(busy_cb, Cint, (Ptr{Cvoid}, Cint))
        @test S.sqlite3_busy_handler(db, bcf, C_NULL) == S.SQLITE_OK()
        @test query1(db, "SELECT COUNT(*) FROM cb") == [3]
        @test S.sqlite3_busy_handler(db, C_NULL, C_NULL) == S.SQLITE_OK()
    end
end

@testset "sqlite3_mprintf ownership" begin
    # mprintf returns a buffer allocated by sqlite3_malloc. The wrapper copies
    # it into a Julia String and frees it through sqlite3_free
    # ([wrap.cstring_owned]) — without that every call here would leak.
    @test S.sqlite3_mprintf("plain") == "plain"
    @test S.sqlite3_mprintf_Cint("n=%d", Cint(-7)) == "n=-7"
    @test S.sqlite3_mprintf_Cdouble("f=%.2f", 2.5) == "f=2.50"

    name = "o'brien"
    GC.@preserve name begin
        # %q is SQLite's SQL-escaping conversion: the quote must be doubled.
        @test S.sqlite3_mprintf_Cstring("%q", Cstring(pointer(name))) == "o''brien"
        @test S.sqlite3_mprintf_Cstring("%s", Cstring(pointer(name))) == "o'brien"
        @test S.sqlite3_mprintf_Cstring_Cint("%s#%d", Cstring(pointer(name)), Cint(3)) ==
              "o'brien#3"
    end

    # Hammer it: a leak here is silent, so run enough iterations that a missing
    # free would be visible as growth rather than a single stray allocation.
    for i in 1:20_000
        s = S.sqlite3_mprintf_Cint("row %d", Cint(i))
        @assert s == "row $i"
    end
    @test true
end

@testset "Extensions compiled in" begin
    withdb() do db
        # The TOML enables FTS5 and RTREE; if those defines were dropped the
        # CREATE statements below fail, which is a much better signal than
        # discovering it in a consumer.
        @test S.sqlite3_exec(db, "CREATE VIRTUAL TABLE ft USING fts5(body)",
                             C_NULL, C_NULL, C_NULL) == S.SQLITE_OK()
        exec!(db, "INSERT INTO ft(body) VALUES ('the quick brown fox')")
        exec!(db, "INSERT INTO ft(body) VALUES ('lazy dogs sleep')")
        @test query1(db, "SELECT COUNT(*) FROM ft WHERE ft MATCH 'quick'") == [1]
        @test query1(db, "SELECT COUNT(*) FROM ft WHERE ft MATCH 'dogs'") == [1]
        @test query1(db, "SELECT COUNT(*) FROM ft WHERE ft MATCH 'absent'") == [0]

        @test S.sqlite3_exec(db, "CREATE VIRTUAL TABLE rt USING rtree(id, minX, maxX, minY, maxY)",
                             C_NULL, C_NULL, C_NULL) == S.SQLITE_OK()
        exec!(db, "INSERT INTO rt VALUES (1, 0.0, 1.0, 0.0, 1.0)")
        exec!(db, "INSERT INTO rt VALUES (2, 5.0, 6.0, 5.0, 6.0)")
        @test query1(db, "SELECT id FROM rt WHERE minX >= 4.0") == [2]

        # SQLITE_DQS=0 means a double-quoted string is an IDENTIFIER only —
        # the misspelled-column footgun is compiled out.
        exec!(db, "CREATE TABLE dq(a)")
        rc = S.sqlite3_exec(db, "SELECT \"no_such_column\" FROM dq", C_NULL, C_NULL, C_NULL)
        @test rc != S.SQLITE_OK()
    end
end

@testset "Churn and GC stress" begin
    # Open/populate/query/close many independent databases with Julia GC
    # interleaved. A slice bound to a stale symbol, or a mishandled owned
    # string, tends to surface as corruption here rather than as a clean error.
    for i in 1:200
        withdb() do db
            exec!(db, "CREATE TABLE c(k INTEGER, v TEXT)")
            withstmt(db, "INSERT INTO c VALUES (?, ?)") do st
                for k in 1:50
                    S.sqlite3_bind_int(st, 1, k * i)
                    S.sqlite3_bind_text(st, 2, "v$k", -1, S.SQLITE_TRANSIENT())
                    @assert S.sqlite3_step(st) == S.SQLITE_DONE()
                    S.sqlite3_reset(st)
                end
            end
            @assert query1(db, "SELECT COUNT(*) FROM c") == [50]
            @assert query1(db, "SELECT SUM(k) FROM c") == [sum(1:50) * i]
        end
        iszero(i % 50) && GC.gc()
    end
    @test true

    # Hammer the Tier-1 column/bind path inside one long-lived database.
    withdb() do db
        exec!(db, "CREATE TABLE h(i INTEGER)")
        exec!(db, "BEGIN")
        withstmt(db, "INSERT INTO h VALUES (?)") do st
            for i in 1:20_000
                S.sqlite3_bind_int64(st, 1, i)
                @assert S.sqlite3_step(st) == S.SQLITE_DONE()
                S.sqlite3_reset(st)
            end
        end
        exec!(db, "COMMIT")
        @test query1(db, "SELECT COUNT(*) FROM h") == [20_000]
        @test query1(db, "SELECT SUM(i) FROM h") == [sum(1:20_000)]
        GC.gc()
    end
end

end  # top-level testset
