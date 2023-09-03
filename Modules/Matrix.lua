--!native
--!strict

local Matrix = {}
type Matrix = { { number } }

function Matrix.Identity(size: number): Matrix
	assert(size > 1)
	size = math.floor(size)

	local self = table.create(size)

	for i = 1, size do
		local row = table.create(size, 0)
		self[i] = row
		row[i] = 1
	end

	return self
end

function Matrix.Multiply(self: Matrix, other: Matrix)
	local size = #self

	for i = 1, size do
		for k = 1, size do
			local dot = 0

			for j = 1, size do
				dot += (self[i][j] * other[j][k])
			end

			self[i][k] = dot
		end
	end
end

function Matrix.ToString(self: Matrix): string
	local size = #self
	local rows = {}

	for i = 1, size do
		local row = {}

		for j = 1, size do
			row[j] = string.format("%8.5f", self[i][j])
		end

		rows[i] = table.concat(row, ", ")
	end

	return table.concat(rows, "\n")
end

-- Gauss-Jordan inverse. Derived from the G3D Matrix implementation by Morgan McGuire:
-- https://github.com/RomkoSI/G3D/blob/master/G3D.lib/source/Matrix.cpp#L1353-L1460
-- Returns nil if the determinant of the Matrix is zero.
local NO_PIVOT = -1

function Matrix.Invert(self: Matrix)
	local size = #self
	local row, col = 1, 1
	local colIndex = table.create(size, 0)
	local rowIndex = table.create(size, 0)
	local pivot = table.create(size, NO_PIVOT)

	-- This is the main loop over the columns to be reduced
	-- Loop over the columns.

	for c = 1, size do
		-- Find the largest element
		-- and use that as a pivot
		local largestMag = 0

		for r = 1, size do
			if pivot[r] == 0 then
				continue
			end

			for k = 1, size do
				if pivot[k] == NO_PIVOT then
					local mag = math.abs(self[r][k])

					if mag >= largestMag then
						largestMag = mag
						row = r
						col = k
					end
				end
			end
		end

		pivot[col] += 1

		-- Interchange columns so that the pivot element is on
		-- the diagonal (we'll have to undo this at the end)

		if row ~= col then
			for k = 1, size do
				self[row][k], self[col][k] = self[col][k], self[row][k]
			end
		end

		local piv = self[col][col]

		if piv == 0 then
			-- Matrix is singular
			return false
		end

		-- The pivot is now at [row, col]
		rowIndex[c] = row
		colIndex[c] = col

		-- Divide everything by the pivot (avoid
		-- computing the division multiple times).
		local pivotInverse = 1 / piv
		self[col][col] = 1

		for k = 1, size do
			self[col][k] *= pivotInverse
		end

		-- Reduce all rows
		for r = 1, size do
			-- Skip over the pivot row
			if r ~= col then
				local oldValue = self[r][col]
				self[r][col] = 0

				for k = 1, size do
					self[r][k] -= (self[col][k] * oldValue)
				end
			end
		end
	end

	-- Put the columns back in
	-- the correct locations

	for i = size, 1, -1 do
		local r = rowIndex[i]
		local c = colIndex[i]

		if r ~= c then
			for k = 1, size do
				self[k][r], self[k][c] = self[k][c], self[k][r]
			end
		end
	end

	return true
end

-- Solves for x in [Ax = B] using LU Decomposition

function Matrix.SolveUsingLU(self: Matrix, targets: Matrix)
	local size = #self
	local lu = Matrix.Identity(size)

	for i = 1, size do
		for j = i, size do
			local sum = 0

			for k = 1, i do
				sum += lu[i][k] * lu[k][j]
			end

			lu[i][j] = self[i][j] - sum
		end

		for j = i + 1, size do
			local sum = 0

			for k = 1, i do
				sum += lu[j][k] * lu[k][i]
			end

			lu[j][i] = (1 / lu[i][i]) * (self[j][i] - sum)
		end
	end

	local dims = #targets[1]
	local solution = table.create(size)

	for dim = 1, dims do
		local rightPart = table.create(size)
		local y = table.create(size, 0)

		for i, col in targets do
			rightPart[i] = col[dim]
		end

		-- lu = L+U-I
		-- find solution of Ly = b
		for i = 1, size do
			local sum = 0

			for k = 1, i do
				sum += lu[i][k] * y[k]
			end

			y[i] = rightPart[i] - sum
		end

		-- find solution of Ux = y
		for i = size, 1, -1 do
			local x = solution[i]
			local sum = 0

			if x == nil then
				x = table.create(dims)
				solution[i] = x
			end

			for k = i + 1, size do
				sum += lu[i][k] * x[k]
			end

			x[dim] = (1 / lu[i][i]) * (y[i] - sum)
		end
	end

	return solution
end

return Matrix
