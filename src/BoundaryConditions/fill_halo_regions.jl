using OffsetArrays: OffsetArray
using Oceananigans.Architectures: device_event

#####
##### General halo filling functions
#####

fill_halo_regions!(::Nothing, args...) = []
"""
    fill_halo_regions!(fields::Union{Tuple, NamedTuple}, arch, args...)

Fill halo regions for each field in the tuple `fields` according to their boundary
conditions, possibly recursing into `fields` if it is a nested tuple-of-tuples.
"""
function fill_halo_regions!(fields::Union{Tuple, NamedTuple}, arch, args...)

    for field in fields
        fill_halo_regions!(field, arch, args...)
    end

    return nothing
end

# Some fields have `nothing` boundary conditions, such as `FunctionField` and `ZeroField`.
fill_halo_regions!(c::OffsetArray, ::Nothing, args...; kwargs...) = NoneEvent()

"Fill halo regions in x, y, and z for a given field's data."
function fill_halo_regions!(c::OffsetArray, field_bcs, arch, grid, args...; kwargs...)

    barrier = device_event(arch)

    fill_halos! = [
        fill_bottom_and_top_halo!,
        fill_south_and_north_halo!,
        fill_west_and_east_halo!,
    ]

    field_bcs_array_left = [
        field_bcs.bottom,
        field_bcs.south,
        field_bcs.west,
    ]

    field_bcs_array_right = [
        field_bcs.top,
        field_bcs.north,
        field_bcs.east,
    ]

    perm = sortperm(field_bcs_array_left, lt=fill_first)

    fill_halos! = fill_halos![perm]
    field_bcs_array_left  = field_bcs_array_left[perm]
    field_bcs_array_right = field_bcs_array_right[perm]

    for task = 1:3
       fill_halo! = fill_halos![task]
       bc_left    = field_bcs_array_left[task]
       bc_right   = field_bcs_array_right[task]
       events     = fill_halo!(c, bc_left, bc_right, arch, barrier, grid, args...; kwargs...)
       
       if eltype(events) <: Nothing
            events = (NoneEvent(), NoneEvent())
       end

       wait(device(arch), MultiEvent(events))
    end

    return NoneEvent()
end

# Fallbacks split into two calls
function fill_west_and_east_halo!(c, west_bc, east_bc, args...; kwargs...)
     west_event = fill_west_halo!(c, west_bc, args...; kwargs...)
     east_event = fill_east_halo!(c, east_bc, args...; kwargs...)
    multi_event = (west_event, east_event)
    return multi_event
end

function fill_south_and_north_halo!(c, south_bc, north_bc, args...; kwargs...)
    south_event = fill_south_halo!(c, south_bc, args...; kwargs...)
    north_event = fill_north_halo!(c, north_bc, args...; kwargs...)
    multi_event = (south_event, north_event)
    return multi_event
end

function fill_bottom_and_top_halo!(c, bottom_bc, top_bc, args...; kwargs...)
    bottom_event = fill_bottom_halo!(c, bottom_bc, args...; kwargs...)
       top_event = fill_top_halo!(c, top_bc, args...; kwargs...)
     multi_event = (bottom_event, top_event)
    return multi_event
end

#####
##### Halo-filling for nothing boundary conditions
#####

  fill_west_halo!(c, ::Nothing, args...; kwargs...) = NoneEvent()
  fill_east_halo!(c, ::Nothing, args...; kwargs...) = NoneEvent()
 fill_south_halo!(c, ::Nothing, args...; kwargs...) = NoneEvent()
 fill_north_halo!(c, ::Nothing, args...; kwargs...) = NoneEvent()
   fill_top_halo!(c, ::Nothing, args...; kwargs...) = NoneEvent()
fill_bottom_halo!(c, ::Nothing, args...; kwargs...) = NoneEvent()

#####
##### Halo filling order
#####

fill_first(bc1::PBC, bc2)      = false
fill_first(bc1, bc2::PBC)      = true
fill_first(bc1::PBC, bc2::PBC) = true
fill_first(bc1, bc2)           = true
