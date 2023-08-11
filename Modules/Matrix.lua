--!strict

local Matrix = {}
Matrix.__index = Matrix

export type Class = typeof(setmetatable({} :: {
    Size: number,
    [number]: { number }
}, Matrix))

function Matrix.new(grid: {{number}}): Class
    local size = #grid
    
    local self = {
        Size = size,
    }
    
    for i = 1, size do
        self[i] = table.create(size)
        
        for j = 1, size do
            self[i][j] = assert(grid[i][j])
        end
    end
    
    return setmetatable(self, Matrix)
end

function Matrix.identity(size: number): Class
    assert(size > 1)
    size = math.floor(size)
    
    local self = {
        Size = size
    }
    
    for i = 1, size do
        local row = table.create(size, 0)
        self[i] = row
        row[i] = 1
    end
    
    return setmetatable(self, Matrix)
end

function Matrix.__mul(self: Class, other: number | Class): Class
    if type(self) == "number" and type(other) == "table" then
        return other * self
    end
    
    local size = self.Size
    local grid = Matrix.identity(size)
    
    if type(other) == "number" then
        for i = 1, size do
            for j = 1, size do
                grid[i][j] = self[i][j] * other
            end
        end
    else
        for i = 1, size do
            for k = 1, size do
                local dot = 0
                
                for j = 1, size do
                    dot += (self[i][j] * other[j][k])
                end
                
                grid[i][k] = dot
            end
        end
    end
    
    return grid
end

function Matrix.__tostring(self: Class): string
    local rows = {}
    local size = self.Size
    
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

function Matrix.Inverse(self: Class): Class?
    local size = self.Size
    local inv = Matrix.identity(size)
    
    for row = 1, size do
        for col = 1, size do
            inv[row][col] = self[row][col]
        end
    end
    
    local pivot = table.create(size, NO_PIVOT) 
    local colIndex = table.create(size, 0)
    local rowIndex = table.create(size, 0)
    local row, col = 1, 1

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
                    local mag = math.abs(inv[r][k])
                        
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
                inv[row][k], inv[col][k] =
                inv[col][k], inv[row][k]
            end
        end
        
        local piv = inv[col][col]

        if piv == 0 then
            -- Matrix is singular
            return nil
        end

		 -- The pivot is now at [row, col]
        rowIndex[c] = row
        colIndex[c] = col
		
        -- Divide everything by the pivot (avoid 
        -- computing the division multiple times).
        local pivotInverse = 1 / piv
        inv[col][col] = 1
        
        for k = 1, size do
            inv[col][k] *= pivotInverse
        end
        
        -- Reduce all rows
        for r = 1, size do                     
            -- Skip over the pivot row
            if r ~= col then
                local oldValue = inv[r][col]
                inv[r][col] = 0
                
                for k = 1, size do
                    inv[r][k] -= (inv[col][k] * oldValue)
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
                inv[k][r], inv[k][c] =
                inv[k][c], inv[k][r]
            end
        end
    end
    
    return inv
end

return Matrix
