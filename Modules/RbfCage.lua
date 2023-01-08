--!strict

local RbfCage = {}
RbfCage.__index = RbfCage

local Modules = script.Parent
local Octree = require(Modules.Octree)
local QuadTree = require(Modules.QuadTree)
local RobloxMesh = require(Modules.RobloxMesh)

type Octree = Octree.Class
type QuadTree = QuadTree.Class

type Vertex = RobloxMesh.Vertex
type RobloxMesh = RobloxMesh.Class

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
	local rbf = QuadTree.new(0.1)

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

return RbfCage
