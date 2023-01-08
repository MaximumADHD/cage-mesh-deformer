--!strict
local JointTree = {}

type Joints = {
	[BasePart]: SpanningTree,
}

type Assembly = {
	[BasePart]: CFrame,
}

type SpanningTree = {
	{
		Joint: JointInstance,
		Part: BasePart,
	}
}

local function addJointEdge(joints: Joints, joint: JointInstance)
	local _part0 = joint.Part0
	local _part1 = joint.Part1

	if _part0 and _part1 then
		local twoWay = {
			[_part0] = _part1,
			[_part1] = _part0,
		}

		for part0, part1 in twoWay do
			local edges = joints[part0]

			if edges == nil then
				edges = {}
				joints[part0] = edges
			end

			table.insert(edges, {
				Joint = joint,
				Part = part1,
			})
		end
	end
end

local function getRootPart(model: Model, tree: Joints): BasePart
	local rootPart = model.PrimaryPart

	if rootPart == nil then
		local bestPriority = -128
		local bestPart: BasePart?

		for part in tree do
			local priority = part.RootPriority

			if priority < bestPriority then
				continue
			end

			if priority == bestPriority then
				local mass = part.Mass

                -- stylua: ignore
				local bestMass = if bestPart
					then bestPart.Mass
					else 0

				if mass > bestMass then
					bestPart = part
				end
			else
				bestPart = part
			end

			if bestPart == part then
				bestPriority = priority
			end
		end

		rootPart = bestPart
	end

	return assert(rootPart, "Model does not have any assembly root!")
end

local function expandTree(joints: Joints, part0: BasePart, edges: SpanningTree?): SpanningTree
	local adjacent = joints[part0]
	local tree: SpanningTree = edges or {}

	if adjacent then
		-- We only want to iterate over part's edges once, remove edges to mark as visited
		joints[part0] = nil

		for i, edge in adjacent do
			local part = edge.Part

			-- Checks if we've already included this part. This will at least be a list with edge back
			-- to parent unless we've already visited this part through another joint and removed it.
			-- Breaks cycles and prioritizes shortest path to root.

			if joints[part] then
				-- Add the parent-child joint edge to the tree list
				table.insert(tree, edge)

				-- Recursively add child's edges, DFS order. BFS would
				-- have been fine too, but either works just as well.
				expandTree(joints, part, tree)
			end
		end
	end

	return tree
end

local CFrameIndex: any = setmetatable({}, {
	__index = function(self, part: BasePart)
		return part.CFrame
	end,

	__newindex = function(self, part: BasePart, cf: CFrame)
		part.CFrame = cf
	end,
})

--[[
	 Returns a list of assembly edges in some tree-sorted order that can be used by `applyTree` to
	 position other parts in `model` relative to `rootPart` if they would be in the same Assembly
	 under a `WorldRoot`. This roughly imitates what the internal spanning tree that `WorldRoot` uses
	 to build an internal transform hierarchy of parts in an assembly, with some limitations:
	
	 - Only supports Motor6D, and Weld. Didn't bother with legacy Motor, Snap, ManualWeld.
	 - Doesn't support Motor/Motor6D.CurrentAngle and co.
	 - Doesn't support WeldConstraints. Can't. Transform isn't exposed to Lua.
	 - Doesn't prioritize by joint type. Weld should take priority over Motor.
	 - Doesn't prioritize by joint/part GUID. Can't. Not exposed to Lua.
	
	 For a reasonable model, like an R15 character, that doesn't have duplicate or unsupported joints
	 it should produce the same results as the Roblox spanning tree when applied.
	
	 { { joint, childPart }, ... }
]]
--

function JointTree.BuildTree(model: Model): (SpanningTree, BasePart)
	local joints: Joints = {}

	-- Gather the part-joint graph.
	for i, desc in model:GetDescendants() do
		if desc:IsA("JointInstance") and desc.Enabled then
			local p0 = desc.Part0
			local p1 = desc.Part1

			if p0 and p1 then
				-- Add edge to both parts. Assembly joints are bidirectional.
				addJointEdge(joints, desc)
			end
		end
	end

	-- Build the tree, in order, by recursively following edges out from the root part
	-- Joint edge list map: { [part] = { { joint, otherPart }, ...}, ... }
	local rootPart = getRootPart(model, joints)
	return expandTree(joints, rootPart), rootPart
end

function JointTree.ApplyTree(tree: SpanningTree, cframes: Assembly?): Assembly
	if cframes == nil then
		cframes = CFrameIndex
	end

	assert(cframes)

	for i, edge in ipairs(tree) do
		local joint = edge.Joint
		local childPart = edge.Part

		local p0 = joint.Part0
		local p1 = joint.Part1

		if p0 and p1 then
			local c0 = joint.C0
			local c1 = joint.C1

			if p1 == childPart then
				cframes[p1] = cframes[p0] * c0 * c1:Inverse()
			else
				cframes[p0] = cframes[p1] * c1 * c0:Inverse()
			end
		end
	end

	return cframes
end

return JointTree

--------------------------------------------------------------------------------------------------------------------------------------------------------
