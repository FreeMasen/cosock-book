--- @class BoundedChannelReceiver
--- @field _link BoundedChannel
local BoundedChannelReceiver = {}
BoundedChannelReceiver.__index = BoundedChannelReceiver
BoundedChannelReceiver.__gc = function(t)
  print("GCing recvr", t)
end


--- Create a new receiving half of the channel
function BoundedChannelReceiver.new(shared_queue)
  return setmetatable({_link = shared_queue}, BoundedChannelReceiver)
end

function BoundedChannelReceiver:close()
  self._link:close()
  --- If anytihing is waiting to send, it should wake up with an error
  self._link:try_wake("sendr")
end

function BoundedChannelReceiver:settimeout(timeout)
  self.timeout = timeout
end
local recv_ct = 0
function BoundedChannelReceiver:receive()
  recv_ct = recv_ct + 1
  while true do
    print("recving", recv_ct)
    local can_recv, err = self._link:can_recv()
    print("can_recv", can_recv, err)
    if can_recv then
      local element = self._link:pop_front()
      print("waking sendr")
      self._link:try_wake("sendr")
      return element
    end
    if err == "closed" then
      return nil, err
    end
    if err == "empty" then
      local _r, _s, err = coroutine.yield({self}, nil, self.timeout)
      if err then
        return nil, err
      end
    end
  end
end

function BoundedChannelReceiver:setwaker(kind, waker)
  if kind == "sendr" then
    error("Unsupported wake kind for receiver: " .. tostring(kind))
  end
  self._link:set_waker_recvr(waker)
end

return BoundedChannelReceiver
