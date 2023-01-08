--!strict
local TweenService = game:GetService("TweenService")
local Modules = game.ReplicatedStorage.Modules

local RbfCage = require(Modules.RbfCage)
local RobloxMesh = require(Modules.RobloxMesh)
local CageBuilder = require(Modules.CageBuilder)

local info = TweenInfo.new(2)
local activeDummy: Model? = nil

local activeMesh = RobloxMesh.fromAssetId(11841081909)
script:SetAttribute("Username", "")

local outNode = Instance.new("Part")
outNode.CFrame = workspace.CurrentCamera.Focus
outNode.Transparency = 1
outNode.Anchored = true
outNode.CanCollide = false
outNode.CanQuery = false
outNode.CanTouch = false
outNode.Parent = workspace

type Vertex = RobloxMesh.Vertex
type RobloxMesh = RobloxMesh.Class

local liveVerts = {} :: {
	[number]: Attachment,
}

local function hashUV(uv: Vector2)
	local x = math.round(uv.X * 1e3) / 1e3
	local y = math.round(uv.Y * 1e3) / 1e3
	return math.round(x * 73856093 + y * 19351301)
end

local function makeVert(index: number)
	local vert = activeMesh.Verts[index]
	local hash = hashUV(vert.UV)

	if not liveVerts[hash] then
		local att = Instance.new("Attachment")
		att.Name = tostring(hash)
		att.Position = vert.Position
		att.Parent = outNode

		liveVerts[hash] = att
	end

	return liveVerts[hash], vert.Color.Tint
end

local function makeWire(v0: Attachment, v1: Attachment, color3: Color3)
	if not v0:FindFirstChild(v1.Name) then
		local wire = Instance.new("RodConstraint")
		wire.Visible = true
		wire.Thickness = 0.01
		wire.Attachment0 = v0
		wire.Attachment1 = v1
		wire.Name = v1.Name
		wire.Color = BrickColor.new(color3)
		wire.Parent = v0
	end
end

for i, face in activeMesh.LODs[1] do
	local a, b, c = unpack(face)

	local vertA, color = makeVert(a)
	local vertB = makeVert(b)
	local vertC = makeVert(c)

	makeWire(vertA, vertB, color)
	makeWire(vertB, vertC, color)
	makeWire(vertC, vertA, color)
end

local function switchMesh(newMesh: RobloxMesh)
	local rbf = RbfCage.new(activeMesh, newMesh)
	local marked = {}

	for inner, outer in rbf.Links do
		local hash = hashUV(inner.UV)
		local att = liveVerts[hash]

		if att then
			local tween = TweenService:Create(att, info, {
				Position = outer.Position,
			})

			marked[att] = true
			tween:Play()
		end
	end

	for vert, att in liveVerts do
		if not marked[att] then
			local tween = TweenService:Create(att, info, {
				Position = Vector3.zero,
			})

			tween:Play()
		end
	end
end

local function updateUser()
	local userName = script:GetAttribute("Username")
	local userId = game.Players:GetUserIdFromNameAsync(userName)

	local desc = game.Players:GetHumanoidDescriptionFromUserId(userId)
	local dummy = game.Players:CreateHumanoidModelFromDescription(desc, "R15")

	local primary = assert(dummy.PrimaryPart)
	primary.Anchored = true

	if activeDummy then
		activeDummy:Destroy()
	end

	local playerCage = CageBuilder.new(dummy)
	dummy:PivotTo(outNode.CFrame * CFrame.new(-5, 0, 0))
	dummy.Parent = workspace
	dummy.Name = userName
	activeDummy = dummy

	local cageMesh = playerCage:BuildSnapshot()
	switchMesh(cageMesh)
end

local listener = script:GetAttributeChangedSignal("Username")
listener:Connect(updateUser)
