--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = ReplicatedStorage.Modules

local RbfCage = require(Modules.RbfCage)
local RobloxMesh = require(Modules.RobloxMesh)
local CageBuilder = require(Modules.CageBuilder)

type RbfCage = RbfCage.Class
type CageMesh = "Reference" | "Cage"

type RobloxMesh = RobloxMesh.Class
type CageBuilder = CageBuilder.Class

local cageBuilders = {} :: {
	[Model]: CageBuilder,
}

local function createWireframe(part: MeshPart, cage: BaseWrap?): WireframeHandleAdornment
	warn("CreateWireframe", part, cage)

	-- stylua: ignore
	local color = Color3.new(0, 1, 1)
	local transparency = 0

	local meshId = part.MeshId
	local offset = CFrame.identity
	local target = part:FindFirstChildWhichIsA("BaseWrap")

	if cage and cage:IsA("WrapLayer") then
		meshId = cage.ReferenceMeshId
		offset = cage.ReferenceOrigin
		color = Color3.new(0, 0, 1)
	elseif target then
		meshId = target.CageMeshId
		offset = target.CageOrigin
		color = Color3.new(1, 0, 0)
		createWireframe(part, target)
	end

	local wireframe = Instance.new("WireframeHandleAdornment")
	wireframe.Transparency = transparency
	wireframe.Color3 = color
	wireframe.Adornee = part
	wireframe.Parent = part

	local success, mesh: RobloxMesh = xpcall(function()
		return RobloxMesh.fromAsset(meshId)
	end, function(err)
		warn("Error loading mesh:", meshId, "because:", err, debug.traceback())
		wireframe:Destroy()
	end)

	if success then
		local scale = part.Size / part.MeshSize
		mesh = mesh:Transform(offset, scale)

		if target then
			local cageBuilder: CageBuilder? = nil
			local rootPart = part.AssemblyRootPart or part

			if rootPart then
				local model = rootPart.Parent

				if model and model:IsA("Model") then
					local builder = cageBuilders[model]

					if not builder then
						builder = CageBuilder.new(model)
						cageBuilders[model] = builder
					end

					cageBuilder = builder
				end
			end

			if cageBuilder and target:IsA("WrapLayer") then
				local refMesh = RobloxMesh.fromAsset(target.ReferenceMeshId)
				refMesh = refMesh:Transform(target.ReferenceOrigin)

				-- Create morph for this layer.
				local rbf = RbfCage.new(refMesh, mesh)

				-- Create snapshot of the target's inner cage.
				local newRefMesh = cageBuilder:BuildSnapshot()

				-- Morph the reference to the target cage.
				local newRbf = rbf:Retarget(newRefMesh)

				-- Render the morphed layer cage.
				mesh = newRbf.OuterCage
			end
		end

		local verts = mesh.Verts
		local faces = mesh.LODs[1]

		for i = 1, #faces do
			local face = faces[i]
			local a, b, c = unpack(face)

			local pointA = verts[a].Position
			local pointB = verts[b].Position
			local pointC = verts[c].Position

			wireframe:AddLine(pointA, pointB)
			wireframe:AddLine(pointB, pointC)
			wireframe:AddLine(pointC, pointA)
		end
	end

	return wireframe
end

local function onDescendantAdded(part: Instance)
	if part:IsA("MeshPart") then
		local wrapLayer: WrapLayer? = part:FindFirstChildOfClass("WrapLayer")

		if wrapLayer then
			local inner = RobloxMesh.fromAsset(wrapLayer.ReferenceMeshId)
			inner = inner:Transform(wrapLayer.ReferenceOrigin)

			local outer = RobloxMesh.fromAsset(wrapLayer.CageMeshId)
			outer = outer:Transform(wrapLayer.CageOrigin)

			local wireframe = createWireframe(part)
			wireframe.Color3 = Color3.new(1, 1, 0)

			local rbf = RbfCage.new(inner, outer)
			part.Transparency = 0.9

			for innerVert, outerVert in rbf.Links do
				wireframe:AddLine(innerVert.Position, outerVert.Position)
			end
		else
			--part.LocalTransparencyModifier = 0.9
		end
	end
end

workspace.DescendantAdded:Connect(onDescendantAdded)

for i, desc in workspace:GetDescendants() do
	task.spawn(onDescendantAdded, desc)
end
