local ReplicatedStorage = game:GetService("ReplicatedStorage")
local QuadTree = require(ReplicatedStorage.Modules.QuadTree)

local rng = Random.new()
local tree = QuadTree.new(16, 4)

for i = 1, 6000 do
	local x = rng:NextNumber(-16, 16)
	local y = rng:NextNumber(-16, 16)

	local part = script.Part:Clone()
	part.Position = Vector3.new(x, 3, y) * 5
	part.Parent = workspace

	local pos = Vector2.new(x, y)
	tree:CreateNode(pos, part)
end

task.wait(3)

local start = os.clock()
local parts, dists = tree:RadiusSearch(Vector2.zero, 16)

local time = os.clock() - start
print("Searched radius", string.format("%.2f ms", time * 1000))

for i, part in parts do
	local dist = dists[i]
	part.Color = Color3.fromHSV(dist / (16 ^ 2), 1, 1)
end
