--less_basic_spawn.lua
local cosock = require "cosock"

local function clock_part(name, sleep_first)
    return function()
        if sleep_first then
            cosock.socket.sleep(1)
        end
        while true do
            print(cosock.socket.gettime(), name)
            cosock.socket.sleep(2)
        end
    end
end

cosock.spawn(clock_part("tick"), "tick-task")
cosock.spawn(clock_part("tock", true), "tock-task")
cosock.run()
