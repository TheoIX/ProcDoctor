-- TheoSoloDPS (Vanilla/Turtle 1.12)
-- Personal-only DPS + proc tracker.
--
-- /tdps           : toggle window
-- /tdps reset     : reset "since last reset" segment
-- /tdps lock|unlock
-- /tdps proc add <name>  (track buff-only procs by name, e.g. "Kiss of the Spider")
-- /tdps proc del <name>
-- /tdps proc list
--
-- Extra-attacks:
-- Tracks ANY combat log event line matching:
--   You gain 1 extra attack through Timeless Strike.
--   You gain 2 extra attacks through Windfury Weapon!
--   You gain 1 exta attack through ...           (typo)
-- All merged into ONE proc bucket:
--   "Extra Attacks" = total extra swings granted (numbers are summed)

TheoSoloDPS = {}
local A = TheoSoloDPS

TheoSoloDPSDB = TheoSoloDPSDB or {}
local function DB()
  TheoSoloDPSDB.profile = TheoSoloDPSDB.profile or {}
  local p = TheoSoloDPSDB.profile
  p.pos = p.pos or { point="CENTER", rel="CENTER", x=0, y=0 }
  p.visible = (p.visible == nil) and 1 or p.visible
  p.lock = (p.lock == nil) and 0 or p.lock
  p.procWhitelist = p.procWhitelist or {} -- buff-only procs you manually add
  p.procBlacklist = p.procBlacklist or {} -- never count as proc
  p.autoProcFromUnknownDamage = (p.autoProcFromUnknownDamage == nil) and 1 or p.autoProcFromUnknownDamage
  p.autoProcFromUnknownBuffs  = (p.autoProcFromUnknownBuffs  == nil) and 0 or p.autoProcFromUnknownBuffs
  return p
end

A.data = {
  damage = { [1] = {} }, -- [1][playerName][action]=dmg ; with _sum/_ctime/_tick
  procs  = { [1] = {} }, -- [1][procName]={count=n, dmg=n}
}

A.internals = { _sum=true, _ctime=true, _tick=true }

local playerName = nil
local knownSpells = {}

local function trim(s) return string.gsub(s or "", "^%s*(.-)%s*$", "%1") end

local function StripColors(msg)
  -- remove chat color codes, just in case
  msg = string.gsub(msg or "", "|c%x%x%x%x%x%x%x%x", "")
  msg = string.gsub(msg or "", "|r", "")
  return msg
end

local function ScanSpellbook()
  knownSpells = {}
  local i = 1
  while true do
    local name = GetSpellName(i, BOOKTYPE_SPELL)
    if not name then break end
    knownSpells[name] = true
    i = i + 1
  end
end

local function EnsurePlayerEntry()
  if not playerName then return nil end
  local seg = A.data.damage[1]
  if not seg[playerName] then
    seg[playerName] = { _sum = 0, _ctime = 1, _tick = GetTime() }
  end
  return seg[playerName]
end

local function AddTime(entry)
  entry._ctime = entry._ctime or 1
  entry._tick = entry._tick or GetTime()
  if entry._tick + 5 < GetTime() then
    entry._tick = GetTime()
    entry._ctime = entry._ctime + 5
  else
    entry._ctime = entry._ctime + (GetTime() - entry._tick)
    entry._tick = GetTime()
  end
end

local function AddDamage(action, amount)
  if not playerName or not action or not amount then return end
  local entry = EnsurePlayerEntry()
  if not entry then return end

  action = trim(action)
  amount = tonumber(amount)
  if not amount or amount <= 0 then return end

  entry[action] = (entry[action] or 0) + amount
  entry._sum = (entry._sum or 0) + amount
  AddTime(entry)
end

local function IncProc(name, dmg, inc)
  if not name or name == "" then return end
  local p = DB()
  name = trim(name)

  if p.procBlacklist[name] then return end

  local seg = A.data.procs[1]
  seg[name] = seg[name] or { count = 0, dmg = 0 }

  inc = tonumber(inc) or 1
  if inc < 1 then inc = 1 end

  seg[name].count = (seg[name].count or 0) + inc
  if dmg and tonumber(dmg) and tonumber(dmg) > 0 then
    seg[name].dmg = (seg[name].dmg or 0) + tonumber(dmg)
  end
end

local function IsProcAction(name, isDamage)
  local p = DB()
  if not name or name == "" then return false end
  name = trim(name)

  if p.procBlacklist[name] then return false end
  if p.procWhitelist[name] then return true end

  if name == "Melee" then return false end

  if isDamage and p.autoProcFromUnknownDamage == 1 and not knownSpells[name] then
    return true
  end

  if (not isDamage) and p.autoProcFromUnknownBuffs == 1 and not knownSpells[name] then
    return true
  end

  return false
end

local function AddBuffProc(buffName)
  if not buffName then return end
  if IsProcAction(buffName, false) then
    IncProc(buffName, 0, 1)
  end
end

local function AddDamageProc(action, amount)
  if not action then return end
  if IsProcAction(action, true) then
    IncProc(action, amount, 1)
  end
end

local function AddExtraAttacks(n)
  n = tonumber(n)
  if not n or n <= 0 then return end
  IncProc("Extra Attacks", 0, n)
end

local function ResetSegment()
  A.data.damage[1] = {}
  A.data.procs[1] = {}
end

-- ----------------------------
-- Combat log parsing (EN patterns; extend as needed)
-- ----------------------------
local function ParseSelfSpellDamage(msg)
  local action, amount = string.match(msg, "^Your (.-) hits .- for (%d+)")
  if action and amount then return action, tonumber(amount) end
  action, amount = string.match(msg, "^Your (.-) crits .- for (%d+)")
  if action and amount then return action, tonumber(amount) end
  return nil
end

local function ParseSelfMeleeDamage(msg)
  local amount = string.match(msg, "^You hit .- for (%d+)")
  if amount then return "Melee", tonumber(amount) end
  amount = string.match(msg, "^You crit .- for (%d+)")
  if amount then return "Melee", tonumber(amount) end
  return nil
end

local function ParsePeriodicYourDamage(msg)
  local _, amount, action = string.match(msg, "^(.-) suffers (%d+) .- from your (.-)%.?$")
  if action and amount then return action, tonumber(amount) end
  return nil
end

local function ParseBuffGain(msg)
  local buff = string.match(msg, "^You gain (.-)%.?$")
  if buff then return buff end
  return nil
end

local function ParseExtraAttackCount(msg)
  -- Normalize punctuation and colors
  msg = StripColors(msg)
  msg = trim(msg)

  -- Numeric versions:
  -- You gain 1 extra attack through Timeless Strike.
  -- You gain 2 extra attacks through Windfury Weapon!
  local n = string.match(msg, "^You gain (%d+) extra attacks? through .-[%.!%?]?$")
  if n then return tonumber(n) end

  -- Typo versions ("exta"):
  n = string.match(msg, "^You gain (%d+) exta attacks? through .-[%.!%?]?$")
  if n then return tonumber(n) end

  -- Rare wording:
  -- You gain an extra attack through X.
  local ok = string.match(msg, "^You gain an extra attack through .-[%.!%?]?$")
  if ok then return 1 end

  return nil
end

-- ----------------------------
-- Event driver (SELF ONLY, but extra-attack parsing is event-agnostic)
-- ----------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("LEARNED_SPELL_IN_TAB")

-- damage
f:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")
f:RegisterEvent("CHAT_MSG_COMBAT_SELF_HITS")
f:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE")
f:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE")
f:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_DAMAGE")

-- potential places extra-attack lines can appear (varies by client/server/chat mods)
f:RegisterEvent("CHAT_MSG_COMBAT_SELF_MISC_INFO")
f:RegisterEvent("CHAT_MSG_COMBAT_MISC_INFO")
f:RegisterEvent("CHAT_MSG_SPELL_SELF_BUFF")
f:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS")
f:RegisterEvent("CHAT_MSG_SYSTEM")

f:SetScript("OnEvent", function()
  if event == "PLAYER_ENTERING_WORLD" then
    playerName = UnitName("player")
    ScanSpellbook()
    EnsurePlayerEntry()
    if DB().visible == 1 then
      if A.window then A.window:Show() end
    else
      if A.window then A.window:Hide() end
    end
    return
  end

  if event == "LEARNED_SPELL_IN_TAB" then
    ScanSpellbook()
    return
  end

  local msg = arg1
  if type(msg) ~= "string" then return end

  -- Extra attacks: count them NO MATTER which event they come in on
  -- But only if it's your message (starts with "You gain ...").
  local extraCt = ParseExtraAttackCount(msg)
  if extraCt and extraCt > 0 and string.match(StripColors(msg), "^You gain") then
    AddExtraAttacks(extraCt)
    if A.Refresh then A.Refresh() end
    return
  end

  -- Damage parsing
  if event == "CHAT_MSG_SPELL_SELF_DAMAGE" then
    local action, amount = ParseSelfSpellDamage(msg)
    if action and amount then
      AddDamage(action, amount)
      AddDamageProc(action, amount)
      if A.Refresh then A.Refresh() end
      return
    end
  elseif event == "CHAT_MSG_COMBAT_SELF_HITS" then
    local action, amount = ParseSelfMeleeDamage(msg)
    if action and amount then
      AddDamage(action, amount)
      if A.Refresh then A.Refresh() end
      return
    end
  elseif event == "CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE"
      or event == "CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE"
      or event == "CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_DAMAGE" then
    local action, amount = ParsePeriodicYourDamage(msg)
    if action and amount then
      AddDamage(action, amount)
      AddDamageProc(action, amount)
      if A.Refresh then A.Refresh() end
      return
    end
  end

  -- Buff gains
  if event == "CHAT_MSG_SPELL_SELF_BUFF" or event == "CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS" then
    local buff = ParseBuffGain(msg)
    if buff then
      AddBuffProc(buff)
      if A.Refresh then A.Refresh() end
      return
    end
  end
end)

-- ----------------------------
-- UI
-- ----------------------------
local function CreateBackdrop(frame)
  frame:SetBackdrop({
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
  })
  frame:SetBackdropColor(0,0,0,0.85)
end

local function MakeButton(parent, text, w, h)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetText(text)
  b:SetWidth(w); b:SetHeight(h)
  return b
end

local function Shorten(n)
  n = tonumber(n) or 0
  if n >= 1000000 then return string.format("%.2fm", n/1000000) end
  if n >= 1000 then return string.format("%.1fk", n/1000) end
  return tostring(math.floor(n + 0.5))
end

local window = CreateFrame("Frame", "TheoSoloDPSFrame", UIParent)
A.window = window
window:SetWidth(260); window:SetHeight(220)
CreateBackdrop(window)
window:SetClampedToScreen(true)
window:SetMovable(true)
window:EnableMouse(true)

window:SetScript("OnMouseDown", function()
  if DB().lock == 1 then return end
  if arg1 == "LeftButton" then this:StartMoving() end
end)
window:SetScript("OnMouseUp", function()
  if arg1 == "LeftButton" then
    this:StopMovingOrSizing()
    local p = DB()
    local point, _, relPoint, xOfs, yOfs = this:GetPoint(1)
    p.pos.point, p.pos.rel, p.pos.x, p.pos.y = point, relPoint, xOfs, yOfs
  end
end)

window:SetScript("OnShow", function()
  local p = DB()
  this:ClearAllPoints()
  this:SetPoint(p.pos.point, UIParent, p.pos.rel, p.pos.x, p.pos.y)
end)

local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOPLEFT", 10, -8)
title:SetText("TheoSoloDPS")

local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", 2, 2)

local tabDPS = MakeButton(window, "DPS", 60, 18)
tabDPS:SetPoint("TOPLEFT", 8, -28)
local tabProcs = MakeButton(window, "Procs", 60, 18)
tabProcs:SetPoint("LEFT", tabDPS, "RIGHT", 6, 0)

local summary = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
summary:SetPoint("TOPLEFT", 10, -52)
summary:SetJustifyH("LEFT")

local content = CreateFrame("Frame", nil, window)
content:SetPoint("TOPLEFT", 8, -66)
content:SetPoint("BOTTOMRIGHT", -8, 34)

local rows = {}
local function CreateRow(i)
  local r = CreateFrame("StatusBar", nil, content)
  r:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  r:SetMinMaxValues(0, 1)
  r:SetValue(0)
  r:SetHeight(14)
  r:SetPoint("TOPLEFT", 0, -((i-1)*15))
  r:SetPoint("TOPRIGHT", 0, -((i-1)*15))
  r.bg = r:CreateTexture(nil, "BACKGROUND")
  r.bg:SetAllPoints(r)
  r.bg:SetTexture("Interface\\BUTTONS\\WHITE8X8")
  r.bg:SetVertexColor(0,0,0,0.35)

  r.left = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.left:SetPoint("LEFT", 2, 0)
  r.left:SetJustifyH("LEFT")

  r.right = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.right:SetPoint("RIGHT", -2, 0)
  r.right:SetJustifyH("RIGHT")

  return r
end
for i=1,8 do rows[i] = CreateRow(i) end

local resetBtn = MakeButton(window, "Reset", 60, 18)
resetBtn:SetPoint("BOTTOMLEFT", 8, 8)
resetBtn:SetScript("OnClick", function()
  ResetSegment()
  if A.Refresh then A.Refresh() end
end)

local lockBtn = MakeButton(window, "Lock", 60, 18)
lockBtn:SetPoint("LEFT", resetBtn, "RIGHT", 6, 0)
lockBtn:SetScript("OnClick", function()
  local p = DB()
  p.lock = (p.lock == 1) and 0 or 1
  this:SetText(p.lock == 1 and "Unlock" or "Lock")
end)

local helpBtn = MakeButton(window, "Cmds", 60, 18)
helpBtn:SetPoint("LEFT", lockBtn, "RIGHT", 6, 0)
helpBtn:SetScript("OnClick", function()
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99TheoSoloDPS|r: /tdps, /tdps reset, /tdps lock|unlock, /tdps proc add <name>, /tdps proc del <name>, /tdps proc list")
end)

local activeTab = "dps"
local function SetTab(which)
  activeTab = which
  if which == "dps" then
    tabDPS:Disable()
    tabProcs:Enable()
  else
    tabProcs:Disable()
    tabDPS:Enable()
  end
end
tabDPS:SetScript("OnClick", function() SetTab("dps"); if A.Refresh then A.Refresh() end end)
tabProcs:SetScript("OnClick", function() SetTab("procs"); if A.Refresh then A.Refresh() end end)
tabDPS:Disable()
tabProcs:Enable()

A.Refresh = function()
  local entry = (playerName and A.data.damage[1][playerName]) or nil
  local total = (entry and entry._sum) or 0
  local ctime = (entry and entry._ctime) or 1
  local dps = (total / math.max(1, ctime))

  if activeTab == "dps" then
    summary:SetText(string.format("Total: %s  |  DPS: %.1f  |  Time: %ds", Shorten(total), dps, math.floor(ctime)))

    local list = {}
    if entry then
      for k,v in pairs(entry) do
        if not A.internals[k] and type(v) == "number" then
          table.insert(list, { name=k, dmg=v })
        end
      end
    end
    table.sort(list, function(a,b) return a.dmg > b.dmg end)

    local top = list[1] and list[1].dmg or 0
    for i=1,8 do
      local r = rows[i]
      local item = list[i]
      if item and total > 0 then
        local pct = (item.dmg / total) * 100
        r:SetValue(item.dmg / math.max(1, top))
        r.left:SetText(item.name)
        r.right:SetText(string.format("%s (%.1f%%)", Shorten(item.dmg), pct))
        r:Show()
      else
        r:SetValue(0)
        r.left:SetText("")
        r.right:SetText("")
        r:Hide()
      end
    end
  else
    local procs = A.data.procs[1] or {}
    local list = {}
    local totalProcs = 0
    for name, t in pairs(procs) do
      if type(t) == "table" then
        totalProcs = totalProcs + (t.count or 0)
        table.insert(list, { name=name, count=(t.count or 0), dmg=(t.dmg or 0) })
      end
    end
    table.sort(list, function(a,b)
      if a.count == b.count then return a.dmg > b.dmg end
      return a.count > b.count
    end)

    summary:SetText(string.format("Proc counts: %d  (Extra Attacks = extra swings granted)", totalProcs))

    local top = list[1] and list[1].count or 0
    for i=1,8 do
      local r = rows[i]
      local item = list[i]
      if item and top > 0 then
        r:SetValue(item.count / top)
        r.left:SetText(item.name)

        if item.name == "Extra Attacks" then
          r.right:SetText(string.format("%d attacks", math.floor(item.count)))
        elseif item.dmg and item.dmg > 0 then
          r.right:SetText(string.format("%dx  |  %s dmg", item.count, Shorten(item.dmg)))
        else
          r.right:SetText(string.format("%dx", item.count))
        end

        r:Show()
      else
        r:SetValue(0)
        r.left:SetText("")
        r.right:SetText("")
        r:Hide()
      end
    end
  end

  lockBtn:SetText(DB().lock == 1 and "Unlock" or "Lock")
end

A.Refresh()

SLASH_THEOSOLODPS1 = "/tdps"
SlashCmdList["THEOSOLODPS"] = function(msg)
  msg = trim(msg or "")
  local cmd, rest = string.match(msg, "^(%S+)%s*(.-)$")
  cmd = cmd and string.lower(cmd)

  if cmd == "show" then
    DB().visible = 1
    window:Show()
    return
  elseif cmd == "hide" then
    DB().visible = 0
    window:Hide()
    return
  elseif cmd == "reset" then
    ResetSegment()
    A.Refresh()
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99TheoSoloDPS|r reset.")
    return
  elseif cmd == "lock" then
    DB().lock = 1
    A.Refresh()
    return
  elseif cmd == "unlock" then
    DB().lock = 0
    A.Refresh()
    return
  elseif cmd == "proc" then
    local sub, name = string.match(rest or "", "^(%S+)%s*(.-)$")
    sub = sub and string.lower(sub) or ""
    name = trim(name)

    if sub == "add" and name ~= "" then
      DB().procWhitelist[name] = true
      DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99TheoSoloDPS|r proc added: " .. name)
      return
    elseif sub == "del" and name ~= "" then
      DB().procWhitelist[name] = nil
      DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99TheoSoloDPS|r proc removed: " .. name)
      return
    elseif sub == "list" then
      DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99TheoSoloDPS|r proc whitelist:")
      for n,_ in pairs(DB().procWhitelist) do
        DEFAULT_CHAT_FRAME:AddMessage(" - " .. n)
      end
      return
    else
      DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99TheoSoloDPS|r usage: /tdps proc add <name> | del <name> | list")
      return
    end
  end

  if window:IsShown() then
    DB().visible = 0
    window:Hide()
  else
    DB().visible = 1
    window:Show()
  end
end
