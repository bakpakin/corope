package.path = package.path .. ';../../../?.lua'

-- Require corope and create a single bundle. A single bundle is probably all you need.
local corope = require 'corope'
local bundle = corope()

-- The ball we will draw
local ball = {
    x = love.graphics.getWidth() / 2,
    y = love.graphics.getHeight() / 2,
    r = 25,
    isMoving = false
}

function love.update(dt)
    -- Without this, nothing happens.
    bundle:update(dt)
end

function love.draw()
    love.graphics.circle('fill', ball.x, ball.y, ball.r)
    if ball.isMoving then
        love.graphics.print('Ball is moving.')
    else
        love.graphics.print('Press space to move the ball.')
    end
end

function love.keypressed(key, scancode, isrepeat)
    if key == 'space' then
        if isrepeat or ball.isMoving then return end
        ball.isMoving = true

        -- Create a rope and move the ball asynchronously.
        bundle(function(rope)

            -- Wait a bit before starting
            rope:wait(0.1)

            -- Tween the x coordinate and the y coordinate to the corner.
            -- Note that tweenFork is non blocking, while tween is.
            rope:tweenFork {
                object = ball,
                key = 'x',
                to = math.random(2 * ball.r, love.graphics.getWidth() - 2 * ball.r),
                time = '1.5s',
                ease = 'cubicout'
            }
            rope:tween {
                object = ball,
                key = 'y',
                to = math.random(2 * ball.r, love.graphics.getHeight() - 2 * ball.r),
                time = '1.5s',
                ease = 'cubicout'
            }

            rope:wait(0.1)

            ball.isMoving = false
        end)

    end
end
