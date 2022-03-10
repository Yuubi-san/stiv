
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

local csi = '\27['   -- Control Sequence Introducer
local st  = '\27\\'  -- String Terminator
local osc = '\27]'   -- Operating System Command

local sgr  -- Select Graphic Rendition
sgr =
{
  mt =
  {
    __call = function(self, str)
      return
        csi..self.push..'m'.. str ..
        csi..self.pop ..'m'
    end,

    __str = function(self)
      return
        csi..self.push..'m'
    end,
  },

  fg = function(c) return setmetatable({push=c, pop=39}, sgr.mt) end,
  bg = function(c) return setmetatable({push=c, pop=49}, sgr.mt) end,
}

local xterm =
{
  -- TODO?: do actual queries in __call
  query_dimensions_px   = csi..'14t',
  query_bg              = osc..'11;?'..st,
}

return
{
  -- foreground
  fg =
  {
    black   = sgr.fg(30),
    red     = sgr.fg(31),
    green   = sgr.fg(32),
    yellow  = sgr.fg(33),
    blue    = sgr.fg(34),
    magenta = sgr.fg(35),
    cyan    = sgr.fg(36),
    white   = sgr.fg(37),

    default = sgr.fg(39),
  },

  -- background
  bg =
  {
    black   = sgr.bg(40),
    red     = sgr.bg(41),
    green   = sgr.bg(42),
    yellow  = sgr.bg(43),
    blue    = sgr.bg(44),
    magenta = sgr.bg(45),
    cyan    = sgr.bg(46),
    white   = sgr.bg(47),

    default = sgr.bg(49),

    query   = xterm.query_bg,
  },

  window =
  {
    query_dimensions_px = xterm.query_dimensions_px,
  },
}
