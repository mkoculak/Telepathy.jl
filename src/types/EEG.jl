abstract type FileType end

struct BDF <: FileType end
struct BVF <: FileType end

Base.show(io::IO, ::Type{BDF}) = print(io, "BDF")
Base.show(io::IO, ::Type{BVF}) = print(io, "BVF")

"""
    Telepathy.Info(filename::String)

    Object containing general information about the file.

    Fields:
        `filename::String`
            Name of the file. Necessary for saving data.
        `participantID::String`
            Individual identifier of the participant (optional).
        `recordingID::String`
            Individual indentifier of the recording (optional).
        `date`
            Date of the recording (optional).
        `history`
            List containg all operations performed in Telepathy on the data.
"""
mutable struct Info{T <: FileType}
    filename::String
    path::String
    participantID::String
    recordingID::String
    date::String
    history::Vector{String}
end

Info(filename) = Info{eval(Symbol(uppercase(filename[end-2:end])))}(filename, "", "", "", "", String[])

"""
    Telepathy.Sensor

    Abstract type grouping different kinds of possible sensors in a recording.
    Currently, Telepathy recognizes the following: EEG, EOG, EMG, ECG, REF, SIG, MISC,
    and STIM.

    While most is self-explanatory, it is worth noting that REF is reserved for electrodes
    serving as reference channels, e.g. mastoids, SIG is a generic type for all sensors
    that should be treated as biological signals. This will assume they are periodic
    in nature and will be processed accordingly (similarly to e.g. EEG).
    MISC on the other hand is a generic type for non-periodic signals. Channels with this
    type will be treated as digital (similarly to STIM).
"""
abstract type Sensor end

struct EEG <: Sensor end
struct EOG <: Sensor end
struct EMG <: Sensor end
struct ECG <: Sensor end
struct REF <: Sensor end
struct SIG <: Sensor end
struct MISC <: Sensor end
struct STIM <: Sensor end

no_module(val) = split(string(val), ".")[2]

Base.show(io::IO, sensor::T) where {T <: Sensor} = print(io, no_module(T))
Base.show(io::IO, ::MIME"text/plain", ::Type{T}) where {T <: Sensor} = print(io, no_module(T))

"""
    Telepathy.Channels(name::Vector{String}, srate::Real)
    Telepathy.Channels(name::Vector{String}, srate::Vector{Real})


    Object containing channel-specific information. Arranged in the same order as columns
    in the data array.

    Fields
        `name::Vector{String}`
            List of names of channels in data.
        `type::Vector{String}`
            List of types of channels in data. Defaults to "EEG", unless declated otherwise.
            Currently Telepathy recognizes "EEG", "EOG", "EMG", and "MISC" types.
        `location::Array{Real}`
            Array containing locations of channels on the scalp (optional).
        `srate::Vector{Real}`
            Array of sampling rates of channels. Defaults to the same value for every channel
            unless declated otherwise.
        `filters::Vector{Dict}`
            Contains filters already applied to the channels. Defaults to the same values 
            for every channel unless declated otherwise.
"""
mutable struct Channels
    name::Vector{String}
    type::Vector{Sensor}
    location::Layout
    srate::Vector{Float64}
    filters::Vector{Dict}
    reference::Vector{Vector{String}}
end

Channels(name, srate) = Channels(name, fill(EEG(), length(name)), EmptyLayout(), srate, Dict[], String[])
Channels(name, srate::Number) = Channels(name, fill(EEG(), length(name)), EmptyLayout(), 
                                fill(convert(Float64,srate), length(name)), Dict[], String[])

"""
    Telepathy.Recording

    General parent type for different data containters in Telepathy.
    Currently includes only `Raw` type.
"""
abstract type Recording end

"""
    Raw(filename::String, name::Vector{String}, srate::Real, data::Array)
    
    Object containing continous signals.

    Fields:
        `info::Info`
            Object containing general information about a file.
        `chans::Channels`
            Object containing channel-specific information.
        `data::Array`
            Array with the signals in the same order as entries in Channels.
        `events::Array`
            Array of timepoint and label pairs marking events in data.
        `status::Dict`
            Dictionary of values extracted from the Status channel of BioSemi .bdf files.
"""
mutable struct Raw{T} <: Recording where T
    info::Info{T}
    chans::Channels
    data::Array
    times::StepRangeLen
    events::Array{Int64}
    status::Dict
    bads::Vector{UnitRange{Int64}}
end

Raw(filename::String, name, srate, data) = Raw(
    Info(filename),
    Channels(name, srate),
    data,
    0:(1/srate):(length(data)/srate),
    Int64[], Dict(), UnitRange{Int64}[]
)

# Overloading some functions from Base to make Raw more workable
Base.length(raw::Raw) = size(raw.data, 2)
Base.size(raw::Raw) = size(raw.data, 2)

# Requirements for indexing Raw as an array Raw.data
Base.getindex(raw::Raw, indices...) = raw.data[_get_data(raw, indices...)...]
Base.setindex!(raw::Raw, v, indices...) = setindex!(raw.data, v, _get_data(raw, indices...)...)

# Commented out first and last index until decided if we want to support `begin` and `end`
# syntax, as it would require changes in get_data - e.g. fixed order of selectors.
#Base.firstindex(raw::Raw) = firstindex(raw.data)
#Base.lastindex(raw::Raw) = lastindex(raw.data)
Base.iterate(raw::Raw, n=1) = n > length(raw) ? nothing : (raw.data[:,n], n+1)
Base.IndexStyle(raw::Raw) = IndexLinear()

Base.axes(raw::Raw) = axes(raw.data)
Base.axes(raw::Raw, d) = axes(raw.data, d)
Base.view(raw::Raw, indices...) = view(raw.data, _get_data(raw, indices...)...)
Base.maybeview(raw::Raw, indices...) = Base.maybeview(raw.data, _get_data(raw, indices...)...)


# Pretty printing structs
function Base.show(io::IO, info::Info{T}) where T 
    printstyled(io, "Info{$T}\n", color=41)
    print(
    io,
    """
    Path .................. $(info.path)
    Filename .............. $(info.filename)
    participant ID ........ $(info.participantID)
    recording ID .......... $(info.recordingID)
    date .................. $(info.date)
    """)
    printstyled(io, "$("-"^23)", color=41)

end

function get_chn_types(chans)
    chnTypes = ""
    for type in unique(chans.type)
        str = string(type)
        chanMask = string.(chans.type) .== str
        chanCount = count(chanMask)
        chnTypes *= " "^(18-length(str))*str*" .... $(chanCount)"
        chanNames = chanCount > 5 ? chans.name[chanMask][1:5] : chans.name[chanMask]
        chnTypes *= chanCount > 5 ? "\t$(join(chanNames, ", "))... \n" : "\t$(join(chanNames, ", "))\n"
    end
    return chnTypes[1:end-1]
end

function get_chn_locations(chans)
    if chans.location == EmptyLayout()
        return "<None>"
    else
        return  "$(valid_locations(chans.location))\t$(chans.location.name)"
    end
end

function get_chn_reference(chans)
    if length(unique(length.(chans.reference))) > 1
        return "Multiple references"
    elseif isempty(chans.reference[1][1])
        return "<None>"
    else
        return chans.reference[1]
    end
end

function get_bads_time(raw::Raw)
    if isempty(raw.bads)
        return 0
    else
        return sum(length.(raw.bads))
    end
end

function Base.show(io::IO, chans::Channels) 
    printstyled(io, "Channel information\n", color=41)
    print(
    io,
    """
    Number of channels .... $(length(chans.name))
    $(get_chn_types(chans))
    Locations ............. $(get_chn_locations(chans))
    Sampling rate ......... $(chans.srate[1]) Hz
    Reference ............. $(get_chn_reference(chans))
    Filtering .............
               Highpass ... $(haskey(chans.filters[1], "Highpass") ? "$(chans.filters[1]["Highpass"]) Hz" : "<None>")
               Lowpass .... $(haskey(chans.filters[1], "Lowpass") ? "$(chans.filters[1]["Lowpass"]) Hz" : "<None>")
               Notch ...... $(haskey(chans.filters[1], "Notch") ? "$(chans.filters[1]["Notch"]) Hz" : "<None>")
    """)
    printstyled(io, "$("-"^23)", color=41)
end

function Base.show(io::IO, raw::Raw)
    printstyled(io, "\nRAW DATA\n", bold=true, color=38)
    show(io, raw.info)
    print(io, "\n\n")
    show(io, raw.chans)
    print(io, "\n\n")
    print(
    io,
    """
    Duration .............. $(samples2time(size(raw.data,1), Float64(raw.chans.srate[1])))
           Bad segments ... $(samples2time(get_bads_time(raw), Float64(raw.chans.srate[1])))
    """
    )
end


mutable struct Epochs{T} <: Recording where T
    info::Info{T}
    chans::Channels
    data::Array
    times::StepRangeLen
    events::Array
    bads::Vector{Int}
end

Epochs(raw::Raw; start=-0.2, stop=0.8) = Epochs(
    raw.info,
    raw.chans,
    create_epochs(raw, start, stop),
    start:1/raw.chans.srate[1]:stop,
    raw.events,
    Int[]
)

function create_epochs(epochs::Array, data::Array, ranges::Vector{UnitRange{Int}})
    for (idx, rang) in enumerate(ranges)
        @views epochs[:,:,idx] = data[rang, :]
    end
end

function create_epochs(raw::Raw, start::Number, stop::Number)
    nEpochs = size(raw.events, 1)
    ranges = Vector{UnitRange{Int}}(undef, nEpochs)
    for i in 1:nEpochs
        ranges[i] = _get_times(raw, start, stop, anchor=raw.events[i,1])
    end
    
    epochs = Array{typeof(raw.data[1]),3}(undef, length(ranges[1]), size(raw.data, 2), nEpochs)
    create_epochs(epochs, raw.data, ranges)

    return epochs
end

function Base.show(io::IO, epochs::Epochs)
    printstyled(io, "\nEPOCHS\n", bold=true, color=38)
    show(io, epochs.info)
    print(io, "\n\n")
    show(io, epochs.chans)
    print(io, "\n\n")
    print(
    io,
    """
    Epochs ................ $(size(epochs.data, 3))
                   Bads ... $(length(epochs.bads))
               Duration ... $(samples2time(size(epochs.data,1), Float64(epochs.chans.srate[1])))
    """
    )
end