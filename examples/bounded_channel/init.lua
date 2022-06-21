local BoundedChannelSender = require "examples.bounded_channel.sendr"
local BoundedChannelReceiver = require "examples.bounded_channel.recvr"

---@class BoundedChannel
--- This is the shared table that coordinates messages from one side of the
--- channel to the other. 
---@field _wakers {recvr: fun()?, sendr: fun()?} The two potential wakers
---@field _msg_queue table The pending messages
---@field _closed boolean If the channel has been closed
---@field _max_depth integer The max size of the channel
local BoundedChannel = {}
BoundedChannel.__index = BoundedChannel


--- Create a new channel pair
--- @return BoundedChannelSender
--- @return BoundedChannelReceiver
function BoundedChannel.new(max_depth)
  local link = setmetatable({
    _max_depth = max_depth,
    _wakers = {},
    _msg_queue = {},
    _closed = false,
  }, BoundedChannel)
  return BoundedChannelSender.new(link), BoundedChannelReceiver.new(link)
end

--- Remove the first element from this channel
function BoundedChannel:pop_front()
  return table.remove(self._msg_queue, 1)
end

--- Add a new element to the back of this channel
function BoundedChannel:push_back(ele)
  table.insert(self._msg_queue, ele)
end

--- Set one of the wakers for this BoundedChannel
--- @param kind "recvr"|"sendr"
--- @param waker fun()|nil
function BoundedChannel:setwaker(kind, waker)
  self._wakers[kind] = waker
  if not waker then
    -- If we are setting this waker to `nil` we
    -- don't want to call it so we return early
    return
  end
  if kind == "sendr" and self:can_send() then
    -- Check if sending is currently available, if
    -- so call the waker to wakeup the yielded sender
    waker()
  elseif kind == "recvr" and self:can_recv() then
    -- Check if receiving is currently available, if
    -- so call the waker to wake up the yielded receiver
    waker()
  end
end

--- If `self._wakers[kind]` is not `nil`, call it
function BoundedChannel:try_wake(kind)
  if type(self._wakers[kind]) == "function" then
    self._wakers[kind]()
  end
end

--- Check if sending is currently available, that means we are not closed
--- and the queue size hasn't been reached
---@return number|nil @if 1, we can send if `nil` consult return 2
---@return string|nil @if not `nil` either "closed" or "full"
function BoundedChannel:can_send()
  if self._closed then
    -- Check first that we are not closed, if we are
    -- return an error message
    return nil, "closed"
  end
  if #self._msg_queue >= self._max_depth then
    -- Check next if our queue is full, if it is
    -- return an error message
    return nil, "full"
  end
  -- The queue is not full and we are not closed, return 1
  return 1
end

--- Check if receiving is currently available, that means we are not closed
--- and the queue has at least 1 message
---@return number|nil @if 1, receiving is currently available if `nil` consult return 2
---@return string|nil @if not `nil` either "closed" or "empty"
function BoundedChannel:can_recv()
  if self._closed then
    -- Check first that we haven't closed, if so
    -- return an error message
    return nil, "closed"
  end
  if #self._msg_queue == 0 then
    -- Check next that we have at least 1 message,
    -- if not, return an error message
    return nil, "empty"
  end
  -- We are not closed and we have at least 1 pending message, return 1
  return 1
end

--- Close this channel
function BoundedChannel:close()
  self._closed = true
end

return BoundedChannel
