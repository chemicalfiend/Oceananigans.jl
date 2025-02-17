@kernel function _compute_vertically_integrated_lateral_areas!(∫ᶻ_A, grid)
    i, j = @index(Global, NTuple)

    @inbounds begin
        ∫ᶻ_A.xᶠᶜᶜ[i, j, 1] = 0
        ∫ᶻ_A.yᶜᶠᶜ[i, j, 1] = 0

        @unroll for k in 1:grid.Nz
            ∫ᶻ_A.xᶠᶜᶜ[i, j, 1] += Δyᶠᶜᵃ(i, j, k, grid) * Δzᶠᶜᶜ(i, j, k, grid)
            ∫ᶻ_A.yᶜᶠᶜ[i, j, 1] += Δxᶜᶠᵃ(i, j, k, grid) * Δzᶜᶠᶜ(i, j, k, grid)
        end
    end
end

function compute_vertically_integrated_lateral_areas!(∫ᶻ_A, grid, arch)

    event = launch!(arch,
                    grid,
                    :xy,
                    _compute_vertically_integrated_lateral_areas!,
                    ∫ᶻ_A,
                    grid,
                    dependencies=Event(device(arch)))

    wait(device(arch), event)

    return nothing
end
