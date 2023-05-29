using POMDPModels: TabularPOMDP

const REGEX_FLOATING_POINT = r"[-+]?[0-9]*\.?[0-9]+"

"""
    Read a `.alpha` file as generated by pomdp-solve.
    Works the same was as `read_pomdp` in `POMDPXFile.jl`.

    The `.alpha` file format is recapped here as follows,
    see: http://www.pomdp.org/code/alpha-file-spec.html

    A set of vectors is the representation use for the value function and each
    vector has an action associated with it. The vectors represent the coefficients
    of a hyperplane passing through the origin. The format specified here is what is
    output from the 'pomdp-solve' program and what will be necessary for input to
    the 'pomdp-solve' program with the '-terminal_values' command line option.

    The format is simply:

    A
    V1 V2 V3 ... VN

    A
    V1 V2 V3 ... VN

    ...


    Where `A` is an action number and the `V1` through `VN` are real values
    representing the components of a particular vector that has the associated
    action. The action number is the 0-based index of the action as specificed in
    the input POMDP file. The vector represents the coefficients of a hyperplane
    representing one facet of the piecewise linear and convex value function.
    Note that the length of the lists needs to be equal to the number of states in
    the POMDP.

    To find which action is the "best" for a given set of alpha vectors, the belief
    state probabilities would be used in a dot product against each alpha vectors'
    coefficients. The action associated with the vector with the highest value is
    the best action to take for that belief state given the value function.
"""
function read_alpha(filename::AbstractString)

    @assert isfile(filename) "filename $(filename) does not exist"

    lines = readlines(open(filename))

    alpha_vector_line_indeces = Int[]
    vector_length = -1
    for i in 1:length(lines)
        
        matches = collect((m.match for m = eachmatch(REGEX_FLOATING_POINT, lines[i])))
        
        if length(matches) > 1
            push!(alpha_vector_line_indeces, i)
            @assert occursin(r"^(\d)*$", lines[i-1]) "previous line must contain an action index"

            if vector_length == -1
                vector_length = length(matches)
            else
                @assert vector_length == length(matches) "vector length is inconsistent. Was $vector_length, is $(length(matches)) on line $i"
            end
        end
    end
    num_alpha_vectors = length(alpha_vector_line_indeces)

    # Initialize the Γ matrix.
    # The α-vectors are the columns
    alpha_vectors = Array{Float64}(undef, vector_length, num_alpha_vectors)

    # Initialize the alpha_actions vector
    # alpha_actions[i] is the index of the action associated with
    # the alpha-vector in the ith column of alpha_vectors
    # Note that these are 0-indexed
    alpha_actions = Array{Int}(undef, num_alpha_vectors)

    for (i,line_index) in enumerate(alpha_vector_line_indeces)
        alpha_actions[i] = parse(Int, lines[line_index-1])

        for (j,match) in enumerate(eachmatch(REGEX_FLOATING_POINT, lines[line_index]))
            alpha_vectors[j,i] = parse(Float64, match.match)
        end
    end

    return alpha_vectors, alpha_actions
end

function read_pomdp(filename::AbstractString)

    @assert isfile(filename) "filename $(filename) does not exist"

    lines = readlines(open(filename))

    alpha_vector_line_indeces = Int[]
    vector_length = -1

    discount = 0
    num_states = 0
    num_actions = 0
    num_observations = 0

    states = 0
    actions = 0
    observations = 0

    all_indices = ':'

    T_lines = Vector{Int64}()
    O_lines = Vector{Int64}()
    R_lines = Vector{Int64}()

    for i in 1:length(lines)
        if occursin(r"discount:", lines[i]) && !occursin(r"#", lines[i])
            discount = parse(Float64, match(REGEX_FLOATING_POINT, lines[i]).match)
        end
        if occursin(r"states:", lines[i]) && !occursin(r"#", lines[i])
            states = split(strip(lines[i]), ' ')
            if length(states) > 2
                num_states = length(states) - 1
                states = states[2:end]
            else
                num_states = parse(Int64, states[2])
                states = collect(string(i) for i in 0:num_states-1)
            end
        end
        if occursin(r"actions:", lines[i]) && !occursin(r"#", lines[i])
            actions = split(strip(lines[i]), ' ')
            if length(actions) > 2
                num_actions = length(actions) - 1
                actions = actions[2:end]
            else
                num_actions = parse(Int64, actions[2])
                actions = collect(string(i) for i in 0:num_actions-1)
            end
        end
        if occursin(r"observations:", lines[i]) && !occursin(r"#", lines[i])
            observations = split(strip(lines[i]), ' ')
            if length(observations) > 2
                num_observations = length(observations) - 1
                observations = observations[2:end]
            else
                num_observations = parse(Int64, observations[2])
                observations = collect(string(i) for i in 0:num_observations-1)
            end
        end
        if occursin(r"T:", lines[i]) || occursin(r"T :", lines[i])
            push!(T_lines, i)
        end
        if occursin(r"O:", lines[i]) || occursin(r"O :", lines[i])
            push!(O_lines, i)
        end
        if occursin(r"R:", lines[i]) || occursin(r"R :", lines[i])
            push!(R_lines, i)
        end
    end

    T = zeros(num_states, num_actions, num_states)
    O = zeros(num_observations, num_actions, num_states)
    R = zeros(num_states, num_actions)

    ind1 = 0
    ind2 = 0
    ind3 = 0

    if length(T_lines) > 0   
        if length(findall(x->x==':', lines[T_lines[1]])) == 3
            for t in T_lines
                l = replace(lines[t], ':'=>' ')
                line = split(l, ' ')
                line = collect(strip(i) for i in line)
                deleteat!(line, findall(x->x=="", line))
                if line[3] == "*"
                    ind1 = collect(1:length(states))
                else
                    ind1 = findall(x->x==line[3], states)
                end
                if line[2] == "*"
                    ind2 = collect(1:length(actions))
                else
                    ind2 = findall(x->x==line[2], actions)
                end
                if line[4] == "*"
                    ind3 = collect(1:length(states))
                else
                    ind3 = findall(x->x==line[4], states)
                end
                T[ind1, ind2, ind3] .= parse(Float64, line[5])
            end
        elseif length(findall(x->x==':', lines[T_lines[1]])) == 2
            for t in T_lines
                l = t+1
                act = strip(split(lines[t], ':')[2])
                st = strip(split(lines[t], ':')[3])
                i = findfirst(x->x==act, actions)
                j = findfirst(x->x==st, states)
                T[j,i,:] = collect((parse(Float64, m.match) for m = eachmatch(REGEX_FLOATING_POINT, lines[l])))
            end
        else
            for t in T_lines
                l = t+1
                id = findall(strip(lines[l]), "identity")
                un = findall(strip(lines[l]), "uniform")
                act = strip(split(lines[t], ':')[2])
                i = findfirst(x->x==act, actions)
                if length(id) > 0
                    for j in 1:num_states
                        T[j,i,j] = 1
                        l += 1
                    end
                elseif length(un) > 0
                    for j in 1:num_states
                        T[j,i,:] = ones(num_states)./num_states
                        l += 1
                    end
                else
                    for j in 1:num_states
                        T[j,i,:] = collect((parse(Float64, m.match) for m = eachmatch(REGEX_FLOATING_POINT, lines[l])))
                        l += 1
                    end
                end
            end
        end
    end

    if length(O_lines) > 0    
        if length(findall(x->x==':', lines[O_lines[1]])) == 3
            for t in O_lines
                l = replace(lines[t], ':'=>' ')
                line = split(l, ' ')
                line = collect(strip(i) for i in line)
                deleteat!(line, findall(x->x=="", line))
                if line[4] == "*"
                    ind1 = collect(1:length(observations))
                else
                    ind1 = findall(x->x==line[4], observations)
                end
                if line[2] == "*"
                    ind2 = collect(1:length(actions))
                else
                    ind2 = findall(x->x==line[2], actions)
                end
                if line[3] == "*"
                    ind3 = collect(1:length(states))
                else
                    ind3 = findall(x->x==line[3], states)
                end
                O[ind1, ind2, ind3] .= parse(Float64, line[5])
            end
        elseif length(findall(x->x==':', lines[O_lines[1]])) == 2
            for t in T_lines
                l = t+1
                act = strip(split(lines[t], ':')[2])
                st = strip(split(lines[t], ':')[3])
                i = findfirst(x->x==act, actions)
                j = findfirst(x->x==st, states)
                O[:,i,j] = collect((parse(Float64, m.match) for m = eachmatch(REGEX_FLOATING_POINT, lines[l])))
            end
        else
            for t in O_lines
                l = t+1
                un = findall(strip(lines[l]), "uniform")
                act = strip(split(lines[t], ':')[2])
                if act == "*"
                    if length(un) > 0
                        for j in 1:num_states
                            for i in 1:num_actions
                                O[:,i,j] = ones(num_observations)./num_observations
                            end
                            l += 1
                        end
                    else
                        for j in 1:num_states
                            for i in 1:num_actions
                                O[:,i,j] = collect((parse(Float64, m.match) for m = eachmatch(REGEX_FLOATING_POINT, lines[l])))
                            end
                            l += 1
                        end
                    end
                else
                    i = findfirst(x->x==act, actions)
                    if length(un) > 0
                        for j in 1:num_states
                            O[:,i,j] = ones(num_observations)./num_observations
                            l += 1
                        end
                    else
                        for j in 1:num_states
                            O[:,i,j] = collect((parse(Float64, m.match) for m = eachmatch(REGEX_FLOATING_POINT, lines[l])))
                            l += 1
                        end
                    end
                end
            end
        end
    end

    if length(R_lines) > 0
        if length(findall(x->x==':', lines[R_lines[1]])) == 4
            for t in R_lines
                l = replace(lines[t], ':'=>' ')
                line = split(l, ' ')
                line = collect(strip(i) for i in line)
                deleteat!(line, findall(x->x=="", line))
                if line[3] == "*"
                    ind1 = collect(1:length(states))
                else
                    ind1 = findall(x->x==line[3], states)
                end
                if line[2] == "*"
                    ind2 = collect(1:length(actions))
                else
                    ind2 = findall(x->x==line[2], actions)
                end
                R[ind1, ind2] .= parse(Float64, line[6])
            end
        elseif length(findall(x->x==':', lines[R_lines[1]])) == 3
            for t in R_lines
                l = t+1
                act = strip(split(lines[t], ':')[2])
                i = findfirst(x->x==act, actions)
                for j in 1:num_states
                    T[j,i,:] = collect((parse(Float64, m.match) for m = eachmatch(REGEX_FLOATING_POINT, lines[l])))
                    l += 1
                end
            end
        else
            for t in R_lines
                l = t+1
                act = strip(split(lines[t], ':')[2])
                i = findfirst(x->x==act, actions)
                for j in 1:num_states
                    T[j,i,:] = collect((parse(Float64, m.match) for m = eachmatch(REGEX_FLOATING_POINT, lines[l])))
                    l += 1
                end
            end
        end
    end

    m = TabularPOMDP(T, R, O, discount)
    return m
    
end
