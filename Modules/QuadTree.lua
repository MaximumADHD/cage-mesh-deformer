--!strict

-- FIXME: This is nearly identical to Octree. Their common logic
--        COULD be consolidated, but it's not really worth doing.
--        Juggling the type annotation conflicts is not fun.

local QuadTree = {}
QuadTree.__index = QuadTree

local QuadTreeNode = {}
QuadTreeNode.__index = QuadTreeNode

type Set<T> = { [T]: true }

type Region = {
	subRegions: { Region },
	lowerBounds: Vector2,
	upperBounds: Vector2,
	position: Vector2,
	size: Vector2,

	parent: Region?,
	parentIndex: number?,
	depth: number,

	nodes: Set<QuadTreeNode>,
	nodeCount: number,
}

export type Class = typeof(setmetatable({} :: {
	_maxDepth: number,
	_nodeCount: number,
	_maxRegionSize: Vector2,
	_regionHashMap: { { Region } },
}, QuadTree))

type QuadTreeNode = typeof(setmetatable({} :: {
	_currentLowestRegion: Region?,
	_position: Vector2,

	_quadtree: Class,
	_object: any,
}, QuadTreeNode))

local EPSILON = 1e-9
local SQRT_2 = math.sqrt(2)

local SUB_REGION_POSITION_OFFSET = {
	Vector2.new(0.25, -0.25),
	Vector2.new(-0.25, -0.25),
	Vector2.new(0.25, 0.25),
	Vector2.new(-0.25, 0.25),
}

----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Region Utils
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

local function createRegion(pos: Vector2, size: Vector2, parent: Region?, parentIndex: number?): Region
	return {
		subRegions = {},

		lowerBounds = pos - (size / 2),
		upperBounds = pos + (size / 2),

		position = pos,
		size = size,

		parent = parent,
		parentIndex = parentIndex,

		depth = if parent then parent.depth + 1 else 1,

		nodes = {}, -- [node] = true (contains subchild nodes too)
		nodeCount = 0,
	}
end

local function addNode(lowestSubregion: Region?, node: QuadTreeNode)
	local current = lowestSubregion
	assert(node, "Bad node")

	while current do
		if not current.nodes[node] then
			current.nodes[node] = true
			current.nodeCount += 1
		end

		current = current.parent
	end
end

local function moveNode(fromLowest: Region, toLowest: Region, node: QuadTreeNode)
	assert(fromLowest.depth == toLowest.depth, "fromLowest.depth ~= toLowest.depth")
	assert(fromLowest ~= toLowest, "fromLowest == toLowest")

	local currentFrom: Region? = fromLowest
	local currentTo: Region? = toLowest

	while currentFrom ~= currentTo do
		-- remove from current
		assert(currentFrom, "currentFrom is nil")
		assert(currentFrom.nodes[node], "Not in currentFrom")
		assert(currentFrom.nodeCount > 0, "No nodes in currentFrom")

		currentFrom.nodes[node] = nil
		currentFrom.nodeCount -= 1

		-- remove subregion!
		if currentFrom.nodeCount <= 0 and currentFrom.parentIndex then
			local parentIndex = assert(currentFrom.parentIndex)
			assert(currentFrom.parent, "Bad currentFrom.parent")
			assert(currentFrom.parent.subRegions[parentIndex] == currentFrom, "Not in subregion")
			currentFrom.parent.subRegions[parentIndex] = nil
		end

		-- add to new
		assert(currentTo, "currentTo is nil")
		assert(currentTo.nodes[node] == nil, "Failed to add")

		currentTo.nodes[node] = true
		currentTo.nodeCount += 1

		currentFrom = currentFrom.parent
		currentTo = currentTo.parent
	end
end

local function removeNode(lowestSubregion: Region?, node: QuadTreeNode)
	local current = lowestSubregion
	assert(node, "Bad node")

	while current do
		assert(current.nodes[node], "Not in current")
		assert(current.nodeCount > 0, "Current has bad node count")

		current.nodes[node] = nil
		current.nodeCount -= 1

		-- remove subregion!
		if current.nodeCount <= 0 and current.parentIndex then
			local parentIndex = assert(current.parentIndex)
			assert(current.parent, "No parent")
			assert(current.parent.subRegions[parentIndex] == current, "Not in subregion")
			current.parent.subRegions[parentIndex] = nil
		end

		current = current.parent
	end
end

local function getSearchRadiusSquared(radius: number, diameter: number, epsilon: number): number
	local diagonal = SQRT_2 * diameter
	local searchRadius = radius + diagonal
	return searchRadius * searchRadius + epsilon
end

local function getNeighborsWithinRadius(region: Region, radius: number, position: Vector2, objectsFound: { any }, nodeDistances2: { number }, maxDepth: number)
	local radiusSquared = radius * radius
	local childDiameter = region.size.X / 2
	local searchRadiusSquared = getSearchRadiusSquared(radius, childDiameter, EPSILON)

	-- for each child
	for _, childRegion in region.subRegions do
		local cposition = childRegion.position
		local offset = position - cposition
		local dist2 = offset:Dot(offset)

		-- within search radius
		if dist2 <= searchRadiusSquared then
			if childRegion.depth == maxDepth then
				for node in childRegion.nodes do
					local nodeOffset = position - node._position
					local nodeDist2 = nodeOffset:Dot(nodeOffset)

					if nodeDist2 <= radiusSquared then
						table.insert(objectsFound, node._object)
						table.insert(nodeDistances2, nodeDist2)
					end
				end
			else
				getNeighborsWithinRadius(childRegion, radius, position, objectsFound, nodeDistances2, maxDepth)
			end
		end
	end
end

local function getSubRegionIndex(region: Region, pos: Vector2): number
	local index = pos.X > region.position.X and 1 or 2

	if pos.Y > region.position.Y then
		index += 2
	end

	return index
end

local function createSubRegion(parentRegion: Region, parentIndex: number): Region
	local size = parentRegion.size
	local position = parentRegion.position
	local multiplier = SUB_REGION_POSITION_OFFSET[parentIndex]

	local p = position + (size * multiplier)
	local s = size / 2

	return createRegion(p, s, parentRegion, parentIndex)
end

local function getOrCreateSubRegionAtDepth(region: Region, position: Vector2, maxDepth: number): Region
	local current = region

	for _ = region.depth, maxDepth do
		local index = getSubRegionIndex(current, position)
		local _next = current.subRegions[index]

		-- construct
		if not _next then
			_next = createSubRegion(current, index)
			current.subRegions[index] = _next
		end

		-- iterate
		current = _next
	end

	return current
end

local function inRegionBounds(region: Region, pos: Vector2): boolean
	local lowerBounds = region.lowerBounds
	local upperBounds = region.upperBounds

	-- stylua: ignore
	return (
		pos.X >= lowerBounds.X and
		pos.X <= upperBounds.X and
		pos.Y >= lowerBounds.Y and
		pos.Y <= upperBounds.Y
	)
end

local function getTopLevelRegionHash(c: Vector2): number
	-- Normally you would modulus this to hash table size, but we want as flat of a structure as possible
	return c.X * 73856093 + c.Y * 19351301
end

local function getTopLevelRegionCellIndex(maxRegionSize: Vector2, pos: Vector2): Vector2
	-- stylua: ignore
	return Vector2.new(
		math.floor(pos.X / maxRegionSize.X + 0.5),
		math.floor(pos.Y / maxRegionSize.Y + 0.5)
	)
end

local function getOrCreateRegion(regionHashMap: { { Region } }, maxRegionSize: Vector2, pos: Vector2): Region
	local cell = getTopLevelRegionCellIndex(maxRegionSize, pos)
	local hash = getTopLevelRegionHash(cell)
	local regionList = regionHashMap[hash]

	if regionList == nil then
		regionList = {}
		regionHashMap[hash] = regionList
	end

	local regionPos = maxRegionSize * cell

	for _, region: Region in regionList do
		if region.position == regionPos then
			return region
		end
	end

	local region = createRegion(regionPos, maxRegionSize)
	table.insert(regionList, region)

	return region
end

local function getOrCreateLowestSubRegion(self: Class, pos: Vector2): Region
	local region = getOrCreateRegion(self._regionHashMap, self._maxRegionSize, pos)
	return getOrCreateSubRegionAtDepth(region, pos, self._maxDepth)
end

function QuadTreeNode.new(quadtree: Class, object: any): QuadTreeNode
	return setmetatable({
		_quadtree = assert(quadtree, "No quadtree"),
		_object = assert(object, "No object"),
		_position = Vector2.zero,
	}, QuadTreeNode)
end

function QuadTreeNode.kNearestNeighborsSearch(self: QuadTreeNode, k, radius)
	return self._quadtree:kNearestNeighborsSearch(self._position, k, radius)
end

function QuadTreeNode.GetObject(self: QuadTreeNode): any
	return self._object
end

function QuadTreeNode.RadiusSearch(self: QuadTreeNode, radius: number)
	return self._quadtree:RadiusSearch(self._position, radius)
end

function QuadTreeNode.GetPosition(self: QuadTreeNode)
	return self._position
end

function QuadTreeNode.SetPosition(self: QuadTreeNode, position: Vector2)
	if self._position == position then
		return
	end

	self._position = position

	if self._currentLowestRegion then
		if inRegionBounds(self._currentLowestRegion, position) then
			return
		end
	end

	local newLowestRegion = getOrCreateLowestSubRegion(self._quadtree, position)

	if self._currentLowestRegion then
		moveNode(self._currentLowestRegion, newLowestRegion, self)
	else
		addNode(newLowestRegion, self)
	end

	self._currentLowestRegion = newLowestRegion
end

function QuadTreeNode.Destroy(self: QuadTreeNode)
	if self._currentLowestRegion then
		removeNode(self._currentLowestRegion, self)
	end

	if self._object then
		self._object = nil
		self._quadtree._nodeCount -= 1
	end
end

function QuadTree.new(maxRegionSize: number?, maxDepth: number?): Class
	if maxRegionSize then
		assert(maxRegionSize > 0)
	end

	if maxDepth then
		assert(maxDepth > 0)
	end

	return setmetatable({
		_maxRegionSize = Vector2.one * (maxRegionSize or 64),
		_maxDepth = maxDepth or 4,

		_regionHashMap = {},
		_nodeCount = 0,
	}, QuadTree)
end

function QuadTree.IterNodes(self: Class): () -> QuadTreeNode
	return coroutine.wrap(function()
		for _, regionList in self._regionHashMap do
			for _, region in regionList do
				for node in region.nodes do
					coroutine.yield(node._position, node._object)
				end
			end
		end
	end)
end

function QuadTree.CreateNode(self: Class, pos: Vector2, obj: any): QuadTreeNode
	local object = assert(obj, "Bad object value")
	self._nodeCount += 1

	local node = QuadTreeNode.new(self, object)
	node:SetPosition(pos)

	return node
end

function QuadTree.RadiusSearch(self: Class, position: Vector2, radius: number): ({ any }, { number })
	local objectsFound = table.create(self._nodeCount)
	local nodeDistances2 = table.create(self._nodeCount)

	local diameter = self._maxRegionSize.X
	local searchRadiusSquared = getSearchRadiusSquared(radius, diameter, EPSILON)

	for _, regionList in self._regionHashMap do
		for _, region in regionList do
			local regionPos = region.position
			local offset = position - regionPos
			local dist2 = offset:Dot(offset)

			if dist2 <= searchRadiusSquared then
				getNeighborsWithinRadius(region, radius, position, objectsFound, nodeDistances2, self._maxDepth)
			end
		end
	end

	return objectsFound, nodeDistances2
end

function QuadTree.kNearestNeighborsSearch(self: Class, position: Vector2, k: number, radius: number): ({ any }, { number })
	assert(typeof(position) == "Vector2", "Bad position")
	assert(type(radius) == "number", "Bad radius")

	local objects, nodeDistances2 = self:RadiusSearch(position, radius)
	local sortable = table.create(#objects)

	for index, dist2 in pairs(nodeDistances2) do
		table.insert(sortable, {
			dist2 = dist2,
			index = index,
		})
	end

	table.sort(sortable, function(a, b)
		return a.dist2 < b.dist2
	end)

	local knearest = {}
	local knearestDist2 = {}

	for i = 1, math.min(#sortable, k) do
		local sorted = sortable[i]
		table.insert(knearestDist2, sorted.dist2)
		table.insert(knearest, objects[sorted.index])
	end

	return knearest, knearestDist2
end

return QuadTree
