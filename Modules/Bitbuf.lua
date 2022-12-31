-------------------------------------------------------------------------------------
-- Bitbuf implements a bit-level buffer, suitable for
-- serialization and storing data in-memory.
-------------------------------------------------------------------------------------
--!strict

local Bitbuf = {}

type Bitbuf = {
	buf: { number },
	len: number,
	i: number,
}

-------------------------------------------------------------------------------------
-- Internal utility functions.
-------------------------------------------------------------------------------------

local function int_from_uint(size: number, v: number): number
	local n = 2 ^ size
	v %= n

	if v >= n / 2 then
		return v - n
	end

	return v
end

local function int_to_uint(size: number, v: number): number
	return v % 2 ^ size
end

local function float_to_fixed(i: number, f: number, v: number): number
	return int_from_uint(i + f, math.floor(v * 2 ^ f))
end

local function float_from_fixed(i: number, f: number, v: number): number
	return math.floor(int_from_uint(i + f, v)) * 2 ^ -f
end

local function float_to_ufixed(i: number, f: number, v: number): number
	return int_to_uint(i + f, math.floor(v * 2 ^ f))
end

local function float_from_ufixed(i: number, f: number, v: number): number
	return math.floor(int_to_uint(i + f, v)) * 2 ^ -f
end

-------------------------------------------------------------------------------------
-- Buffer is a variable-size bit-level buffer with methods for reading and
-- writing various common types.
--
-- The buffer has a cursor to determine where data is read and written, indexed
-- in bits. Methods that read and write advance the cursor automatically by the
-- given size. The buffer grows when the cursor moves beyond the length of the
-- buffer. Bits read past the length of the buffer are returned as zeros.
--
-- Bits are written in little-endian.
-------------------------------------------------------------------------------------

local Buffer = {}
Buffer.__index = Buffer

export type Class = typeof(setmetatable({} :: Bitbuf, Buffer))

-------------------------------------------------------------------------------------
-- Returns a new Buffer *size* bits in length, with the
-- cursor set to 0. Defaults to a zero-length buffer.
-------------------------------------------------------------------------------------

function Bitbuf.new(size: number?): Class
	size = size or 0
	assert(size)
	
	return setmetatable({
		buf = table.create(math.ceil(size / 32), 0),
		len = size,
		i = 0,
	}, Buffer)
end

-------------------------------------------------------------------------------------
-- Returns a Buffer with the contents initialized
-- with the bits of *s*. The cursor is set to 0.
-------------------------------------------------------------------------------------

function Bitbuf.fromString(s: string): Class
	local n = math.ceil(#s / 4)

	local self: Bitbuf = {
		buf = table.create(n, 0),
		len = #s * 8,
		i = 0,
	}

	for i = 0, math.floor(#s / 4) - 1 do
		local a, b, c, d = string.byte(s, i * 4 + 1, i * 4 + 4)
		self.buf[i + 1] = bit32.bor(a, b * 256, c * 65536, d * 16777216)
	end

	for i = 0, #s % 4 - 1 do
		local b = assert(s:byte((n - 1) * 4 + i + 1))
		self.buf[n] = bit32.bor(self.buf[n], b * 256 ^ i)
	end

	return setmetatable(self, Buffer)
end

-------------------------------------------------------------------------------------
-- Converts the content of the buffer to a string. If the length is not
-- a multiple of 8, then the result will be padded with zeros until it is.
-------------------------------------------------------------------------------------

function Buffer.String(self: Class): string
	local n = math.ceil(self.len / 32)
	local s = table.create(n, "")

	for i in ipairs(s) do
		local v = self.buf[i]

		if v then
			s[i] = string.pack("<I4", v)
		else
			s[i] = "\0\0\0\0"
		end
	end

	local rem = self.len % 32

	if rem > 0 then
		-- Truncate to length.
		local v = bit32.band(self.buf[n] or 0, bit32.lshift(1, rem) - 1)
		local width = math.floor((self.len - 1) / 8) % 4 + 1
		s[n] = string.pack("<I" .. width, v)
	end

	return table.concat(s)
end

-------------------------------------------------------------------------------------
-- Writes the first *size* bits of the unsigned integer *v* to
-- the buffer, and advances the cursor by *size* bits. *size* must be
-- an integer between 0 and 32. *v* is normalized according to the bit32 library.
--
-- The capacity of the buffer is extended as needed to write the value.
-- The buffer is assumed to be a sequence of 32-bit unsigned integers.
-------------------------------------------------------------------------------------

function Buffer.WriteUnit(self: Class, size: number, v: number)
	assert(size >= 0 and size <= 32, "size must be in range [0, 32]")

	if size == 0 then
		return
	end

	-- Index of unit in buffer.
	local i = bit32.rshift(self.i, 5) + 1

	-- Index of first unread bit in unit.
	local u = self.i % 32

	if u == 0 and size == 32 then
		self.buf[i] = bit32.band(v, 0xFFFFFFFF)
	else
		-- Index of of unit end relative to first unread bit.
		local f = 32 - u
		local r = size - f

		if r <= 0 then
			-- Size fits within current unit.
			self.buf[i] = bit32.replace(self.buf[i] or 0, v, u, size)
		else
			-- Size extends into next unit.
			self.buf[i] = bit32.replace(self.buf[i] or 0, bit32.extract(v, 0, f), u, f)
			self.buf[i + 1] = bit32.replace(self.buf[i + 1] or 0, bit32.extract(v, f, r), 0, r)
		end
	end

	self.i += size

	if self.i > self.len then
		self.len = self.i
	end
end

-------------------------------------------------------------------------------------
-- Reads *size* bits as an unsigned integer from the buffer, and advances
-- the cursor by *size* bits. *size* must be an integer between 0 and 32.
--
-- The buffer is assumed to be a sequence of 32-bit unsigned integers.
-- Bits past the length of the buffer are read as zeros.
-------------------------------------------------------------------------------------

function Buffer.ReadUnit(self: Class, size: number): number
	assert(size >= 0 and size <= 32, "size must be in range [0, 32]")

	if size == 0 then
		return 0
	end

	local i = bit32.rshift(self.i, 5) + 1
	local u = self.i % 32

	self.i += size

	if self.i > self.len then
		self.len = self.i
	end

	if u == 0 and size == 32 then
		return self.buf[i] or 0
	end

	local f = 32 - u
	local r = f - size

	if r >= 0 then
		return bit32.extract(self.buf[i] or 0, u, size)
	end

	return bit32.bor(bit32.extract(self.buf[i] or 0, u, f), bit32.lshift(bit32.extract(self.buf[i + 1] or 0, 0, -r), f))
end

-------------------------------------------------------------------------------------
-- Returns the length of the buffer in bits.
-------------------------------------------------------------------------------------

function Buffer.Len(self: Class): number
	return self.len
end

-------------------------------------------------------------------------------------
-- Shrinks or grows the length of the buffer. Shrinking truncates
-- the buffer, and growing pads the buffer with zeros. If the
-- cursor is greater than *size*, then it is set to *size*.
-------------------------------------------------------------------------------------

function Buffer.SetLen(self: Class, size: number)
	-- Clear removed portion of buffer.
	size = if size < 0 then 0 else size

	if size < self.len then
		local lower = math.floor(size / 32) + 1

		-- Truncate lower unit.
		if size % 32 == 0 then
			self.buf[lower] = nil
		else
			self.buf[lower] = bit32.band(self.buf[lower], 2 ^ (size % 32) - 1)
		end

		-- Clear everything after lower unit.
		local upper = math.floor((self.len - 1) / 32) + 1

		for i = lower + 1, upper do
			self.buf[i] = nil
		end
	end

	self.len = size

	if self.i > size then
		self.i = size
	end
end

-------------------------------------------------------------------------------------
-- Returns the position of the cursor, in bits.
-------------------------------------------------------------------------------------

function Buffer.Index(self: Class): number
	return self.i
end

-------------------------------------------------------------------------------------
-- Sets the position of the cursor to *i*, in bits. If *i* is greater
-- than the length of the buffer, then buffer is grown to length *i*.
-------------------------------------------------------------------------------------

function Buffer.SetIndex(self: Class, i: number)
	i = (if i < 0 then 0 else i)
	self.i = i

	if i > self.len then
		self.len = i
	end
end

-------------------------------------------------------------------------------------
-- Returns true if *size* bits can be read from or
-- written to the buffer without exceeding its length.
-------------------------------------------------------------------------------------

function Buffer.Fits(self: Class, size: number): boolean
	return size <= self.len - self.i
end

-------------------------------------------------------------------------------------
-- Pads the buffer with *size* zero bits. Does nothing
-- if *size* is less than or equal to zero.
-------------------------------------------------------------------------------------

local function writePad(self: Class, size: number)
	for i = 1, math.floor(size / 32) do
		self:WriteUnit(32, 0)
	end

	self:WriteUnit(size % 32, 0)
end

function Buffer.WritePad(self: Class, size: number)
	if size > 0 then
		writePad(self, size)
	end
end

-------------------------------------------------------------------------------------
-- Moves the cursor by *size* bits without reading any data.
-- Does nothing if *size* is less than or equal to zero.
-------------------------------------------------------------------------------------

local function readPad(self: Class, size: number)
	self.i += size

	if self.i > self.len then
		self.len = self.i
	end
end

function Buffer.ReadPad(self: Class, size: number)
	if size > 0 then
		readPad(self, size)
	end
end

-------------------------------------------------------------------------------------
-- Pads the buffer with zero bits until the position of the cursor is a
-- multiple of *size*. Does nothing if *size* is less than or equal to 1.
-------------------------------------------------------------------------------------

function Buffer.WriteAlign(self: Class, size: number)
	assert(type(size) == "number", "number expected")

	if size > 1 and self.i % size ~= 0 then
		size = math.floor(math.ceil(self.i / size) * size - self.i)
		writePad(self, size)
	end
end

-------------------------------------------------------------------------------------
-- Moves the cursor until its position is a multiple of *size* without
-- reading any data. Does nothing if *size* is less than or equal to 1.
-------------------------------------------------------------------------------------

function Buffer.ReadAlign(self: Class, size: number)
	assert(type(size) == "number", "number expected")

	if size > 1 and self.i % size ~= 0 then
		size = math.floor(math.ceil(self.i / size) * size - self.i)
		readPad(self, size)
	end
end

-------------------------------------------------------------------------------------
-- Clears the buffer, setting the length and cursor to 0.
-------------------------------------------------------------------------------------

function Buffer.Reset(self: Class)
	self.i = 0
	self.len = 0
	table.clear(self.buf)
end

-------------------------------------------------------------------------------------
-- Writes a raw sequence of bytes by assuming
-- that the buffer is aligned to 8 bits
-------------------------------------------------------------------------------------

local function fastWriteBytes(self: Class, s: string)
	-- Handle short string.
	if #s <= 4 then
		self:WriteUnit(#s * 8, (string.unpack("<I" .. #s, s)))
		return
	end

	-- Write until cursor is aligned to unit.
	local a = math.floor(3 - (self.i / 8 - 1) % 4)

	if a > 0 then
		self:WriteUnit(a * 8, (string.unpack("<I" .. a, s)))
	end

	-- Write unit-aligned groups of 32 bits.
	local c = math.floor((#s - a) / 4)
	local n = bit32.rshift(self.i, 5) + 1

	for i = 0, c - 1 do
		self.buf[n + i] = string.unpack("<I4", s, a + i * 4 + 1)
	end

	self.i += c * 32

	if self.i > self.len then
		self.len = self.i
	end

	-- Write remainder.
	local r = (#s - a) % 4

	if r > 0 then
		self:WriteUnit(r * 8, string.unpack("<I" .. r, s, #s - r + 1))
	end
end

-------------------------------------------------------------------------------------
-- Writes *v* by interpreting it as a raw sequence of bytes.
-------------------------------------------------------------------------------------

function Buffer.WriteBytes(self: Class, v: string)
	assert(type(v) == "string", "string expected")

	if v == "" then
		return
	end

	if self.i % 8 == 0 then
		fastWriteBytes(self, v)
		return
	end

	for i = 1, #v do
		self:WriteUnit(8, string.byte(v, i))
	end
end

-------------------------------------------------------------------------------------
-- Reads a raw sequence of bytes by assuming
-- that the buffer is aligned to 8 bits.
-------------------------------------------------------------------------------------

local function fastReadBytes(self: Class, size: number): string
	-- Handle short string.
	if size <= 4 then
		return string.pack("<I" .. size, self:ReadUnit(size * 8))
	end

	local a = math.floor(3 - (self.i / 8 - 1) % 4)
	local r = (size - a) % 4

	local v = table.create((size - a) / 4 + r)
	local i = 1

	-- Read until cursor is aligned to unit.
	if a > 0 then
		v[i] = string.pack("<I" .. a, self:ReadUnit(a * 8))
		i += 1
	end

	-- Read unit-aligned groups of 32 bits.
	local c = math.floor((size - a) / 4)
	local n = bit32.rshift(self.i, 5) + 1

	for j = 0, c - 1 do
		local x = self.buf[n + j]

		if x then
			v[i] = string.pack("<I4", x)
		else
			v[i] = "\0\0\0\0"
		end

		i += 1
	end

	self.i += c * 32

	if i > self.len then
		self.len = i
	end

	-- Read remainder.
	if r > 0 then
		v[i] = string.pack("<I" .. r, self:ReadUnit(r * 8))
	end

	return table.concat(v)
end

-------------------------------------------------------------------------------------
-- Reads *size* bytes from the buffer as a raw sequence of bytes.
-------------------------------------------------------------------------------------

function Buffer.ReadBytes(self: Class, size: number): string
	assert(type(size) == "number", "number expected")

	if size == 0 then
		return ""
	end

	if self.i % 8 == 0 then
		return fastReadBytes(self, size)
	end

	local v = table.create(size, "")

	for i = 1, size do
		v[i] = string.char(self:ReadUnit(8))
	end

	return table.concat(v)
end

-------------------------------------------------------------------------------------
-- Writes *v* as an unsigned integer of *size* bits.
-- *size* must be an integer between 0 and 53.
-------------------------------------------------------------------------------------

function Buffer.WriteUint(self: Class, size: number, v: number)
	assert(type(size) == "number", "number expected for size")
	assert(type(v) == "number", "number expected for v")
	assert(size >= 0 and size <= 53, "size must be in range [0, 53]")

	if size == 0 then
		return
	elseif size <= 32 then
		self:WriteUnit(size, v)
		return
	end

	v %= 2 ^ size
	self:WriteUnit(32, v)
	self:WriteUnit(size - 32, math.floor(v / 2 ^ 32))
end

-------------------------------------------------------------------------------------
-- Reads *size* bits as an unsigned integer.
-- *size* must be an integer between 0 and 53.
-------------------------------------------------------------------------------------

function Buffer.ReadUint(self: Class, size: number): number
	assert(type(size) == "number", "number expected for size")
	assert(size >= 0 and size <= 53, "size must be in range [0, 53]")

	if size == 0 then
		return 0
	elseif size <= 32 then
		return self:ReadUnit(size)
	end

	return self:ReadUnit(32) + self:ReadUnit(size - 32) * 2 ^ 32
end

-------------------------------------------------------------------------------------
-- Writes a 0 bit if *v* is falsy, or a 1 bit if *v* is truthy.
-------------------------------------------------------------------------------------

function Buffer.WriteBool(self: Class, v: any?)
	self:WriteUnit(1, if v then 1 else 0)
end

-------------------------------------------------------------------------------------
-- Reads one bit and returns true if the bit is set to 1.
-------------------------------------------------------------------------------------

function Buffer.ReadBool(self: Class): boolean
	return self:ReadUnit(1) == 1
end

-------------------------------------------------------------------------------------
-- Shorthand for `Buffer:WriteUint(8, v)`.
-------------------------------------------------------------------------------------

function Buffer.WriteByte(self: Class, v: number)
	assert(type(v) == "number", "number expected for v")
	self:WriteUnit(8, v)
end

-------------------------------------------------------------------------------------
-- Shorthand for `Buffer:ReadUint(8, v)`.
-------------------------------------------------------------------------------------

function Buffer.ReadByte(self: Class): number
	return self:ReadUnit(8)
end

-------------------------------------------------------------------------------------
-- Writes *v* as a signed integer of *size* bits.
-- *size* must be an integer between 0 and 53.
-------------------------------------------------------------------------------------

function Buffer.WriteInt(self: Class, size: number, v: number)
	assert(type(size) == "number", "number expected for argument: size")
	assert(type(v) == "number", "number expected for argument: v")
	assert(size >= 0 and size <= 53, "size must be in range [0, 53]")

	if size == 0 then
		return
	end

	v = int_to_uint(size, v)

	if size <= 32 then
		self:WriteUnit(size, v)
		return
	end

	self:WriteUnit(32, v)
	self:WriteUnit(size - 32, math.floor(v / 2 ^ 32))
end

-------------------------------------------------------------------------------------
-- Reads *size* bits as a signed integer.
-- *size* must be an integer between 0 and 53.
-------------------------------------------------------------------------------------

function Buffer.ReadInt(self: Class, size: number): number
	assert(type(size) == "number", "number expected")
	assert(size >= 0 and size <= 53, "size must be in range [0, 53]")

	if size == 0 then
		return 0
	end

	local v: number

	if size <= 32 then
		v = self:ReadUnit(size)
	else
		v = self:ReadUnit(32) + self:ReadUnit(size - 32) * 2 ^ 32
	end

	return int_from_uint(size, v)
end

-------------------------------------------------------------------------------------
-- Writes *v* as a floating-point number. Throws an error
-- if *size* is not one of the following values:
--
-- - `32`: IEEE 754 binary32
-- - `64`: IEEE 754 binary64
-------------------------------------------------------------------------------------

function Buffer.WriteFloat(self: Class, size: number, v: number)
	assert(size == 32 or size == 64, "size must be 32 or 64")
	assert(type(v) == "number", "number expected")

	if size == 32 then
		self:WriteBytes(string.pack("<f", v))
	else
		self:WriteBytes(string.pack("<d", v))
	end
end

-------------------------------------------------------------------------------------
-- Reads a floating-point number. Throws an error
-- if *size* is not one of the following values:
--
-- - `32`: IEEE 754 binary32
-- - `64`: IEEE 754 binary64
-------------------------------------------------------------------------------------

function Buffer.ReadFloat(self: Class, size: number): number
	assert(type(size) == "number", "number expected")
	assert(size == 32 or size == 64, "size must be 32 or 64")

	local s = self:ReadBytes(size / 8)

	if size == 32 then
		return string.unpack("<f", s)
	else
		return string.unpack("<d", s)
	end
end

-------------------------------------------------------------------------------------
-- Writes *v* as an unsigned fixed-point number. *i* is the number of bits
-- used for the integer portion, and *f* is the number of bits used for the
-- fractional portion. Their combined size must be between 0 and 53.
-------------------------------------------------------------------------------------

function Buffer.WriteUfixed(self: Class, i: number, f: number, v: number)
	assert(type(i) == "number", "number expected for argument: i")
	assert(type(f) == "number", "number expected for argument: f")
	assert(type(v) == "number", "number expected for argument: v")

	assert(i >= 0, "integer size must be >= 0")
	assert(f >= 0, "fractional size must be >= 0")
	assert(i + f <= 53, "combined size must be <= 53")

	self:WriteUint(i + f, float_to_ufixed(i, f, v))
end

-------------------------------------------------------------------------------------
-- Reads an unsigned fixed-point number. *i* is the number of bits used
-- for the integer portion, and *f* is the number of bits used for the
-- fractional portion. Their combined size must be between 0 and 53.
-------------------------------------------------------------------------------------

function Buffer.ReadUfixed(self: Class, i: number, f: number): number
	assert(type(i) == "number", "number expected")
	assert(type(f) == "number", "number expected")

	assert(i >= 0, "integer size must be >= 0")
	assert(f >= 0, "fractional size must be >= 0")
	assert(i + f <= 53, "combined size must be <= 53")

	return float_from_ufixed(i, f, self:ReadUint(i + f))
end

-------------------------------------------------------------------------------------
-- Writes *v* as a signed fixed-point number. *i* is the number of bits used
-- for the integer portion, and *f* is the number of bits used for the
-- fractional portion. Their combined size must be between 0 and 53.
-------------------------------------------------------------------------------------

function Buffer.WriteFixed(self: Class, i: number, f: number, v: number)
	assert(type(i) == "number", "number expected for argument: i")
	assert(type(f) == "number", "number expected for argument: f")
	assert(type(v) == "number", "number expected for argument: v")

	assert(i >= 0, "integer size must be >= 0")
	assert(f >= 0, "fractional size must be >= 0")
	assert(i + f <= 53, "combined size must be <= 53")

	self:WriteInt(i + f, float_to_fixed(i, f, v))
end

-------------------------------------------------------------------------------------
-- Reads a signed fixed-point number. *i* is the number of bits used
-- for the integer portion, and *f* is the number of bits used for the
-- fractional portion. Their combined size must be between 0 and 53.
-------------------------------------------------------------------------------------

function Buffer.ReadFixed(self: Class, i: number, f: number): number
	assert(type(i) == "number", "number expected for argument: i")
	assert(type(f) == "number", "number expected for arugment: f")

	assert(i >= 0, "integer size must be >= 0")
	assert(f >= 0, "fractional size must be >= 0")
	assert(i + f <= 53, "combined size must be <= 53")

	return float_from_fixed(i, f, self:ReadInt(i + f))
end

-------------------------------------------------------------------------------------
-- Returns true if the provided value is a Buffer.
-------------------------------------------------------------------------------------

function Bitbuf.isBuffer(value: any): boolean
	return getmetatable(value) == Buffer
end

-------------------------------------------------------------------------------------
-- Module export.
-------------------------------------------------------------------------------------

table.freeze(Bitbuf)
table.freeze(Buffer)

return Bitbuf

-------------------------------------------------------------------------------------
