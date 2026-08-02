#!/usr/bin/env julia
# miniaudio Hub package — deep integration test
#
# Assumes the wrapper is already built (this only verifies; it builds on miss).
#
# miniaudio is in the Hub as an ABI stress vehicle, not because Julia needs an
# audio library. Three properties earn it that job, and this file asserts all
# three WITHOUT opening a playback device:
#
#   1. BY-VALUE STRUCT RETURNS. `ma_*_config_init` returns a config struct by
#      value. `ma_waveform_config` is 32 bytes — over the SysV 16-byte
#      threshold, so it is MEMORY class and must travel by hidden sret pointer.
#      Getting that wrong yields garbage fields rather than a crash, which is
#      why every field is checked against what was passed in.
#   2. SCALE. One 95k-line translation unit, ~1180 functions, ~350 types —
#      the largest package in the Hub, and the widest DWARF surface the
#      extractor sees anywhere.
#   3. MIXED-TIER DISPATCH at that scale: ~1080 slices accepted, ~560 emitted
#      as Tier-1 llvmcall, the rest ccall. Both tiers have to agree.
#
# Deliberately device-free. `ma_waveform` + `ma_data_source_read_pcm_frames`
# exercise the same config/struct machinery as the device API while writing
# into a Julia buffer, so the suite is deterministic and runs on a headless
# box. Anything touching ma_device belongs in a separate, opt-in test — see
# the note at the bottom.
#
# Usage:  julia --project=/path/to/RepliBuild.jl packages/miniaudio/test_deep.jl

using Test

const PKG_DIR = @__DIR__
const WRAPPER = joinpath(PKG_DIR, "julia", "Miniaudio.jl")

if !isfile(WRAPPER)
    @info "Wrapper missing — building first"
    using RepliBuild
    RepliBuild.build(joinpath(PKG_DIR, "replibuild.toml"))
    RepliBuild.wrap(joinpath(PKG_DIR, "replibuild.toml"))
end

include(WRAPPER)
using .Miniaudio

const MA_SUCCESS = 0
const SAMPLE_RATE = 48000
const FREQUENCY   = 440.0
const AMPLITUDE   = 0.5

@testset "miniaudio" begin

@testset "Wrapper surface" begin
    # The extractor saw the whole 95k-line TU, not a truncated prefix.
    @test isdefined(Miniaudio, :ma_waveform_config_init)
    @test isdefined(Miniaudio, :ma_waveform_init)
    @test isdefined(Miniaudio, :ma_waveform_uninit)
    @test isdefined(Miniaudio, :ma_data_source_read_pcm_frames)

    # Enums came through as real @enum types, not bare integers.
    @test Int(Miniaudio.ma_format_f32) == 5
    @test Int(Miniaudio.ma_waveform_type_sine) == 0
end

@testset "Struct layout matches C" begin
    # Named fields, not an opaque byte blob — the whole point of DWARF-driven
    # extraction. A blob here would still "work" via ccall and silently lose
    # every field accessor.
    @test fieldnames(Miniaudio.ma_waveform_config) ==
          (:format, :channels, :sampleRate, :type_, :amplitude, :frequency)

    # 4+4+4+4+8+8 = 32 bytes: MEMORY class under SysV (>16), which is what
    # forces the sret convention exercised below.
    @test sizeof(Miniaudio.ma_waveform_config) == 32
    @test sizeof(Miniaudio.ma_waveform_config) > 16

    # Nested struct-by-value member survived as a real field.
    @test :config in fieldnames(Miniaudio.ma_waveform)
    @test fieldtype(Miniaudio.ma_waveform, :config) === Miniaudio.ma_waveform_config
end

@testset "By-value config return (MEMORY-class sret)" begin
    cfg = Miniaudio.ma_waveform_config_init(
        Miniaudio.ma_format_f32, 1, SAMPLE_RATE,
        Miniaudio.ma_waveform_type_sine, AMPLITUDE, FREQUENCY)

    @test cfg isa Miniaudio.ma_waveform_config

    # Every field round-trips. A wrong sret convention shifts arguments by a
    # register and these come back as garbage — the failure this test exists
    # for. Checking all six also catches a partial/shifted copy.
    @test cfg.format     == Miniaudio.ma_format_f32
    @test cfg.channels   == 1
    @test cfg.sampleRate == SAMPLE_RATE
    @test cfg.type_      == Miniaudio.ma_waveform_type_sine
    @test cfg.amplitude  ≈ AMPLITUDE
    @test cfg.frequency  ≈ FREQUENCY

    # Distinct call, distinct values: proves the return isn't a cached or
    # zero-initialized buffer that happens to match the first call.
    cfg2 = Miniaudio.ma_waveform_config_init(
        Miniaudio.ma_format_s16, 2, 44100,
        Miniaudio.ma_waveform_type_square, 0.25, 1000.0)
    @test cfg2.format     == Miniaudio.ma_format_s16
    @test cfg2.channels   == 2
    @test cfg2.sampleRate == 44100
    @test cfg2.type_      == Miniaudio.ma_waveform_type_square
    @test cfg2.amplitude  ≈ 0.25
    @test cfg2.frequency  ≈ 1000.0
end

@testset "Synthesis into a Julia buffer" begin
    cfg = Miniaudio.ma_waveform_config_init(
        Miniaudio.ma_format_f32, 1, SAMPLE_RATE,
        Miniaudio.ma_waveform_type_sine, AMPLITUDE, FREQUENCY)

    wave_ref = Ref(Miniaudio.ma_waveform())
    cfg_ref  = Ref(cfg)

    GC.@preserve wave_ref cfg_ref begin
        rc = Miniaudio.ma_waveform_init(
            Base.unsafe_convert(Ptr{Miniaudio.ma_waveform_config}, cfg_ref),
            Base.unsafe_convert(Ptr{Miniaudio.ma_waveform}, wave_ref))
        @test Int(rc) == MA_SUCCESS

        # 0.1 s of mono f32 — miniaudio writes straight into Julia-owned memory.
        nframes = SAMPLE_RATE ÷ 10
        buf = zeros(Float32, nframes)
        read_ref = Ref{Culonglong}(0)

        GC.@preserve buf read_ref begin
            rc2 = Miniaudio.ma_waveform_read_pcm_frames(
                Base.unsafe_convert(Ptr{Miniaudio.ma_waveform}, wave_ref),
                pointer(buf), nframes,
                Base.unsafe_convert(Ptr{Culonglong}, read_ref))
            @test Int(rc2) == MA_SUCCESS
            @test read_ref[] == nframes
        end

        # It is actually a sine, not zeros or noise:
        @test any(!iszero, buf)                      # something was written
        @test maximum(abs, buf) ≤ AMPLITUDE + 1f-5   # amplitude respected
        @test maximum(buf) > 0.9 * AMPLITUDE         # ...and reached
        @test minimum(buf) < -0.9 * AMPLITUDE

        # Frequency check via zero crossings: 440 Hz over 0.1 s is 44 periods,
        # 2 crossings each ⇒ ~88. This is what distinguishes a correct signal
        # from a plausible-looking wrong one (wrong sample rate, wrong format
        # reinterpretation, half-filled buffer).
        crossings = count(i -> signbit(buf[i]) != signbit(buf[i+1]),
                          1:length(buf)-1)
        @test 85 ≤ crossings ≤ 91

        # Sine starts at phase 0.
        @test abs(buf[1]) < 1f-3

        Miniaudio.ma_waveform_uninit(
            Base.unsafe_convert(Ptr{Miniaudio.ma_waveform}, wave_ref))
    end
end

@testset "Tier-1 dispatch at scale" begin
    # Sliced llvmcall is on for this package; at ~560 emitted kernels this is
    # the largest Tier-1 surface in the Hub.
    @test !isempty(Miniaudio.TIER1_FUNCTIONS)
    @test length(Miniaudio.TIER1_FUNCTIONS) > 400

    # Every emitted kernel has a slice file on disk. A missing slice is not a
    # crash — the @generated kernel silently demotes to ccall — so nothing
    # else in this suite would notice.
    slices_dir = joinpath(PKG_DIR, "julia", "slices")
    @test isdir(slices_dir)
    @test length(filter(f -> endswith(f, ".ll"), readdir(slices_dir))) ≥
          length(Miniaudio.TIER1_FUNCTIONS)

    # Pins the [link] link_libraries fix. These two declare pow/log in their
    # slices and are Tier-1 ONLY because libm is in the .so's DT_NEEDED chain
    # — the pre-flight scopes symbol lookup to the library, so without that
    # line all 51 libm-dependent slices demote to ccall (see the toml).
    # Verified against the pre-flight's own demotion list, not assumed.
    @test "ma_volume_db_to_linear" in Miniaudio.TIER1_FUNCTIONS
    @test "ma_volume_linear_to_db" in Miniaudio.TIER1_FUNCTIONS

    # Note the converse is NOT true: plenty of libm-declaring functions
    # (ma_notch2_reinit, ma_waveform_read_pcm_frames) still dispatch via ccall,
    # demoted by the emission gate rather than the pre-flight. Tier 1 is
    # opportunistic — ~560 of ~1180 functions — and that mix is the point.
    @test !("ma_waveform_read_pcm_frames" in Miniaudio.TIER1_FUNCTIONS)
end

end  # testset

# ── Not covered here, on purpose ─────────────────────────────────────────────
# ma_device_* opens a real playback device and fires ma_device_data_proc on the
# BACKEND's thread (ALSA/PipeWire), not one Julia created. That needs thread
# adoption and a GC-safepoint-free callback, and it tests Julia's foreign-thread
# story as much as it tests this wrapper — a different experiment, and one that
# should run over HDMI on this machine: the ALC897 analog output has confirmed
# GPU-EMI static, and "crackling" is indistinguishable from a real ABI bug by
# ear.
