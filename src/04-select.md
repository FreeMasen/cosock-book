# Select

Now that we have covered how to spawn and run coroutines using cosock, let's talk about how we
could handle multiple IO sources in a single coroutine. For this kind of work, cosock provides
`cosock.socket.select`, this function works in a very similar way to luasocket's `socket.select`,
its arguments are

- `recvt`: This is a list of cosock sockets that are waiting to be ready to `receive`
- `sendt`: This is a list of cosock sockets that are waiting to be ready to `send`
- `timeout`: This is the maximum amount of seconds to wait for one or more entries in `recvt` or `sendt` to be ready
  - If this value is `nil` or negative it will treat the timeout as infinity

> Note: The list entries for `sendt` and `recvt` can be other "cosock aware" tables like the
> [lustre WebSocket](https://github.com/cosock/lustre), for specifics on how to make a table "cosock aware" 
> [see the chapter on it](07-setwaker.md)

Its return values are

- `recvr`: A list of ready receivers, any entry here should be free to call `receive` and immediately be ready
- `sendr`: A list of ready senders, any entry here should be free to call `send` and immediately be ready
- `err`: If this value is not `nil` it represents an error message
  - The most common error message here would be `"timeout"` if the `timeout` argument provided is not `nil` and positive
