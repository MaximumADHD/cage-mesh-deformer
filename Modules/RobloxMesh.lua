--!strict

local RobloxMesh = {}
RobloxMesh.__index = RobloxMesh

export type Vertex = {
	Position: Vector3,
	Normal: Vector3,
	UV: Vector2,

	Tangent: {
		Vector: Vector3,
		Sign: number,
	}?,

	Color: {
		Tint: Color3,
		Alpha: number,
	},

	Weights: {
		[string]: number,
	},
}

type Envelope = {
	Bones: { number },
	Weights: { number },
}

type Pose = {
	[string]: CFrame,
}

type Face = { number }
type LOD = { Face }

export type Class = typeof(setmetatable(
	{} :: {
		LODs: { LOD },
		Bones: { Bone }?,
		Verts: { Vertex },

		Morphs: {
			[number]: {
				Label: string,
				Transforms: Pose,
			},
		}?,
	},
	RobloxMesh
))

--------------------------------------------------------------------

local HttpService = game:GetService("HttpService")
local Modules = script.Parent

local Bitbuf = require(Modules.Bitbuf)
local DEG2RAD = math.pi / 180

local function deepClone(t: any, instMap: { [Instance]: Instance }?): any
	local copy = table.clone(t)

	for key, value in pairs(copy) do
		if type(value) == "table" then
			copy[key] = deepClone(value, instMap)
		elseif typeof(value) == "Instance" and instMap then
			local clone = value:Clone()

			if clone then
				instMap[value] = clone
			end
		end
	end

	return copy
end

local function fromV1(file: string): Class
	local readLine = file:gmatch("[^\r\n]+")

	local header = assert(readLine())
	assert(header:sub(1, 8) == "version ", "Not a mesh file")

	local meshVersion = assert(tonumber(header:sub(9)), "Bad version header")
	assert(meshVersion >= 1 and meshVersion < 2, "mesh version not supported: " .. meshVersion)

	local numFaces = assert(tonumber(readLine()), "bad face count")
	local readXYZ = string.gmatch(assert(readLine()), "%[([^,]+),([^,]+),([^%]]+)%]")

	local xs, ys, zs
	local x, y, z

	local function nextVector3(): Vector3
		xs, ys, zs = readXYZ()

		x = tonumber(xs)
		y = tonumber(ys)
		z = tonumber(zs)

		return Vector3.new(x, y, z)
	end

	local function nextVector2(): Vector2
		xs, ys, zs = readXYZ()

		x = tonumber(xs)
		y = tonumber(ys)

		return Vector2.new(x, y)
	end

	local verts: { Vertex } = {}
	local faces: { { number } } = {}

	for i = 1, numFaces do
		for v = 1, 3 do
			local pos = nextVector3()
			local norm = nextVector3()
			local uv = nextVector2()

			if meshVersion < 1.01 then
				pos *= 0.5
			end

			table.insert(verts, {
				Position = pos,
				Normal = norm,
				UV = uv,

				Color = {
					Tint = Color3.new(1, 1, 1),
					Alpha = 1,
				},

				Weights = {},
			})
		end

		local c = i * 3
		local b = c - 1
		local a = b - 1

		local face = { a, b, c }
		table.insert(faces, face)
	end

	return setmetatable({
		LODs = { faces },
		Verts = verts,
	}, RobloxMesh)
end

function RobloxMesh.new(bin: string): Class
	local reader = Bitbuf.fromString(bin)

	local header = reader:ReadBytes(13)
	assert(header:sub(1, 8) == "version ", "Not a mesh file")

	local meshVersion = assert(tonumber(header:match("%d+")), "Bad version header")
	assert(meshVersion >= 1 and meshVersion <= 5, "mesh version not supported: " .. meshVersion)

	if meshVersion < 2 then
		return fromV1(bin)
	end

	local function skip(bytes: number)
		reader:ReadPad(bytes * 8)
	end

	local function readByte(): number
		return reader:ReadByte()
	end

	local function readBytes(count: number): { number }
		local bytes = table.create(count)

		for i = 1, count do
			bytes[i] = readByte()
		end

		return bytes
	end

	local function readFloat(): number
		return reader:ReadFloat(32)
	end

	local function readInt32(): number
		return reader:ReadInt(32)
	end

	local function readUInt16(): number
		return reader:ReadUint(16)
	end

	local function readUInt32(): number
		return reader:ReadUint(32)
	end

	local function readVector2(): Vector2
		local x = readFloat()
		local y = readFloat()

		return Vector2.new(x, y)
	end

	local function readVector3(): Vector3
		local x = readFloat()
		local y = readFloat()
		local z = readFloat()

		return Vector3.new(x, y, z)
	end

	---------------------------------------------------------------------
	-- Read Mesh
	---------------------------------------------------------------------

	local numLODs = 0
	local numVerts = 0
	local numFaces = 0
	local numBones = 0
	local numSubsets = 0

	local vertSize = 0
	local facsDataType = 0
	local boneNamesSize = 0

	-- HeaderSize
	skip(2)

	if meshVersion >= 4 then
		skip(2) -- LodType

		numVerts = readUInt32()
		numFaces = readUInt32()

		numLODs = readUInt16()
		numBones = readUInt16()

		boneNamesSize = readUInt32()
		numSubsets = readUInt16()

		skip(2) -- NumHighQualityLODs

		if meshVersion >= 5 then
			facsDataType = readUInt32()
			skip(4) -- facsDataSize
		end

		vertSize = 40
	else
		vertSize = readByte()
		skip(1) -- faceSize

		if meshVersion >= 3 then
			skip(2) -- lodOffsetSize
			numLODs = readUInt16()
		end

		numVerts = readUInt32()
		numFaces = readUInt32()
	end

	local bones: { Bone } = table.create(numBones)
	local verts: { Vertex } = table.create(numVerts)

	local faces: { { number } } = table.create(numFaces)
	local lodOffsets: { number } = table.create(numLODs)

	-- stylua: ignore
	local envelopes: { Envelope } = table.create(if numBones > 0 then numVerts else 0)

	for i = 1, numVerts do
		local vert: Vertex = {
			Weights = {},

			Color = {
				Tint = Color3.new(1, 1, 1),
				Alpha = 1,
			},

			Position = readVector3(),
			Normal = readVector3(),
			UV = readVector2(),
		}

		local xyzs = readUInt32()

		if xyzs ~= 0 then
			local tx = xyzs % 256
			local ty = bit32.rshift(xyzs, 8) % 256
			local tz = bit32.rshift(xyzs, 16) % 256
			local ts = bit32.rshift(xyzs, 24) % 256

			-- stylua: ignore
			vert.Tangent = {
				Sign = (ts - 127) / 127,

				Vector = Vector3.new(
					(tx - 127) / 127,
					(ty - 127) / 127,
					(tz - 127) / 127
				),
			}
		end

		if vertSize > 36 then
			local r = readByte()
			local g = readByte()
			local b = readByte()

			vert.Color = {
				Tint = Color3.fromRGB(r, g, b),
				Alpha = readByte() / 255,
			}
		end

		verts[i] = vert
	end

	if numBones > 0 then
		for i = 1, numVerts do
			envelopes[i] = {
				Bones = readBytes(4),
				Weights = readBytes(4),
			}
		end
	end

	-- Read Indices
	for i = 1, numFaces do
		local face = table.create(3)

		for j = 1, 3 do
			face[j] = 1 + readUInt32()
		end

		faces[i] = face
	end

	-- Read LOD offsets
	for i = 1, numLODs do
		lodOffsets[i] = readUInt32()
	end

	if numLODs < 2 or lodOffsets[2] == 0 then
		lodOffsets = { 0, numFaces }
		numLODs = 2
	end

	-- Read Bones

	for i = 1, numBones do
		local bone = Instance.new("Bone")
		local nameIndex = readInt32()
		local parentId = readUInt16()

		local _lodParentId = readUInt16()
		local _culling = readFloat()

		bone:SetAttribute("NameIndex", nameIndex)
		bone.Parent = bones[parentId + 1]
		bones[i] = bone

		local m1 = readVector3()
		local m2 = readVector3()
		local m3 = readVector3()
		local m0 = readVector3()

		-- stylua: ignore
		bone.WorldCFrame = CFrame.new(
			m0.X, m0.Y, m0.Z,
			m1.X, m1.Y, m1.Z,
			m2.X, m2.Y, m2.Z,
			m3.X, m3.Y, m3.Z
		)
	end

	-- Read Bone Names
	local boneNames = reader:ReadBytes(boneNamesSize)
	local boneMap = {}

	for i, bone in bones do
		local startAt: number = bone:GetAttribute("NameIndex") + 1
		local endAt = boneNames:find("\0", startAt)

		if endAt then
			local name = boneNames:sub(startAt, endAt - 1)
			boneMap[name] = bone
			bone.Name = name
		end
	end

	-- Read Bone Subsets
	for i = 1, numSubsets do
		local _facesBegin = readUInt32()
		local _facesLength = readUInt32()

		local vertsBegin = readUInt32()
		local vertsEnd = vertsBegin + readUInt32()

		local _numBones = readUInt32()
		local boneSubset = table.create(26, 0)

		for b = 1, 26 do
			boneSubset[b] = readUInt16()
		end

		for v = vertsBegin + 1, vertsEnd do
			local vert = verts[v]
			local envelope = envelopes[v]

			for s = 1, 4 do
				local subsetIndex = 1 + envelope.Bones[s]
				local boneId = boneSubset[subsetIndex]

				if boneId == 0xFFFF then
					continue
				end

				local bone = bones[1 + boneId]
				local weight = envelope.Weights[s]

				if weight > 0 then
					vert.Weights[bone.Name] = weight
				end
			end
		end
	end

	-- Break faces up by LOD
	local lods = table.create(numLODs - 1)

	for L = 1, numLODs - 1 do
		local lodStart = lodOffsets[L]
		local lodEnd = lodOffsets[L + 1]
		local lod = table.create(lodEnd - lodStart)

		for i = lodStart + 1, lodEnd do
			local face = faces[i]
			table.insert(lod, face)
		end

		table.insert(lods, lod)
	end

	-- Read FACS data
	local morphs = {}

	if facsDataType == 1 then
		local sizeof_faceBoneBuffer = readUInt32()
		local sizeof_faceControlBuffer = readUInt32()
		local _sizeof_quantizedTransforms = readUInt32()

		local _unknown = readUInt32()
		local numTwoPoseCorrectives = readUInt32() / 4
		local numThreePoseCorrectives = readUInt32() / 6

		local faceBoneBuffer = reader:ReadBytes(sizeof_faceBoneBuffer)
		local faceControlBuffer = reader:ReadBytes(sizeof_faceControlBuffer)

		local nameStart = 0
		local faceBoneNames = {}
		local faceControlNames = {}

		while true do
			local nameEnd = faceBoneBuffer:find("\0", nameStart)

			if nameEnd then
				local name = faceBoneBuffer:sub(nameStart, nameEnd - 1)
				table.insert(faceBoneNames, name)
				nameStart = nameEnd + 1
			else
				break
			end
		end

		nameStart = 0

		while true do
			local nameEnd = faceControlBuffer:find("\0", nameStart)

			if nameEnd then
				local name = faceControlBuffer:sub(nameStart, nameEnd - 1)
				table.insert(faceControlNames, name)
				nameStart = nameEnd + 1
			else
				break
			end
		end

		local transform = table.create(6)

		for i = 1, 6 do
			local format = readUInt16()
			local rows = readUInt32()
			local cols = readUInt32()

			local matrix = table.create(rows * cols)
			transform[i] = matrix

			if format == 1 then
				for i = 1, rows * cols do
					matrix[i] = readFloat()
				end
			elseif format == 2 then
				local min = readFloat()
				local max = readFloat()

				local range = math.abs(max - min)
				assert(range <= 65535)

				local alpha = if range > 1e-4 then range / 65535 else 0

				for i = 1, rows * cols do
					local value = readUInt16()
					matrix[i] = (value * alpha) + min
				end
			end
		end

		local numPoses = #faceControlNames + numTwoPoseCorrectives + numThreePoseCorrectives
		local poseNames = table.clone(faceControlNames)
		local poses = table.create(numPoses)

		for i = 1, numTwoPoseCorrectives do
			local poseA = faceControlNames[1 + readUInt16()]
			local poseB = faceControlNames[1 + readUInt16()]
			table.insert(poseNames, `{poseA} + {poseB}`)
		end

		for i = 1, numThreePoseCorrectives do
			local poseA = faceControlNames[1 + readUInt16()]
			local poseB = faceControlNames[1 + readUInt16()]
			local poseC = faceControlNames[1 + readUInt16()]
			table.insert(poseNames, `{poseA} + {poseB} + {poseC}`)
		end

		-- stylua: ignore
		local posTblX, posTblY, posTblZ, 
		      rotTblX, rotTblY, rotTblZ = unpack(transform)

		for row, boneName in faceBoneNames do
			local begin = ((row - 1) * numPoses)

			for col = 1, numPoses do
				local pose = poses[col] or {}
				local i = begin + col

				if begin == 0 then
					poses[col] = pose
				end

				local posX = posTblX[i]
				local posY = posTblY[i]
				local posZ = posTblZ[i]

				local rotX = rotTblX[i] * DEG2RAD
				local rotY = rotTblY[i] * DEG2RAD
				local rotZ = rotTblZ[i] * DEG2RAD

				local rot = CFrame.Angles(rotX, rotY, rotZ)
				pose[boneName] = rot * CFrame.new(posX, posY, posZ)
			end
		end

		for i, name in poseNames do
			table.insert(morphs, {
				Label = name,
				Transforms = poses[i],
			})
		end
	end

	return setmetatable({
		Morphs = morphs,
		Bones = bones,
		Verts = verts,
		LODs = lods,
	}, RobloxMesh)
end

function RobloxMesh.Clone(self: Class): Class
	local instMap = {}
	local mesh = deepClone(self, instMap)

	for source, copy in instMap do
		local parent = source.Parent

		if parent and instMap[parent] then
			copy.Parent = instMap[parent]
		end
	end

	return setmetatable(mesh, RobloxMesh)
end

function RobloxMesh.Transform(self: Class, offset: CFrame?, scale: Vector3?): Class
	local copy = self:Clone()

	if scale or offset then
		for i, vert in copy.Verts do
			local pos = vert.Position
			local norm = vert.Normal

			if scale and scale ~= Vector3.one then
				pos *= scale
			end

			if offset and offset ~= CFrame.identity then
				pos = offset:PointToWorldSpace(pos)
				norm = offset:VectorToWorldSpace(norm)
			end

			vert.Position = pos
			vert.Normal = norm
		end
	end

	return copy
end

-- TODO: This doesn't merge bones yet!
--       Doing so will require some transforms.

function RobloxMesh.Append(self: Class, other: Class): Class
	local copy = self:Clone()
	local offset = #copy.Verts

	for i, vert in other.Verts do
		local newVert = deepClone(vert)
		table.insert(copy.Verts, newVert)
	end

	for lod, faces in other.LODs do
		local myFaces = copy.LODs[lod]

		if myFaces == nil then
			myFaces = {}
			copy.LODs[lod] = myFaces
		end

		for i, face in faces do
			local newFace = table.clone(face)

			for f = 1, 3 do
				newFace[f] += offset
			end

			table.insert(myFaces, newFace)
		end
	end

	return copy
end

function RobloxMesh.fromHash(hash: string): Class
	local id = 31

	for char in hash:gmatch(".") do
		local byte = char:byte()
		id = bit32.bxor(id, byte)
	end

	local url = string.format("https://c%d.rbxcdn.com/%s", id % 8, hash)
	local bin = HttpService:GetAsync(url)

	return RobloxMesh.new(bin)
end

function RobloxMesh.fromAssetId(assetId: number): Class
	local url = string.format("http://localhost:20326/asset?id=%i", assetId)
	local bin = HttpService:GetAsync(url, false)
	return RobloxMesh.new(bin)
end

function RobloxMesh.fromAsset(asset: string): Class
	local assetId = tonumber(asset:match("%d+$"))
	assert(assetId, "invalid asset")

	return RobloxMesh.fromAssetId(assetId)
end

function RobloxMesh.empty(): Class
	return setmetatable({
		LODs = { {} },
		Verts = {},
	}, RobloxMesh)
end

return RobloxMesh
