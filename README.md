
# Stiv the Slow Terminal Image Viewer

A.k.a SJV (Slow JPEG Viewer).

Streams JPEG images right into your RGB-supporting terminal, downscaling to fit
width.

Scaling is implemented entirely in Lua, using coroutines for the hell of it.


## Installation

```sh
prefix=/usr/local
luarocks install dromozoa-jpeg &&
default_lua_version=$(lua -e '_,n=_VERSION:gsub("%d+%.%d+$",print) os.exit(1-n)') &&
mkdir -p $prefix/share/lua/$default_lua_version &&
cp -r mjk $prefix/share/lua/$default_lua_version &&
mkdir -p $prefix/bin &&
cp stiv.lua $prefix/bin/stiv
```

### On Termux

Change `prefix` to `/data/data/com.termux/files/usr`.


## Usage

`curl -s https://upload.wikimedia.org/wikipedia/commons/6/6d/\
The_Garden_of_Earthly_Delights_by_Bosch_High_Resolution.jpg | stiv` and watch
your CPU burn.

*Lifehack:* For cooling, you can use Tor over
[snowflake](https://snowflake.torproject.org) or live in the U.S. with a DSL
ISP!

### On Termux

Plug in your charger and `stiv Lenna.jpeg`.

Do come back after your $beverage break!


## License

[GNU Affero GPL 3+](COPYING.md).  No Picasa over SSH!


## Further work

Now, to tackle PNG.  WITH TRANSPARENCY!
