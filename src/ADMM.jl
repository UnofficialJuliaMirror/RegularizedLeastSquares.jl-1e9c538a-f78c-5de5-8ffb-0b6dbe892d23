using LinearOperators
export admm

type ADMM <: AbstractLinearSolver
  A
  regularizer::Regularization
  params
end

ADMM(A, regularization; kargs...) = ADMM(A,regularization,kargs)

function solve(solver::ADMM, b::Vector)
  return admm(solver.A, b, solver.regularizer; solver.params...)
end

A_mul_B{T}(A::AbstractLinearOperator{T}, x::Vector{T}) = A*x

"""
 Alternating Direction Method of Multipliers

 Solve the problem: X = arg min_x 1/2*|| Ax-b||² + λ*g(X) where:
    x: variable (vector)
    b: measured data
    A: a general linear operator
    g(X): a convex but not necessarily a smooth function

  For details see:
  Boyd et al.,
  Distributed Optimization and Statistical Learning via the Alternating Direction
    Method of Multipliers,
  Foundations and Trends in Machine Learning, Vol. 3, No. 1 (2010) 1–122
"""
function admm(A, b::Vector, reg::Regularization
              ; sparseTrafo=nothing
              , startVector=nothing
              , iterations::Int64=50
              , ρ::Float64=1.e-2
              , ɛᵃᵇˢ::Float64=1.e-8
              , ɛʳᵉˡ::Float64=1.e-6
              , solverInfo = nothing
              , kargs...)

  σᵃᵇˢ = sqrt(length(b))*ɛᵃᵇˢ
  # initialize x, u and z
  if startVector == nothing
    x = Ac_mul_B(A,b)
  else
    x = copy(startVector)
  end
  z = zeros(eltype(x), size(x))
  u = zeros(eltype(x), size(x))

  op = A'*A+ρ*opEye(length(x))

  A_mul_B!(reg,1./ρ)

  p = Progress(iterations,dt=0.1,desc="Doing ADMM...";barglyphs=BarGlyphs("[=> ]"),barlen=50)
  for k=1:iterations
    # 1. solve arg min_x 1/2|| Ax-b ||² + ρ/2 ||x+u-z||²
    # <=> (A'A+ρ)*x = A'b+ρ(z-u)
    x = cg(op, x,  Ac_mul_B(A,b)+ρ*(z-u), iterations=10, verbose=false, solverInfo=solverInfo )

    # 2. update z using the proximal map of 1/ρ*g(x)
    zᵒˡᵈ = z

    if sparseTrafo != nothing
      zˢᵖᵃʳˢᵉ = sparseTrafo*(x[:]+u[:])
      prox!(reg, zˢᵖᵃʳˢᵉ)
      z = sparseTrafo\zˢᵖᵃʳˢᵉ[:]
    else
      z=x[:]+u[:]
      prox!( reg, z)
    end

    # 3. update u
    u=u+x-z

    # exit if residual is below tolerance
    rᵏ = norm(x-z)
    ɛᵖʳⁱ = σᵃᵇˢ + ɛʳᵉˡ*max( norm(x), norm(z) );
    sᵏ = norm(ρ * (z - zᵒˡᵈ))
    ɛᴰᵘᵃˡ = σᵃᵇˢ + ɛʳᵉˡ*norm(ρ*u);

    next!(p)

    solverInfo != nothing && storeRegularization(solverInfo,norm(reg,z))

    if (rᵏ < ɛᵖʳⁱ) && (sᵏ < ɛᴰᵘᵃˡ)
      break;
    end
  end

  return x
end