--[[
Copyright (c) 2016 Calvin Rose

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
]]

local setmetatable = setmetatable
local create = coroutine.create
local status = coroutine.status
local resume = coroutine.resume
local yield = coroutine.yield
local running = coroutine.running
local type = type
local select = select
local assert = assert
local unpack = unpack or table.unpack

-- Object definitions

local Bundle = {}
local Bundle_mt = {
    __index = Bundle
}

local Rope = {}
local Rope_mt = {
    __index = Rope
}

local function newBundle(options)
    options = options or {}
    return setmetatable({
        ropes = {}, -- Active threads
        signals = {}, -- Signal listeners
        time = 0,
        errhand = options.errhand or print
    }, Bundle_mt)
end

local function newRope(fn, ...)
    return setmetatable({
        thread = create(fn),
        primer = {
            args = {...},
            n = select('#', ...)
        }
    }, Rope_mt)
end

-- Bundle implementation

-- TODO: Should ropes be allowed to change bundles?
function Bundle:suspend(rope)
    assert(rope.bundle == self, 'rope does not belong to this bundle')
    assert(not rope.paused, 'cannot suspend already suspended rope')
    local ts = self.ropes
    local index = rope.index
    rope.paused = true
    ts[index] = ts[#ts]
    ts[index].index = index
    ts[#ts] = nil
end

function Bundle:resume(rope)
    assert(rope.bundle == self, 'rope does not belong to this bundle')
    assert(rope.paused, 'cannot resume active rope')
    local ts = self.ropes
    local newIndex = #ts + 1
    ts[newIndex] = rope
    rope.index = newIndex
    rope.paused = nil
end

function Bundle:update(dseconds)
    local ropes = self.ropes
    local i = 1
    while i <= #ropes do
        local rope = ropes[i]
        local t = rope.thread
        local stat, err
        if rope.primer then
            local n = rope.primer.n
            local args = rope.primer.args
            rope.primer = nil
            stat, err = resume(t, rope, unpack(args, 1, n))
        else
            stat, err = resume(t, dseconds, rope.signal)
        end
        if not stat then
            local errhand = rope.errhand or self.errhand
            errhand(err)
        end
        if status(t) == 'dead' then -- rope has finished
            ropes[i] = ropes[#ropes]
            ropes[i].index = i
            ropes[#ropes] = nil
        else
            i = i + 1
        end
    end
end

function Bundle:rope(fn, ...)
    local ropes = self.ropes
    local index = #ropes + 1
    local rope = newRope(fn, ...)
    rope.index = index
    rope.bundle = self
    ropes[index] = rope
    return rope
end
Bundle_mt.__call = Bundle.rope

-- Rope implmentation

local timeUnitToSeconds = {
    s = 1,
    sec = 1,
    seconds = 1, second = 1,
    ms = 0.001,
    milliseconds = 0.0001, millisecond = 0.0001,
    min = 60, min = 60, mn = 60,
    minutes = 60, minute = 60,
    h = 3600, hs = 3600, hours = 3600, hour = 3600
}

local timeUnitFrames = {
    f = true, fs = true, frames = true, frame = true
}

local function checkCorrectCoroutine(rope)
    if running() ~= rope.thread then
        error('rope function called outside of dispatch function or inside coroutine', 3)
    end
end

function Rope:wait(time)
    checkCorrectCoroutine(self)
    if time == nil then
        return yield()
    end
    local tp = type(time)
    if tp == 'number' then
        while (time > 0) do
            time = time - yield()
        end
    elseif tp == 'string' then
        local numstr, unit = time:match('^(.-)(%a*)$')
        local num = tonumber(numstr) or 1
        if timeUnitFrames[unit] then
            for i = 1, num do
                yield()
            end
        else
            local time = num * (timeUnitToSeconds[unit] or 1)
            while (time > 0) do
                time = time - yield()
            end
        end
    else
        local f = time
        local time = 0
        while not f(time) do
            time = time + yield()
        end
    end
end

-- Generate ease functions - https://github.com/rxi/flux/
local easeFunctions = {}
do
    local expressions = {
        quad    = "p * p",
        cubic   = "p * p * p",
        quart   = "p * p * p * p",
        quint   = "p * p * p * p * p",
        expo    = "2 ^ (10 * (p - 1))",
        sine    = "-math.cos(p * (math.pi * .5)) + 1",
        circ    = "-(math.sqrt(1 - (p * p)) - 1)",
        back    = "p * p * (2.7 * p - 1.7)",
        elastic = "-(2^(10 * (p - 1)) * math.sin((p - 1.075) * (math.pi * 2) / .3))"
    }

    local function makeEaseFunction(str, expr)
        local load = loadstring or load
        return load("return function(p) " .. str:gsub("%$e", expr) .. " end")()
    end

    local function generateEase(name, expression)
        easeFunctions[name] = makeEaseFunction("return $e", expression)
        easeFunctions[name .. "in"] = easeFunctions[name]
        easeFunctions[name .. "out"] = makeEaseFunction([[
        p = 1 - p
        return 1 - ($e)
        ]], expression)
        easeFunctions[name .. "inout"] = makeEaseFunction([[
        p = p * 2
        if p < 1 then
            return .5 * ($e)
        else
            p = 2 - p
            return .5 * (1 - ($e)) + .5
        end
        ]], expression)
    end

    for k, v in pairs(expressions) do
        generateEase(k, v)
    end
    easeFunctions['linear'] = makeEaseFunction('return $e', 'p')
end

function Rope:tween(options)
    checkCorrectCoroutine(self)
    local object = options.object
    local key = options.key
    local to = options.to
    local ease = options.ease or 'linear'
    local timenumstr, timeunit = options.time:match('^(.-)(%a*)$')
    local timenum = tonumber(timenumstr) or 1
    local from = options.from or object[key]
    local scale = to - from
    ease = easeFunctions[ease] or ease
    assert(type(ease) == 'function' or type(ease) == 'table',
        'expected valid name of callable object for easing function')
    if timeUnitFrames[timeunit] then
        local t = 0
        local dt = 1 / timenum
        for frame = 1, timenum do
            object[key] = from + scale * ease(t)
            t = t + dt
            yield()
        end
    else
        object[key] = to
        local tscale = 1 / (timenum * (timeUnitToSeconds[timeunit] or 1))
        local t = 0
        while t < 1 do
            object[key] = from + scale * ease(t)
            local dt = yield()
            t = t + tscale * dt
        end
    end
    object[key] = to
end

function Rope:tweenFork(options)
    return self.bundle(Rope.tween, options)
end

function Rope:fork(fn, ...)
    checkCorrectCoroutine(self)
    return self.bundle(fn, ...)
end

function Rope:listen(name)
    checkCorrectCoroutine(self)
    local bundle = self.bundle
    local signals = bundle.signals
    local slist = signals[name]
    bundle:suspend(self)
    if not slist then
        slist = {}
        signals[name] = slist
    end
    slist[#slist + 1] = self
    local dt, sig = yield()
    return sig
end

function Rope:signal(name, data)
    checkCorrectCoroutine(self)
    local bundle = self.bundle
    local signals = bundle.signals
    local slist = signals[name]
    if slist then
        for i = 1, #slist do
            local rope = slist[i]
            bundle:resume(rope)
            rope.signal = data
        end
        signals[name] = nil
    end
end

function Rope:parallel(...)
    checkCorrectCoroutine(self)
    local bundle = self.bundle
    local n = select('#', ...)
    local ropes = {} -- also used as signal
    local function onDone(rope)
        local pindex = rope.pindex
        ropes[pindex] = ropes[#ropes]
        ropes[pindex].pindex = pindex
        ropes[#ropes] = nil
        if #ropes == 0 then
            rope:signal(ropes, false) -- no error
        end
    end
    for i = 1, n do
        local fn = select(i, ...)
        local function wrappedfn(r)
            fn(r)
            onDone(r)
        end
        local rope = bundle(wrappedfn)
        local function errhand(err)
            for i = 1, #ropes do
                bundle:suspend(ropes[i])
            end
            rope:signal(ropes, err) -- we errored out
        end
        rope.errhand = errhand
        rope.pindex = i
        ropes[#ropes + 1] = rope
    end
    return self:listen(ropes)
end

return newBundle
