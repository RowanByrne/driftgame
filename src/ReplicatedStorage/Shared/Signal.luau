--!strict
-- Signal: events between modules (docs/workflow/CODING.md "Foundation kit").

export type Connection = {
	Disconnect: (self: Connection) -> (),
	Connected: boolean,
}

local Connection = {}
Connection.__index = Connection

function Connection.Disconnect(self: any)
	if not self.Connected then
		return
	end
	self.Connected = false
	local handlers = self._signal._handlers
	local index = table.find(handlers, self)
	if index then
		table.remove(handlers, index)
	end
end

local Signal = {}
Signal.__index = Signal

export type Signal = typeof(setmetatable(
	{} :: { _handlers: { any } },
	Signal :: any
))

function Signal.new(): Signal
	return setmetatable({ _handlers = {} }, Signal) :: any
end

function Signal.Connect(self: Signal, fn: (...any) -> ()): Connection
	local connection = setmetatable({
		Connected = true,
		_signal = self,
		_fn = fn,
	}, Connection)
	table.insert(self._handlers, connection)
	return connection :: any
end

function Signal.Once(self: Signal, fn: (...any) -> ()): Connection
	local connection: Connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		fn(...)
	end)
	return connection
end

function Signal.Fire(self: Signal, ...: any)
	-- A copy, so a handler that disconnects during the fire doesn't skip the next one.
	for _, connection in table.clone(self._handlers) do
		if connection.Connected then
			task.spawn(connection._fn, ...)
		end
	end
end

function Signal.Wait(self: Signal): ...any
	local thread = coroutine.running()
	self:Once(function(...)
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal.DisconnectAll(self: Signal)
	for _, connection in table.clone(self._handlers) do
		connection:Disconnect()
	end
end

return Signal
