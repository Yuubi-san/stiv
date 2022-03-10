
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

return
{
  create = function(config_subdir)
    local function load_from(dir, name, base)
      name = name or 'conf'
      local path = dir..'/'..config_subdir..'/'..name..'.lua'
      local file = io.open(path,'rb')
      if not file then return base end
      local conf = {}
      local f = assert(
        load(function() return file:read(2^12) end, path, 't', conf)
      )
      file:close()
      if f then
        (setfenv or function(f) return f end)(f, conf)()
        return setmetatable(conf, {__index = base})
      end
      return base
    end

    return
    {
      load = function(base, name)
        local dir =
          os.getenv'XDG_CONFIG_HOME' or
          os.getenv'APPDATA'
        if dir then
          return load_from(dir, name, base)
        else
          local home = os.getenv'HOME'
          if home then return load_from(home..'/.config', name, base) end
        end
      end,

      -- wip, untested
      load_sys = function(base, name)
        local res = load_from('/etc', name, base)
        if not res then
          local aup = os.getenv'ALLUSERSPROFILE'
          return aup and load_from(aup, name, base) or nil
        end
      end,
    }
  end,
}
