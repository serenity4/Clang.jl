import CMake_jll: cmake
using Clang.Generators

function build_libbitfield_native()
    @info "Building libbitfield binary with native tools. This will break if CMake fails to find a C compiler"
    success = true
    try
        src_dir = joinpath(@__DIR__, "bitfield")
        build_dir = joinpath(@__DIR__, "build")

        config_cmd = `$(cmake()) -B $build_dir -S $src_dir`
        if Sys.WORD_SIZE == 32
            if Sys.iswindows()
                config_cmd = `$config_cmd -A win32`
            elseif Sys.islinux()
                config_cmd = `$config_cmd -D CMAKE_C_FLAGS='-m32 -march=native'`
            end
        end
        build_cmd = `$(cmake()) --build $build_dir --config Debug`
        install_cmd = `$(cmake()) --install $build_dir --config Debug --prefix $build_dir`

        run(config_cmd)
        run(build_cmd)
        run(install_cmd)
    catch e
        @warn "Building libbitfield with native tools failed" exception=(e, catch_backtrace())
        success = false
    end
    return success
end

function build_libbitfield()
    success = true
    try
        # Compile binary
        if !build_libbitfield_native()
            error("Could not build libbitfield binary. Hint: Deleting `$(joinpath(@__DIR__, "build/"))` may resolve the issue.")
        end

        # Generate wrappers
        @info "Building libbitfield wrapper"
        args = get_default_args()
        headers = joinpath(@__DIR__, "build", "include", "bitfield.h")
        options = load_options(joinpath(@__DIR__, "bitfield", "generate.toml"))
        lib_path = joinpath(@__DIR__, "build", "lib", Sys.iswindows() ? "bitfield.dll" : "libbitfield")
        output_path = joinpath(@__DIR__, "LibBitField.jl")
        options["general"]["library_name"] = "\"$(escape_string(lib_path))\""
        options["general"]["output_file_path"] = output_path
        ctx = create_context(headers, args, options)
        build!(ctx)

        # Call a function to ensure build is successful
        include(output_path)

        m = Base.@invokelatest LibBitField.Mirror(10, 1.5, 1e6, -4, 7, 3)
        Base.@invokelatest LibBitField.toBitfield(Ref(m))
    catch e
        if haskey(ENV, "CI")
            rethrow()
        else
            @warn "Building libbitfield failed: $e"
            success = false
        end
    end
    return success
end

# The actual tests are in this separate function so it's easier to @invokelatest
# all of the new functions.
function test_libbitfield()
    bf = Ref(LibBitField.BitField(Int8(10), 1.5, Int32(1e6), Int32(-4), Int32(7), UInt32(3)))
    m = Ref(LibBitField.Mirror(10, 1.5, 1e6, -4, 7, 3))
    GC.@preserve bf m begin
        pbf = Ptr{LibBitField.BitField}(pointer_from_objref(bf))
        pm = Ptr{LibBitField.Mirror}(pointer_from_objref(m))
        @test LibBitField.toMirror(bf) == m[]
        @test LibBitField.toBitfield(m).a == bf[].a
        @test LibBitField.toBitfield(m).b == bf[].b
        @test LibBitField.toBitfield(m).c == bf[].c
        @test LibBitField.toBitfield(m).d == bf[].d
        @test LibBitField.toBitfield(m).e == bf[].e
        @test LibBitField.toBitfield(m).f == bf[].f
    end
end

@testset "Bitfield" begin
    if build_libbitfield()
        Base.@invokelatest test_libbitfield()
    end
end
