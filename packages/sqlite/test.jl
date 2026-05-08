#!/usr/bin/env julia
# SQLite Hub package — integration test
#
# Tests the full RepliBuild pipeline for SQLite 3.51.1:
#   clean → build → load wrapper → exercise API
#
# Usage:  julia --project=/path/to/RepliBuild.jl packages/sqlite/test.jl

using Test
using RepliBuild

const PKG_DIR = @__DIR__
const TOML_PATH = joinpath(PKG_DIR, "replibuild.toml")

# ── Build ────────────────────────────────────────────────────────────────────

@testset "SQLite Hub Package" begin

@testset "Build pipeline" begin
    RepliBuild.clean(TOML_PATH)
    lib = RepliBuild.build(TOML_PATH)
    @test isfile(lib)
    @test endswith(lib, "libsqlite.so") || endswith(lib, "libsqlite.dylib")

    julia_dir = joinpath(PKG_DIR, "julia")
    @test isfile(joinpath(julia_dir, "compilation_metadata.json"))

    wrapper = RepliBuild.wrap(TOML_PATH)
    @test isfile(wrapper)
    @test isfile(joinpath(julia_dir, "Sqlite.jl"))
end

# ── Load wrapper ─────────────────────────────────────────────────────────────

include(joinpath(PKG_DIR, "julia", "Sqlite.jl"))

@testset "Module structure" begin
    # Core API functions
    @test isdefined(Sqlite, :sqlite3_open)
    @test isdefined(Sqlite, :sqlite3_close)
    @test isdefined(Sqlite, :sqlite3_close_v2)
    @test isdefined(Sqlite, :sqlite3_exec)
    @test isdefined(Sqlite, :sqlite3_prepare_v2)
    @test isdefined(Sqlite, :sqlite3_step)
    @test isdefined(Sqlite, :sqlite3_finalize)
    @test isdefined(Sqlite, :sqlite3_errmsg)
    @test isdefined(Sqlite, :sqlite3_free)
    @test isdefined(Sqlite, :sqlite3_libversion)

    # Column accessors
    @test isdefined(Sqlite, :sqlite3_column_count)
    @test isdefined(Sqlite, :sqlite3_column_int)
    @test isdefined(Sqlite, :sqlite3_column_int64)
    @test isdefined(Sqlite, :sqlite3_column_double)
    @test isdefined(Sqlite, :sqlite3_column_text)
    @test isdefined(Sqlite, :sqlite3_column_blob)
    @test isdefined(Sqlite, :sqlite3_column_bytes)
    @test isdefined(Sqlite, :sqlite3_column_type)
    @test isdefined(Sqlite, :sqlite3_column_name)

    # Bind functions
    @test isdefined(Sqlite, :sqlite3_bind_int)
    @test isdefined(Sqlite, :sqlite3_bind_int64)
    @test isdefined(Sqlite, :sqlite3_bind_double)
    @test isdefined(Sqlite, :sqlite3_bind_text)
    @test isdefined(Sqlite, :sqlite3_bind_null)

    # Macro shims (result codes)
    @test isdefined(Sqlite, :SQLITE_OK)
    @test isdefined(Sqlite, :SQLITE_ERROR)
    @test isdefined(Sqlite, :SQLITE_ROW)
    @test isdefined(Sqlite, :SQLITE_DONE)
    @test isdefined(Sqlite, :SQLITE_BUSY)
    @test isdefined(Sqlite, :SQLITE_CONSTRAINT)

    # Type codes
    @test isdefined(Sqlite, :SQLITE_INTEGER)
    @test isdefined(Sqlite, :SQLITE_FLOAT)
    @test isdefined(Sqlite, :SQLITE_TEXT)
    @test isdefined(Sqlite, :SQLITE_BLOB)
    @test isdefined(Sqlite, :SQLITE_NULL)

    # Open flags
    @test isdefined(Sqlite, :SQLITE_OPEN_READONLY)
    @test isdefined(Sqlite, :SQLITE_OPEN_READWRITE)
    @test isdefined(Sqlite, :SQLITE_OPEN_CREATE)
    @test isdefined(Sqlite, :SQLITE_OPEN_MEMORY)

    # Destructor sentinels
    @test isdefined(Sqlite, :SQLITE_STATIC)
    @test isdefined(Sqlite, :SQLITE_TRANSIENT)

    # Varargs overloads
    @test isdefined(Sqlite, :sqlite3_mprintf)
    @test isdefined(Sqlite, :sqlite3_mprintf_Cstring)
    @test isdefined(Sqlite, :sqlite3_mprintf_Cint)
    @test isdefined(Sqlite, :sqlite3_mprintf_Cdouble)
    @test isdefined(Sqlite, :sqlite3_mprintf_Cstring_Cint)

    # Metadata
    @test haskey(Sqlite.METADATA, "llvm_version")
    @test haskey(Sqlite.METADATA, "target_triple")
    @test Sqlite.METADATA["function_count"] >= 200
end

# ── Helper: open an in-memory database ──────────────────────────────────────

function open_memory_db()
    db_handle = Ref{Ptr{Sqlite.sqlite3}}(C_NULL)
    rc = Sqlite.sqlite3_open(":memory:", db_handle)
    @assert rc == Sqlite.SQLITE_OK() "sqlite3_open failed: $rc"
    return db_handle[]
end

function exec!(db, sql)
    errmsg = Ref{Ptr{UInt8}}(C_NULL)
    rc = Sqlite.sqlite3_exec(db, sql, C_NULL, C_NULL, errmsg)
    if rc != Sqlite.SQLITE_OK()
        msg = errmsg[] != C_NULL ? unsafe_string(errmsg[]) : "unknown error"
        Sqlite.sqlite3_free(errmsg[])
        error("sqlite3_exec failed ($rc): $msg")
    end
    return rc
end

# ── API tests ────────────────────────────────────────────────────────────────

@testset "Library version" begin
    ver = Sqlite.sqlite3_libversion()
    @test startswith(ver, "3.")
    @test occursin('.', ver)  # version string like "3.x.y"
end

@testset "Result code values" begin
    @test Sqlite.SQLITE_OK() == 0
    @test Sqlite.SQLITE_ERROR() == 1
    @test Sqlite.SQLITE_ROW() == 100
    @test Sqlite.SQLITE_DONE() == 101
end

@testset "Open and close (in-memory)" begin
    db = open_memory_db()
    @test db != C_NULL
    @test Sqlite.sqlite3_close(db) == Sqlite.SQLITE_OK()
end

@testset "Exec: CREATE, INSERT, error handling" begin
    db = open_memory_db()

    # CREATE TABLE
    exec!(db, "CREATE TABLE t1 (id INTEGER PRIMARY KEY, name TEXT)")

    # INSERT
    exec!(db, "INSERT INTO t1 VALUES (1, 'alice')")
    exec!(db, "INSERT INTO t1 VALUES (2, 'bob')")

    # changes() after insert
    @test Sqlite.sqlite3_changes(db) == 1

    # Duplicate PK → SQLITE_CONSTRAINT
    errmsg = Ref{Ptr{UInt8}}(C_NULL)
    rc = Sqlite.sqlite3_exec(db, "INSERT INTO t1 VALUES (1, 'duplicate')", C_NULL, C_NULL, errmsg)
    @test rc != Sqlite.SQLITE_OK()
    if errmsg[] != C_NULL
        Sqlite.sqlite3_free(errmsg[])
    end

    # errmsg after error
    msg = Sqlite.sqlite3_errmsg(db)
    @test occursin("UNIQUE", uppercase(msg)) || occursin("PRIMARY", uppercase(msg))

    Sqlite.sqlite3_close(db)
end

@testset "Prepare / step / finalize" begin
    db = open_memory_db()
    exec!(db, "CREATE TABLE nums (val INTEGER)")
    exec!(db, "INSERT INTO nums VALUES (10)")
    exec!(db, "INSERT INTO nums VALUES (20)")
    exec!(db, "INSERT INTO nums VALUES (30)")

    # Prepare a SELECT
    stmt = Ref{Ptr{Sqlite.sqlite3_stmt}}(C_NULL)
    sql = "SELECT val FROM nums ORDER BY val"
    rc = Sqlite.sqlite3_prepare_v2(db, sql, -1, stmt, C_NULL)
    @test rc == Sqlite.SQLITE_OK()
    @test stmt[] != C_NULL

    # Step through rows
    values = Int[]
    while (rc = Sqlite.sqlite3_step(stmt[])) == Sqlite.SQLITE_ROW()
        push!(values, Sqlite.sqlite3_column_int(stmt[], 0))
    end
    @test rc == Sqlite.SQLITE_DONE()
    @test values == [10, 20, 30]

    @test Sqlite.sqlite3_finalize(stmt[]) == Sqlite.SQLITE_OK()
    Sqlite.sqlite3_close(db)
end

@testset "Column types and accessors" begin
    db = open_memory_db()
    exec!(db, "CREATE TABLE types_test (i INTEGER, f REAL, t TEXT, b BLOB, n)")
    exec!(db, "INSERT INTO types_test VALUES (42, 3.14, 'hello', X'DEADBEEF', NULL)")

    stmt = Ref{Ptr{Sqlite.sqlite3_stmt}}(C_NULL)
    rc = Sqlite.sqlite3_prepare_v2(db, "SELECT * FROM types_test", -1, stmt, C_NULL)
    @test rc == Sqlite.SQLITE_OK()

    rc = Sqlite.sqlite3_step(stmt[])
    @test rc == Sqlite.SQLITE_ROW()

    # Column count
    @test Sqlite.sqlite3_column_count(stmt[]) == 5

    # Integer
    @test Sqlite.sqlite3_column_int(stmt[], 0) == 42
    @test Sqlite.sqlite3_column_type(stmt[], 0) == Sqlite.SQLITE_INTEGER()

    # Double
    @test Sqlite.sqlite3_column_double(stmt[], 1) ≈ 3.14
    @test Sqlite.sqlite3_column_type(stmt[], 1) == Sqlite.SQLITE_FLOAT()

    # Text
    text_ptr = Sqlite.sqlite3_column_text(stmt[], 2)
    @test text_ptr != C_NULL
    @test unsafe_string(Ptr{UInt8}(text_ptr)) == "hello"
    @test Sqlite.sqlite3_column_type(stmt[], 2) == Sqlite.SQLITE_TEXT()

    # Blob
    blob_ptr = Sqlite.sqlite3_column_blob(stmt[], 3)
    @test blob_ptr != C_NULL
    blob_len = Sqlite.sqlite3_column_bytes(stmt[], 3)
    @test blob_len == 4
    blob_data = unsafe_wrap(Array, Ptr{UInt8}(blob_ptr), blob_len)
    @test blob_data == UInt8[0xDE, 0xAD, 0xBE, 0xEF]

    # NULL
    @test Sqlite.sqlite3_column_type(stmt[], 4) == Sqlite.SQLITE_NULL()

    # Column names
    @test Sqlite.sqlite3_column_name(stmt[], 0) == "i"
    @test Sqlite.sqlite3_column_name(stmt[], 1) == "f"
    @test Sqlite.sqlite3_column_name(stmt[], 2) == "t"

    Sqlite.sqlite3_finalize(stmt[])
    Sqlite.sqlite3_close(db)
end

@testset "Bind parameters" begin
    db = open_memory_db()
    exec!(db, "CREATE TABLE bound (a INTEGER, b REAL, c TEXT)")

    stmt = Ref{Ptr{Sqlite.sqlite3_stmt}}(C_NULL)
    rc = Sqlite.sqlite3_prepare_v2(db, "INSERT INTO bound VALUES (?, ?, ?)", -1, stmt, C_NULL)
    @test rc == Sqlite.SQLITE_OK()

    # Bind values
    @test Sqlite.sqlite3_bind_int(stmt[], 1, 99) == Sqlite.SQLITE_OK()
    @test Sqlite.sqlite3_bind_double(stmt[], 2, 2.718) == Sqlite.SQLITE_OK()
    text = "world"
    @test Sqlite.sqlite3_bind_text(stmt[], 3, text, -1, Sqlite.SQLITE_TRANSIENT()) == Sqlite.SQLITE_OK()

    @test Sqlite.sqlite3_step(stmt[]) == Sqlite.SQLITE_DONE()
    Sqlite.sqlite3_finalize(stmt[])

    # Verify the row
    stmt2 = Ref{Ptr{Sqlite.sqlite3_stmt}}(C_NULL)
    Sqlite.sqlite3_prepare_v2(db, "SELECT a, b, c FROM bound", -1, stmt2, C_NULL)
    @test Sqlite.sqlite3_step(stmt2[]) == Sqlite.SQLITE_ROW()
    @test Sqlite.sqlite3_column_int(stmt2[], 0) == 99
    @test Sqlite.sqlite3_column_double(stmt2[], 1) ≈ 2.718
    text_ptr = Sqlite.sqlite3_column_text(stmt2[], 2)
    @test unsafe_string(Ptr{UInt8}(text_ptr)) == "world"

    Sqlite.sqlite3_finalize(stmt2[])
    Sqlite.sqlite3_close(db)
end

@testset "Bind NULL" begin
    db = open_memory_db()
    exec!(db, "CREATE TABLE nulltest (v INTEGER)")

    stmt = Ref{Ptr{Sqlite.sqlite3_stmt}}(C_NULL)
    Sqlite.sqlite3_prepare_v2(db, "INSERT INTO nulltest VALUES (?)", -1, stmt, C_NULL)
    @test Sqlite.sqlite3_bind_null(stmt[], 1) == Sqlite.SQLITE_OK()
    @test Sqlite.sqlite3_step(stmt[]) == Sqlite.SQLITE_DONE()
    Sqlite.sqlite3_finalize(stmt[])

    stmt2 = Ref{Ptr{Sqlite.sqlite3_stmt}}(C_NULL)
    Sqlite.sqlite3_prepare_v2(db, "SELECT v FROM nulltest", -1, stmt2, C_NULL)
    @test Sqlite.sqlite3_step(stmt2[]) == Sqlite.SQLITE_ROW()
    @test Sqlite.sqlite3_column_type(stmt2[], 0) == Sqlite.SQLITE_NULL()

    Sqlite.sqlite3_finalize(stmt2[])
    Sqlite.sqlite3_close(db)
end

@testset "Varargs: sqlite3_mprintf" begin
    # No varargs
    ptr = Sqlite.sqlite3_mprintf("hello mprintf")
    @test ptr != C_NULL
    @test unsafe_string(ptr) == "hello mprintf"
    Sqlite.sqlite3_free(Ptr{Cvoid}(ptr))

    # With integer arg
    ptr = Sqlite.sqlite3_mprintf_Cint("%d apples", Cint(42))
    @test unsafe_string(ptr) == "42 apples"
    Sqlite.sqlite3_free(Ptr{Cvoid}(ptr))

    # With string arg (Cstring = Ptr{UInt8}, need GC.@preserve)
    let s = "sqlite"
        GC.@preserve s begin
            ptr = Sqlite.sqlite3_mprintf_Cstring("name=%s", Base.unsafe_convert(Cstring, s))
            @test unsafe_string(ptr) == "name=sqlite"
            Sqlite.sqlite3_free(Ptr{Cvoid}(ptr))
        end
    end

    # With double arg
    ptr = Sqlite.sqlite3_mprintf_Cdouble("pi=%.2f", 3.14)
    @test unsafe_string(ptr) == "pi=3.14"
    Sqlite.sqlite3_free(Ptr{Cvoid}(ptr))
end

@testset "Multiple statements / transactions" begin
    db = open_memory_db()

    exec!(db, """
        CREATE TABLE multi (id INTEGER PRIMARY KEY, val TEXT);
        INSERT INTO multi VALUES (1, 'a');
        INSERT INTO multi VALUES (2, 'b');
        INSERT INTO multi VALUES (3, 'c');
    """)

    stmt = Ref{Ptr{Sqlite.sqlite3_stmt}}(C_NULL)
    Sqlite.sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM multi", -1, stmt, C_NULL)
    Sqlite.sqlite3_step(stmt[])
    @test Sqlite.sqlite3_column_int(stmt[], 0) == 3
    Sqlite.sqlite3_finalize(stmt[])

    # Transaction rollback
    exec!(db, "BEGIN")
    exec!(db, "INSERT INTO multi VALUES (4, 'd')")
    exec!(db, "ROLLBACK")

    Sqlite.sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM multi", -1, stmt, C_NULL)
    Sqlite.sqlite3_step(stmt[])
    @test Sqlite.sqlite3_column_int(stmt[], 0) == 3
    Sqlite.sqlite3_finalize(stmt[])

    # Transaction commit
    exec!(db, "BEGIN")
    exec!(db, "INSERT INTO multi VALUES (4, 'd')")
    exec!(db, "COMMIT")

    Sqlite.sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM multi", -1, stmt, C_NULL)
    Sqlite.sqlite3_step(stmt[])
    @test Sqlite.sqlite3_column_int(stmt[], 0) == 4
    Sqlite.sqlite3_finalize(stmt[])

    Sqlite.sqlite3_close(db)
end

@testset "Int64 values" begin
    db = open_memory_db()
    exec!(db, "CREATE TABLE big (v INTEGER)")

    stmt = Ref{Ptr{Sqlite.sqlite3_stmt}}(C_NULL)
    Sqlite.sqlite3_prepare_v2(db, "INSERT INTO big VALUES (?)", -1, stmt, C_NULL)
    big_val = Int64(2)^40
    @test Sqlite.sqlite3_bind_int64(stmt[], 1, big_val) == Sqlite.SQLITE_OK()
    Sqlite.sqlite3_step(stmt[])
    Sqlite.sqlite3_finalize(stmt[])

    Sqlite.sqlite3_prepare_v2(db, "SELECT v FROM big", -1, stmt, C_NULL)
    Sqlite.sqlite3_step(stmt[])
    @test Sqlite.sqlite3_column_int64(stmt[], 0) == big_val
    Sqlite.sqlite3_finalize(stmt[])

    Sqlite.sqlite3_close(db)
end

@testset "Column metadata" begin
    db = open_memory_db()
    exec!(db, "CREATE TABLE meta_test (id INTEGER PRIMARY KEY, name TEXT NOT NULL)")
    exec!(db, "INSERT INTO meta_test VALUES (1, 'test')")

    stmt = Ref{Ptr{Sqlite.sqlite3_stmt}}(C_NULL)
    Sqlite.sqlite3_prepare_v2(db, "SELECT id, name FROM meta_test", -1, stmt, C_NULL)
    Sqlite.sqlite3_step(stmt[])

    # Column names
    @test Sqlite.sqlite3_column_name(stmt[], 0) == "id"
    @test Sqlite.sqlite3_column_name(stmt[], 1) == "name"

    # Declared types (SQLITE_ENABLE_COLUMN_METADATA)
    @test uppercase(Sqlite.sqlite3_column_decltype(stmt[], 0)) == "INTEGER"
    @test uppercase(Sqlite.sqlite3_column_decltype(stmt[], 1)) == "TEXT"

    # Table name (SQLITE_ENABLE_COLUMN_METADATA)
    @test Sqlite.sqlite3_column_table_name(stmt[], 0) == "meta_test"

    # Origin name
    @test Sqlite.sqlite3_column_origin_name(stmt[], 0) == "id"
    @test Sqlite.sqlite3_column_origin_name(stmt[], 1) == "name"

    Sqlite.sqlite3_finalize(stmt[])
    Sqlite.sqlite3_close(db)
end

@testset "Parameter count and names" begin
    db = open_memory_db()
    exec!(db, "CREATE TABLE params (a INT, b INT, c INT)")

    stmt = Ref{Ptr{Sqlite.sqlite3_stmt}}(C_NULL)
    Sqlite.sqlite3_prepare_v2(db, "INSERT INTO params VALUES (:alpha, :beta, :gamma)", -1, stmt, C_NULL)

    @test Sqlite.sqlite3_bind_parameter_count(stmt[]) == 3
    @test Sqlite.sqlite3_bind_parameter_name(stmt[], 1) == ":alpha"
    @test Sqlite.sqlite3_bind_parameter_name(stmt[], 2) == ":beta"
    @test Sqlite.sqlite3_bind_parameter_name(stmt[], 3) == ":gamma"
    @test Sqlite.sqlite3_bind_parameter_index(stmt[], ":beta") == 2

    Sqlite.sqlite3_finalize(stmt[])
    Sqlite.sqlite3_close(db)
end

end  # top-level testset
