-- This is a strictly typed binding of sleitnick's Signal module.
-- Use is optional but nice to have.

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage.Packages
local Signal: any = require(Packages.Signal)

export type Connection = {
	Connected: boolean,
	Disconnect: (Connection) -> (),
	Destroy: (Connection) -> (),
}

export type Typed<Args...> = {
	Connect: (self: Typed<Args...>, func: (Args...) -> ()) -> Connection,
	ConnectOnce: (self: Typed<Args...>, func: (Args...) -> ()) -> Connection,
	Once: (self: Typed<Args...>, func: (Args...) -> ()) -> Connection,
	GetConnections: (self: Typed<Args...>) -> { Connection },
	DisconnectAll: (self: Typed<Args...>) -> (),
	Fire: (self: Typed<Args...>, Args...) -> (),
	FireDeferred: (self: Typed<Args...>, Args...) -> (),
	Wait: (self: Typed<Args...>) -> (Args...),
	Destroy: (self: Typed<Args...>) -> (),
}

export type Generic = Typed<...any>

local function bind(object: any, signal: any, func: (...any) -> ()): any
	assert(typeof(func) == "function", "bad function bind")
	assert(Signal.Is(signal) or typeof(signal) == "RBXScriptSignal", "bad signal")

	return signal:Connect(function(...)
		func(object, ...)
	end)
end

rawset(Signal, "Bind", bind)

if typeof(rawget(Signal, "Once")) ~= "function" then
	rawset(Signal, "Once", Signal.ConnectOnce)
end

-- stylua: ignore
return Signal :: {
	new: <Args...>() -> Typed<Args...>,
	Is: (object: any) -> boolean,

	Bind: (<T, Args...>(object: T, signal: RBXScriptSignal, func: (T, Args...) -> ()) -> RBXScriptConnection)
		& (<T, Args...>(object: T, signal: Typed<Args...>, func: (T, Args...) -> ()) -> Connection),

	Wrap: <Args...>(signal: RBXScriptSignal) -> Typed<Args...>
}