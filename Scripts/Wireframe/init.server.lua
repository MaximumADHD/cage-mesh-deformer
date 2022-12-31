--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RobloxMesh = require(ReplicatedStorage.Modules.RobloxMesh)

type CageMesh = "Reference" | "Cage"
type RobloxMesh = RobloxMesh.Class

local function createWireframe(part: MeshPart, cage: CageMesh?): WireframeHandleAdornment
	-- stylua: ignore
	local baseWrap = if cage
		then part:FindFirstChildWhichIsA("BaseWrap")
		else nil

	local color = Color3.new(0, 1, 1)
	local transparency = 0

	local meshId = part.MeshId
	local offset: CFrame? = nil

	if baseWrap then
		if baseWrap:IsA("WrapTarget") or cage == "Reference" then
			color = Color3.new(0, 1, 0)
		else
			color = Color3.new(1, 0, 1)
		end

		if cage == "Reference" and baseWrap:IsA("WrapLayer") then
			offset = baseWrap.ReferenceOrigin
			meshId = baseWrap.ReferenceMeshId
		elseif cage == "Cage" then
			offset = baseWrap.CageOrigin
			meshId = baseWrap.CageMeshId
		end
	end

	if part:FindFirstChildWhichIsA("BaseWrap") and not cage then
		transparency = 0.8
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

		local bones = mesh.Bones
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

		--[[
		for i, vert in verts do
			local pos = vert.Position
			local normal = vert.Normal
			local tangent = vert.Tangent

			wireframe.Color3 = B
			wireframe:AddLine(pos, pos + (normal / 30))

			if tangent then
				local up = tangent.Vector
				local right = normal:Cross(up) * tangent.Sign

				wireframe.Color3 = G
				wireframe:AddLine(pos, pos + (up / 30))

				wireframe.Color3 = R
				wireframe:AddLine(pos, pos + (right / 30))
			end
		end
		]]
		--

		wireframe.Color3 = Color3.new(1, 0, 1)

		if bones then
			for i, bone in bones do
				local parent = bone.Parent

				if parent and parent:IsA("Attachment") then
					wireframe:AddLine(parent.WorldPosition, bone.WorldPosition)
				end
			end
		end
	end

	return wireframe
end

local function onDescendantAdded(part: Instance)
	if not part:IsA("MeshPart") then
		return
	end

	-- Make Luau happy.
	assert(part:IsA("MeshPart"))

	if part:FindFirstChildOfClass("WrapLayer") then
		createWireframe(part, "Reference")
	end

	createWireframe(part, "Cage")
end

workspace.DescendantAdded:Connect(onDescendantAdded)

for i, desc in workspace:GetDescendants() do
	task.spawn(onDescendantAdded, desc)
end
