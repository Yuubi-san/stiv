
--[[
Copyright © 2021-2022 mjk <https://github.com/Yuubi-san>

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU Affero General Public License as published by the Free
Software Foundation, either version 3 of the License, or (at your option) any
later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE.  See the GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License along
with this program.  If not, see <https://www.gnu.org/licenses/>.
--]]

local t = require 'mjk.terminal'

local function nop() end

local letters = {[0]='E','a','c','e','w','n','i','d','t'}

local function find_level(letter)
  for lvl, ltr in pairs(letters) do
    if ltr == letter then return lvl end
  end
end

return
{
  create = function(prog, lvl, out)
    lvl = type(lvl) == 'number' and lvl or find_level(lvl)
    out = out or io.stderr

    local function log(...)
      out:write(prog, ': ', ...)
      out:write('\n')
    end

    local functions = {
      [0] =
      function(...) log(t.fg.   red('emergency:'),' ', ...) end,
      function(...) log(t.fg.   red('alert:'    ),' ', ...) end,
      function(...) log(t.fg.   red('crtical:'  ),' ', ...) end,
      function(...) log(t.fg.   red('error:'    ),' ', ...) end,
      function(...) log(t.fg.yellow('warning:'  ),' ', ...) end,
      function(...) log(t.fg.  cyan('notice:'   ),' ', ...) end,
      function(...) log('info: ' , ...) end,
      function(...) log('debug: ', ...) end,
      function(...) log('trace: ', ...) end,
    }

    local ret = {raw=log, program=prog, level=lvl, output=out}
    for l, f in pairs(functions) do
      ret[letters[l]] = l <= lvl and f or nop
    end
    return ret
  end,
}
