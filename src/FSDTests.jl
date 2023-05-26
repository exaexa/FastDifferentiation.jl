#Test functions need access to non-exported names from FastSymbolicDifferentiation. 
module FSDInternals
using FastSymbolicDifferentiation: compute_factorable_subgraphs, edges, vertices, isa_connected_path, add_non_dom_edges!, edges, PathEdge, dominated_node, partial_value, compute_paths_to_roots, num_vertices, unique_edges, parent_edges, edge_path, all_nodes, dominator_subgraph, postdominator_subgraph, dominating_node, times_used, reachable_dominance, postorder_number, variable_index_to_postorder_number, root_index_to_postorder_number, parents, children, DomPathConstraint, edge_exists, FactorableSubgraph, each_vertex, node_edges, factor_order, subgraph_edges, node, subset, factor_subgraph!, factor!, deconstruct_subgraph, forward_edges, evaluate_subgraph, make_factored_edge, path_sort_order, multiply_sequence, root, reachable_roots, bott_vertex, top_vertex, reachable_variables, compute_paths_to_variables, compute_edge_paths!, relation_node_indices, value_equal, is_tree, is_leaf, is_variable, is_constant, set_diff, value, bit_equal, _symbolic_jacobian, _symbolic_jacobian!, _sparse_symbolic_jacobian!, roots, variables, domain_dimension, codomain_dimension, DerivativeGraph, _jacobian_function!

export compute_factorable_subgraphs, edges, vertices, isa_connected_path, add_non_dom_edges!, edges, PathEdge, dominated_node, partial_value, compute_paths_to_roots, num_vertices, unique_edges, parent_edges, edge_path, all_nodes, dominator_subgraph, postdominator_subgraph, dominating_node, times_used, reachable_dominance, postorder_number, variable_index_to_postorder_number, root_index_to_postorder_number, parents, children, DomPathConstraint, edge_exists, FactorableSubgraph, each_vertex, node_edges, factor_order, subgraph_edges, node, subset, factor_subgraph!, factor!, deconstruct_subgraph, forward_edges, evaluate_subgraph, make_factored_edge, path_sort_order, multiply_sequence, root, reachable_roots, bott_vertex, top_vertex, reachable_variables, compute_paths_to_variables, compute_edge_paths!, relation_node_indices, value_equal, is_tree, is_leaf, is_variable, is_constant, set_diff, value, bit_equal, _symbolic_jacobian, _symbolic_jacobian!, _sparse_symbolic_jacobian!, roots, variables, domain_dimension, codomain_dimension, DerivativeGraph, _jacobian_function!
end #module


module FSDTests
using DiffRules
using TermInterface
import SymbolicUtils
import Symbolics
using StaticArrays
using Memoize
using Rotations
using DataStructures

using ..FastSymbolicDifferentiation
using ..FSDInternals

const FSD = FastSymbolicDifferentiation
export FSD

using TestItems

include("../FSDBenchmark/src/Types.jl")
include("../FSDBenchmark/src/Chebyshev.jl")
include("../FSDBenchmark/src/SphericalHarmonics.jl")

"""If `compute_dominators` is `true` then computes `idoms` tables for graph, otherwise computes `pidoms` table`"""
function compute_dominance_tables(graph::DerivativeGraph{T}, compute_dominators::Bool) where {T<:Integer}
    if compute_dominators
        start_vertices = root_index_to_postorder_number(graph)
    else
        start_vertices = variable_index_to_postorder_number(graph)
    end

    doms = Dict{T,T}[]   #create one idom table for each root

    for (start_index, node_postorder_number) in pairs(start_vertices)
        push!(doms, FastSymbolicDifferentiation.compute_dom_table(graph, compute_dominators, start_index, node_postorder_number))
    end
    return doms
end
export compute_dominance_tables

""" Utility function for working with symbolic expressions as Symbolics.jl defines them."""
function number_of_operations(symbolic_expr)
    if SymbolicUtils.istree(symbolic_expr) && operation(symbolic_expr) ∈ (+, *, -)
        return 1 + sum(number_of_operations.(arguments(symbolic_expr)))
    else
        return 0
    end
end

function simple_dag(cache::Union{IdDict,Nothing}=IdDict())
    Symbolics.@variables zz y
    return expr_to_dag(zz^2 + y * (zz^2), cache), zz, y
end
export simple_dag

function simple_numbered_dag()
    Symbolics.@variables zz
    return expr_to_dag(zz * cos(zz^2))
end
export simple_numbered_dag

function dominators_dag()
    Symbolics.@variables zz
    return expr_to_dag(zz * (cos(zz) + sin(zz))), zz
end
export dominators_dag

#Each line in the postorder listing has two spaces at the end which causes a line break. Don't delete the trailing spaces or the formatting will get messed up.
"""
Every line in this comment is terminated by 2 spaces to make markdown format properly.

creates dag with this postorder:  
1    x  
2    cos (x)  
3    sin (x)  
4    k1 = (cos(x) * sin(x))  
5    sin (k1)  
6    k2 = exp(sin(x))  
7    (k1 * k2)  
8    (sin(k1) + (k1 * k2))  

with this edge table:  
nodenum  
1    [(2, 1), (3, 1)]  
2    [(2, 1), (4, 2)]  
3    [(3, 1), (4, 3), (6, 3)]  
4    [(4, 2), (4, 3), (5, 4), (7, 4)]  
5    [(5, 4), (8, 5)]  
6    [(6, 3), (7, 6)]  
7    [(7, 4), (7, 6), (8, 7)]  
8    [(8, 5), (8, 7)]  

with this idoms/pidoms table:  
nodenum   idoms    pidoms  
1         8        1  
2         4        1  
3         8        1  
4         8        1  
5         8        4  
6         7        3  
7         8        1  
8         8        1  

with these factorable subgraphs  
(8,4), (8,3), (8,1), (1,4), (1,7), (1,8)
"""
function complex_dominator_dag()
    Symbolics.@variables zz
    # generate node dag explicitly rather than starting from Symbolics expression because don't know how Symbolics might rearrange the nodes, causing the postorder numbers to change for tests.
    nx = FastSymbolicDifferentiation.Node(zz.val)
    sinx = FastSymbolicDifferentiation.Node(sin, MVector(nx))
    cosx = FastSymbolicDifferentiation.Node(cos, MVector(nx))
    A = FastSymbolicDifferentiation.Node(*, MVector(cosx, sinx))
    sinA = FastSymbolicDifferentiation.Node(sin, MVector(A))
    expsin = FastSymbolicDifferentiation.Node(*, MVector(A, FastSymbolicDifferentiation.Node(exp, MVector(sinx))))
    plus = FastSymbolicDifferentiation.Node(+, MVector(sinA, expsin))
    return plus
end
export complex_dominator_dag

complex_dominator_graph() = DerivativeGraph(complex_dominator_dag())
export complex_dominator_graph

function R2_R2_function()
    Symbolics.@variables x y

    nx = Node(x)
    ny = Node(y)
    n2 = nx * ny
    n4 = n2 * ny
    n5 = n2 * n4

    return DerivativeGraph([n5, n4])
end
export R2_R2_function

function simple_dominator_graph()
    Symbolics.@variables x

    nx = Node(x)
    ncos = Node(cos, nx)
    nplus = Node(+, ncos, nx)
    ntimes = Node(*, ncos, nplus)
    four_2_subgraph = Node(+, nplus, ncos)
    one_3_subgraph = Node(+, Node(*, Node(-1), Node(sin, nx)), Node(1))
    return x, DerivativeGraph(ntimes), four_2_subgraph, one_3_subgraph
end
export simple_dominator_graph

"""returns 4 factorable subgraphs in this order: (4,2),(1,3),(1,4),(4,1)"""
function simple_factorable_subgraphs()
    _, graph, _, _ = simple_dominator_graph()
    temp = extract_all!(compute_factorable_subgraphs(graph))
    return graph, [
        temp[findfirst(x -> FastSymbolicDifferentiation.vertices(x) == (4, 2), temp)],
        temp[findfirst(x -> FastSymbolicDifferentiation.vertices(x) == (1, 3), temp)],
        temp[findfirst(x -> FastSymbolicDifferentiation.vertices(x) == (1, 4), temp)],
        temp[findfirst(x -> FastSymbolicDifferentiation.vertices(x) == (4, 1), temp)]
    ]
end
export simple_factorable_subgraphs

@testitem "isa_connected_path 1" begin # case when path is one edge long
    using Symbolics: @variables
    using DataStructures
    using FastSymbolicDifferentiation.FSDInternals

    @variables x y

    nx = Node(x)
    func = nx * nx

    gr = DerivativeGraph([func])
    subs_heap = compute_factorable_subgraphs(gr)
    subs = extract_all!(subs_heap)
    test_sub = subs[1]

    etmp = parent_edges(gr, dominated_node(test_sub))
    rroots = reachable_roots(etmp[1])
    rroots .= rroots .& .!rroots

    @test !isa_connected_path(test_sub, etmp[1])
    @test isa_connected_path(test_sub, etmp[2])
end

@testitem "isa_connected_path 2" begin #cases when path is longer than one edge and various edges have either roots or variables reset.
    using Symbolics: @variables
    using DataStructures
    using FastSymbolicDifferentiation.FSDInternals
    @variables x y

    nx = Node(x)
    ny = Node(y)
    n2 = nx * ny
    n4 = n2 * ny
    n5 = n2 * n4


    graph = DerivativeGraph([n4, n5])
    subs_heap = compute_factorable_subgraphs(graph)
    subs = extract_all!(subs_heap)
    println(subs)
    _5_3_index = findfirst(x -> vertices(x) == (5, 3), subs)
    _5_3 = subs[_5_3_index]

    _2_4_index = findfirst(x -> vertices(x) == (2, 4), subs)
    _2_4 = subs[_2_4_index]

    _3_5_index = findfirst(x -> vertices(x) == (3, 5), subs)
    _3_5 = subs[_3_5_index]

    etmp = edges(graph, 3, 5)[1]
    @test isa_connected_path(_5_3, etmp)


    etmp = edges(graph, 3, 4)[1]
    @test isa_connected_path(_5_3, etmp)
    rts = reachable_roots(etmp)
    rts[2] = 0

    @test !isa_connected_path(_5_3, etmp)
    #reset path
    rts[2] = 1

    e2_4 = edges(graph, 2, 4)[1]
    @test isa_connected_path(_2_4, e2_4)
    e2_3 = edges(graph, 2, 3)[1]
    @test isa_connected_path(_2_4, e2_3)
    e3_4 = edges(graph, 3, 4)[1]
    vars = reachable_variables(e3_4)
    @. vars &= !vars
    @test !isa_connected_path(_2_4, e3_4)
end

@testitem "add_non_dom_edges" begin
    using Symbolics: @variables
    using DataStructures
    using FastSymbolicDifferentiation.FSDInternals

    #utility function to make it easier to create edges and test them against edges generated during graph operations.
    function edge_fields_equal(edge1, edge2)
        return edge1.top_vertex == edge2.top_vertex &&
               edge1.bott_vertex == edge2.bott_vertex &&
               edge1.edge_value == edge2.edge_value &&
               edge1.reachable_variables == edge2.reachable_variables &&
               edge1.reachable_roots == edge2.reachable_roots
    end

    @variables x y

    nx = Node(x)
    ny = Node(y)
    n2 = nx * ny
    n4 = n2 * ny
    n5 = n2 * n4

    graph = DerivativeGraph([n4, n5])
    subs_heap = compute_factorable_subgraphs(graph)
    subs = extract_all!(subs_heap)
    _5_3 = subs[1]
    @test (5, 3) == vertices(_5_3)

    add_non_dom_edges!(_5_3)
    #single edge 3,4 should be split into two: ([r1,r2],[v1,v2]) -> ([r1],[v1,v2]),([r2],[v1,v2])
    edges3_4 = edges(graph, 4, 3)
    @test length(edges3_4) == 2
    test_edge = PathEdge(4, 3, ny, BitVector([1, 1]), BitVector([0, 1]))
    @test count(edge_fields_equal.(edges3_4, Ref(test_edge))) == 1
    test_edge = (PathEdge(4, 3, ny, BitVector([1, 1]), BitVector([1, 0])))
    @test count(edge_fields_equal.(edges3_4, Ref(test_edge))) == 1

    graph = DerivativeGraph([n4, n5])
    sub_heap = compute_factorable_subgraphs(graph)
    subs = extract_all!(sub_heap)
    _2_4 = subs[2]
    @test (2, 4) == vertices(_2_4)

    add_non_dom_edges!(_2_4)
    #single edge 3,4 should be split in two: ([r1,r2],[v1,v2])->([r1,r2],[v1]),([r1,r2],[v2])
    edges3_4 = edges(graph, 4, 3)
    @test length(edges3_4) == 2
    test_edge = PathEdge(4, 3, ny, BitVector([1, 0]), BitVector([1, 1]))
    @test count(edge_fields_equal.(edges3_4, Ref(test_edge))) == 1
    test_edge = (PathEdge(4, 3, ny, BitVector([0, 1]), BitVector([1, 1])))
    @test count(edge_fields_equal.(edges3_4, Ref(test_edge))) == 1
end

@testitem "iteration" begin
    using Symbolics: @variables
    using DataStructures
    using FastSymbolicDifferentiation.FSDInternals

    @variables x y

    nx = Node(x)
    ny = Node(y)
    n2 = nx * ny
    n4 = n2 * ny
    n5 = n2 * n4


    graph = DerivativeGraph([n4, n5])
    subs_heap = compute_factorable_subgraphs(graph)

    subs = extract_all!(subs_heap)

    _5_3_index = findfirst(x -> vertices(x) == (5, 3), subs)
    _5_3 = subs[_5_3_index]

    _2_4_index = findfirst(x -> vertices(x) == (2, 4), subs)
    _2_4 = subs[_2_4_index]

    _3_5_index = findfirst(x -> vertices(x) == (3, 5), subs)
    _3_5 = subs[_3_5_index]

    e5_3 = edges(graph, 5, 3)[1]

    pedges = collect(edge_path(_5_3, e5_3))
    @test length(pedges) == 1
    @test e5_3 in pedges

    e3_4 = edges(graph, 3, 4)[1]
    e5_4 = edges(graph, 5, 4)[1]

    pedges = collect(edge_path(_5_3, e3_4))
    @test length(pedges) == 2
    @test all(in.((e3_4, e5_4), Ref(pedges)))

    e2_3 = edges(graph, 2, 3)[1]
    e2_4 = edges(graph, 2, 4)[1]

    pedges = collect(edge_path(_2_4, e3_4))
    @test length(pedges) == 2
    @test all(in.((e2_3, e3_4), Ref(pedges)))

    pedges = collect(edge_path(_2_4, e2_4))
    @test length(pedges) == 1
    @test e2_4 in pedges
end



@testitem "all_nodes" begin
    using FastSymbolicDifferentiation.FSDTests
    using FastSymbolicDifferentiation.FSDInternals

    cache = IdDict()
    dag, x, y = simple_dag(cache)

    correct = expr_to_dag.([((x^2) + (y * (x^2))), (x^2), x, 2, (y * (x^2)), y], Ref(cache))
    tmp = all_nodes(dag)

    #verify that all the node expressions exist in the dag. Can't rely on them being in a particular order because Symbolics can
    #arbitrarily choose how to reorder trees.
    for expr in correct
        @test in(expr, tmp)
    end
end

@testitem "make_function for Node" begin
    import Symbolics

    Symbolics.@variables x y

    A = [x^2+y 0 2x
        0 0 2y
        y^2+x 0 0]
    dag = expr_to_dag.(A)
    symbolics_answer = Symbolics.substitute.(A, Ref(Dict(x => 1.1, y => 2.3)))
    float_answer = similar(symbolics_answer, Float64)
    for index in eachindex(symbolics_answer)
        float_answer[index] = symbolics_answer[index].val
    end

    FSD_func = make_function.(dag, Ref([x, y]))
    res = [FSD_func[1, 1](1.1, 2.3) FSD_func[1, 2](0.0, 0.0) FSD_func[1, 3](1.1, 0.0)
        FSD_func[2, 1](0.0, 0.0) FSD_func[2, 2](0.0, 0.0) FSD_func[2, 3](0, 2.3)
        FSD_func[3, 1](1.1, 2.3) FSD_func[3, 2](0, 0) FSD_func[3, 3](0, 0)
    ]
    @test isapprox(res, float_answer)
end

@testitem "conversion from graph of FastSymbolicDifferentiation.Node to Symbolics expression" begin
    using FastSymbolicDifferentiation.FSDTests
    import Symbolics

    order = 7
    Symbolics.@variables x y z

    derivs = Symbolics.jacobian(SHFunctions(order, x, y, z), [x, y, z]; simplify=true)
    # show(@time SHDerivatives(order,x,y,z))
    tmp = expr_to_dag.(derivs)
    # show(@time expr_to_dag.(derivs))
    from_dag = dag_to_Symbolics_expression.(tmp)
    subs = Dict([x => rand(), y => rand(), z => rand()])
    @test isapprox(map(xx -> xx.val, Symbolics.substitute.(derivs, Ref(subs))), map(xx -> xx.val, Symbolics.substitute.(from_dag, Ref(subs))), atol=1e-12)
end

@testitem "is_tree" begin
    using Symbolics: @variables
    using FastSymbolicDifferentiation.FSDInternals

    @variables x

    nx = Node(x)
    z = Node(0)
    tm = nx * nx

    @test is_tree(nx) == false
    @test is_leaf(nx) == true
    @test is_variable(nx) == true
    @test is_constant(nx) == false

    @test is_tree(z) == false
    @test is_leaf(z) == true
    @test is_constant(z) == true
    @test is_variable(z) == false

    @test is_leaf(tm) == false
    @test is_variable(tm) == false
    @test is_tree(tm) == true
    @test is_constant(tm) == false
end

@testitem "derivative" begin
    using Symbolics: @variables
    @variables x, y

    nx = Node(x)
    ny = Node(y)
    a = nx * ny
    @test derivative(a, Val(1)) == ny
    @test derivative(a, Val(2)) == nx
    @test derivative(nx) == Node(1)
    @test derivative(Node(1)) == Node(0)
end

@testitem "simple make_function" begin
    using FastSymbolicDifferentiation.FSDTests

    x, graph, four_2_subgraph, one_3_subgraph = simple_dominator_graph()
    #not practical to compare the graphs directly since the order in which nodes come out of the differentiation
    #process is complicated. For dom subgraphs it depends on the order nodes appear in the parents list of a node. This 
    #is determined by code that has nothing to do with differentiation so don't want to take a dependency on it since it is
    #subject to change. Comparing graphs
    #directly would make the test fragile. Instead verify that the functions evaluate to the same thing.

    for testval in -π:0.08345:π
        correct_4_2_value = make_function(four_2_subgraph)
        computed_4_2_value = make_function(four_2_subgraph)
        correct_1_3_value = make_function(one_3_subgraph)
        computed_1_3_value = make_function(one_3_subgraph)
        @test isapprox(correct_4_2_value(testval), computed_4_2_value(testval), atol=1e-14)
        @test isapprox(correct_1_3_value(testval), computed_1_3_value(testval), atol=1e-14)
    end
end

@testitem "compute_factorable_subgraphs test order" begin
    using Symbolics: @variables
    using DataStructures
    using FastSymbolicDifferentiation.FSDInternals

    @variables x y

    nv1 = Node(x)
    nv2 = Node(y)
    n3 = nv1 * nv2
    n4 = n3 * nv1

    n5 = n3 * n4

    graph = DerivativeGraph([n4, n5])
    # factor_subgraph!(graph, postdominator_subgraph(2, 4, 2, BitVector([0, 1]), BitVector([0, 1])))
    sub_heap = compute_factorable_subgraphs(graph)
    subs = extract_all!(sub_heap)

    _5_3 = dominator_subgraph(graph, 5, 3, Bool[0, 1], Bool[0, 1], Bool[1, 1])
    _1_4 = postdominator_subgraph(graph, 1, 4, Bool[1, 0], Bool[1, 1], Bool[1, 0])
    _3_5 = postdominator_subgraph(graph, 3, 5, Bool[0, 1], Bool[0, 1], Bool[1, 1])
    _4_1 = dominator_subgraph(graph, 4, 1, Bool[1, 0], Bool[1, 1], Bool[1, 0])
    _5_1 = dominator_subgraph(graph, 5, 1, Bool[0, 1], Bool[0, 1], Bool[1, 0])
    _1_5 = postdominator_subgraph(graph, 1, 5, Bool[1, 0], Bool[0, 1], Bool[1, 0])

    correctly_ordered_subs = (_5_3, _1_4, _3_5, _4_1, _5_1, _1_5) #order of last two could switch and still be correct but all others should be in exactly this order.

    tmp = zip(correctly_ordered_subs[1:4], subs[1:4])
    for (correct, computed) in tmp
        @test value_equal(correct, computed)
    end
    #last two
    @test (value_equal(_5_1, subs[5]) && value_equal(_1_5, subs[6])) || (value_equal(_1_5, subs[5]) && value_equal(5_1, subs[6]))
end

@testitem "compute_factorable_subgraphs" begin
    using FastSymbolicDifferentiation.FSDTests
    using DataStructures
    using FastSymbolicDifferentiation.FSDInternals

    dgraph = DerivativeGraph(complex_dominator_dag())

    sub_heap = compute_factorable_subgraphs(dgraph)
    subs = extract_all!(sub_heap)


    equal_subgraphs(x, y) = dominating_node(x) == dominating_node(y) && dominated_node(x) == dominated_node(y) && times_used(x) == times_used(y) && reachable_dominance(x) == reachable_dominance(y)


    index_1_4 = findfirst(x -> equal_subgraphs(x, postdominator_subgraph(dgraph, 1, 4, BitVector([1]), BitVector([1]), BitVector([1]))), subs)
    index_1_7 = findfirst(x -> equal_subgraphs(x, postdominator_subgraph(dgraph, 1, 7, BitVector([1]), BitVector([1]), BitVector([1]))), subs)
    @test index_1_4 < index_1_7

    index_8_4 = findfirst(x -> equal_subgraphs(x, dominator_subgraph(dgraph, 8, 4, BitVector([1]), BitVector([1]), BitVector([1]))), subs)
    index_8_3 = findfirst(x -> equal_subgraphs(x, dominator_subgraph(dgraph, 8, 3, BitVector([1]), BitVector([1]), BitVector([1]))), subs)
    @test index_8_4 < index_8_3

    index_8_1d = findfirst(x -> equal_subgraphs(x, dominator_subgraph(dgraph, 8, 1, BitVector([1]), BitVector([1]), BitVector([1]))), subs)
    @test index_8_4 < index_8_1d
    @test index_8_3 < index_8_1d
    @test index_1_7 < index_8_1d

    index_8_1p = findfirst(x -> equal_subgraphs(x, dominator_subgraph(dgraph, 8, 1, BitVector([1]), BitVector([1]), BitVector([1]))), subs)
    @test index_8_4 < index_8_1p
    @test index_8_3 < index_8_1p
    @test index_1_7 < index_8_1p
end

@testitem "make_function" begin #generation of derivative functions
    import Symbolics
    using Symbolics: @variables, substitute
    using FastSymbolicDifferentiation.FSDTests
    using FastSymbolicDifferentiation.FSDInternals

    Symbolics.@variables zz
    dom_expr = zz * (cos(zz) + sin(zz))

    symbol_result = substitute(dom_expr, zz => 3.7)

    exe = make_function(dom_expr)

    @test exe(3.7) ≈ symbol_result

    Symbolics.@variables x, y
    sym_expr = cos(log(x) + sin(y)) * zz
    symbol_result = substitute(sym_expr, Dict([zz => 3.2, x => 2.5, y => 7.0]))

    exe = make_function(sym_expr)

    sym_expr2 = cos(2.0 * x) - sqrt(y)
    symbol_result = substitute(sym_expr2, Dict([x => 5.0, y => 3.2]))
    exe2 = make_function(sym_expr2, [x, y])

    symbol_val = symbol_result.val
    @test symbol_val ≈ exe2(5.0, 3.2)

    sym_expr3 = sin(x^3 + y^0.3)
    symbol_result3 = substitute(sym_expr3, Dict([x => 7.0, y => 0.4]))
    exe3 = make_function(sym_expr3, [x, y])
    symbol_val3 = symbol_result3.val
    @test symbol_val3 ≈ exe3(7.0, 0.4)

    #ensure that common terms are not reevaluated.
    sym_expr4 = sin(cos(x)) * cos(cos(x))
    symbol_result4 = substitute(sym_expr4, Dict([x => 7.0]))
    exe4 = make_function(sym_expr4, [x])
    symbol_val4 = symbol_result4.val
    @test symbol_val4 ≈ exe4(7.0)
end

@testitem "edges" begin
    using Symbolics: @variables
    using FastSymbolicDifferentiation.FSDInternals

    @variables x y

    nx = Node(x)
    ny = Node(y)
    n2 = nx * ny
    n4 = n2 * ny
    n5 = n2 * n4

    graph = DerivativeGraph([n5, n4])

    function test_edge_access(graph, correct_num_edges, vert1, vert2)
        edge_group1 = edges(graph, vert1, vert2)
        edge_group2 = edges(graph, vert2, vert1)
        @test length(edge_group1) == correct_num_edges
        @test length(edge_group1) == length(edge_group2)
        for edge_pair in zip(edge_group1, edge_group2)
            @test edge_pair[1] == edge_pair[2]
        end

        for edge in edge_group1
            @test top_vertex(edge) == max(vert1, vert2)
            @test bott_vertex(edge) == min(vert1, vert2)
        end
    end

    edge_verts = ((1, 3), (3, 2), (2, 4), (5, 4), (3, 5), (4, 3))
    num_edges = (1, 1, 1, 1, 1, 1)

    for (edge, num) in zip(edge_verts, num_edges)
        test_edge_access(graph, num, edge[1], edge[2])
    end
end

@testitem "DerivativeGraph constructor" begin
    import Symbolics
    using Symbolics: @variables, substitute
    using FastSymbolicDifferentiation.FSDInternals

    @variables x, y

    #f = [cos(x) * sin(y), cos(x) + sin(y)]
    nx = Node(x)
    ny = Node(y)
    cosx = Node(cos, nx)
    sinx = Node(sin, nx)
    partial_cosx = Node(-, sinx)
    siny = Node(sin, ny)
    partial_siny = Node(cos, ny)
    ctimess = cosx * siny
    partial_times = [siny, cosx]
    cpluss = cosx + siny
    partial_plus = [Node(1), Node(1)]
    roots = [ctimess, cpluss]
    grnodes = [nx, ny, cosx, siny, cpluss, ctimess]

    correct_postorder_numbers = Dict((nx => 1, cosx => 2, ny => 3, siny => 4, ctimess => 5, cpluss => 6))

    graph = DerivativeGraph(roots)

    @test all([correct_postorder_numbers[node] == postorder_number(graph, node) for node in grnodes])

    correct_partials = Dict((cosx => [partial_cosx], siny => [partial_siny], ctimess => partial_times, cpluss => partial_plus))
    for (node, partials) in pairs(correct_partials)
        for (i, one_partial) in pairs(partials)
            f1 = dag_to_Symbolics_expression(partial_value(graph, node, i))
            f2 = dag_to_Symbolics_expression(one_partial)

            for test_point in BigFloat(-1):BigFloat(0.01):BigFloat(1) #graphs might have equivalent but different forms so evaluate at many points at high precision to verify derivatives are the same.
                v1 = Symbolics.value(Symbolics.substitute(f1, Dict((x => test_point), (y => test_point))))
                v2 = Symbolics.value(Symbolics.substitute(f2, Dict((x => test_point), (y => test_point))))
                @test isapprox(v1, v2, atol=1e-50)
            end
        end
    end
end

@testitem "DerivativeGraph pathmasks" begin
    using Symbolics: @variables
    using FastSymbolicDifferentiation.FSDInternals

    @variables x, y

    nx = Node(x) #postorder # 2
    ny = Node(y) #postorder # 3
    xy = Node(*, nx, ny) #postorder # 4
    n5 = Node(5) #postorder # 1
    f1 = Node(*, n5, xy) #postorder 5
    n3 = Node(3) #postorder # 6
    f2 = Node(*, xy, n3) #postorder # 7
    roots = [f1, f2]
    graph = DerivativeGraph(roots)

    #nx,ny,xy shared by both roots. n5,f1 only on f1 path, n3,f2 only on f2 path
    correct_roots_pathmasks = [
        BitArray([1, 0]),
        BitArray([1, 1]),
        BitArray([1, 1]),
        BitArray([1, 1]),
        BitArray([1, 0]),
        BitArray([0, 1]),
        BitArray([0, 1])]

    correct_variable_pathmasks = [
        BitArray([0, 0]),
        BitArray([1, 0]),
        BitArray([0, 1]),
        BitArray([1, 1]),
        BitArray([1, 1]),
        BitArray([0, 0]),
        BitArray([1, 1])
    ]

    variable_path_masks = compute_paths_to_variables(num_vertices(graph), edges(graph), variable_index_to_postorder_number(graph))
    @test variable_path_masks == correct_variable_pathmasks
    parent_path_masks = compute_paths_to_roots(num_vertices(graph), edges(graph), root_index_to_postorder_number(graph))
    @test parent_path_masks == correct_roots_pathmasks
end

@testitem "ConstrainedPathIterator" begin
    using Symbolics: @variables
    using FastSymbolicDifferentiation.FSDInternals

    @variables x, y

    #ℝ²->ℝ² function (f1,f2) = (5*(x*y),(x*y)*3)
    nx = Node(x) #postorder # 2
    ny = Node(y) #postorder # 3
    xy = Node(*, nx, ny) #postorder # 4
    n5 = Node(5) #postorder # 1
    f1 = Node(*, n5, xy) #postorder 5
    n3 = Node(3) #postorder # 6
    f2 = Node(*, xy, n3) #postorder # 7
    roots = [f1, f2]
    graph = DerivativeGraph(roots)
    root_masks = compute_paths_to_roots(num_vertices(graph), edges(graph), root_index_to_postorder_number(graph))
    variable_masks = compute_paths_to_variables(num_vertices(graph), edges(graph), variable_index_to_postorder_number(graph))

    piterator = DomPathConstraint(graph, true, 1)

    parents = Int64[]
    correct_parents = (postorder_number(graph, xy))
    for parent in relation_node_indices(piterator, postorder_number(graph, nx))
        push!(parents, parent)
    end

    @test length(parents) == 1
    @test parents[1] == postorder_number(graph, xy)

    piterator = DomPathConstraint(graph, true, 1)
    parents = Int64[]
    pnum = postorder_number(graph, xy)
    for parent in relation_node_indices(piterator, pnum)
        push!(parents, parent)
    end
    @test length(parents) == 1
    @test postorder_number(graph, f1) == parents[1]

    piterator = DomPathConstraint(graph, true, 2)

    parents = Int64[]
    for parent in relation_node_indices(piterator, postorder_number(graph, xy))
        push!(parents, parent)
    end

    @test length(parents) == 1
    @test postorder_number(graph, f2) == parents[1]


    viterator = DomPathConstraint(graph, false, 1)
    children = Int64[]
    for child in relation_node_indices(viterator, postorder_number(graph, xy))
        push!(children, child)
    end
    @test length(children) == 1
    @test children[1] == postorder_number(graph, nx)

    viterator = DomPathConstraint(graph, false, 2)
    children = Int64[]
    for child in relation_node_indices(viterator, postorder_number(graph, xy))
        push!(children, child)
    end
    @test length(children) == 1
    @test children[1] == 3
end

@testitem "edge_exists" begin
    using Symbolics: @variables
    using FastSymbolicDifferentiation.FSDInternals

    @variables x, y

    nx = Node(x) #postorder # 2
    ny = Node(y) #postorder # 3
    xy = Node(*, nx, ny) #postorder # 4
    n5 = Node(5) #postorder # 1
    f1 = Node(*, n5, xy) #postorder 5
    n3 = Node(3) #postorder # 6
    f2 = Node(*, xy, n3) #postorder # 7
    roots = [f1, f2]
    graph = DerivativeGraph(roots)

    all_edges = unique_edges(graph)

    for edge in all_edges
        @test edge_exists(graph, edge)
    end

    @test !edge_exists(graph, PathEdge(1, 7, Node(0), 2, 2)) #this edge is not in the graph

end

@testitem "add_edge! for DerivativeGraph" begin
    using Symbolics: @variables
    using FastSymbolicDifferentiation.FSDInternals

    @variables x, y

    nx = Node(x) #postorder # 2
    ny = Node(y) #postorder # 3
    xy = Node(*, nx, ny) #postorder # 4
    n5 = Node(5) #postorder # 1
    f1 = Node(*, n5, xy) #postorder 5
    n3 = Node(3) #postorder # 6
    f2 = Node(*, xy, n3) #postorder # 7
    roots = [f1, f2]
    variables = [nx, ny]
    graph = DerivativeGraph(roots)

    previous_edges = unique_edges(graph)
    new_edge = PathEdge(1, 7, Node(y), length(variables), length(roots))
    FastSymbolicDifferentiation.add_edge!(graph, new_edge)

    #make sure existing edges are still in the graph.
    for edge in previous_edges
        @test edge_exists(graph, edge)
    end

    prnts = parents.(values(edges(graph)))
    numprnts = sum(length.(prnts))
    chldrn = children.(values(edges(graph)))
    numchldrn = sum(length.(chldrn))
    num_edges = (numprnts + numchldrn) / 2
    @test num_edges == 7 #ensure number of edges has increased by 1

    @test edge_exists(graph, new_edge) #and that there is only one new edge
end

@testitem "delete_edge! for DerivativeGraph" begin
    using Symbolics: @variables
    using FastSymbolicDifferentiation.FSDInternals

    @variables x, y

    function reset_test(all_edges, graph, func::Function)
        for edge in all_edges
            tmp = func(edge)
            for i in eachindex(tmp)
                tmp[i] = 0
            end

            #can't delete edge till roots or variables are all unreachable

            FastSymbolicDifferentiation.delete_edge!(graph, edge)
            @test !edge_exists(graph, edge) #make sure edge has been deleted from graph

            delete!(all_edges, edge) #now delete edge and see if all the other edges that are still supposed to be in the graph are still there
            for edge2 in all_edges
                @test edge_exists(graph, edge2) #other edges have not been deleted
            end
        end
    end
    nx = Node(x) #postorder # 2
    ny = Node(y) #postorder # 3
    xy = Node(*, nx, ny) #postorder # 4
    n5 = Node(5) #postorder # 1
    f1 = Node(*, n5, xy) #postorder 5
    n3 = Node(3) #postorder # 6
    f2 = Node(*, xy, n3) #postorder # 7
    roots = [f1, f2]
    graph = DerivativeGraph(roots)
    all_edges = unique_edges(graph)

    reset_test(all_edges, graph, reachable_roots)

    graph = DerivativeGraph(roots)
    all_edges = unique_edges(graph)

    reset_test(all_edges, graph, reachable_variables)
end

@testitem "compute_edge_paths" begin
    using Symbolics: @variables
    using FastSymbolicDifferentiation.FSDInternals


    @variables x, y

    nx = Node(x) #postorder # 2
    ny = Node(y) #postorder # 3
    xy = Node(*, nx, ny) #postorder # 4
    n5 = Node(5) #postorder # 1
    f1 = Node(*, n5, xy) #postorder 5
    n3 = Node(3) #postorder # 6
    f2 = Node(*, xy, n3) #postorder # 7
    roots = [f1, f2]
    variables = [nx, ny]
    graph = DerivativeGraph(roots)
    compute_edge_paths!(num_vertices(graph), edges(graph), variable_index_to_postorder_number(graph), root_index_to_postorder_number(graph))

    correct_root_masks = Dict(
        (4, 2) => BitVector([1, 1]),
        (4, 3) => BitVector([1, 1]),
        (5, 1) => BitVector([1, 0]),
        (5, 4) => BitVector([1, 0]),
        (7, 4) => BitVector([0, 1]),
        (7, 6) => BitVector([0, 1])
    )

    correct_variable_masks = Dict(
        (4, 2) => BitVector([1, 0]),
        (4, 3) => BitVector([0, 1]),
        (5, 1) => BitVector([0, 0]),
        (5, 4) => BitVector([1, 1]),
        (7, 4) => BitVector([1, 1]),
        (7, 6) => BitVector([0, 0])
    )

    for index in each_vertex(graph)
        c_and_p = node_edges(graph, index)
        for edge in [parents(c_and_p); children(c_and_p)]
            @test edge.reachable_variables == correct_variable_masks[(top_vertex(edge), bott_vertex(edge))]
            @test edge.reachable_roots == correct_root_masks[(top_vertex(edge), bott_vertex(edge))]
        end
    end
end

@testitem "dominators DerivativeGraph" begin
    using Symbolics: @variables
    using FastSymbolicDifferentiation.FSDTests
    using FastSymbolicDifferentiation.FSDInternals


    @variables x, y

    nx = Node(x) #postorder # 2
    ny = Node(y) #postorder # 3
    xy = Node(*, nx, ny) #postorder # 4
    n5 = Node(5) #postorder # 1
    f1 = Node(*, n5, xy) #postorder 5
    n3 = Node(3) #postorder # 6
    f2 = Node(*, xy, n3) #postorder # 7
    roots = [f1, f2]
    graph = DerivativeGraph(roots)
    idoms = compute_dominance_tables(graph, true)

    correct_dominators = [
        (1 => 5, 4 => 5, 2 => 4, 3 => 4, 5 => 5),
        (2 => 4, 3 => 4, 6 => 7, 4 => 7, 7 => 7)
    ]

    for (i, idom) in pairs(idoms)
        for elt in correct_dominators[i]
            @test elt[2] == idom[elt[1]]
        end
    end


    nx = Node(x) #postorder #1
    ny = Node(y) #postorder #3
    ncos = Node(cos, nx) # 2
    nsin = Node(sin, ny) # 4
    n5 = Node(*, ncos, nsin) #5
    n6 = Node(*, n5, ny) #6
    n7 = Node(*, n5, n6) #7
    nexp = Node(exp, n6) # 8

    roots = [n7, nexp]
    graph = DerivativeGraph(roots)
    idoms = compute_dominance_tables(graph, true)

    correct_dominators = [
        (1 => 2, 2 => 5, 3 => 7, 4 => 5, 5 => 7, 6 => 7, 7 => 7),
        (1 => 2, 2 => 5, 3 => 6, 4 => 5, 5 => 6, 6 => 8, 8 => 8)
    ]

    for (i, idom) in pairs(idoms)
        for elt in correct_dominators[i]
            @test elt[2] == idom[elt[1]]
        end
    end

    pidoms = compute_dominance_tables(graph, false)

    correct_post_dominators = [
        (1 => 1, 2 => 1, 5 => 2, 6 => 5, 7 => 5, 8 => 6),
        (3 => 3, 4 => 3, 5 => 4, 6 => 3, 7 => 3, 8 => 6)
    ]

    for (i, pidom) in pairs(pidoms)
        for elt in correct_post_dominators[i]
            @test elt[2] == pidom[elt[1]]
        end
    end
end


@testitem "dom_subgraph && pdom_subgraph" begin
    using Symbolics: @variables

    using FastSymbolicDifferentiation: dom_subgraph, pdom_subgraph
    using FastSymbolicDifferentiation.FSDTests
    using FastSymbolicDifferentiation.FSDInternals

    @variables x, y

    nx = Node(x) #postorder # 1
    ncos = Node(cos, nx) #pos
    ntimes1 = Node(*, ncos, nx)
    ntimes2 = Node(*, ncos, ntimes1)
    roots = [ntimes2, ntimes1]
    graph = DerivativeGraph(roots)
    idoms = compute_dominance_tables(graph, true)
    pidoms = compute_dominance_tables(graph, false)

    r1_doms = ((4, 1), (4, 2))
    v1_pdoms = ((1, 3), (1, 4))

    computed = (
        dom_subgraph(graph, 1, 1, idoms[1]),
        dom_subgraph(graph, 1, 2, idoms[1]))

    @test computed[1] == r1_doms[1]
    @test computed[2] == r1_doms[2]

    computed = (
        pdom_subgraph(graph, 1, 3, pidoms[1]),
        pdom_subgraph(graph, 1, 4, pidoms[1]))

    @test computed[1] == v1_pdoms[1]
    @test computed[2] == v1_pdoms[2]

    r2_dom = (3, 1)

    computed = dom_subgraph(graph, 2, 1, idoms[2])

    @test computed == r2_dom
end


@testitem "reachable" begin
    using Symbolics: @variables
    using FastSymbolicDifferentiation.FSDInternals

    @variables x, y


    nx1 = Node(x)
    ny2 = Node(y)
    n3 = nx1 * ny2
    n4 = n3 * ny2
    n5 = n3 * n4

    graph = DerivativeGraph([n5, n4])
    two = BitVector([1, 1])
    one_zero = BitVector([1, 0])
    zero_one = BitVector([0, 1])

    for node in (1, 2, 3, 4)
        @test reachable_roots(graph, node) == two
    end
    @test reachable_roots(graph, 5) == one_zero

    @test reachable_variables(graph, 2) == zero_one
    for node in (3, 4, 5)
        @test reachable_variables(graph, node) == two
    end

    @test reachable_variables(graph, 1) == one_zero
end

@testitem "relation_edges" begin

end

@testitem "factor_order" begin
    using FastSymbolicDifferentiation.FSDTests
    using DataStructures
    using FastSymbolicDifferentiation.FSDInternals

    _, graph, four_2_subgraph, one_3_subgraph = simple_dominator_graph()



    sub_heap = compute_factorable_subgraphs(graph)
    subgraphs = extract_all!(sub_heap)
    @test length(subgraphs) == 4
    four_one = subgraphs[findfirst(x -> x.subgraph == (4, 1), subgraphs)]
    one_3 = subgraphs[findfirst(x -> x.subgraph == (1, 3), subgraphs)]
    four_2 = subgraphs[findfirst(x -> x.subgraph == (4, 2), subgraphs)]
    one_4 = subgraphs[findfirst(x -> x.subgraph == (1, 4), subgraphs)]

    @test factor_order(one_3, four_one) == true
    @test factor_order(four_2, four_one) == true
    @test factor_order(one_3, four_2) == false
    @test factor_order(four_2, one_3) == false
    @test factor_order(four_one, one_3) == false
    @test factor_order(four_one, four_2) == false


    @test factor_order(one_3, one_4) == true
    @test factor_order(four_2, one_4) == true
    @test factor_order(one_3, four_2) == false
    @test factor_order(four_2, one_3) == false
    @test factor_order(one_4, one_3) == false
    @test factor_order(one_4, four_2) == false #one_3 should be sorted before one_4

    equal_subgraphs(x, y) = dominating_node(x) == dominating_node(y) && dominated_node(x) == dominated_node(y) && times_used(x) == times_used(y) && reachable_dominance(x) == reachable_dominance(y)


    # doms = dominator_subgraph.((
    #     (graph, 4, 2, BitVector([1, 0]), BitVector([1, 0])BitVector([1])),
    #     (graph, 4, 1, BitVector([1, 1]), BitVector([1, 0])BitVector([1]))))
    # pdoms = postdominator_subgraph.((
    #     (graph, 1, 3, BitVector([1, 1]), BitVector([1]), BitVector([1, 1])),
    #     (graph, 1, 4, BitVector([1, 1]), BitVector([1]), BitVector([1, 0]))))
    # subs2 = collect((pdoms..., doms...))


    index_1_4 = findfirst(x -> equal_subgraphs(x, one_4), subgraphs)
    index_4_2 = findfirst(x -> equal_subgraphs(x, four_2), subgraphs)
    index_1_3 = findfirst(x -> equal_subgraphs(x, one_3), subgraphs)

    @test index_1_3 < index_1_4
end

@testitem "subgraph_edges" begin
    using FastSymbolicDifferentiation.FSDTests
    using DataStructures
    using FastSymbolicDifferentiation.FSDInternals

    dgraph = DerivativeGraph([complex_dominator_dag()])

    _1_4_sub_ref = Set(map(x -> x[1], edges.(Ref(dgraph), ((4, 3), (4, 2), (2, 1), (3, 1)))))

    _8_4_sub_ref = Set(map(x -> x[1], edges.(Ref(dgraph), ((8, 7), (8, 5), (5, 4), (7, 4)))))

    subs = extract_all!(compute_factorable_subgraphs(dgraph))
    _1_4_sub = subs[findfirst(x -> vertices(x) == (1, 4), subs)]
    _1_7_sub = subs[findfirst(x -> vertices(x) == (1, 7), subs)]
    _8_4_sub = subs[findfirst(x -> vertices(x) == (8, 4), subs)]
    _8_1_sub = subs[findfirst(x -> vertices(x) == (8, 1), subs)]
    _1_8_sub = subs[findfirst(x -> vertices(x) == (1, 8), subs)]

    @test issetequal(_1_4_sub_ref, subgraph_edges(_1_4_sub))
    factor_subgraph!(_1_4_sub)
    _1_7_sub_ref = Set(map(x -> x[1], edges.(Ref(dgraph), ((4, 1), (3, 1), (7, 4), (7, 6), (6, 3)))))


    @test issetequal(_1_7_sub_ref, subgraph_edges(_1_7_sub))
    @test issetequal(_8_4_sub_ref, subgraph_edges(_8_4_sub))
    factor_subgraph!(_8_4_sub)
    _8_1_sub_ref = Set(map(x -> x[1], edges.(Ref(dgraph), ((8, 7), (8, 4), (4, 1), (3, 1), (6, 3), (7, 6)))))
    @test issetequal(_8_1_sub_ref, subgraph_edges(_8_1_sub))
    @test issetequal(_8_1_sub_ref, subgraph_edges(_1_8_sub))

end

@testitem "subgraph_edges with branching" begin
    using Symbolics: @variables
    using FastSymbolicDifferentiation.FSDTests
    using FastSymbolicDifferentiation.FSDInternals

    @variables x

    nx = Node(x)
    gr = DerivativeGraph((cos(nx) * cos(nx)) + nx)
    # Vis.draw_dot(gr)
    # Vis.draw_dot(gr)
    sub = FactorableSubgraph{Int64,FSD.DominatorSubgraph}(gr, 4, 1, BitVector([1]), BitVector([1]), BitVector([1]))

    edges_4_1 = collect(subgraph_edges(sub))

    sub = FactorableSubgraph{Int64,FSD.PostDominatorSubgraph}(gr, 1, 4, BitVector([1]), BitVector([1]), BitVector([1]))
    edges_1_4 = collect(subgraph_edges(sub))

    @test count(x -> vertices(x) == (4, 3), edges_4_1) == 1
    @test count(x -> vertices(x) == (4, 1), edges_4_1) == 1
    @test count(x -> vertices(x) == (3, 2), edges_4_1) == 2
    @test count(x -> vertices(x) == (2, 1), edges_4_1) == 1

    @test count(x -> vertices(x) == (4, 3), edges_1_4) == 1
    @test count(x -> vertices(x) == (4, 1), edges_1_4) == 1
    @test count(x -> vertices(x) == (3, 2), edges_1_4) == 2
    @test count(x -> vertices(x) == (2, 1), edges_1_4) == 1
end

@testitem "deconstruct_subgraph" begin
    using FastSymbolicDifferentiation.FSDTests
    using FastSymbolicDifferentiation.FSDInternals

    graph, subs = simple_factorable_subgraphs()

    all_edges = collect(unique_edges(graph))

    _4_2 = all_edges[findfirst(x -> vertices(x) == (4, 2), all_edges)]
    _4_3 = all_edges[findfirst(x -> vertices(x) == (4, 3), all_edges)]
    _3_2 = all_edges[findfirst(x -> vertices(x) == (3, 2), all_edges)]
    _2_1 = all_edges[findfirst(x -> vertices(x) == (2, 1), all_edges)]
    _3_1 = all_edges[findfirst(x -> vertices(x) == (3, 1), all_edges)]

    ed, nod = deconstruct_subgraph(subs[1]) #can only deconstruct these two subgraphs because the larger ones need to be factored first.
    @test issetequal([4, 2, 3], nod)
    @test issetequal((_4_2, _4_3, _3_2), ed)

    ed, nod = deconstruct_subgraph(subs[2])
    @test issetequal((_3_2, _3_1, _2_1), ed)
    @test issetequal([1, 2, 3], nod)

    factor_subgraph!(subs[1]) #now can test larger subgraphs

    #new edges created and some edges deleted during factorization so get them again
    all_edges = collect(unique_edges(graph))

    _4_2 = all_edges[findfirst(x -> vertices(x) == (4, 2), all_edges)]
    _4_3 = all_edges[findfirst(x -> vertices(x) == (4, 3), all_edges)]
    _2_1 = all_edges[findfirst(x -> vertices(x) == (2, 1), all_edges)]
    _3_1 = all_edges[findfirst(x -> vertices(x) == (3, 1), all_edges)]

    ed, nod = deconstruct_subgraph(subs[3])
    println(ed)
    sub_4_1 = (_4_3, _4_2, _3_1, _2_1)
    @test issetequal(sub_4_1, ed)
    @test issetequal([1, 2, 3, 4], nod)
    ed, nod = deconstruct_subgraph(subs[4])
    @test issetequal(sub_4_1, ed)
    @test issetequal([1, 2, 3, 4], nod)
end

@testitem "subgraph reachable_roots, reachable_variables" begin
    using Symbolics: @variables
    using DataStructures
    using FastSymbolicDifferentiation.FSDInternals

    @variables x, y

    nx1 = Node(x)
    ny2 = Node(y)
    nxy3 = nx1 * ny2
    r2_4 = nx1 * nxy3
    r1_5 = r2_4 * nxy3

    gnodes = (nx1, ny2, nxy3, r2_4, r1_5)

    graph = DerivativeGraph([r1_5, r2_4])
    sub_heap = compute_factorable_subgraphs(graph)
    subs = extract_all!(sub_heap)

    subnums = ((5, 3), (4, 1), (5, 1), (1, 5), (3, 5), (1, 4))
    roots = (BitVector([1, 0]), BitVector([1, 1]), BitVector([1, 0]), BitVector([1, 0]), BitVector([1, 0]), BitVector([1, 1]))
    variables = (BitVector([1, 1]), BitVector([1, 0]), BitVector([1, 0]), BitVector([1, 0]), BitVector([1, 1]), BitVector([1, 0]))

    subgraphs = [x.subgraph for x in subs]
    #verify subgraphs have proper numbers in them
    for one_num in subnums
        @test one_num in subgraphs
    end

    for (i, one_root) in pairs(roots)
        sub = subs[findfirst(x -> x.subgraph == subnums[i], subs)]
        @test reachable_roots(sub) == one_root
    end

    for (i, one_var) in pairs(variables)
        sub = subs[findfirst(x -> x.subgraph == subnums[i], subs)]
        @test reachable_variables(sub) == one_var
    end
end

@testitem "Path_Iterator" begin
    using Symbolics: @variables
    using DataStructures
    using FastSymbolicDifferentiation.FSDInternals

    @variables x, y

    nx1 = Node(x)
    ny2 = Node(y)
    nxy3 = nx1 * ny2
    r2_4 = nx1 * nxy3
    r1_5 = r2_4 * nxy3

    gnodes = (nx1, ny2, nxy3, r2_4, r1_5)

    graph = DerivativeGraph([r1_5, r2_4])

    #first verify all nodes have the postorder numbers we expect
    for (i, nd) in pairs(gnodes)
        @test node(graph, i) == nd
    end

    sub_heap = compute_factorable_subgraphs(graph)
    subs = extract_all!(sub_heap)

    sub_5_3 = first(filter(x -> x.subgraph == (5, 3), subs))
    sub_3_5 = first((filter(x -> x.subgraph == (3, 5), subs)))

    rmask = reachable_dominance(sub_5_3)
    V = reachable_variables(sub_5_3)


    path_edges1 = [edges(graph, 4, 3)[1], edges(graph, 5, 4)[1]]
    path_edges2 = [edges(graph, 5, 3)[1]]


    start_edges = forward_edges(sub_5_3, dominated_node(sub_5_3))
    temp_edges = collect(edge_path(sub_5_3, start_edges[1]))

    @test all(x -> x[1] == x[2], zip(path_edges1, temp_edges))
    temp_edges = collect(edge_path(sub_5_3, start_edges[2]))
    @test all(x -> x[1] == x[2], zip(path_edges2, temp_edges))

    #for postdominator subgraph (3,5)

    start_edges = forward_edges(sub_3_5, dominated_node(sub_3_5))

    temp_edges = collect(edge_path(sub_3_5, start_edges[1]))
    @test all(x -> x[1] == x[2], zip(reverse(path_edges1), temp_edges))
    temp_edges = collect(edge_path(sub_3_5, start_edges[2]))
    @test all(x -> x[1] == x[2], zip(path_edges2, temp_edges))


    path_edges1 = [edges(graph, 4, 1)[1]]
    path_edges2 = [edges(graph, 3, 1)[1], edges(graph, 4, 3)[1]]
    sub_4_1 = first(filter(x -> x.subgraph == (4, 1), subs))
    sub_1_4 = first(filter(x -> x.subgraph == (1, 4), subs))


    start_edges = forward_edges(sub_4_1, dominated_node(sub_4_1))
    #for dominator subgraph (4,1)

    temp_edges = collect(edge_path(sub_4_1, start_edges[1]))
    @test all(x -> x[1] == x[2], zip(path_edges1, temp_edges))
    temp_edges = collect(edge_path(sub_4_1, start_edges[2]))
    @test all(x -> x[1] == x[2], zip(path_edges2, temp_edges))


    #for postdominator subgraph (1,4)
    start_edges = forward_edges(sub_1_4, dominated_node(sub_1_4))
    temp_edges = collect(edge_path(sub_1_4, start_edges[1]))

    @test all(x -> x[1] == x[2], zip(path_edges1, temp_edges))
    temp_edges = collect(edge_path(sub_1_4, start_edges[2]))
    @test all(x -> x[1] == x[2], zip(reverse(path_edges2), temp_edges))
end

@testitem "set_diff" begin
    using FastSymbolicDifferentiation.FSDInternals

    @test set_diff(falses(1), falses(1)) == falses(1)
    @test set_diff(falses(1), trues(1)) == falses(1)
    @test set_diff(trues(1), falses(1)) == trues(1)
    @test set_diff(trues(1), trues(1)) == falses(1)
end

@testitem "make_factored_edge" begin
    using Symbolics: @variables
    using DataStructures
    using FastSymbolicDifferentiation.FSDInternals

    @variables v1, v2

    n1 = Node(v1)
    n2 = Node(v2)
    n3 = n1 * n2
    n4 = n3 * n2
    n5 = n3 * n4
    n6 = n5 * n4

    graph = DerivativeGraph([n5, n6])

    sub_heap = compute_factorable_subgraphs(graph)
    subs = extract_all!(sub_heap)

    _5_3 = filter(x -> vertices(x) == (5, 3), subs)[1]
    e_5_3 = make_factored_edge(_5_3, evaluate_subgraph(_5_3))

    _3_5 = filter(x -> vertices(x) == (3, 5), subs)[1]
    e_3_5 = make_factored_edge(_3_5, evaluate_subgraph(_3_5))

    @test bit_equal(reachable_roots(e_5_3), BitVector([1, 0]))
    @test bit_equal(reachable_variables(e_5_3), BitVector([1, 1]))

    @test bit_equal(reachable_roots(e_3_5), BitVector([1, 1]))
    @test bit_equal(reachable_variables(e_3_5), BitVector([1, 0]))
end


@testitem "factor_subgraph simple ℝ²->ℝ²" begin
    using Symbolics: @variables
    using FastSymbolicDifferentiation.FSDInternals

    @variables x y

    nv1 = Node(x)
    nv2 = Node(y)
    n3 = nv1 * nv2
    n4 = n3 * nv1
    n5 = n3 * n4

    graph = DerivativeGraph([n4, n5])
    # factor_subgraph!(graph, postdominator_subgraph(2, 4, 2, BitVector([0, 1]), BitVector([0, 1])))
    subs = compute_factorable_subgraphs(graph)

    _5_3 = dominator_subgraph(graph, 5, 3, Bool[0, 1], Bool[0, 1], Bool[1, 1])
    _1_4 = postdominator_subgraph(graph, 1, 4, Bool[1, 0], Bool[1, 1], Bool[1, 0])
    _3_5 = postdominator_subgraph(graph, 3, 5, Bool[0, 1], Bool[0, 1], Bool[1, 1])
    _4_1 = dominator_subgraph(graph, 4, 1, Bool[1, 0], Bool[1, 1], Bool[1, 0])
    _5_1 = dominator_subgraph(graph, 5, 1, Bool[0, 1], Bool[0, 1], Bool[1, 0])
    _1_5 = postdominator_subgraph(graph, 1, 5, Bool[1, 0], Bool[0, 1], Bool[1, 0])

    sub_eval = evaluate_subgraph(_5_3)
    factor_subgraph!(_5_3)
end


@testitem "factor_subgraph 2" begin
    using Symbolics: @variables
    using FastSymbolicDifferentiation.FSDInternals

    @variables x y

    nx1 = Node(x)
    ny2 = Node(y)
    n3 = nx1 * ny2
    n4 = n3 * ny2
    n5 = n3 * n4

    graph = DerivativeGraph([n5, n4])
    tmp = postdominator_subgraph(graph, 2, 4, BitVector([0, 1]), BitVector([0, 1]), BitVector([0, 1]))
    factor_subgraph!(tmp)
    @test length(edges(graph, 2, 4)) == 2

end



@testitem "evaluate_subgraph" begin
    using FastSymbolicDifferentiation.FSDTests
    using FastSymbolicDifferentiation.FSDInternals


    _, graph, _, _ = simple_dominator_graph()

    sub = postdominator_subgraph(graph, 1, 3, BitVector([1]), BitVector([1]), BitVector([1]))
end

@testitem "factor simple ℝ²->ℝ²" begin
    using Symbolics: @variables
    using FastSymbolicDifferentiation.FSDInternals

    @variables x, y

    nx1 = Node(x)
    ny2 = Node(y)
    n3 = nx1 * ny2
    r1_4 = sin(n3)
    r2_5 = cos(n3)

    graph = DerivativeGraph([r1_4, r2_5])
    result = _symbolic_jacobian!(graph, [nx1, ny2])

    #symbolic equality will work here because of common subexpression caching.
    @test result[1, 1] == cos(nx1 * ny2) * ny2
    @test result[1, 2] == cos(nx1 * ny2) * nx1
    @test result[2, 1] == -sin(nx1 * ny2) * ny2
    @test result[2, 2] == (-sin(nx1 * ny2)) * nx1
end


@testitem "subset" begin
    using FastSymbolicDifferentiation.FSDInternals

    a = falses(3)
    b = BitVector([1, 1, 1])
    @test subset(a, b)
    a = BitVector([1, 1, 1])
    @test subset(a, b)
    b = BitVector([1, 1, 0])
    @test !subset(a, b)
end


@testitem "constant and variable roots" begin
    using Symbolics: @variables
    using FastSymbolicDifferentiation.FSDInternals

    @variables x
    nx = Node(x)
    zr = Node(0.0)

    graph = DerivativeGraph([nx, zr])
    jac = _symbolic_jacobian!(graph, [nx])

    @test value(jac[1, 1]) == 1
    @test value(jac[2, 1]) == 0
end

@testitem "times_used PathEdge" begin
    using FastSymbolicDifferentiation.FSDInternals

    e = PathEdge(1, 2, Node(0), BitVector([1, 0, 1]), BitVector([0, 0, 1]))
    @test times_used(e) == 2
    e = PathEdge(1, 2, Node(0), BitVector([1, 0, 0]), BitVector([0, 0, 1]))
    @test times_used(e) == 1
    e = PathEdge(1, 2, Node(0), BitVector([1, 0, 1]), BitVector([1, 0, 1]))
    @test times_used(e) == 4
end

@testitem "path_sort_order" begin
    using FastSymbolicDifferentiation.FSDInternals
    e1 = PathEdge(1, 2, Node(0), BitVector([1, 0, 1]), BitVector([0, 0, 1]))
    e2 = PathEdge(3, 2, Node(0), BitVector([1, 0, 0]), BitVector([0, 0, 1]))
    @test path_sort_order(e1, e2) == true

    e3 = PathEdge(3, 2, Node(0), BitVector([1, 1, 0]), BitVector([0, 0, 1]))
    @test path_sort_order(e1, e3) == false
end

@testitem "multiply_sequence" begin
    using Symbolics: @variables
    using FastSymbolicDifferentiation.FSDInternals

    @variables x, y, z, w, u

    e1 = PathEdge(1, 2, Node(x), BitVector([1, 0, 1]), BitVector([0, 0, 1]))
    e2 = PathEdge(3, 2, Node(y), BitVector([1, 0, 0]), BitVector([0, 0, 1]))
    e3 = PathEdge(3, 2, Node(z), BitVector([1, 1, 0]), BitVector([0, 0, 1]))
    e4 = PathEdge(3, 2, Node(w), BitVector([1, 1, 0]), BitVector([1, 0, 1]))
    e5 = PathEdge(3, 2, Node(u), BitVector([1, 1, 0]), BitVector([0, 1, 1]))


    path = [e1, e3, e2]   #2,2,1 times used
    @test (Node(x) * Node(z)) * Node(y) === multiply_sequence(path)
    path = [e4, e5]
    @test (Node(w) * Node(u)) === multiply_sequence(path)
    path = [e4, e5, e1]
    @test (Node(w) * Node(u)) * Node(x) === multiply_sequence(path)
    path = [e4, e5, e1, e3]
    @test (Node(w) * Node(u)) * (Node(x) * Node(z)) === multiply_sequence(path)
end


@testitem "factor ℝ¹->ℝ¹ " begin
    using FastSymbolicDifferentiation.FSDTests
    using FiniteDifferences
    using FastSymbolicDifferentiation.FSDInternals

    _, graph, _, _ = simple_dominator_graph()
    factor!(graph)
    fedge = edges(graph, 1, 4)[1]
    dfsimp = make_function(value(fedge))
    _, graph, _, _ = simple_dominator_graph()
    origfsimp = make_function(root(graph, 1))
    @test isapprox(central_fdm(5, 1)(origfsimp, 3), dfsimp(3))

    graph = complex_dominator_graph()
    factor!(graph)
    fedge = edges(graph, 1, 8)[1]
    df = make_function(value(fedge))

    graph = complex_dominator_graph()
    origf = make_function(root(graph, 1))
    for test_val in -3.0:0.013:3.0
        @test isapprox(central_fdm(5, 1)(origf, test_val), df(test_val))
    end
end


@testitem "symbolic_jacobian" begin
    using Symbolics: @variables
    using FastSymbolicDifferentiation.FSDInternals

    @variables x y

    nx = Node(x)
    ny = Node(y)
    n2 = nx * ny
    n4 = n2 * ny
    n5 = n2 * n4

    graph = DerivativeGraph([n4, n5])

    df21(x, y) = 2 * x * y^3
    df22(x, y) = 4 * x^2 * y^2
    df11(x, y) = y^2
    df12(x, y) = 2 * x * y

    correct_jacobian = [df11 df12; df21 df22]
    copy_jac = _symbolic_jacobian(graph, [nx, ny])
    jac = _symbolic_jacobian!(graph, [nx, ny])

    @test all(copy_jac .== jac) #make sure the jacobian computed by copying the graph has the same variables as the one computed by destructively modifying the graph

    computed_jacobian = make_function.(jac, Ref([x, y]))

    #verify the computed and hand caluclated jacobians agree.
    for x in -1.0:0.01:1.0
        for y in -1.0:0.3:1.0
            for index in CartesianIndices(correct_jacobian)
                @test isapprox(correct_jacobian[index](x, y), computed_jacobian[index](x, y))
            end
        end
    end
end

@testitem "sparse_symbolic_jacobian!" begin
    using FastSymbolicDifferentiation.FSDTests
    using FastSymbolicDifferentiation.FSDInternals
    using Symbolics: @variables

    @variables x, y, z

    fsd_graph = spherical_harmonics(FastSymbolic(), 10, x, y, z)
    sprse = _sparse_symbolic_jacobian!(fsd_graph, variables(fsd_graph))
    fsd_graph = spherical_harmonics(FastSymbolic(), 10, x, y, z) #because global cache has not been reset the sparse and dense graphs should have identical elements.
    dense = _symbolic_jacobian!(fsd_graph, variables(fsd_graph))

    # for index in CartesianIndices(sprse)
    #     @test sprse[index] == dense[index]
    # end

    for index in CartesianIndices(dense)
        if sprse[index] != dense[index] #empty elements in sprse get value Node{Int64,0} wherease zero elements in dense get value Node{Float64,0}. These are not == so need special case.
            @test value(sprse[index]) == value(dense[index])
        else
            @test sprse[index] == dense[index]
        end
    end

    fsd_graph = spherical_harmonics(FastSymbolic(), 10, x, y, z)
    sprse = _sparse_symbolic_jacobian!(fsd_graph, reverse(variables(fsd_graph)))
    fsd_graph = spherical_harmonics(FastSymbolic(), 10, x, y, z) #because global cache has not been reset the sparse and dense graphs should have identical elements.
    dense = _symbolic_jacobian!(fsd_graph, reverse(variables(fsd_graph)))

    # for index in CartesianIndices(sprse)
    #     @test sprse[index] == dense[index]
    # end

    for index in CartesianIndices(dense)
        if sprse[index] != dense[index] #empty elements in sprse get value Node{Int64,0} wherease zero elements in dense get value Node{Float64,0}. These are not == so need special case.
            @test value(sprse[index]) == value(dense[index])
        else
            @test sprse[index] == dense[index]
        end
    end
end

@testitem "spherical harmonics jacobian evaluation test" begin
    using FastSymbolicDifferentiation.FSDTests
    using FiniteDifferences
    using FastSymbolicDifferentiation.FSDInternals

    fsd_graph = spherical_harmonics(FastSymbolic(), 10)
    fsd_func = make_function(fsd_graph, variables(fsd_graph))

    sym_func = _jacobian_function!(fsd_graph, variables(fsd_graph))

    for xr in -1.0:0.3:1.0
        for yr in -1.0:0.3:1.0
            for zr = -1.0:0.3:1.0
                finite_diff = jacobian(central_fdm(12, 1, adapt=3), fsd_func, xr, yr, zr)
                mat_form = hcat(finite_diff[1], finite_diff[2], finite_diff[3])
                symbolic = sym_func(xr, yr, zr)

                @test isapprox(symbolic, mat_form, rtol=1e-8)
            end
        end
    end
end

@testitem "Chebyshev jacobian evaluation test" begin
    using FiniteDifferences
    using FastSymbolicDifferentiation.FSDTests
    using FastSymbolicDifferentiation.FSDInternals

    chebyshev_order = 20
    fsd_graph = chebyshev(FastSymbolic(), chebyshev_order)
    fsd_func = make_function(fsd_graph)

    func_wrap(x) = fsd_func(x)[1]

    sym_func = _jacobian_function!(fsd_graph, in_place=false)

    for xr in -1.0:0.214:1.0
        finite_diff = central_fdm(12, 1, adapt=3)(func_wrap, xr)

        symbolic = sym_func(xr)

        @test isapprox(symbolic[1, 1], finite_diff[1], rtol=1e-8)
    end

    tmp = Matrix{Float64}(undef, 1, 1)
    fsd_graph = chebyshev(FastSymbolic(), chebyshev_order)
    sym_func = _jacobian_function!(fsd_graph, in_place=false)

    #the in place form of jacobian function
    for xr in -1.0:0.214:1.0
        finite_diff = central_fdm(12, 1, adapt=3)(func_wrap, xr)

        symbolic = sym_func(xr, tmp)

        @test isapprox(symbolic[1, 1], finite_diff[1], rtol=1e-8)
    end
end

@testitem "derivative of matrix" begin
    using Symbolics: @variables
    using FastSymbolicDifferentiation.FSDInternals

    @variables q1 q2
    nq1 = Node(q1)
    nq2 = Node(q2)

    A = [
        cos(nq1) -cos(nq1)
        sin(nq1) sin(nq1)
    ]

    DA = [
        -sin(nq1) sin(nq1)
        cos(nq1) cos(nq1)
    ]

    @test isapprox(zeros(2, 2), value.(derivative(A, nq2))) #taking derivative wrt variable not present in the graph returns all zero matrix
    @test DA == derivative(A, nq1)
end

@testitem "jacobian_times_v" begin
    using FastSymbolicDifferentiation.FSDInternals
    using FastSymbolicDifferentiation.FSDTests

    order = 10

    fsd_graph = spherical_harmonics(FastSymbolic(), order)
    fsd_func = roots(fsd_graph)
    func_vars = variables(fsd_graph)

    Jv, v_vars = jacobian_times_v(fsd_func, func_vars)

    #compute the product the slow way
    Jv_slow = convert.(Node, symbolic_jacobian(fsd_func, func_vars) * v_vars)
    both_vars = [func_vars; v_vars]
    slow_symbolic = reshape(Jv_slow, (length(Jv_slow), 1))

    slow = make_function(slow_symbolic, both_vars)
    fast = make_function(reshape(Jv, (length(Jv), 1)), both_vars)

    for _ in 1:100
        input = rand(length(func_vars) + length(v_vars))
        slow_val = slow(input...)
        fast_val = fast(input...)

        @test isapprox(slow_val, fast_val, rtol=1e-9)
    end

    fast2 = jacobian_times_v_exe(fsd_func, func_vars)

    for _ in 1:100
        xin = rand(length(fsd_func))
        vin = rand(domain_dimension(fsd_graph))
        slow_val = slow([xin; vin]...)
        fast_val = fast2(xin, vin)

        @test isapprox(slow_val, fast_val, rtol=1e-8)
    end
end

@testitem "jacobian_transpose_v" begin
    using FastSymbolicDifferentiation.FSDInternals
    using FastSymbolicDifferentiation.FSDTests

    order = 10

    fsd_graph = spherical_harmonics(FastSymbolic(), order)
    fsd_func = roots(fsd_graph)
    func_vars = variables(fsd_graph)

    Jᵀv, r_vars = jacobian_transpose_v(fsd_func, func_vars)

    Jᵀv_slow = convert.(Node, transpose(symbolic_jacobian(fsd_func, func_vars)) * r_vars)
    both_vars = [func_vars; r_vars]
    slow_symbolic = reshape(Jᵀv_slow, (length(Jᵀv_slow), 1))

    slow = make_function(slow_symbolic, both_vars)
    fast = make_function(reshape(Jᵀv, (length(Jᵀv), 1)), both_vars)

    for _ in 1:100
        input = rand(length(func_vars) + length(r_vars))
        slow_val = slow(input...)
        fast_val = fast(input...)

        @test isapprox(slow_val, fast_val, rtol=1e-8)
    end

    fast2 = jacobian_transpose_v_exe(fsd_func, func_vars)

    for _ in 1:100
        xin = rand(length(fsd_func))
        vin = rand(codomain_dimension(fsd_graph))
        slow_val = slow([xin; vin]...)
        #comment
        fast_val = fast2(xin, vin)

        @test isapprox(slow_val, fast_val, rtol=1e-8)
    end
end

end #module
