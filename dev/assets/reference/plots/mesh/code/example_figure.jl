# This file was generated, do not modify it. # hide
using Makie.LaTeXStrings: @L_str # hide
__result = begin # hide
    using FileIO
using GLMakie
GLMakie.activate!() # hide


brain = load(assetpath("brain.stl"))

mesh(
    brain,
    color = [tri[1][2] for tri in brain for i in 1:3],
    colormap = Reverse(:Spectral),
    figure = (size = (1000, 1000),)
)
end # hide
save(joinpath(@OUTPUT, "example_8717661952113808911.png"), __result; ) # hide

nothing # hide