--!strict

local RbfCage = {}
RbfCage.__index = RbfCage

local Modules = script.Parent
local Octree = require(Modules.Octree)
local QuadTree = require(Modules.QuadTree)
local RobloxMesh = require(Modules.RobloxMesh)
local CageBuilder = require(Modules.CageBuilder)

type Octree = Octree.Class
type QuadTree = QuadTree.Class
type Vertex = RobloxMesh.Vertex
type RobloxMesh = RobloxMesh.Class
type CageBuilder = CageBuilder.Class

type Link = {
	InnerVert: Vertex,
	OuterVert: Vertex,
}

export type Class = typeof(setmetatable({} :: {
	Rbf: QuadTree,
	Verts: Octree,

	InnerCage: RobloxMesh,
	OuterCage: RobloxMesh,

	Links: {
		[Vertex]: Vertex,
	},
}, RbfCage))

local function hashUV(uv: Vector2)
	local x = math.round(uv.X * 1e3) / 1e3
	local y = math.round(uv.Y * 1e3) / 1e3
	return math.round(x * 73856093 + y * 19351301)
end

function RbfCage.new(innerCage: RobloxMesh, outerCage: RobloxMesh): Class
	local verts = Octree.new(10)
	local rbf = QuadTree.new(0.2)

	local innerVerts = innerCage.Verts
	local outerVerts = outerCage.Verts

	local uvMap = {} :: {
		[number]: {
			InnerVert: Vertex,
			OuterVert: Vertex?,
		},
	}

	for i, vert in innerVerts do
		local pos = vert.Position
		local uv = vert.UV

		local link = {
			InnerVert = vert,
			OuterVert = nil,
		}

		local hash = hashUV(uv)
		uvMap[hash] = link

		rbf:CreateNode(uv, link)
		verts:CreateNode(pos, link)
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
		Rbf = rbf,
		Verts = verts,

		InnerCage = innerCage,
		OuterCage = outerCage,

		Links = linkMap,
	}, RbfCage)
end

-- Creates a new RbfCage, morphing the outer layer of
-- this RbfCage onto the provided inner target cage.

function RbfCage.Retarget(self: Class, innerTarget: RobloxMesh): Class
	local outerTarget = innerTarget:Clone()
	local rbf = self.Rbf

	for i, innerVert in innerTarget.Verts do
		local layer: Link? = rbf:kNearestNeighborsSearch(innerVert.UV, 1, 0.1)[1]
		local innerPos = innerVert.Position

		if layer then
			local inner = layer.InnerVert
			local outer = layer.OuterVert

			if inner and outer then
				local refPos = inner.Position
				local cagePos = outer.Position
				local offset = cagePos - refPos

				local outerVert = outerTarget.Verts[i]
				outerVert.Position += offset
			end
		end
	end

	return RbfCage.new(innerTarget, outerTarget)
end

return RbfCage
