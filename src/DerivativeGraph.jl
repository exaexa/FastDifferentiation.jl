"""This iterator is used for traversing RnToRmGraph's allowing paths to all roots or all variables. This is used to determine which edges must be preserved in the graph (see frontier_nodes function)"""
struct UnconstrainedPathIterator{T<:Integer}
    node_index::T
    edges::Vector{PathEdge{T}}
    iterate_parents::Bool

    UnconstrainedPathIterator(node_index::T, edges::Vector{PathEdge{T}}, iterate_parents::Bool) where {T<:Integer} = new{T}(node_index, edges, iterate_parents)
end

Base.IteratorSize(::UnconstrainedPathIterator) = Base.SizeUnknown
Base.IteratorEltype(::UnconstrainedPathIterator) = Base.HasEltype
Base.eltype(::UnconstrainedPathIterator{T}) where {T<:Integer} = T


function Base.iterate(unconstrained::UnconstrainedPathIterator{T}, state::T=1) where {T<:Integer}
    node_edges = unconstrained.edges

    while true
        if state > length(node_edges)
            return nothing
        else
            edge = node_edges[state]
            if unconstrained.iterate_parents
                if edge.bott_vertex == unconstrained.node_index  #edge.top_vertex is a parent of node_index
                    return edge.top_vertex, state + 1
                end
            else
                if edge.top_vertex == unconstrained.node_index  #edge.bott_vertex is a child of node_index
                    return edge.bott_vertex, state + 1
                end
            end
        end
        state += 1
    end
end

struct ConstrainedPathIterator{T<:Integer}
    node_index::T
    edges::Vector{PathEdge{T}}
    iterate_parents::Bool
    constraint::Function
    end_node_index::T

    """`constraint_function` takes a single `PathEdge` argument and returns true or false"""
    ConstrainedPathIterator(node_index::T, end_node_index::T, edges::Vector{PathEdge{T}}, iterate_parents::Bool, constraint_function::Function) where {T<:Integer} = new{T}(node_index, end_node_index, edges, iterate_parents, constraint_function)
end

Base.IteratorSize(::ConstrainedPathIterator) = Base.SizeUnknown
Base.IteratorEltype(::ConstrainedPathIterator) = Base.HasEltype
Base.eltype(::ConstrainedPathIterator{T}) where {T<:Integer} = T


function Base.iterate(path_iterator::ConstrainedPathIterator{T}, state::T=1) where {T<:Integer}
    node_edges = path_iterator.edges

    while true
        if state > length(node_edges)
            return nothing
        else
            edge = node_edges[state]
            if path_iterator.iterate_parents
                if edge.bott_vertex == path_iterator.node_index && path_iterator.constraint(edge) #edge.top_vertex is a parent of node_index
                    return edge.top_vertex, state + 1
                end
            else
                if edge.top_vertex == path_iterator.node_index && path_iterator.constraint(edge) #edge.bott_vertex is a child of node_index
                    return edge.bott_vertex, state + 1
                end
            end
        end
        state += 1
    end
end

struct EdgeRelations{T}
    parents::Vector{PathEdge{T}}
    children::Vector{PathEdge{T}}

    EdgeRelations(T::Type=Int64) = new{T}(PathEdge{T}[], PathEdge{T}[])
end
export EdgeRelations

parents(a::EdgeRelations) = a.parents
export parents
children(a::EdgeRelations) = a.children
export children

struct DerivativeGraph{T<:Integer}
    postorder_number::Dict{Node,T}
    nodes::Vector{Node}
    roots::Vector{Node}
    variables::Vector{Node}
    root_index_to_postorder_number::Vector{T}
    root_postorder_to_index::Dict{T,T}
    variable_index_to_postorder_number::Vector{T}
    variable_postorder_to_index::Dict{T,T}
    edges::Dict{T,EdgeRelations{T}}
    expression_cache::IdDict

    """postorder numbers the nodes in the roots vector using a global numbering, i.e., the first root gets the numbers 1:length(roots[1]), the second root gets the numbers length(roots[1])+1:length(roots[2])+1, etc. This makes it possible to compute dominance relations, factorization subgraphs, etc., for each ℝ¹→ℝ¹ derivative subgraph using the global postorder numbers, without having to renumber each subgraph with a local set of postorder numbers."""
    function DerivativeGraph(roots::AbstractVector, index_type::Type=Int64)
        postorder_number = IdDict{Node,index_type}()

        (postorder_number, nodes, var_array) = postorder(roots)

        expression_cache = IdDict()

        edges = partial_edges(roots, postorder_number, expression_cache, length(var_array), length(roots))

        @assert length(var_array) != 0 "No variables in your function. Your function must have at least one variable."

        sort!(var_array, by=x -> postorder_number[x]) #sort by postorder number from lowest to highest

        root_index_to_postorder_number = Vector{index_type}(undef, length(roots)) #roots are handled differently than variables because variable node can only occur once in list of variables but root node can occur multiple times in list of roots
        for (i, x) in pairs(roots)
            root_index_to_postorder_number[i] = postorder_number[x]
        end

        root_postorder_to_index = Dict{index_type,index_type}()
        for (i, postorder_number) in pairs(root_index_to_postorder_number)
            root_postorder_to_index[postorder_number] = i
        end

        variable_index_to_postorder_number = [postorder_number[x] for x in var_array]
        variable_postorder_to_index = Dict{index_type,index_type}()
        for (i, postorder_number) in pairs(variable_index_to_postorder_number)
            variable_postorder_to_index[postorder_number] = i
        end

        num_nodes = length(postorder_number)
        compute_edge_paths!(num_nodes, edges, variable_index_to_postorder_number, root_index_to_postorder_number)

        return new{index_type}(
            postorder_number,
            nodes,
            roots,
            var_array,
            root_index_to_postorder_number,
            root_postorder_to_index,
            variable_index_to_postorder_number,
            variable_postorder_to_index,
            edges,
            expression_cache
        )
    end
end
export DerivativeGraph

DerivativeGraph(root::Node) = DerivativeGraph([root]) #convenience constructor for single root functions

nodes(a::DerivativeGraph) = a.nodes
export nodes

node(a::DerivativeGraph, node_index) = nodes(a)[node_index]
export node

num_vertices(a::DerivativeGraph) = length(nodes(a))
export num_vertices

function parents(a::Dict{T,EdgeRelations{T}}, node_index::T) where {T<:Integer}
    nedges = get(a, node_index, nothing)
    return nedges === nothing ? nothing : UnconstrainedPathIterator(node_index, nedges.parents, true)
end

function children(a::Dict{T,EdgeRelations{T}}, node_index::T) where {T<:Integer}
    nedges = get(a, node_index, nothing)
    return nedges === nothing ? nothing : UnconstrainedPathIterator(node_index, nedges.children, false)
end
export children

# parents(constraint_function, a::RnToRmGraph, node_index::T)

"""returns iterator of indices of parents of node"""
parents(a::DerivativeGraph, node_index::T) where {T<:Integer} = parents(edges(a), node_index)


"""returns iterator of indices of children of node"""
children(a::DerivativeGraph, node_index::T) where {T<:Integer} = children(edges(a), node_index)
export children

root_path_masks(a::DerivativeGraph) = a.root_path_masks
variable_path_masks(a::DerivativeGraph) = a.variable_path_masks

each_vertex(a::DerivativeGraph) = 1:length(nodes(a))
export each_vertex
roots(a::DerivativeGraph) = a.roots
export roots
root(a::DerivativeGraph, root_index::Integer) = roots(a)[root_index]
export root
root_index_to_postorder_number(a::DerivativeGraph) = a.root_index_to_postorder_number
export root_index_to_postorder_number
root_index_to_postorder_number(a::DerivativeGraph, index::Integer) = root_index_to_postorder_number(a)[index]

root_postorder_to_index(a::DerivativeGraph, index::Integer) = a.root_postorder_to_index[index]
export root_postorder_to_index



#These two functions are not efficient, primarily intended for visualization
is_root(graph::DerivativeGraph, postorder_index::Integer) = get(graph.root_postorder_to_index, postorder_index, nothing) !== nothing
export is_root
is_variable(graph::DerivativeGraph, postorder_index::Integer) = postorder_index in keys(graph.variable_postorder_to_index)
export is_root


variables(a::DerivativeGraph) = a.variables
export variables
variable(a::DerivativeGraph, variable_index::Integer) = variables(a)[variable_index]
export variable
variable_index_to_postorder_number(a::DerivativeGraph) = a.variable_index_to_postorder_number
export variable_index_to_postorder_number
variable_index_to_postorder_number(a::DerivativeGraph, index::Integer) = get(variable_index_to_postorder_number(a), index, nothing)

variable_postorder_to_index(a::DerivativeGraph, index) = get(a.variable_postorder_to_index, index, nothing)
export variable_postorder_to_index


postorder_number(a::DerivativeGraph, node::Node) = get(a.postorder_number, node, nothing)
export postorder_number

function variable_node_to_index(a::DerivativeGraph, vnode::Node)
    pnum = postorder_number(a, vnode)
    if pnum === nothing
        return nothing
    else
        return variable_postorder_to_index(a, pnum)
    end
end
export variable_node_to_index

edges(a::DerivativeGraph) = a.edges
export edges

"""returns edges that directly connect top_vert and bott_vert"""
function edges(a::DerivativeGraph, vert1::Integer, vert2::Integer)
    @assert 0 < vert1 ≤ length(nodes(a))
    @assert 0 < vert2 ≤ length(nodes(a))

    (bott, top) = (extrema((vert1, vert2)))
    return filter(x -> bott_vertex(x) == bott, child_edges(a, top))
end

"""This is not an especially fast function. Currently only used for testing and diagnostics so this isn't a problem."""
function unique_edges(a::DerivativeGraph)
    edges_unique = Set{PathEdge}()
    for edge_vector in values(edges(a))
        for edge in parents(edge_vector)
            push!(edges_unique, edge)
        end
        for edge in children(edge_vector)
            push!(edges_unique, edge)
        end
    end
    return edges_unique
end
export unique_edges


_node_edges(edge_map::Dict{T,EdgeRelations{T}}, node_index::T) where {T<:Integer} = get(edge_map, node_index, nothing)

node_edges(a::DerivativeGraph, node::Node) = _node_edges(edges(a), postorder_number(a, node)) #if the node doesn't exist in the graph return nothing rather than throwing exception. 
node_edges(a::DerivativeGraph, node_index::Integer) = _node_edges(edges(a), node_index)
export node_edges
# node_edges(a::RnToRmGraph, node_index::Integer) = get(a.edges, node_index, nothing) #if the node doesn't exist in the graph return nothing rather than throwing exception. 
# #version that doesn't require having the entire graph constructed

function reachable_variables(a::DerivativeGraph, node_index::Integer)
    node_edges = children(edges(a)[node_index])
    path_mask = falses(domain_dimension(a))
    for edge in node_edges
        path_mask .= path_mask .| reachable_variables(edge)
    end

    if is_variable(a, node_index) #if node index is a variable then need to set its variable bit. No edge will have node_index as the top_vertex so the bit won't be set in the previous code.
        path_mask[variable_postorder_to_index(a, node_index)] = 1
    end
    return path_mask
end

function reachable_roots(a::DerivativeGraph, node_index::Integer)
    node_edges = parents(edges(a)[node_index])
    path_mask = falses(codomain_dimension(a))
    for edge in node_edges
        path_mask .= path_mask .| reachable_roots(edge)
    end

    #If node is a root then no edges will have it as a bott_vertex. A root is reachable from itself.
    if is_root(a, node_index) #if node_index is a root then need to set it's reachable bit
        path_mask[root_postorder_to_index(a, node_index)] = 1
    end
    return path_mask
end



codomain_dimension(a::DerivativeGraph) = length(roots(a))
export codomain_dimension
domain_dimension(a::DerivativeGraph) = length(variables(a))
export domain_dimension
dimensions(a::DerivativeGraph) = (domain_dimension(a), codomain_dimension(a))
export dimensions

function mean_reachable_variables(a::DerivativeGraph)
    total = 0
    num_edges = 0

    for edge_list in values(edges(a))
        num_edges += length(edge_list)
        total += sum(num_reachable_variables.(edge_list))
    end
    return 0.5 * total / num_edges #halve the result to account for 2x redundancy of edges
end
export mean_reachable_variables

function fraction_reachable_variables(a::DerivativeGraph)
    return mean_reachable_variables(a) / domain_dimension(a)
end
export fraction_reachable_variables

#these functions implicitly assume the nodes are postorder numbered. Parent nodes will have higher numbers than children nodes. Vertices in PathEdge are sorted with highest number first. These are inefficient since the filtering happens at every access. Change to fixed parent, child fields if this is too slow.
"""Returns a vector of edges which satisfy `edge.top_vertex == node_index`. These edges lead to the children of `node_index`."""
function child_edges(dgraph::DerivativeGraph, node_index::T) where {T<:Integer}
    nedges = node_edges(dgraph, node_index)
    if nedges !== nothing
        return children(nedges)
    else
        return PathEdge{T}[] #seems wasteful to return an empty array but other code depends on a zero length return rather than nothing.
    end
end
export child_edges

child_edges(dgraph::DerivativeGraph, node::Node) = child_edges(dgraph, postorder_number(dgraph, node))

child_edges(graph::DerivativeGraph, curr_edge::PathEdge{T}) where {T} = child_edges(graph, (bott_vertex(curr_edge)))

"""The way `parent_edges` works is somewhat subtle. Assume we have a root node `nᵢ` with no parents but some children. No edge in `node_edges(nᵢ)` will pass the test `edge.bott_vertex == node` so `parent_edges` will return T[]. But this empty vector is not explicitly stored in the edge list."""
function parent_edges(dgraph::DerivativeGraph, node::T) where {T<:Integer}
    nedges = _node_edges(edges(dgraph), node)
    if nedges !== nothing
        return parents(nedges)
    else
        return PathEdge{T}[] #seems wasteful to return an empty array but other code depends on a zero length return rather than nothing.
    end
end
export parent_edges

parent_edges(dgraph::DerivativeGraph, node::Node) = parent_edges(dgraph, postorder_number(dgraph, node))

#put this function here because it requires child_edges to be defined before it in the file. And child edges has a dependency on _node_edges so it shouldn't move up.
is_constant(graph::DerivativeGraph, postorder_index::Integer) = is_constant(node(graph, postorder_index))
export is_constant
partial_value(dgraph::DerivativeGraph, parent::Node, child_index::T) where {T<:Integer} = value(child_edges(dgraph, parent)[child_index])
export partial_value

"""Computes partial values for all edges in the graph"""
function _partial_edges(postorder_number::IdDict{Node,Int64}, visited::IdDict{Node,Bool}, current_node::Node{T,N}, edges::Dict{Int64,EdgeRelations{Int64}}, expression_cache::IdDict{Any,Any}, domain_dim, codomain_dim) where {T,N}
    if get(visited, current_node, nothing) !== nothing || N == 0
        return
    else
        visited[current_node] = true #mark as visited


        current_index = postorder_number[current_node]
        for (i, child) in pairs(children(current_node))
            child_index = postorder_number[child]

            edge = PathEdge(current_index, child_index, derivative(current_node, Val(i)), domain_dim, codomain_dim) #Val can be very slow. TODO see if this is affecting speed.

            if get(edges, current_index, nothing) === nothing
                edges[current_index] = EdgeRelations()
            end
            push!(edges[current_index].children, edge)


            if get(edges, child_index, nothing) === nothing
                edges[child_index] = EdgeRelations()
            end
            push!(edges[child_index].parents, edge)


            _partial_edges(postorder_number, visited, child, edges, expression_cache, domain_dim, codomain_dim)
        end
    end
end

"""computes partials for all edges in the ℝⁿ→ℝᵐ graph."""
function partial_edges(roots::AbstractVector{T}, postorder_number::IdDict{Node,Int64}, expression_cache::IdDict, domain_dim::S, codomain_dim::S) where {T<:Node,S<:Integer}
    visited = IdDict{Node,Bool}()
    edges = Dict{Int64,EdgeRelations{Int64}}()

    for root in roots
        _partial_edges(postorder_number, visited, root, edges, expression_cache, domain_dim, codomain_dim)
    end

    return edges
end

function edge_exists(graph::DerivativeGraph, edge::PathEdge)
    edges = node_edges(graph, bott_vertex(edge))
    if edges === nothing
        val1 = false
    else
        val1 = any(value_equal(x, edge) for x in parents(edges))
    end

    edges = node_edges(graph, top_vertex(edge))
    if edges === nothing
        val2 = false
    else
        val2 = any(value_equal(x, edge) for x in children(edges))
    end

    @assert val1 == val2

    return val1 && val2
end

export edge_exists



"""Adds an edge to the graph"""
function add_edge!(graph::DerivativeGraph, edge::PathEdge)
    if edge_exists(graph, edge) #if the edge is already in the graph something is seriously wrong.
        throw(ErrorException("Attempt to add edge to graph but the edge is already in the graph. This should never happen."))
    end

    #add edge to vertex list of nodes for which this will be a parent edge
    vertex_edges = _node_edges(edges(graph), bott_vertex(edge))
    tmp = edges(graph)

    if nothing === vertex_edges #this vertex doesn't yet exist in the graph so add it
        er = EdgeRelations()
        tmp[bott_vertex(edge)] = er
    else
        er = tmp[bott_vertex(edge)]
    end

    push!(parents(er), edge)



    #add edge to vertex list of nodes for which this will be a child edge
    vertex_edges = _node_edges(edges(graph), top_vertex(edge))
    if nothing === vertex_edges #this vertex doesn't yet exist in the graph so add it
        er = EdgeRelations()
        tmp[top_vertex(edge)] = er
    else
        er = tmp[top_vertex(edge)] #vertex already in the graph so add edge to the list of edges connecting to this vertex
    end
    push!(children(er), edge)
    return nothing
end


"""Deletes an edge from the graph"""
function delete_edge!(graph::DerivativeGraph, edge::PathEdge, force::Bool=false)
    if !edge_exists(graph, edge)
        throw(ErrorException("Attempt to delete non-existant edge. This should never happen."))
    end

    if !force
        @assert can_delete(edge) "can only delete edge if no variable or no root can be reached through it."
    end

    #delete edge from bott vertex edge list
    all_edges = edges(graph)
    c_and_p_edges = all_edges[bott_vertex(edge)]
    prnts = parents(c_and_p_edges)
    matching_index = findall(x -> x === edge, prnts)
    @assert length(matching_index) == 1 "Should have found one matching edge but didn't find any or found more than one. This should never happen."
    deleteat!(prnts, matching_index)
    if length(prnts) == 0 && length(children(c_and_p_edges)) == 0
        delete!(all_edges, bott_vertex(edge)) #remove the vertex from all_edges since nothing connects to it anymore
    end


    #delete edge from top vertex edge list
    c_and_p_edges = all_edges[top_vertex(edge)]
    chldrn = children(c_and_p_edges)
    matching_index = findall(x -> x === edge, chldrn)
    @assert length(matching_index) == 1 "Should have found one matching edge but didn't find any or found more than one. This should never happen."
    deleteat!(chldrn, matching_index)
    if length(chldrn) == 0 && length(parents(c_and_p_edges)) == 0
        delete!(all_edges, top_vertex(edge)) #remove the vertex from all_edges since nothing connects to it anymore
    end

    return nothing
end
export delete_edge!

make_function(graph::DerivativeGraph) = make_function(graph, variables(graph))

"""Returns an n vector of Julia functions"""
function make_function(graph::DerivativeGraph, variable_order::AbstractVector{S}) where {S<:Node}
    node_to_var = Dict{Node,Union{Symbol,Real}}()
    body = Expr(:block)
    push!(body.args, :(result = fill(0.0, $(length(roots(graph))))))
    all_vars = variables(graph)
    if variable_order === nothing
        ordering = all_vars
    else
        ordering = Node.(variable_order)
    end

    @assert Set(all_vars) ⊆ Set(ordering) "Not every variable in the graph had a corresponding ordering variable."

    for (i, node) in pairs(roots(graph))
        node_body, variable = function_body(node, node_to_var)
        push!(node_body.args, :(result[$i] = $variable))
        push!(body.args, node_body)
    end

    push!(body.args, :(return result))

    return @RuntimeGeneratedFunction(Expr(:->, Expr(:tuple, map(x -> node_symbol(x), ordering)...), body))
end
export make_function