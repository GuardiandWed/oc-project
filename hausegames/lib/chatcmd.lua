-- /lib/chatcmd.lua

local component = require("component")
local event     = require("event")
local thread    = require("thread")
local computer  = require("computer")
local fs        = require("filesystem")
local ser       = require("serialization")

local Chat = {}; Chat.__index = Chat
local ADMINS_FILE = "/home/data/chat_admins.json"

local function toSet(t) local s={} for _,v in ipairs(t or {}) do s[v]=true end return s end

local function save_admins(set)
  fs.makeDirectory("/home/data")
  local arr = {}
  for k,v in pairs(set) do if v then arr[#arr+1]=k end end
  local f = assert(io.open(ADMINS_FILE,"wb")); f:write(ser.serialize(arr)); f:close()
end
local function load_admins()
  if not (fs.exists(ADMINS_FILE) and not fs.isDirectory(ADMINS_FILE)) then return {} end
  local f = io.open(ADMINS_FILE,"rb"); if not f then return {} end
  local data = f:read("*a"); f:close()
  local ok,t = pcall(ser.unserialize, data); if ok and type(t)=="table" then return t else return {} end
end

local function splitArgs(str)
  local out = {}; str = str or ""; local i=1
  while i <= #str do
    while str:sub(i,i):match("%s") do i=i+1 if i>#str then break end end
    if i>#str then break end
    local c=str:sub(i,i)
    if c=='"' or c=="'" then
      local q=c; local j=i+1; while j<=#str and str:sub(j,j)~=q do j=j+1 end
      table.insert(out, str:sub(i+1, j-1)); i=j+1
    else
      local j=i; while j<=#str and not str:sub(j,j):match("%s") do j=j+1 end
      table.insert(out, str:sub(i, j-1)); i=j
    end
  end
  return out
end

function Chat.new(opts)
  opts = opts or {}
  local self = setmetatable({}, Chat)
  self.prefix   = opts.prefix or "@"
  self.name     = opts.name or "Оператор"
  self.chatBox  = opts.chatBox or (component.isAvailable("chat_box") and component.chat_box or nil)
  self.permAll  = opts.allow_all or false
  local persisted = load_admins()
  self.admins   = toSet(#persisted>0 and persisted or (opts.admins or {}))
  self.allow    = toSet(opts.allow or {})
  self.deny     = toSet(opts.deny  or {})
  self.commands = {}
  self.running  = false
  self.thread   = nil
  self._helpAdded = false
  self._lastSeen  = {}   -- ник -> os.time() последнего сообщения

  self._ctxBase = {
    computer = computer,
    say   = function(msg) if self.chatBox then self.chatBox.say(tostring(msg)) end end,
    reply = function(msg) if self.chatBox then self.chatBox.say(tostring(msg)) end end,
    setName = function(nm) if self.chatBox then self.chatBox.setName(nm) end end,
  }
  return self
end

function Chat:isAllowed(nick) if self.deny[nick] then return false end; if self.permAll then return true end; if self.admins[nick] or self.allow[nick] then return true end; return false end
function Chat:setNameTag(tag) if self.chatBox then self.chatBox.setName(tag) end end
function Chat:addAdmin(nick)  self.admins[nick]=true; save_admins(self.admins) end
function Chat:removeAdmin(nick) self.admins[nick]=nil; save_admins(self.admins) end
function Chat:addAllow(nick)  self.allow[nick]=true end
function Chat:removeAllow(nick) self.allow[nick]=nil end

function Chat:register(name, fn, help, opts)
  local cmd = {name=name, fn=fn, help=help or "", admin_only=opts and opts.admin_only or false}
  self.commands[name]=cmd
  if opts and opts.aliases then for _,al in ipairs(opts.aliases) do self.commands[al]=cmd end end
  return self
end

function Chat:_ensureHelp()
  if self._helpAdded then return end
  self._helpAdded = true

  self:register("help", function(ctx)
    ctx.reply("Доступные команды:")
    local seen={}
    for _,cmd in pairs(self.commands) do
      if not seen[cmd] and ((not cmd.admin_only) or ctx.isAdmin) then
        ctx.reply(("  %s%s — %s"):format(self.prefix, cmd.name, cmd.help or ""))
        seen[cmd]=true
      end
    end
  end, "Список команд", {aliases={"?"}})

  self:register("echo", function(ctx,args) ctx.reply(table.concat(args," ")) end, "Повторить текст")

  self:register("sleep", function(ctx)
    if not ctx.isAdmin then ctx.reply("Только для админа.") return end
    ctx.reply("Перезагрузка..."); computer.shutdown(true)
  end, "Перезагрузить ПК", {admin_only=true})

  self:register("addadmin", function(ctx,args)
    if not ctx.isAdmin then ctx.reply("Только для админа.") return end
    local who = args[1]; if not who then ctx.reply("Кого добавить?") return end
    self:addAdmin(who); ctx.reply("Админ добавлен: "..who)
  end, "Добавить админа (только админ)", {admin_only=true})

  self:register("removeadmin", function(ctx,args)
    if not ctx.isAdmin then ctx.reply("Только для админа.") return end
    local who = args[1]; if not who then ctx.reply("Кого удалить?") return end
    self:removeAdmin(who); ctx.reply("Админ удалён: "..who)
  end, "Удалить админа (только админ)", {admin_only=true})
end

function Chat:_handle(nick, raw)
  if not raw or raw:sub(1,#self.prefix) ~= self.prefix then
    -- НЕ команда: простая привет/прощай логика для админов
    if self.admins[nick] and self.chatBox then
      local last = self._lastSeen[nick]
      local now  = os.time()
      if not last or (now - last) > 300 then  -- 5 минут не писал
        self.chatBox.say("Привет, "..nick.."! Я здесь, если что. Напиши "..self.prefix.."help")
      end
      self._lastSeen[nick] = now
    end
    return false
  end

  local text  = raw:sub(#self.prefix+1)
  local parts = splitArgs(text)
  local cmdName = parts[1]; table.remove(parts,1)
  if not cmdName or cmdName=="" then return true end
  local cmd = self.commands[cmdName]
  if not cmd then
    self._ctxBase.reply(("Неизвестная команда: %s%s (см. %shelp)"):format(self.prefix, cmdName, self.prefix))
    return true
  end

  local ctx = { nick=nick, isAdmin=self.admins[nick] or false, args=parts }
  for k,v in pairs(self._ctxBase) do ctx[k]=v end
  if cmd.admin_only and not ctx.isAdmin then ctx.reply("Недостаточно прав."); return true end
  local ok,err = pcall(cmd.fn, ctx, parts); if not ok then ctx.reply("Ошибка: "..tostring(err)) end
  return true
end

function Chat:start()
  if self.running then return self end
  self.running = true
  self:_ensureHelp()
  if self.chatBox then self.chatBox.setName("§9§l"..self.name.."§7§o") end

  self.thread = thread.create(function()
    while self.running do
      local _, _, nick, msg = event.pull(0.5, "chat_message")
      if nick and msg and self:isAllowed(nick) then
        local handled = self:_handle(nick, msg)
        if not handled then
          -- тут можно повесить авто-прощание: если 5 мин молчание после приветствия
          local now = os.time()
          for name,last in pairs(self._lastSeen) do
            if (now - last) > 300 then
              self._lastSeen[name] = now + 10^9 -- чтобы не спамить
              if self.chatBox then self.chatBox.say("До встречи, "..name.."!") end
            end
          end
        end
      end
    end
  end)

  return self
end

function Chat:stop() self.running=false; if self.thread then pcall(self.thread.kill, self.thread) end; self.thread=nil end

return Chat
