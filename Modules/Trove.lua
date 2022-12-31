-- This is a strictly typed binding of sleitnick's Trove module.
-- Use is optional but nice to have.

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage.Packages
local Modules = ReplicatedStorage.Modules

local Trove = require(Packages.Trove)
local Signal = require(Modules.Signal)

type Connection = Signal.Connection
type Signal<T...> = Signal.Typed<T...>

-- stylua: ignore
export type Class = {
	Extend: (self: Class) -> Class,
	Clone: <T>(self: Class, instance: T) -> T,

	Construct: (<T>(self: Class, createFunc: (...any) -> ...any, ...any) -> T)
	         & (<T>(self: Class, classTable: { new: ((...any) -> ...any)? }, ...any) -> T),

	Connect: (<Args...>(self: Class, signal: RBXScriptSignal, fn: (Args...) -> ()) -> RBXScriptConnection)
	       & (<Args...>(self: Class, signal: Signal<Args...>, fn: (Args...) -> ()) -> Connection),

	BindToRenderStep: (self: Class, name: string, priority: number, fn: (dt: number) -> ()) -> (),
	AttachToInstance: (self: Class, instance: Instance) -> RBXScriptConnection,
	Add: <T>(self: Class, object: T, cleanupMethod: string?) -> T,
	Remove: (self: Class, object: any) -> boolean,
	Destroy: (self: Class) -> (),
	Clean: (self: Class) -> (),
}

return Trove :: {
	new: () -> Class,
}
