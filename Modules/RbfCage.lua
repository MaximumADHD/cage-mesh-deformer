local RbfCage = {}
RbfCage.__index = RbfCage

local Modules = script.Parent
local Octree = require(Modules.Octree)
local RobloxMesh = require(Modules.RobloxMesh)

type Octree = Octree.Class
type RobloxMesh = RobloxMesh.Class

export type Class = typeof(setmetatable({} :: {
	_rbf: Octree,
	_verts: Octree,

	_innerCage: RobloxMesh,
	_outerCage: RobloxMesh,
}, RbfCage))

-- I hate this, but it's way more ergonomic to
-- just use one spatial tree implementation.

local function toRbf(uv: Vector2): Vector3
	return Vector3.new(uv.X, 0, uv.Y)
end

function RbfCage.new(innerCage: RobloxMesh, outerCage: RobloxMesh)
	local verts = Octree.new()
	local rbf = Octree.new()

	local innerVerts = innerCage.Verts
	local outerVerts = outerCage.Verts

	for i, vert in innerVerts do
		local pos = vert.Position
		local uv = toRbf(vert.UV)

		local link = {
			InnerVert = vert,
			OuterVert = nil,
		}

		verts:CreateNode(pos, link)
		rbf:CreateNode(uv, link)
	end

	for i, vert in outerVerts do
		local uv = toRbf(vert.UV)
		local links, dists = rbf:kNearestNeighborsSearch(uv, 1, 0.2)

		local link = unpack(links)
		local dist = unpack(dists)

		if link and dist then
			link.OuterVert = vert
			print(i, link, dist)
		end
	end
end

return RbfCage
