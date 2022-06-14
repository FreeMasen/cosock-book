# Spawn

At the core of cosock's ability to work is the ability to wrap any operation in a coroutine and
register that with cosock. For this cosock exports the function `cosock.spawn`. This function takes
2 arguments, first is a function that will be our coroutine, the second is a name for that coroutine.

For example, this is a simple program that will spawn a single coroutine, which will print the current
timestamp and the word "tick" then sleep for 1 second in a loop forever.

```lua
{{#include ../examples/basic_spawn.lua}}
```

The act of calling `cosock.spawn` allow us to use the non-blocking `cosock.socket.sleep` function. This means
we could extend our application to not only print this message every second but use the time this coroutine
is sleeping to perform some other work. Let's extend our little example a bit.

```lua
{{#include ../examples/less_basic_spawn.lua}}
```

This time we have changed things up a bit. Instead of defining our coroutine right in the call to `cosock.spawn`
a local function is defined `clock_part` which will return a function. This is required because `cosock.spawn` doesn't
have the ability to forward any arguments initially but by returning a function here we can capture the arguments
to our initial call to `clock_part`.

This script will essentially just spawn 2 of the same coroutine, which will sleep for 2 seconds and then print the timestamp
along with their name. We then register one named "tick" and one named "tock". Since we don't want to try and print both
"tick" and "tock" at the same time, for "tock" we sleep for 1 second right at the start.
