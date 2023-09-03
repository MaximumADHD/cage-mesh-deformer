--!native
--!strict

local CageSolver = {}
CageSolver.__index = CageSolver

local Root = script.Parent
local Matrix = require(Root.Matrix)
local Octree = require(Root.Octree)
local QuadTree = require(Root.QuadTree)
local RobloxMesh = require(Root.RobloxMesh)
local CageBuilder = require(Root.CageBuilder)

type Octree = Octree.Class
type QuadTree = QuadTree.Class
type Vertex = RobloxMesh.Vertex
type RobloxMesh = RobloxMesh.Class
type CageBuilder = CageBuilder.Class

export type Class = typeof(setmetatable({} :: {
	Lookup2D: QuadTree,
	Lookup3D: Octree,

	InnerCage: RobloxMesh,
	OuterCage: RobloxMesh,

	Links: {
		[Vertex]: Vertex,
	},
}, CageSolver))

local function hashUV(uv: Vector2)
	local x = math.round(uv.X * 1e3) / 1e3
	local y = math.round(uv.Y * 1e3) / 1e3
	return math.round(x * 73856093 + y * 19351301)
end

function CageSolver.new(innerCage: RobloxMesh, outerCage: RobloxMesh): Class
	local lookup3D = Octree.new(10)
	local lookup2D = QuadTree.new(0.2)

	local innerVerts = innerCage.Verts
	local outerVerts = outerCage.Verts

	local uvMap = {} :: {
		[number]: {
			InnerVert: Vertex,
			OuterVert: Vertex?,
		},
	}

	for _, vert in innerVerts do
		local pos = vert.Position
		local uv = vert.UV

		local link = {
			InnerVert = vert,
			OuterVert = nil,
		}

		local hash = hashUV(uv)
		uvMap[hash] = link

		lookup2D:CreateNode(uv, link)
		lookup3D:CreateNode(pos, link)
	end

	local linkMap = {} :: {
		[Vertex]: Vertex,
	}

	for i, outerVert in outerVerts do
		local hash = hashUV(outerVert.UV)
		local link = uvMap[hash]

		if link then
			local innerVert = link.InnerVert
			linkMap[innerVert] = outerVert
			link.OuterVert = outerVert
		end
	end

	return setmetatable({
		Lookup2D = lookup2D,
		Lookup3D = lookup3D,

		InnerCage = innerCage,
		OuterCage = outerCage,

		Links = linkMap,
	}, CageSolver)
end

function CageSolver.SolveRbf(self: Class): { Vector3 }
	local _keys = self.InnerCage.Verts
	local _values = self.OuterCage.Verts

	-- Deduplicate verts
	local inputs = #_keys
	local keys = table.create(inputs)
	local values = table.create(#_values)

	for i = 1, inputs do
		local isDup = false
		local key = _keys[i].Position
		local val = _values[i].Position

		for _, otherKey in keys do
			if key:FuzzyEq(otherKey, 1e-5) then
				isDup = true
				break
			end
		end

		if not isDup then
			table.insert(keys, key)
			table.insert(values, val)
		end
	end

	-- Allocate Matrix & Targets
	local size = #keys
	local dists = table.create(size)
	local targets = table.create(size)

	for i = 1, size do
		local pos = values[i]
		dists[i] = table.create(size)
		targets[i] = { pos.X, pos.Y, pos.Z }
	end

	-- Compute Distances
	for i = 1, size do
		for j = i, size do
			local dist = 0

			if i ~= j then
				local keyI = keys[i]
				local keyJ = keys[j]

				dist = (keyJ - keyI).Magnitude
				dists[j][i] = dist
			end

			dists[i][j] = dist
		end
	end

	local solution = Matrix.SolveUsingLU(dists, targets)
	local weights = table.create(size)

	for i, xyz in solution do
		local x, y, z = table.unpack(xyz, 1, 3)
		weights[i] = Vector3.new(x, y, z)
	end

	return weights
end

return CageSolver
