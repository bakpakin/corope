package.path = package.path .. ';../../../?.lua'

-- Require corope and create a single bundle. A single bundle is probably all you need.
local corope = require 'corope'
local bundle = corope()

bundle(function(rope)
    rope:wait(1)
    print "Start"
    rope:parallel(
        function(ropea)
            ropea:wait(0.5)
            print "First"
        end,
        function(ropeb)
            ropeb:wait(1.5)
            print "Second"
        end
    )
    print "Last"
    rope:wait(1)
    os.exit()
end)

-- Without this, nothing happens.
while (true) do
    os.execute("sleep 0.1")
    bundle:update(0.1)
end
