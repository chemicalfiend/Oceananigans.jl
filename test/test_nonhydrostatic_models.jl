@testset "Models" begin
    @info "Testing models..."

    @testset "Model constructor errors" begin
        grid = RectilinearGrid(CPU(), size=(1, 1, 1), extent=(1, 1, 1))
        @test_throws TypeError NonhydrostaticModel(grid=grid, boundary_conditions=1)
        @test_throws TypeError NonhydrostaticModel(grid=grid, forcing=2)
        @test_throws TypeError NonhydrostaticModel(grid=grid, background_fields=3)
    end

    topos = ((Periodic, Periodic, Periodic),
             (Periodic, Periodic,  Bounded),
             (Periodic,  Bounded,  Bounded),
             (Bounded,   Bounded,  Bounded))

    for topo in topos
        @testset "$topo model construction" begin
            @info "  Testing $topo model construction..."
            for arch in archs, FT in float_types
		        arch isa GPU && topo == (Bounded, Bounded, Bounded) && continue

                grid = RectilinearGrid(arch, FT, topology=topo, size=(16, 16, 2), extent=(1, 2, 3))
                model = NonhydrostaticModel(grid=grid)

                @test model isa NonhydrostaticModel
            end
        end
    end

    @testset "Adjustment of halos in NonhydrostaticModel constructor" begin
        @info "  Testing adjustment of halos in NonhydrostaticModel constructor..."

        default_grid = RectilinearGrid(size=(1, 1, 1), extent=(1, 2, 3))
        funny_grid = RectilinearGrid(size=(1, 1, 1), extent=(1, 2, 3), halo=(1, 3, 4))

        # Model ensures that halos are at least of size 1
        model = NonhydrostaticModel(grid=default_grid)
        @test model.grid.Hx == 1 && model.grid.Hy == 1 && model.grid.Hz == 1

        model = NonhydrostaticModel(grid=funny_grid)
        @test model.grid.Hx == 1 && model.grid.Hy == 3 && model.grid.Hz == 4

        # Model ensures that halos are at least of size 2
        for scheme in (CenteredFourthOrder(), UpwindBiasedThirdOrder())
            model = NonhydrostaticModel(advection=scheme, grid=default_grid)
            @test model.grid.Hx == 2 && model.grid.Hy == 2 && model.grid.Hz == 2

            model = NonhydrostaticModel(advection=scheme, grid=funny_grid)
            @test model.grid.Hx == 2 && model.grid.Hy == 3 && model.grid.Hz == 4
        end

        # Model ensures that halos are at least of size 3
        for scheme in (WENO5(), UpwindBiasedFifthOrder())
            model = NonhydrostaticModel(advection=scheme, grid=default_grid)
            @test model.grid.Hx == 3 && model.grid.Hy == 3 && model.grid.Hz == 3

            model = NonhydrostaticModel(advection=scheme, grid=funny_grid)
            @test model.grid.Hx == 3 && model.grid.Hy == 3 && model.grid.Hz == 4
        end

        # Model ensures that halos are at least of size 2 with AnisotropicBiharmonicDiffusivity
        model = NonhydrostaticModel(closure=AnisotropicBiharmonicDiffusivity(), grid=default_grid)
        @test model.grid.Hx == 2 && model.grid.Hy == 2 && model.grid.Hz == 2

        model = NonhydrostaticModel(closure=AnisotropicBiharmonicDiffusivity(), grid=funny_grid)
        @test model.grid.Hx == 2 && model.grid.Hy == 3 && model.grid.Hz == 4
    end

    @testset "Model construction with single tracer and nothing tracer" begin
        @info "  Testing model construction with single tracer and nothing tracer..."
        for arch in archs
            grid = RectilinearGrid(arch, size=(1, 1, 1), extent=(1, 2, 3))

            model = NonhydrostaticModel(grid=grid, tracers=:c, buoyancy=nothing)
            @test model isa NonhydrostaticModel

            model = NonhydrostaticModel(grid=grid, tracers=nothing, buoyancy=nothing)
            @test model isa NonhydrostaticModel
        end
    end

    @testset "Setting model fields" begin
        @info "  Testing setting model fields..."
        for arch in archs, FT in float_types
            N = (4, 4, 4)
            L = (2π, 3π, 5π)

            grid = RectilinearGrid(arch, FT, size=N, extent=L)
            model = NonhydrostaticModel(grid=grid,
                                        buoyancy=SeawaterBuoyancy(), tracers=(:T, :S))

            u, v, w = model.velocities
            T, S = model.tracers

            # Test setting an array
            T₀ = rand(FT, size(grid)...)
            T_answer = deepcopy(T₀)

            set!(model; enforce_incompressibility=false, T=T₀)

            @test Array(interior(T)) ≈ T_answer

            # Test setting functions
            u₀(x, y, z) = 1 + x + y + z
            v₀(x, y, z) = 2 + sin(x * y * z)
            w₀(x, y, z) = 3 + y * z
            T₀(x, y, z) = 4 + tanh(x + y - z)
            S₀(x, y, z) = 5

            set!(model, enforce_incompressibility=false, u=u₀, v=v₀, w=w₀, T=T₀, S=S₀)

            xC, yC, zC = nodes((Center, Center, Center), model.grid; reshape=true)
            xF, yF, zF = nodes((Face, Face, Face), model.grid; reshape=true)

            # Form solution arrays
            u_answer = u₀.(xF, yC, zC)
            v_answer = v₀.(xC, yF, zC)
            w_answer = w₀.(xC, yC, zF)
            T_answer = T₀.(xC, yC, zC)
            S_answer = S₀.(xC, yC, zC)

            Nx, Ny, Nz = size(model.grid)

            u_cpu = XFaceField(CPU(), grid)
            v_cpu = YFaceField(CPU(), grid)
            w_cpu = ZFaceField(CPU(), grid)
            T_cpu = CenterField(CPU(), grid)
            S_cpu = CenterField(CPU(), grid)

            set!(u_cpu, u)
            set!(v_cpu, v)
            set!(w_cpu, w)
            set!(T_cpu, T)
            set!(S_cpu, S)

            values_match = [
                            all(u_answer .≈ interior(u_cpu)),
                            all(v_answer .≈ interior(v_cpu)),
                            all(w_answer[:, :, 2:Nz] .≈ interior(w_cpu)[:, :, 2:Nz]),
                            all(T_answer .≈ interior(T_cpu)),
                            all(S_answer .≈ interior(S_cpu)),
                           ]

            @test all(values_match)

            # Test that update_state! works via u boundary conditions
            @test u_cpu[1, 1, 1] == u_cpu[Nx+1, 1, 1]  # x-periodicity
            @test u_cpu[1, 1, 1] == u_cpu[1, Ny+1, 1]  # y-periodicity
            @test all(u_cpu[1:Nx, 1:Ny, 1] .== u_cpu[1:Nx, 1:Ny, 0])     # free slip at bottom
            @test all(u_cpu[1:Nx, 1:Ny, Nz] .== u_cpu[1:Nx, 1:Ny, Nz+1]) # free slip at top

            # Test that enforce_incompressibility works
            set!(model, u=0, v=0, w=1, T=0, S=0)
            ϵ = 10 * eps(FT)
            set!(w_cpu, w)
            @test all(abs.(interior(w_cpu)) .< ϵ)

            # Test setting the background_fields to a Field
            U_field = XFaceField(arch, grid)
            U_field .= 1
            model = NonhydrostaticModel(grid = grid, background_fields = (u=U_field,))
            @test model.background_fields.velocities.u isa Field
			
	    U_field = CenterField(arch, grid)            
	    @test_throws ArgumentError NonhydrostaticModel(grid=grid, background_fields = (u=U_field,))            
        end
    end
end

