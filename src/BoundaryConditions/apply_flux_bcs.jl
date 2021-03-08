using Oceananigans: instantiated_location

#####
##### Algorithm for adding fluxes associated with non-trivial flux boundary conditions.
##### Value and Gradient boundary conditions are handled by filling halos.
#####

"""
    apply_x_bcs!(Gc, arch, grid, args...)

Apply flux boundary conditions to a field `c` by adding the associated flux divergence to
the source term `Gc` at the left and right.
"""
apply_x_bcs!(Gc, c, arch, dep, args...) = launch!(arch, c.grid, :yz, _apply_x_bcs!, Gc, instantiated_location(Gc), c.grid, 
                                                  c.boundary_conditions.x.left, c.boundary_conditions.x.right, args...,
                                                  dependencies=dep)

"""
    apply_y_bcs!(Gc, arch, grid, args...)

Apply flux boundary conditions to a field `c` by adding the associated flux divergence to
the source term `Gc` at the left and right.
"""
apply_y_bcs!(Gc, c, arch, dep, args...) = launch!(arch, c.grid, :xz, _apply_y_bcs!, Gc, instantiated_location(Gc), c.grid, 
                                                  c.boundary_conditions.y.left, c.boundary_conditions.y.right, args...,
                                                  dependencies=dep)

"""
    apply_z_bcs!(Gc, arch, grid, args...)

Apply flux boundary conditions to a field `c` by adding the associated flux divergence to
the source term `Gc` at the top and bottom.
"""
apply_z_bcs!(Gc, c, arch, dep, args...) = launch!(arch, c.grid, :xy, _apply_z_bcs!, Gc, instantiated_location(Gc), c.grid, 
                                                  c.boundary_conditions.z.left, c.boundary_conditions.z.right, args...,
                                                  dependencies=dep)

"""
    _apply_x_bcs!(Gc, grid, west_bc, east_bc, args...)

Apply a west and/or east boundary condition to variable `c`.
"""
@kernel function _apply_x_bcs!(Gc, loc, grid, west_bc, east_bc, args...)
    j, k = @index(Global, NTuple)
    apply_x_west_bc!(Gc, loc, west_bc, j, k, grid, args...)
    apply_x_east_bc!(Gc, loc, east_bc, j, k, grid, args...)
end

"""
    _apply_y_bcs!(Gc, grid, south_bc, north_bc, args...)

Apply a south and/or north boundary condition to variable `c`.
"""
@kernel function _apply_y_bcs!(Gc, loc, grid, south_bc, north_bc, args...)
    i, k = @index(Global, NTuple)
    apply_y_south_bc!(Gc, loc, south_bc, i, k, grid, args...)
    apply_y_north_bc!(Gc, loc, north_bc, i, k, grid, args...)
end

"""
    _apply_z_bcs!(Gc, grid, bottom_bc, top_bc, args...)

Apply a top and/or bottom boundary condition to variable `c`.
"""
@kernel function _apply_z_bcs!(Gc, loc, grid, bottom_bc, top_bc, args...)
    i, j = @index(Global, NTuple)
    apply_z_bottom_bc!(Gc, loc, bottom_bc, i, j, grid, args...)
       apply_z_top_bc!(Gc, loc, top_bc,    i, j, grid, args...)
end

# Avoid some computation / memory accesses for Value, Gradient, Periodic, NormalFlow,
# and zero-flux boundary conditions --- every boundary condition that does *not* prescribe
# a non-trivial flux.
const NotFluxBC = Union{VBC, GBC, PBC, NFBC, ZFBC}

# Fall back functions for boundary conditions that are not of type Flux.
@inline apply_x_east_bc!(  Gc, args...) = nothing
@inline apply_x_west_bc!(  Gc, args...) = nothing
@inline apply_y_north_bc!( Gc, args...) = nothing
@inline apply_y_south_bc!( Gc, args...) = nothing
@inline apply_z_top_bc!(   Gc, args...) = nothing
@inline apply_z_bottom_bc!(Gc, args...) = nothing

# Shortcuts for 'zero' flux boundary conditions.
@inline apply_x_east_bc!(  Gc, loc, ::ZFBC, args...) = nothing
@inline apply_x_west_bc!(  Gc, loc, ::ZFBC, args...) = nothing
@inline apply_y_north_bc!( Gc, loc, ::ZFBC, args...) = nothing
@inline apply_y_south_bc!( Gc, loc, ::ZFBC, args...) = nothing
@inline apply_z_top_bc!(   Gc, loc, ::ZFBC, args...) = nothing
@inline apply_z_bottom_bc!(Gc, loc, ::ZFBC, args...) = nothing

@inline flip(::Center) = Face()
@inline flip(::Face) = Center()

"""
    apply_x_west_bc!(Gc, west_flux::BC{<:Flux}, j, k, grid, args...)

Add the flux divergence associated with a west flux boundary condition on `c`.
Note that because

    `tendency = ∂c/∂t = Gc = - ∇ ⋅ flux`

a positive west flux is associated with an *increase* in `Gc` near the west boundary.
If `west_bc.condition` is a function, the function must have the signature

    `west_bc.condition(j, k, grid, boundary_condition_args...)`

The same logic holds for south and bottom boundary conditions in `y`, and `z`, respectively.
"""
@inline apply_x_west_bc!(Gc, loc, west_flux::BC{<:Flux}, j, k, grid, args...) =
    @inbounds Gc[1, j, k] += getbc(west_flux,   j, k, grid, args...) /  Δx(1, j, k, grid)

@inline apply_y_south_bc!(Gc, loc, south_flux::BC{<:Flux}, i, k, grid, args...) =
    @inbounds Gc[i, 1, k] += getbc(south_flux,  i, k, grid, args...) /  Δy(i, 1, k, grid)

@inline function apply_z_bottom_bc!(Gc, loc, bottom_flux::BC{<:Flux}, i, j, grid, args...)
    LX, LY, LZ = loc
    flipped_LZ = flip(LZ)
    @inbounds Gc[i, j, 1] += getbc(bottom_flux, i, j, grid, args...) * Az(i, j, 1, grid, LX, LY, flipped_LZ) / volume(i, j, 1, grid, LX, LY, LZ)
    return nothing
end

"""
    apply_x_east_bc!(Gc, top_flux::BC{<:Flux}, j, k, grid, args...)

Add the part of flux divergence associated with a east boundary condition on `c`.
Note that because

    `tendency = ∂c/∂t = Gc = - ∇ ⋅ flux`

a positive east flux is associated with a *decrease* in `Gc` near the east boundary.
If `east_bc.condition` is a function, the function must have the signature

    `east_bc.condition(i, j, grid, boundary_condition_args...)`

The same logic holds for north and top boundary conditions in `y`, and `z`, respectively.
"""
@inline apply_x_east_bc!(Gc, loc, east_flux::BC{<:Flux}, j, k, grid, args...) =
    @inbounds Gc[grid.Nx, j, k] -= getbc(east_flux,  j, k, grid, args...) /  Δx(grid.Nx, j, k, grid)

@inline apply_y_north_bc!(Gc, loc, north_flux::BC{<:Flux}, i, k, grid, args...) =
    @inbounds Gc[i, grid.Ny, k] -= getbc(north_flux, i, k, grid, args...) /  Δy(i, grid.Ny, k, grid)

@inline function apply_z_top_bc!(Gc, loc, top_flux::BC{<:Flux}, i, j, grid, args...)
    LX, LY, LZ = loc
    flipped_LZ = flip(LZ)
    @inbounds Gc[i, j, grid.Nz] -= getbc(top_flux, i, j, grid, args...) * Az(i, j, grid.Nz+1, grid, LX, LY, flipped_LZ) / volume(i, j, grid.Nz, grid, LX, LY, LZ)
    return nothing
end
