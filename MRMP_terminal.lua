
-- Microwave remote message protocol (MRMP)
-- Bidirectional message transfer using a UDP style standard

local ver = "v2.3.0"

local component = require("component")
local event = require("event")
local m = component.modem
local gpu = component.gpu

local message = {}

local m_port = 6969 -- Message port.
local p_port = 1 -- Port for modem detection.

local modems = {}

local toSend = ""

------------------------------| INITIALIZATION |-----------------------------------

local text = "Microwave Remote Messaging Protocol (MRMP) " .. ver .. " on port [" .. tostring(m_port) .. "]"

local w, h = gpu.getResolution()
if string.sub(ver, 9, 9) == "a" then
  gpu.setBackground(0x400000)
  text = text .. " ALPHA"
else
  gpu.setBackground(0x000040)
end

gpu.fill(1, 1, w, h, " ")
gpu.set(1, 1, text)

local line = 3
local column = 3

local function checkClear(force)
  gpu.set(1, line, "> ")
  if line >= h or force then
    gpu.fill(1, 1, w, h, " ")
    gpu.set(1, 1, text)
    line = 3
    column = 3
  end
end

------------------------------| OUTPUT |-----------------------------------

local function onMessage(f, p, m2)
  local msg = "> " .. f.. " [" .. p.. "]:= " .. m2
  local msg_table = {}
  while string.len(msg) > w do -- terrible text wrap code!!
    local lower = string.sub(msg, 0, w)
    if #lower < w then
      break;
    end
    table.insert(msg_table, lower)
    local msg_sub = string.sub(msg, w + 1, #msg)
    if #msg_sub < w then
      table.insert(msg_table, msg_sub)
      break;
    end
    msg = msg_sub
  end
  if string.len(toSend) > 0 then
    if #msg_table > 0 then
      gpu.copy(1, line, w, line + 5, 0, #msg_table)
    end
    gpu.copy(1, line, w, line + 5, 0, 1)
  end
  if #msg_table > 0 then
    for _, v in pairs(msg_table) do
      gpu.set(1, line, v)
      line = line + 1
      checkClear()
    end
    return;
  else
    gpu.set(1, line, msg)
    line = line + 1
    checkClear()
  end
end

------------------------------| HANDLERS |-----------------------------------

local function receive(_, loc, addr, port, _, msg)
  if port == p_port then
    if msg == "REP" then
      table.insert(modems, addr)
    elseif msg == "DSC" then
      for i, v in pairs(modems) do
        if v == addr then
          table.remove(modems, i)
          onMessage(loc, 65535, "Modem disconnected: " .. addr)
        end
      end
    elseif msg == "CHK" then
      for j, v in pairs(modems) do
        if v == addr then
          table.remove(modems, j)
          onMessage(loc, 65535, "Removing duplicate modem: " .. addr)
        end
      end
      m.send(addr, p_port, "REP")
      table.insert(modems, addr)
      onMessage(loc, 65535, "New modem connected: " .. addr)
    end
  elseif port == m_port then
    for _, v in pairs(modems) do
      if v == addr then
        onMessage(addr, m_port, msg)
      end
    end
  end
end

local running = true

local function key(_, _, key1, code)
  if key1 == 0 then -- Things like shift, control, capslock, anything that doesnt have an assigned key.
    return;
  elseif key1 == 3 then -- Interrupts.
    running  = false
    return false;
  elseif code == 28 then -- Enter key.
    if string.sub(toSend, 0, 2) == "-/" then -- Terminal command.
      line = line + 1
      column = 1
      checkClear()
      if toSend == "-/Clear" or toSend == "-/clear" then
        checkClear(true)
      elseif toSend == "-/Connected" or toSend == "-/connected" then
        onMessage(m.address, 65535, "# of connected terminals: " .. #modems + 1)
        for i, v in pairs(modems) do
          onMessage(m.address, 65535, "[" .. i .. "]: " .. v)
        end
      elseif toSend == "-/Help" or toSend == "-/help" then
        onMessage(m.address, 65535, "Commands List: -/Help, -/Connected, -/Clear")
      else
        onMessage(m.address, 65535, "Unknown command, use -/Help for commands.")
      end
      checkClear()
      toSend = ""
    elseif toSend ~= "" then -- Normal text.
      message.sendMessage(toSend)
      toSend = ""
      column = 3
      line = line + 1
      checkClear()
    end
  elseif code == 14 then -- Backspace key.
    if toSend ~= "" then
      toSend = string.sub(toSend, 1, #toSend - 1)
      column = column - 1
      gpu.set(column, line, " ")
    end
  else
    key1 = require("unicode").char(key1) -- Normal character.
    gpu.set(column, line, key1)
    column = column + 1
    if column == w then
      line = line + 1
      column = 1
    end
    toSend = toSend .. key1
  end
end

------------------------------| MESSAGING |-----------------------------------

function message.sendMessage(data)
  for _, v in pairs(modems) do
    m.send(v, m_port, data)
  end
end

function message.close(bool)
  m.close(p_port)
  m.close(m_port)
  for _, v in pairs(modems) do
    m.send(v, p_port, "DSC")
  end
  while #modems > 0 do
    table.remove(modems, 1)
  end
  event.ignore("modem_message", receive)
  event.ignore("key_down", key)
  if bool then
    gpu.setBackground(0x000000)
    require("shell").execute("clear")
  end
end

-- In case theres duplicate listeners.
message.close(false)

------------------------------| LISTENERS/PORTS |-----------------------------------

m.open(p_port)
m.open(m_port)
m.broadcast(p_port, "CHK")
event.listen("modem_message", receive)
event.listen("key_down", key)

os.sleep(2)

onMessage(m.address, 65535, "Welcome to the MRMP terminal! Press Ctrl-C to exit.")
onMessage(m.address, 65535, "# of connected terminals: " .. #modems + 1)
gpu.set(1, line, "> ")

------------------------------| LOOP |-----------------------------------

while running do
  os.sleep(0.05)
end

message.close(true)
