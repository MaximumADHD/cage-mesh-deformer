--!strict

local CageBuilder = {}
CageBuilder.__index = CageBuilder

local Modules = script.Parent
local Trove = require(Modules.Trove)
local JointTree = require(Modules.JointTree)
local RobloxMesh = require(Modules.RobloxMesh)

type Trove = Trove.Class
type RobloxMesh = RobloxMesh.Class

export type Class = typeof(setmetatable({} :: {
	_model: Model,
	_trove: Trove,

	_targets: {
		[WrapTarget]: RobloxMesh,
	},
}, CageBuilder))

function CageBuilder.new(target: Model)
	local trove = Trove.new()

	local builder = {
		_model = target,
		_trove = trove,
		_targets = {},
	}

	local function onDescendantAdded(desc: Instance)
		if desc:IsA("WrapTarget") then
			local cage = RobloxMesh.fromAsset(desc.CageMeshId)
			builder._targets[desc] = cage:Transform(desc.CageOrigin)
		end
	end

	local function onDescendantRemoving(desc: Instance)
		if desc:IsA("WrapTarget") and builder._targets[desc] then
			builder._targets[desc] = nil
		end
	end

	trove:Connect(target.DescendantAdded, onDescendantAdded)
	trove:Connect(target.DescendantRemoving, onDescendantRemoving)

	for i, desc in target:GetDescendants() do
		onDescendantAdded(desc)
	end

	return setmetatable(builder, CageBuilder)
end

function CageBuilder.BuildSnapshot(self: Class): RobloxMesh
	local cage = RobloxMesh.empty()
	local spanTree, rootPart = JointTree.BuildTree(self._model)

	local assembly = JointTree.ApplyTree(spanTree, {
		[rootPart] = CFrame.identity,
	})

	for part, offset in assembly do
		local target = part:FindFirstChildOfClass("WrapTarget")
		
		-- stylua: ignore
		local mesh = if target
			then self._targets[target]
			else nil

		if mesh then
			local scale: Vector3?

			if part:IsA("MeshPart") then
				scale = part.Size / part.MeshSize
			end

			mesh = mesh:Transform(offset, scale)
			cage:Append(mesh)
		end
	end

	return cage
end

function CageBuilder.Destroy(self: Class)
	self._trove:Destroy()
	table.clear(self._targets)
end

return CageBuilder
