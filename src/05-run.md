# Advanced Overview of `cosock.run`

## Global Variables

- `threads`: List of coroutines cosock is aware of
  - This is populated by the first argument to `cosock.spawn`
- `threadnames`: A map of coroutine<->name pairs
  - This is populated by the second argument ot `cosock.spawn`
- `threadswaitingfor`: A map of coroutine<->select args
  - Select args have the type `{recvr = {"list of cosock sockets"}, sendr = {"list of cosock sockets"}, timeout = 0}`
  - This populated by the values provided to `coroutine.yield` for cosock tasks from a call to `cosock.socket.select`
- `readythreads`: A list of coroutines that will be ready on the next pass
  - This is populated by coroutine wak-ups that occur on the current pass
- `socketwrappermap`: A map of luasocket<->cosock socket pairs
  - This map is keyed with the table pointer for the luasocket for easily getting back to a cosock socket when you
    only have a luasocket
  - This gets populated when a cosock socket is included in a select args table
- `threaderrorhandler`: Potential error handler function. Not currently settable.
- `timers`: A list of `timer` tables
  - A timer has the shape `{timeoutat = "deadline timestamp", callback = "function to be called at deadline", ref = "table pointer"}`
  - `timers.set`
    - Updates `timers` to include that value. Also updates a private scoped table named `refs`
      - `refs` is a map of table pointer<->timer
  - `timers.cancel`
    - If the provided table pointer is in `refs`, remove the `callback` and `ref` properties from that table
    - Set the table pointer key in `refs` to `nil`
  - `timers.run`
    - Sort all timeouts by deadline (earliest first)
    - Pop the timer off the front of the `timers` list
    - If that `timer.timeoutat` is `nil` or `< socket.gettime()`
      - Call `timer.callback`
      - remove this `timer` from `refs`
    - If there are any more timeouts left, return how long before that timeout should expire
    - If there are no more timeouts, return `nil`
  
## Run loop steps

1. define `wakethreads`
2. define an empty list of senders (`sendt`), receivers (`recvt`) and a `timeout`
3. pop all `readythreads` entries into the `wakethreads`
4. Loop over all threads in `wakethreads`
   1. If `coroutine.status` for that thread returns "suspended"
      1. Clear any timers
      2. Clear any wakers registered with a `timeout`
      3. `coroutine.resume` with the stored `recv4`, `sendr` and `err` arguments
      4. if `coroutine.resume` returned `true` in the first position and `coroutine.status` returns "suspended"
         1. re-populate `threadswaitingfor[thread]` with the 3 other return values from `coroutine.resume`
            1. These should be the `recvt`, `sendt` and `timeout` values that will populate select args
         2. set the waker for all sockets in `recvt` and `sendt` to call `wake_thread` and then unset themselves
         3. if `coroutine.resume` returned a `timeout`, create a new timer for this thread which will call `wake_thread_err` on expirations with the value "timeout"
      5. if `coroutine.status` returned "dead"
         1. If `coroutine.resume` returned `false` in the first position and no `threaderrorhandler` has been set
            1. Raise and error
               1. If the `debug` library is available, include a `debug.traceback` and the second return value from `cosock.resume`
               2. else just raise an error with the second return value from `cosock.resume`
            2. Exit the application
               1. This calls `os.exit(-1)`
5. Else, print a warning message if printing is turned on
6. initialize a variable `running` to `false`
7. loop over all `threads`, if `coroutine.status` doesn't return "dead" for any, set `running` to `true`
8. If `running` is `false` and `readythreads` is empty
   1. Exit the run loop
9. Loop over all the values in `threadswaitingfor`
    1. Insert the luasockets on any `sendr` or `recvr` parameters to the loop local variables `sendt` and `recvt`
    2. Populate `socketwrappermap` with any `sendr` or `recvr`s
10. Call `timers.run`
11. If `readythreads` is not empty
    1. Set `timeout` to `0`
12. If `timeout` is falsy and `recvt` is empty and `sendt` is empty
    1. Raise an error that cosock.select was called with no sockets and no timeouts
13. Call luasocket's `socket.select` with our loops `recvt`, `sendt` and `timeout`
14. If `socket.select` returns a value in the 3rd position and that value is not `"timeout"`
    1. Raise an error with that return value
15. Loop over the `recvr` (1st) return from `socket.select`
    1. Look up the `cosock.socket` from `socketwrappermap`
    2. call `skt:_wake("recvr")`
16. Loop over the `sendr` (2nd) return from `socket.select`
    1. Look up the `cosock.socket` from `socketwrappermap`
    2. call `skt:_wake("sendr")`
