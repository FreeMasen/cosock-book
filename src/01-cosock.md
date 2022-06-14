# Cosock

Cosock is a coroutine runtime written in pure Lua and based on teh popular luasocket library.

The goal of the project is to provide the same interfaces that luasocket provides but wrapped
up in coroutines to allow for concurrent IO.

For example, the following 2 lua programs use luasocket to define a tcp client and server.

```lua
{{#include ../examples/client.lua}}
```

```lua
{{#include ../examples/server.lua}}
```

If you were to run first `lua ./server.lua` and then `client.lua` you should see each terminal print out
their "sending ..." messages forever.

Using cosock, we can actually write the same thing as a single application.

```lua
{{#include ../examples/client_server.lua}}
```

Now if we run this with `lua ./client_server.lua` we should see the messages alternate.
