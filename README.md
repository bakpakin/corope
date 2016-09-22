# Corope

Corope is a Lua module to help organize your asynchronous code in games or any situation with a timed
main loop. No need for callbacks or
other ugly code to do asynchronous code on a single thread. Using Lua coroutines, Corope allows you to easily
write AI behaviors, animations, scripting systems, and timing related code in a simple style.

The main idea behind Corope is that you create a __bundle__ of __ropes__ to organize your asynchronous tasks. Each rope
is like a thread, but with more built-in goodies. A bundle, also called a dispatcher in some contexts, keeps track of
all of your ropes and can create new ropes. Each rope can wait, or do block operations, without halting other ropes, or
relying on ugly constructs like callbacks.

Here is an example using LOVE. Note that Corope does not require LOVE or indeed any environment other than
a default Lua environment to work properly.

```lua

-- Require the module and create our bundle object
local corope = require 'corope'
local bundle = corope()

function love.update(dt)
    bundle:update(dt)
end

-- Run this asynchronously
bundle(function(rope)
    rope:wait(0.5) -- wait half a second
    for i = 1, 10 do
        print(i)
        rope:wait(1)
    end
end)

-- Also run this asynchronously
bundle(function(rope)
    for i = 1, 10 do
        print('Hey! ' .. i)
        rope:wait(1)
    end
end)
```
Besides a simple wait function, Corope also provides tweening and signals for communication between ropes.
Corope can do more than what is shown here. Docs coming soon.

## API

### Creating a Bundle
```lua
local corope = require 'corope'
local bundle = corope(options)
```

The Corope module is a function used to create a bundle. Takes one optional argument, an
options table.

The current options are:

* `errhand` - A function to handle errors when a rope throws an error. Defaults to `print`.

### Bundle

#### `Bundle:rope(fn, ...)`
#### `Bundle(fn, ...)`

Creates a new rope. The first argument, `fn`, is mandatory and contains the logic of the rope in
a function. It should take at least one argument, the first argument being the new rope object for
use inside the dispatch function. It returns the new rope object as well. The remaining optional
arguments are passed to the dispatch function `fn`, after the original rope object.

#### `Bundle:update(dt)`

Update all ropes in the Bundle. Place this function in your main loop and ensure that it is called
every frame/interval. If this is not called, literally nothing will happen with your ropes. The only
parameter is `dt`, which is the number of seconds that have passed since the previous update. `dt` does
not strictly have to be in seconds, but some of the arguments to `Rope:wait` expect `dt` to be in seconds.


#### `Bundle:suspend(rope)`

Suspend execution of a rope. This essentially just removes the rope from a list of ropes
that are update every frame/interval and marks it as paused. Only use this for ropes belong to the bundle.
Using other bundle's ropes will throw an error. The rope can be resumed later, or it can be eventually
garbage collected.

#### `Bundle:resume(rope)`

Restart a Rope that has been suspend. Only use this for ropes belong to the bundle.
Using other bundle's ropes will throw an error.

### Rope

Rope functions should only be called inside the rope dispatch function. Calling them outside the dispatch
function or inside another coroutine will throw an error.

#### `Rope:wait(amount)`

Wait a certain amount of time before continuing. Note the resolution of the wait is entirely
dependent on how frequently you update the Bundle. `amount` can be either a number, string, function,
or nothing

* nothing/nil - waits a single frame regardless of dt.
* number - waits the specified number of seconds
* function - waits until the function evaluates to truthy.
* string - waits an amount of time specified by a number followed by a unit.
  Units are as follows:
  * 's/seconds' - Seconds
  * 'm/minutes' - Minutes
  * 'h/hours' - Hours
  * 'f/frames' - Number of frames (ignores dt)

#### `Rope:fork(fn, ...)`

Convenience function for `rope.bundle(fn, ...)`. Makes a new rope that belongs to
the same bundle as the current rope.

#### `Rope:listen(name)`

Useful for inter-rope communication within a Bundle. The rope blocks until a signal of
the given name is broadcasted. Returns the data associated with the signal.

#### `Rope:signal(name, data)`

Broadcasts a signal to all other ropes in the Bundle. If they are listening, they
resume with the data in the current update cycle. This call does not block the rope.

#### `Rope:tween(options)`

A very useful method for doing animations or other tweening over a period of time. The tweening
is performed by continually updating a value in a table over a period of time. This method blocks until
the tweening is completed.
Takes one argument, options,
which is a table of parameters for tweening a value in an object.

* `object` - The table to tween in. Required.
* `key` - The key to tween in the given `object`. Required.
* `from` - The starting (numeric) value of the tween. Defaults the current `object[key]`.
* `to` - The final value for the tween. Required.
* `time` - The total amount of time to tween. Takes the same arguments as Rope:wait. Required.
* `ease` - The easing method to use. Uses the same methods as [flux](https://github.com/rxi/flux), plus some extras. Defaults to linear.

#### `Rope:tweenFork(options)`

The same as Rope:tween, but does not block. Useful for setting off a bunch of animations at the same time. (Or you can use Rope:fork).

#### `Rope:parallel(...)`

Create any number of knew rope (like Rope:fork), but block until they are all complete or one errors out.
Returns success in the first argument, or false and an error message in the second argument if a rope throws
an error. Takes a variable number of dispatch functions, each of which will be used to create a new Rope.

## More Examples

Examples are in the examples directory. Currently there are only examples for the LOVE game engine. To run
the examples, just cd into the specific example directory and run with love.

## TODO

* Unit tests
* Travis
* Can ropes be in multiple bundles? Can ropes change bundles? (Not currently, but should they be able to?)
* More utility functionality with ropes.
* Allow rope function inside coroutines.
