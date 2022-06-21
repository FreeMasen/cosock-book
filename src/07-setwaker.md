# Integrating with Cosock

So far we have covered what cosock provides but what if we want to integrate our
own libraries directly into cosock, what would that look like?

To start the general interface for a "cosock aware" lua table is to define a method `setwaker`
which takes 2 arguments, `kind: str` and `waker: fun()|nil`. The general idea here is
that a "waker" function can be provided that will get called when that task is ready
to be woken again.

Let's try and build an example `Timer` that will define this `setwaker` method to make
it "cosock aware"

```lua
{{#include ../examples/timer.lua}}
```

To start we create a lua meta-table `Timer`, which has the properties `secs: number` and
`waker: fun()|nil`. There is a constructor `Timer.new(secs)` which takes the number of
seconds we want to wait for. Finally we define `Timer:wait` which is where our magic happens.
This method calls `coroutine.yield`, with 3 arguments `{self}`, an empty table, and `self.secs`.
These arguments match exactly what would be passed to `socket.select`, the first is a list of any
receivers, the second is a list of any senders and finally the timeout. Since we pass `{self}` as the
first argument that means we are treating `Timer` as a receiver. ultimately what we are doing here
is asking `cosock` to call `socket.select({self}, {}, self.secs)`. While we don't end up calling `self.waker`
ourselves, cosock uses `setwaker` to register tasks to be resumed so we need to conform to that. Just to
illustrate that is happening, a `print` statement has been added to `setwaker`, if we run this
we would see something like the following.

```shell
waiting
setwaker        recvr   function: 0x5645e6410770
setwaker        recvr   nil
waited
```

We can see that cosock calls `setwaker` once with a function and a second time with `nil`. Notice though
that `self.waker` never actually gets called, since we don't see a `"waking up"` message. That
is because we don't really _need_ to be woken up, our timer yields the whole coroutine until
we have waited `self.secs`, nothing can interrupt that. Let's extend our `Timer` to have a reason
to call `self.waker`, we can do that by adding the ability to cancel a `Timer`.

```lua
{{#include ../examples/timer_with_cancel.lua}}
```

In this example, we create our timer that will wait 10 seconds but before we call `wait` we
spawn a new task that will sleep for 3 seconds and then call `cancel`. If we look over the
changes made to `wait` we can see that we still call `coroutine.yield({self}, {}, self.secs)`
but this time we are assigning its result to `r, s, err`. Cosock calls `coroutine.resume`
with the same return values we would get from `select`, that is a list of ready receivers,
a list of ready senders, and an optional error string. If the timer expires, we would expect
to get back `nil, nil, "timeout"`, if someone calls the `waker` before our timer expires
we would expect to get back `{self}, {}, nil`. This means we can treat any `err == "timeout"`
as a normal timer expiration but if `err ~= "timeout"` then we can safely assume our timer
was cancelled. If we were to run this code we would see something like the following

```shell
waiting
setwaker        recvr   function: 0x556d39beb6d0
waking up!
setwaker        recvr   nil
setwaker        recvr   nil
waited  3.0     nil     cancelled
```

Notice we only slept for 3 seconds instead of 10, and `wait` returned `nil, "cancelled"`!
One thing we can take away from this new example, is that the waker api is designed to allow
one coroutine to signal cosock that another coroutine is ready to wake up. With that in mind, 
let's try and build something a little more useful, a version of the
`cosock.channel` api that allows for a maximum queue size. Looking over the
[existing channels](https://github.com/cosock/cosock/blob/8388c8ebcf5810be2978ec18c36c3561eedb5ea8/cosock/channel.lua)
, to implement this we are going to need to have 3 parts. A shared table for queueing and
setting the appropriate wakers, a receiver table and a sender table. Let's start by
defining the shared table.

```lua
{{#include ../examples/bounded_channel/init.lua:11:12}}
```

This table should have the following properties

- `_wakers`: This is a table with 2 keys
  - `sendr`: An optional function that takes no arguments, this will wake our sender
  - `recvr`: An optional function that takes no arguments, this will wake our receiver
- `_max_depth`: This is the integer value that our queue should not grow larger than
- `_msg_queue`: This is the message queue we will use to hold pending messages
- `_closed`: This is a boolean to indicate if we have been explicitly closed

To make our lives easier, next we will add a couple of methods that will enforce the
queue nature of our `_msg_queue`, one for removing the oldest message and one for 
adding a new message.

```lua
{{#include ../examples/bounded_channel/init.lua:28:36}}
```

Next, let's add a method for testing if we can send a new message.

```lua
{{#include ../examples/bounded_channel/init.lua:70:83}}
```

This method first checks that we haven't been closed, if we have then it returns
`nil, "closed"`, if we are still open it next checks to see if we have any space in
our queue, if not it returns `nil, "full"`. So if we are not closed and not full
it returns 1.

Now we should create a similar method for checking if we can receive a new message.

```lua
{{#include ../examples/bounded_channel/init.lua:89:102}}
```

Again, first we check for the closed case, returning `nil, "closed"`, next we
check to see if the queue is empty, if so we return `nil, "empty"`, if there is
at least 1 message and we aren't closed then we return `1`.

Now we can define our `setwaker` method.

```lua
{{#include ../examples/bounded_channel/init.lua:41:57}}
```

Ok, so this one is pretty simple now that we have our helpers. First we populate the
value in our `self.wakers` table that corresponds to the `kind` argument. The `kind`
argument should either be `"sendr"` or `"recvr"`. Next we check to see if `waker` is
`nil`, this is used as a way to clear a waker from a "cosock aware" table, if it is
we return early. If `waker` is not `nil` then we consult the `kind` variable, if it 
is `"sendr"` and `self:can_send` returns `1` or if it is `"recvr"` and `self:can_recv`
returns `1` we want to immediately call the `waker` because it means we are already ready
to be woken up.

There are 2 more methods we can add here that will make things easier for us later.

```lua
{{#include ../examples/bounded_channel/init.lua:60:64}}

{{#include ../examples/bounded_channel/init.lua:105:107}}
```

`try_wake` will attempt to call one of the `wakers` based on the `kind` provided
by the caller so long as it is not `nil`. `close` will just set our `_closed` property
to `true`

Ok, now that we have our shared channel defined, lets now implement our receiver.
This table will have 2 properties `_link` which will be our `BoundedChannel` and
a `timeout` which will be an optional `number`.

```lua
{{#include ../examples/bounded_channel/recvr.lua:3:4}}
```

Ok, let's create a constructor for it, this will take 1 argument which should populate
its `_link` property.

```lua
{{#include ../examples/bounded_channel/recvr.lua:8:10}}
```

Next, we want to define the `setwaker` method used by this side of the queue.

```lua
{{#include ../examples/bounded_channel/recvr.lua:43:48}}
```

In this method, we have added a check to make sure it isn't getting called
with a `kind` of `"sendr"`, since that would be pretty much meaningless. If
we have a valid `kind` then we pass the waker down to `self._link:setwaker`.

Before we get into the bulk of our receiver, we should define a method for
setting the `timeout` property.

```lua
{{#include ../examples/bounded_channel/recvr.lua:18:20}}
```

While this is not _essential_ but it is nice to match the same api that `cosock.channel` uses.

Ok, now for the good stuff: the `receive` method.

```lua
{{#include ../examples/bounded_channel/recvr.lua:22:41}}
```

Alright, there is a lot going on here so let's unpack it. To start we have a long running
loop that will only stop when we have reached either an error or a new message. Each iteration
of the loop first checks if `self._link:can_recv()`, if that returns `1`, then we 
first call `self._link:pop_front` to capture our eventual return value, next we want
to alert any senders that more space has just been made on our queue so we call
`self._link:try_wake("sendr")`, finally we return the element we popped off. If `can_recv`
returned `nil` we check to see which `err` was provided, if it was `"closed"` we return
that in the error position. If `can_recv` returns `nil, "empty"` then we want to yield until
we would be able to actually return a message, or wait for the duration of `self.timeout`.
We do this by calling `coroutine.yield({self}, nil, self.timeout)`, this will give up control
to cosock until either someone calls `self.link.wakers.recvr` or our `timeout` is reached.

If we recall that `coroutine.yield` returns a list of ready receivers and a list of senders
or `nil, nil` and on error message. This means if `coroutine.yield` returns `{self}` then
we have a new message so we go to the top of the loop and the next call to `self.link:can_recv`
should return `1` or `nil, "closed"`. If `coroutine.yield` returns `nil, nil, "timeout"` that
means we have yielded for `self.timeout`. 

One final thing we want to make sure is that we are keeping our end of that `nil "closed"`
bargain, so let's define a `closed` method.

```lua
{{#include ../examples/bounded_channel/recvr.lua:12:16}}
```

For this, we first call `self.link:close` which will set our shared table's `_closed` property
to `true` which will ultimately make both `can_send` and `can_recv` return `nil, "closed"`. Next
we want to wake up any sending tasks since they are reliant on us to tell them something has
changed, so we call `self._link:try_wake("sendr")`.

With that we have the complete receiver side of our channel, now let's write up the sender.

```lua
{{#include ../examples/bounded_channel/sendr.lua:5:6}}
```

This table will have the same shape as our `BoundedChannelReceiver`, it will have a 
`_link` property and a `timeout` property. We will also define a `settimeout` method
that looks exactly the same.

```lua
{{#include ../examples/bounded_channel/sendr.lua:46:48}}
```

Our constructor is also nearly identical.

```lua
{{#include ../examples/bounded_channel/sendr.lua:10:12}}
```

The sender will also have a very similar `setwaker` method.

```lua
{{#include ../examples/bounded_channel/sendr.lua:50:55}}
```

The only real difference here is that we error on a kind of `"recvr"` instead of `"sendr"`.

Our `close` method is also very close to the receiver's implementation.

```lua
{{#include ../examples/bounded_channel/sendr.lua:15:19}}
```
Here also, just the argument to `self._link:try_wake` changed from `"sendr"` to `"recvr"`.

Even our `send` looks very similar to `receive`

```lua
{{#include ../examples/bounded_channel/sendr.lua:23:42}}
```

For this method, start a long running loop again which begins by calling `self._link:can_send`.
If `can_send` returns `1` we can call `self._link:push_back`, then wake up any waiting
receivers by calling `self._link:try_wake("recvr")`, finally we return `1`. If `can_send`
returned `nil, "closed"` then we can return `nil, "closed"`. Finally if `can_send` returned
`nil, "full"` then we call `coroutine.yield(nil, {self}, self.timeout)`, if that returns
an `err` value, we reached our timeout so we can return `nil, err`. If `yield`
didn't return an `err` then we can assume we were woken up so going back to the top of the loop
`self._link:can_send` should now return either `nil, "closed"` or `1`.

The last thing we need to do is add a constructor to `BoundedChannel`. 

```lua
{{#include ../examples/bounded_channel/init.lua:18:26}}
```

This constructor takes 1 argument, the number telling us how large our queue can get.
This returns 2 tables, the first return is a `BoundedChannelSender` and the second 
return is a `BoundedChannelReceiver` both have the same shared `BoundedChannel` as
their `_link` property.

Now let's see our new channel in action!


```lua
{{#include ../examples/use_bounded_channel.lua}}
```

After we import both `cosock` and our `BoundedChannel` we create a new channel pair
with a maximum queue size of 2. We then spawn a new task for the sender, in that task
we loop 10 times, sending a message and then sleeping for 0.2 seconds.
We have a call to `cosock.socket.gettime` here before and after the `send` to see if there is any 
delay.

Next we spawn a task for our receiver, this receives a message and then sleeps for 1 second
also 10 times.

Since we are sending a lot faster than we are receiving, we would expect that after the 
first few messages we should see the amount of time it takes to send a message hits about
1 second indicating that our queue has reached its maximum of 5. If we were to run this
we should see something _like_ the following.

```
sent 1 in 0.0s
recd 1 in 0.0s
sent 2 in 0.2s
sent 3 in 0.2s
recd 2 in 1.0s
sent 4 in 0.6s
recd 3 in 1.0s
sent 5 in 1.0s
recd 4 in 1.0s
sent 6 in 1.0s
recd 5 in 1.0s
sent 7 in 1.0s
recd 6 in 1.0s
sent 8 in 1.0s
recd 7 in 1.0s
sent 9 in 1.0s
recd 8 in 1.0s
sent 10 in 1.0s
recd 9 in 1.0s
recd 10 in 1.0s
```

At first, things operate as expected, `sendr` pushes 1 onto the queue
then `recvr` pops that back off. Now, `recvr` sleeps for 1 second, which
allows `sendr` to push 2 and 3 on to the queue. `recvr` wakes from sleep
and pops 2 off then goes back to `sleep` for 1 second. At this point,
there is 1 message in the queue, `sendr` wakes up and pushes 4, then sleeps
for 0.2 and tries to push 5 but the queue has reached its maximum depth of 2
so `sendr` `yields`. `recvr` wakes from `sleep` and pops 3 off the queue and
calls `try_wake` which will should call `BoundedChannel._wakers.sendr()` since
that wouldn't be `nil`, this triggers our `sendr` task to `resume` and finally 
pushes 5 onto the queue. When `sendr` tries to push 6 it is again met with
a full queue and yields this repeats itself until we reach the end of our loop.
