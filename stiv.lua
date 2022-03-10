#!/usr/bin/env lua
-- 5.2 seems faster than 5.1, which is significantly faster than 5.3
-- other versions not tested

--[[
This is Stiv, the Slow Terminal Image Viewer.

Copyright © 2022 mjk <https://github.com/Yuubi-san>.

Stiv is free software: you can redistribute it and/or modify it under the terms
of the GNU Affero General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later
version.

Stiv is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE.  See the GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License along
with this program.  If not, see <https://www.gnu.org/licenses/>.
--]]


local term   = require 'mjk.terminal'
local jpeg   = require 'dromozoa.jpeg'
local config = require 'mjk.config'.create'stiv'
local logger = require 'mjk.log'


local conf_defaults =
{
  log =
  {
    level = 'n';
  };
}
local conf = config.load(conf_defaults)
local log = logger.create(arg[0], conf.log.level)


local unpack = unpack or table.unpack

-- equivalent to `unpack(list, i, i+2)`, but
-- also respects metamethods on older Lua versions
local function unpack3(list, i)
  return list[i], list[i+1], list[i+2]
end

-- lazily concats `list` with itself to cover all integer index space
-- `len` is what's reported by the length operator
local function make_tiled_list(list, len)
  assert(#list ~= 0)
  len = len or 2^32
  return setmetatable({},
  {
    __len   = function() return len end,
    __index = function(self, idx) return list[(idx-1) % #list + 1] end,
  })
end

-- unnormalized
local function rational(num, den)
  assert(den ~= 0)
  return {num=num, den=den}
end


----
-- a filter/coroutine jumble
----
local flow
flow =
{
  create = function(f, dbg)
    return setmetatable(
      {
        c = coroutine.create(f),
        dbg = dbg
      },
      flow
    )
  end,
  finish = {},
  null_sink = function(read) while read() do end end,

  __call = function(self, ...)
    if coroutine.status(self.c) == 'dead' then
      error('trynna resume dead filter \''..
        self.dbg.short_src..':'..self.dbg.linedefined.."'", 2)
    end

    local res = {coroutine.resume(self.c, ...)}

    if not res[1] then
      log.d('filter ',self.dbg.short_src,':',self.dbg.linedefined,
        ' terminated with error: ',tostring(res[2]))
      error(res[2], 2)
    else
      if coroutine.status(self.c) == 'dead' then
        local caller = debug.getinfo(2)
        log.d('filter ',self.dbg.short_src,':',self.dbg.linedefined,
          ' returned ',tostring(res[2]),
          ' to ', caller.short_src,':',caller.currentline)
      end
      return unpack(res, 2)
    end
  end,

  __bor = function(prev, next)
    if to == flow.finish then return prev() end
    return flow.create(
      function() return next(prev, coroutine.yield) end,
      debug.getinfo(next)
    )
  end,
}
flow.__div = flow.__bor
flow.start = setmetatable({}, flow)


----
-- pixel and component utils
----

local inv_255   = 1/255
local inv_1_055 = 1/1.055
local inv_12_92 = 1/12.92
local inv_2_4   = 1/2.4

local function from_srgb_byte(byte)
  local c = byte*inv_255
  return c > 0.04045
    and
      ((c+0.055)*inv_1_055)^2.4
    or
      c*inv_12_92
end

local function to_srgb_byte(number)
  local c = number > 0.0031308
    and
      1.055*number^inv_2_4 - 0.055
    or
      12.92*number
  assert(c >= 0)
  assert(c <= 1)
  return math.floor(c*255 + 0.5)  -- TODO: tie-break to even
end

local make_unicolor_row = make_tiled_list

local function make_near_sampler( background )
  local function sample_nearly( pixels, x )
    local x_local = x * #pixels/3    -- imagine -0.5 (for centering)
    local idx = math.floor(x_local)  -- imagine +0.5 (for rounding)
    return unpack3(pixels, idx*3+1)
  end
  return sample_nearly
end

local function make_linear_sampler( background )
  local function sample_linearly( pixels, x )
    local x_local = x * #pixels/3 - 0.5
    local idx = math.floor(x_local)
    local t = x_local - idx
    local lr, lg, lb = unpack3(pixels, (idx  )*3+1)
    local rr, rg, rb = unpack3(pixels, (idx+1)*3+1)
    if not rr then
      rr, rg, rb = unpack(background)
    end
    return
      lr*(1-t) + rr*t,
      lg*(1-t) + rg*t,
      lb*(1-t) + rb*t
  end
  return sample_linearly
end

-- lerp(rows[1], rows[2], y)
local function make_linear_row_sampler(background)
  local bg_row = make_unicolor_row(background)
  return function(rows, y)
    assert(y >= 0 and y < 1)
    local t = y
    local top, bot = rows[1], rows[2] or bg_row
    for x = 1, #top do
      top[x] = top[x]*(1-t) + bot[x]*t
    end
    return top
  end
end
-- specilization of the above for y=0.5
local function make_row_averager(background)
  local bg_row = make_unicolor_row(background)
  return function(rows)
    local top, bot = rows[1], rows[2] or bg_row
    for x = 1, #top do
      top[x] = (top[x] + bot[x])*0.5
    end
    return top
  end
end


----
-- filters
----

-- lineraly downsamples vertically 2x
local function make_2x_v_minifier(background, dbg)
  local lerp = make_row_averager(background)
  dbg = dbg or '\t'
  return function(read,write) local y = 0; while true do
    local r0 = read()
    if not r0 then break end
    local r1 = read()
    log.t(dbg, #r0/3, ' ', y)
    write( lerp({r0, r1}, 0.5) )
    y = y + 1
    if not r1 then break end
  end log.d('v2 minifier done after writing ', y, ' rows') end
end

local impl = {}
impl.minify_h_2x =
{
  [3] = function(r)
    for x = 0, #r/6-1 do
      r[x*3+1] = (r[x*6+1] + r[x*6+4])*0.5
      r[x*3+2] = (r[x*6+2] + r[x*6+5])*0.5
      r[x*3+3] = (r[x*6+3] + r[x*6+6])*0.5
    end
  end,
  [1] = function(r)
    for x = 0, #r/2-1 do
      r[x+1] = (r[x*2+1] + r[x*2+2])*0.5
    end
  end,
}

-- lineraly downsamples horizontally 2x
local function make_2x_h_minifier(background)
  local components = #background
  local in_stride = 2*components
  return function(read,write) local y = 0; while true do
    local r = read()
    if not r then break end
    if #r % in_stride ~= 0 then
      assert(#r % in_stride == components)
      for _, c in ipairs(background) do r[#r+1] = c end
    end

    impl.minify_h_2x[components](r)
    for x = #r/2+1, #r do
      r[x] = nil
    end

    write( r )
    y = y + 1
  end log.d('h2 minifier done after writing ', y, ' rows') end
end

-- lineraly downsamples vertically by a rational factor `factor`
-- 1 < `factor` < 2
-- `background` is the color to use for out-of-range samples
local function make_v_minifier( factor, background )
  local in_stride = factor.num/factor.den
  log.d('making v minifier with factor = ',
    factor.num,'/',factor.den,' ≈ ',in_stride)
  assert( factor.num > factor.den,   'minifying filter doesn\'t minify!' )
  assert( factor.num < factor.den*2, 'minifying filter minifies 2x or more' )
  local sample = make_linear_row_sampler(background)

  return function(read,write)
    local out_pos = 0.5
    local in_idx = -2  -- zero-based
    local s = {}
    local function advance()
      s[1] = s[2]
      s[2] = read()
      in_idx = in_idx + 1
    end
    advance()
    advance()  -- input assumed to contain at least one sample

    local in_pos = out_pos*in_stride
    local t = (in_pos-0.5) % 1
    while true do
      write( sample(s, t) )
      out_pos = out_pos + 1
      if not s[2] then break end
      in_pos = out_pos*in_stride
      local next_in_idx
      next_in_idx, t = math.modf(in_pos-0.5)
      local adv = next_in_idx-in_idx
      assert(adv == 1 or adv == 2, 'adv is '..adv)
      advance()
      if not s[2] then break end
      if adv == 2 then advance() end
    end

    log.d('v minifier done after writing ', out_pos-0.5, ' rows')
  end
end

-- lineraly downsamples horizontally by a rational factor `factor`
-- 1 < `factor` < 2
-- `background` is the color to use for out-of-range samples
local function make_h_minifier( factor, background )
  log.d('making h minifier with factor = ',
    factor.num,'/',factor.den,' ≈ ',factor.num/factor.den)
  assert( factor.num > factor.den,   'minifying filter doesn\'t minify!' )
  assert( factor.num < factor.den*2, 'minifying filter minifies 2x or more' )
  local sample = make_linear_sampler(background)

  return function(read,write) local y = 0; while true do
    local r = read()
    if not r then break end
    local w = #r/3 * factor.den / factor.num
    log.t('h minifier: ', #r/3, ' -> ', w)
    assert(w%1 == 0, 'non-integral h minifier output width!\n')
    local w_inv = 1/w
    local r_out = {}
    for x = 0, w-1 do
      r_out[x*3+1], r_out[x*3+2], r_out[x*3+3] = sample( r, (x+0.5)*w_inv )
    end
    write( r_out )
    y = y + 1
  end log.d('h minifier done after writing ', y, ' rows') end
end

-- accumulates pixels into rows.  disused (and incorrect)
--  input: pixels, with nil for end-of-row
-- output: rows
local function accum_rows(read,write) while true do
  local row = {}
  while true do
    local r, g, b = read()
    if not r then break end
    row[#row+1] = r
    row[#row+1] = g
    row[#row+1] = b
  end
  write(row)
end end

-- zips pairs of rows pixelwise.  disused
local function zip(read,write) while true do
  local r0 = read()
  if not r0 then break end
  local r1 = read()
  if not r1 then break end
  local row = {}
  for x = 0, #r0-1, 3 do
    row[x*2+1], row[x*2+2], row[x*2+3] = unpack(r0, x+1, x+3)
    row[x*2+4], row[x*2+5], row[x*2+6] = unpack(r1, x+1, x+3)
  end
  write(row)
end end


local LANG = os.getenv'LANG'
local encoding
if LANG and #LANG ~= 0 then
  LANG:gsub('^[^.]+%.([^.]+)$', function(e) encoding = e end)
  if not encoding then
    log.w('unexpected LANG format, assuming UTF-8 encoding')
    encoding = 'utf8'
  end
else
  log.n('LANG empty or not defined, assuming UTF-8 encoding')
  encoding = 'utf8'
end
local iconv =  -- some encodings of ▀ U+2580 UPPER HALF BLOCK
{
  utf8        = {0xE2,0x96,0x80},
  ['utf-8']   = {0xE2,0x96,0x80},
  ibm437      = 0xDF,
  ibm775      = 0xDF,
  ibm848      = 0xDF,
  ibm850      = 0xDF,
  ibm851      = 0xDF,
  ibm852      = 0xDF,
  ibm855      = 0xDF,
  ibm856      = 0xDF,
  ibm857      = 0xDF,
  ibm858      = 0xDF,
  ibm860      = 0xDF,
  ibm861      = 0xDF,
  ibm862      = 0xDF,
  ibm863      = 0xDF,
  ibm865      = 0xDF,
  ibm866      = 0xDF,
  ibm869      = 0xDF,
  -- TODO?: add more
}
local the_char = iconv[encoding:lower()]
if not the_char then
  the_char =
    io.popen('echo "▀" | iconv --from UTF-8 --to '..encoding):read'*a'
  if #the_char == 0 then
    log.e(
      'don\'t know how to spell U+2580 in \''..encoding..'\' encoding')
    os.exit(1)
    the_char = ' '  -- TODO: handle monopixels down the line
  end
  the_char = the_char:sub(1, -2)  -- strip the newline
  assert(#the_char ~= 0)
elseif type(the_char) == 'table' then
  the_char = string.char(unpack(the_char))
elseif type(the_char) == 'number' then
  the_char = string.char(the_char)
end


--[[
local term_w, term_h =
  assert(tonumber(os.getenv'COLUMNS')),
  assert(tonumber(os.getenv'LINES'))

  these aren't exported by default
]]
local term_w, term_h =
  assert(tonumber(io.popen'tput cols 2> /dev/null' :read'*a')),
  assert(tonumber(io.popen'tput lines 2> /dev/null':read'*a'))
-- `stty size` is fine too


-- returns 5 values:
--   width & height in pixels,
--   background red, green and blue in [0.0, 1.0]
local function query_terminal_properties()
  if not os.execute() then return end

  local ttyin  = io.open('/dev/tty','r')
  if not ttyin then return end
  local ttyout = io.open('/dev/tty','w')
  if not ttyout then return end

  local saved_settings = io.popen'stty -F /dev/tty -g 2> /dev/null':read'*a'
  if not saved_settings or #saved_settings == 0 then return end
  local exec_res =
    os.execute('stty -F /dev/tty raw -echo min 0 time 1 2> /dev/null')
  if exec_res ~= true and exec_res ~= 0 then return end

  ttyout:write(term.window.query_dimensions_px)
  ttyout:flush()
--for i = 1, 2^20 do end  -- less reliable than using `time 1` above, but faster
  local dim = ttyin:read'*l' or ''

  ttyout:write(term.bg.query)
  ttyout:flush()
--for i = 1, 2^20 do end
  local bgc = ttyin:read'*l' or ''

  local exec_res, _, c =
    os.execute('stty -F /dev/tty '..saved_settings..' 2> /dev/null')
  if exec_res ~= true and exec_res ~= 0 then
    log.w('failed to restore terminal settings: stty exited with code ',
      c or exec_res
    )
  end

  local w, h
  dim:gsub('^\27%[4;([0-9]+);([0-9]+)t$', function(sw, sh)
    w = tonumber(sw)
    h = tonumber(sh)
  end)

  local r, g, b
  bgc:gsub('^\27%]11;rgb:([0-9A-Fa-f]+)/([0-9A-Fa-f]+)/([0-9A-Fa-f]+)\27\\$',
    function(sr, sg, sb)
      r = tonumber(sr, 16) / (16^#sr - 1)
      g = tonumber(sg, 16) / (16^#sg - 1)
      b = tonumber(sb, 16) / (16^#sb - 1)
    end)

  return w,h, r and {r,g,b} or nil
end

local term_w_px, term_h_px, term_bg = query_terminal_properties()

if term_w_px then
  -- Termux (version 0.75) is horribly broken here:
  -- * term_[wh]_px are mixed up and/or behave weirdly on orientation change;
  -- * swapping them seems to always produce bogus 12x12 px chars;
  -- Luckily, brokenness can be kinda reliably detected with modulo:
  if term_w_px%term_w == 0 and term_h_px%term_h == 0 then
    car = rational(term_w_px/term_w, term_h_px/term_h)
  else
    car = rational(1, 2)
    log.w('CAR broken, fell back to ',car.num,':',car.den)
  end
else
  car = rational(1, 2)
  log.w('couldn\'t detect CAR, fell back to ',car.num,':',car.den)
end

local par = rational(car.num*2, car.den)

if term_bg then
  term_bg[1] = term_bg[1]*255
  term_bg[2] = term_bg[2]*255
  term_bg[3] = term_bg[3]*255
else
  term_bg = {0,0,0}
end

log.i('\n',
  '   terminal width: ',term_w,' chars\n',
  'char aspect ratio: ',car.num,':',car.den,'\n',
  '  px aspect ratio: ',par.num,':',par.den,'\n',
  ' terminal backgnd: ',term_bg[1],', ',term_bg[2],', ',term_bg[3]
)
term_bg[1] = from_srgb_byte(term_bg[1])
term_bg[2] = from_srgb_byte(term_bg[2])
term_bg[3] = from_srgb_byte(term_bg[3])

local filename = ... --'dl/EXmpNIgVcAAYbRY.jpg'
local f = filename and assert(io.open(filename,'rb')) or io.stdin
local dec = jpeg.decompressor()
assert(dec:set_fill_input_buffer(function(n) return f:read(n) end))
assert(dec:set_out_color_space(jpeg.JCS_RGB))
assert(dec:read_header() == jpeg.JPEG_HEADER_OK)
assert(dec:start_decompress())
assert(dec:get_out_color_space() == jpeg.JCS_RGB)
local w = assert(dec:get_output_width())
local h = assert(dec:get_output_height())

local function decode(_, write)
  local y = 0
  while assert(dec:get_output_scanline()) <= h do
    write(assert(dec:read_scanlines()))
    y = y + 1
  end
  assert(dec:finish_decompress())
  log.d('decoder done after writing ', y, ' rows')
end

local function srgb_string_to_number_array(read,write)
  local y = 0
  while true do
    local str = read()
    if not str then break end
    local row = {}
    for comp = 1, #str do
      row[comp] = from_srgb_byte(str:byte(comp))
    end
    log.t(#row/3,' ', y)
    y = y + 1
    write(row)
  end
  log.d('linearizer done after writing ', y, ' rows')
end

local pipeline = flow.start /
  decode / srgb_string_to_number_array

local lod = 0
local lod_w, lod_h = w, h
while math.ceil(lod_w/2) >= term_w do
  lod_w = math.ceil(lod_w/2)
  lod_h = math.ceil(lod_h/2)
  lod = lod + 1
  pipeline = pipeline /
    make_2x_v_minifier(term_bg, string.rep('\t',lod)) /
    make_2x_h_minifier(term_bg)
end
local out_w, out_h
if lod_w > term_w then
  local factor = rational(lod_w, term_w)
  pipeline = pipeline /
    make_v_minifier(factor, term_bg) /
    make_h_minifier(factor, term_bg)
  out_w = term_w
  out_h = lod_h * term_w/lod_w
  out_h = (out_h % 1 ~= 0 and '~' or '')..tostring(out_h)
else
  log.d('no non-POT minification needed')
  out_w = lod_w
  out_h = lod_h
end

log.i('\n',
  '     image  width: ',w,' px\n',
  '     image height: ',h,' px\n',
  '  level of detail: ',lod,'\n',
  '       LOD  width: ',lod_w,' px\n',
  '       LOD height: ',lod_h,' px\n',
  '    output  width: ',out_w,' px\n',
  '    output height: ',out_h,' px'
)

local tobyte = to_srgb_byte
local function write_2_rows(file, r0, r1)
  local t = {}
  for x = 1, #r0, 3 do
    t[#t+1] =
    '\27[38;2;'.. tobyte(r0[x]) ..';'.. tobyte(r0[x+1]) ..';'.. tobyte(r0[x+2])
     ..';48;2;'.. tobyte(r1[x]) ..';'.. tobyte(r1[x+1]) ..';'.. tobyte(r1[x+2])
     ..'m'..the_char
  end
  file:write(table.concat(t))
  file:write'\27[39;49m\n'
end

pipeline = pipeline /
  function(read)
    local bg_row = make_unicolor_row(term_bg)
    local y = 0
    while true do
      local r0 = read()
      if not r0 then break end
      local r1 = read()
      write_2_rows(io.stdout, r0, r1 or bg_row)
      log.t(string.rep('\t',lod+1), #r0/3, ' ', y)
      y = y + 1
      if not r1 then break end
    end
    log.d('terminal writer done after writing ', y, ' lines')
  end

-- TODO: test if this actually helps with performance,
-- compared to line-buffered output
-- does look a bit uglier during output
-- usually results in rows teared and FUBAR by other output (log messages, etc.)
--io.stdout:setvbuf('full', 64*1024)

pipeline()
