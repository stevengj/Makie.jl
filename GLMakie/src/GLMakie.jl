module GLMakie

if isdefined(Base, :Experimental) && isdefined(Base.Experimental, Symbol("@max_methods"))
    # GLMakie doesn't do much work, besides assembling shaders.
    # If it does, code should be 100% inferable, so hopefully shouldn't be influenced by this
    @eval Base.Experimental.@max_methods 1
end

using ModernGL, FixedPointNumbers, Colors, GeometryBasics
using Makie, FileIO

using Makie: @key_str, Key, broadcast_foreach, to_ndim, NativeFont
using Makie: Scene, Lines, Text, Image, Heatmap, Scatter
using Makie: convert_attribute, @extractvalue, LineSegments
using Makie: @get_attribute, to_value, to_colormap, extrema_nan
using Makie: ClosedInterval, (..)
using Makie: to_native
using Makie: spaces, is_data_space, is_pixel_space, is_relative_space, is_clip_space
import Makie: to_font, el32convert, Shape, CIRCLE, RECTANGLE, ROUNDED_RECTANGLE, DISTANCEFIELD, TRIANGLE
import Makie: RelocatableFolders

using ShaderAbstractions
using FreeTypeAbstraction
using GeometryBasics: StaticVector
using Observables

using Base: RefValue
import Base: push!, isopen, show
using Base.Iterators: repeated, drop

using LinearAlgebra

# re-export Makie, including deprecated names
for name in names(Makie, all=true)
    if Base.isexported(Makie, name)
        @eval using Makie: $(name)
        @eval export $(name)
    end
end

import ShaderAbstractions: Sampler, Buffer
export Sampler, Buffer

const GL_ASSET_DIR = RelocatableFolders.@path joinpath(@__DIR__, "..", "assets")
const SHADER_DIR = RelocatableFolders.@path joinpath(GL_ASSET_DIR, "shader")
const LOADED_SHADERS = Dict{String, String}()

function loadshader(name)
    # Turns out, joinpath is so slow, that it actually makes sense
    # To memoize it :-O
    # when creating 1000 plots with the PlotSpec API, timing drop from 1.5s to 1s just from this change:
    return get!(LOADED_SHADERS, name) do
        return joinpath(SHADER_DIR, name)
    end
end

gl_texture_atlas() = Makie.get_texture_atlas(2048, 64)

# don't put this into try catch, to not mess with normal errors
include("gl_backend.jl")

function __init__()
    activate!()
end

include("precompiles.jl")

end
