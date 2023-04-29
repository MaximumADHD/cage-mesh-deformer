--!strict

local MatrixMxN = {}
MatrixMxN.__index = MatrixMxN

export type Class = typeof(setmetatable({} :: {
    Rows: number,
    Columns: number,
    [number]: { number }
}, MatrixMxN))

local function generateMatrix(rows: number, cols: number): Class
    local self = {
        Rows = rows,
        Columns = cols,
    }

    for row = 1, rows do
        self[row] = table.create(cols, 0)
    end
    
    return setmetatable(self, MatrixMxN)
end

function MatrixMxN.new(grid: {{number}}): Class
    local rows, cols = #grid, #(grid[1] or {})
    assert(rows > 0 and cols > 0)
    
    local self = {
        Rows = rows,
        Cols = cols,
    }
    
    for m = 1, rows do
        for n = 1, cols do
            self[m][n] = assert(grid[m][n])
        end
    end
    
    return setmetatable(self, MatrixMxN)
end

function MatrixMxN.Transpose(self: Class): Class
    local rows = self.Rows
    local cols = self.Columns
    local grid = generateMatrix(cols, rows)
    
    for m = 1, rows do
        for n = 1, cols do
            grid[m][n] = self[n][m]
        end
    end
    
    return grid
end

function MatrixMxN.__add(self: Class, other: Class): Class
    local rows = self.Rows
    assert(rows == other.Rows, "Matrix rows must match!")
    
    local cols = self.Columns
    assert(cols == other.Columns, "Matrix columns must match!")

    local grid = generateMatrix(rows, cols)
    
    for m = 1, rows do
        for n = 1, cols do
            grid[m][n] = self[m][n] + other[m][n]
        end
    end
    
    return grid
end

function MatrixMxN.__mul(self: Class, other: number | Class): Class
    if type(self) == "number" and type(other) == "table" then
        return other * self
    end
    
    if type(other) == "number" then
        local rows = self.Rows
        local cols = self.Columns
        local grid = generateMatrix(rows, cols)
    
        for m = 1, rows do
            for n = 1, cols do
                grid[m][n] = self[m][n] * other
            end
        end
        
        return grid
    else
        local cross = self.Columns
        local grid = generateMatrix(self.Rows, other.Columns) 
        assert(cross == other.Rows, "Undefined matrix multiplication (lh.Columns != rh.Rows)")
        
        for m = 1, grid.Rows do
            for p = 1, grid.Columns do
                for n = 1, cross do
                    grid[m][p] += self[m][n] * other[n][p]
                end
            end
        end
        
        return grid
    end
end

return MatrixMxN 
