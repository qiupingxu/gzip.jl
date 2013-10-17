type BitStream
    stream::IOStream
    bv::BitVector
end

typealias GzipFlags Uint8

type GzipHeader
  id::Vector{Uint8} # length 2
  compression_method::Uint8
  flags::GzipFlags
  mtime::Vector{Uint8} # length 4
  extra_flags::Uint8
  os::Uint8
end

has_ext(flags::GzipFlags)     = bool(0x01 & flags)
has_crc(flags::GzipFlags)     = bool(0x02 & flags)
has_extra(flags::GzipFlags)   = bool(0x04 & flags)
has_name(flags::GzipFlags)    = bool(0x08 & flags)
has_comment(flags::GzipFlags) = bool(0x10 & flags)

type GzipFile
  header::GzipHeader
  xlen::Uint16
  extra::Vector{Uint8}
  fname::Vector{Uint8}
  fcomment::Vector{Uint8}
  crc16::Uint16
end

function Base.read(file::IO, ::Type{GzipHeader})
    id = readbytes(file, 2)
    compression_method = read(file, Uint8)
    flags = read(file, GzipFlags)
    mtime = readbytes(file, 4)
    extra_flags = read(file, Uint8)
    os = read(file, Uint8)
    assert(id == [0x1f, 0x8b], "Gzip magic bytes not present")
    assert(compression_method == 8, "Unknown compression method")
    return GzipHeader(id, compression_method, flags, mtime, extra_flags, os)
end

function Base.read(file::IO, ::Type{GzipFile})
    header = read(file, GzipHeader)
    xlen::Uint16 = 0
    extra::Vector{Uint8} = []
    fname::Vector{Uint8} = []
    fcomment::Vector{Uint8} = []
    crc16::Uint16 = 0
    if has_extra(header.flags)
        xlen = read(file, Uint16)
        extra = readbytes(file, xlen)
    end
    if has_name(header.flags)
        fname = readuntil(file, 0x00)
    end
    if has_comment(header.flags)
        fcomment = readuntil(file, 0x00)
    end
    if has_crc(header.flags)
        crc16 = read(file, Uint16)
    end
    return GzipFile(header, xlen, extra, fname, fcomment, crc16)
end

BitStream(io::IOStream) = BitStream(io, BitVector(0))

function make_bitvector(n::Uint8)
    bits = BitVector(8)
    for i=1:8
        bits[i] = n & 0x1
        n >>= 1
    end
    return bits
end

function read_bits(stream::BitStream, n)
    cached_bits = stream.bv
    while n > length(cached_bits)
        byte = read(stream.stream, Uint8)
        new_bits = make_bitvector(byte)
        cached_bits = vcat(cached_bits, new_bits)
    end
    stream.bv = cached_bits[n+1:end]
    return cached_bits[1:n]
end

function read_gzip_byte(bs::BitStream, n)
    bits = reverse!(read_bits(bs, n))
    return make_int(bits)
end

function make_int(bv::BitVector)
    num = 0x00
    for i=1:length(bv)
        num = (num << 1) + bv[i]
    end
    return num
end

function read_huffman_stream(stream)
    n_lit  = make_int(read_bits(stream, 5))
    n_dist = make_int(read_bits(stream, 5))
    n_len  = make_int(read_bits(stream, 4))
    return (n_lit, n_dist, n_len)
end

#read_huffman_stream(file)
