-- TheoSoloDPS (Vanilla/Turtle 1.12)
-- Personal-only DPS + procs + hit-table stats.
--
-- /tdps           : toggle window
-- /tdps reset     : reset "since last reset" segment
-- /tdps lock|unlock
-- /tdps proc add <name>  : track buff-only procs by name
-- /tdps proc del <name>
-- /tdps proc list
--
-- Extra-attacks:
-- Tracks ANY line matching:
--   You gain 1 extra attack through Timeless Strike.
--   You gain 2 extra attacks through Windfury Weapon!
--   You gain 1 exta attack through ... (typo)
--
-- It always sums into "Extra Attacks" (total extra swings granted).
-- If the proc source name is in your whitelist, it also tracks that proc separately
-- (counts = how many extra attacks that proc granted).

TheoSoloDPS = {}
local A = TheoSoloDPS

-- ----------------------------
-- SavedVariables defaults
-- ----------------------------
TheoSoloDPSDB = TheoSoloDPSDB or {}
local function DB()
  TheoSoloDPSDB.profile = TheoSoloDPSDB.profile or {}
  local p = TheoSoloDPSDB.profile
  p.pos = p.pos or { point="CENTER", rel="CENTER", x=0, y=0 }
  p.visible = (p.visible == nil) and 1 or p.visible
  p.lock = (p.lock == nil) and 0 or p.lock
  p.procWhitelist = p.procWhitelist or {} -- buff-only procs you manually add (AND extra-attack proc sources you want listed)
  p.procBlacklist = p.procBlacklist or {} -- never count as proc
  p.autoProcFromUnknownDamage = (p.autoProcFromUnknownDamage == nil) and 1 or p.autoProcFromUnknownDamage
  p.autoProcFromUnknownBuffs  = (p.autoProcFromUnknownBuffs  == nil) and 0 or p.autoProcFromUnknownBuffs
  return p
end

-- ----------------------------
-- Runtime data (since last reset)
-- ----------------------------
A.data = {
  damage = { [1] = {} }, -- [1][playerName][action]=dmg ; with _sum/_ctime/_tick
  procs  = { [1] = {} }, -- [1][procName]={count=n, dmg=n}
  stats  = { [1] = { auto={}, abil={} } }, -- hit tables
}
A.internals = { _sum=true, _ctime=true, _tick=true }

-- Segment timer (since last reset; starts on first damage/proc/stat event)
A.seg = A.seg or { start = nil }
local function TouchSegment()
  if not A.seg.start then A.seg.start = GetTime() end
end
local function SegmentElapsed()
  if not A.seg.start then return 0 end
  local e = GetTime() - A.seg.start
  if e < 0 then e = 0 end
  return e
end

local playerName = nil
local knownSpells = {}

local function trim(s) return string.gsub(s or "", "^%s*(.-)%s*$", "%1") end

local function StripColors(msg)
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

-- ----------------------------
-- DPS aggregation
-- ----------------------------
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

  TouchSegment()

  entry[action] = (entry[action] or 0) + amount
  entry._sum = (entry._sum or 0) + amount
  AddTime(entry)
end

-- ----------------------------
-- Proc aggregation
-- ----------------------------
local function IncProc(name, dmg, inc)
  if not name or name == "" then return end
  local p = DB()
  name = trim(name)

  if p.procBlacklist[name] then return end

  TouchSegment()

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

  -- unknown damage sources are often enchants/gear/set bonuses
  if isDamage and p.autoProcFromUnknownDamage == 1 and not knownSpells[name] then
    return true
  end

  -- buffs are risky; only if you enable it or whitelist explicitly
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
  -- One unified bucket for total extra swings
  IncProc("Extra Attacks", 0, n)
end

-- ----------------------------
-- Hit-table stats aggregation
-- ----------------------------
local function EnsureStats()
  A.data.stats[1] = A.data.stats[1] or { auto={}, abil={} }
  A.data.stats[1].auto = A.data.stats[1].auto or {}
  A.data.stats[1].abil = A.data.stats[1].abil or {}
  return A.data.stats[1].auto, A.data.stats[1].abil
end

local function IncStat(which, key, inc)
  local auto, abil = EnsureStats()
  local t = (which == "auto") and auto or abil
  inc = tonumber(inc) or 1
  if inc < 1 then inc = 1 end
  TouchSegment()
  t[key] = (t[key] or 0) + inc
end

local function SumStats(t, keys)
  local s = 0
  for _,k in ipairs(keys) do s = s + (t[k] or 0) end
  return s
end

-- ----------------------------
-- Reset
-- ----------------------------
local function ResetSegment()
  A.data.damage[1] = {}
  A.data.procs[1] = {}
  A.data.stats[1] = { auto={}, abil={} }
  A.seg.start = nil
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

-- Returns procSourceName, extraAttackCount
local function ParseExtraAttackProc(msg)
  msg = StripColors(msg)
  msg = trim(msg)

  local n, via = string.match(msg, "^You gain (%d+) extra attacks? through (.-)[%.!%?]?$")
  if via and n then return trim(via), tonumber(n) end

  n, via = string.match(msg, "^You gain (%d+) exta attacks? through (.-)[%.!%?]?$")
  if via and n then return trim(via), tonumber(n) end

  via = string.match(msg, "^You gain an extra attack through (.-)[%.!%?]?$")
  if via then return trim(via), 1 end

  return nil
end

-- Auto attack result parsing
local function ParseAutoHitResult(msg)
  msg = StripColors(msg)
  msg = trim(msg)

  if string.match(msg, "^You crit ") then
    return "crit"
  end
  if string.match(msg, "^You hit ") then
    if string.find(string.lower(msg), "glancing") then
      return "glance"
    end
    return "hit"
  end
  return nil
end

local function ParseAutoMissResult(msg)
  msg = StripColors(msg)
  msg = trim(msg)
  local low = string.lower(msg)

  if string.find(low, "miss") then return "miss" end
  if string.find(low, "dodge") then return "dodge" end
  if string.find(low, "parry") then return "parry" end
  if string.find(low, "block") then return "block" end
  return nil
end

-- Ability result parsing (melee abilities / spells)
local function ParseAbilityResult(msg)
  msg = StripColors(msg)
  msg = trim(msg)
  local low = string.lower(msg)

  if string.match(msg, "^Your .- hits ") then return "hit" end
  if string.match(msg, "^Your .- crits ") then return "crit" end

  if string.find(low, "miss") and string.match(msg, "^Your ") then return "miss" end
  if string.find(low, "dodge") and string.match(msg, "^Your ") then return "dodge" end
  if string.find(low, "parry") and string.match(msg, "^Your ") then return "parry" end
  if string.find(low, "block") and string.match(msg, "^Your ") then return "block" end
  if string.find(low, "resist") and string.match(msg, "^Your ") then return "resist" end
  if string.find(low, "immune") and string.match(msg, "^Your ") then return "immune" end

  return nil
end

-- ----------------------------
-- Event driver (SELF ONLY)
-- ----------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("LEARNED_SPELL_IN_TAB")

-- damage
f:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")
f:RegisterEvent("CHAT_MSG_COMBAT_SELF_HITS")
f:RegisterEvent("CHAT_MSG_COMBAT_SELF_MISSES")
f:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE")
f:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE")
f:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_DAMAGE")

-- potential places extra-attack lines can appear (varies by chat mods)
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
    EnsureStats()

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

  -- Extra attacks: always count total, optionally per-source if whitelisted
  local procName, extraCt = ParseExtraAttackProc(msg)
  if extraCt and extraCt > 0 and string.match(StripColors(msg), "^You gain") then
    AddExtraAttacks(extraCt)
    if procName and DB().procWhitelist[procName] then
      IncProc(procName, 0, extraCt)
    end
    if A.Refresh then A.Refresh() end
    return
  end

  -- Auto hit table (white swings)
  if event == "CHAT_MSG_COMBAT_SELF_HITS" then
    local res = ParseAutoHitResult(msg)
    if res == "hit" then IncStat("auto", "hit", 1)
    elseif res == "crit" then IncStat("auto", "crit", 1)
    elseif res == "glance" then IncStat("auto", "glance", 1)
    end

    -- also parse damage for DPS
    local action, amount = ParseSelfMeleeDamage(msg)
    if action and amount then
      AddDamage(action, amount)
      if A.Refresh then A.Refresh() end
      return
    end
  elseif event == "CHAT_MSG_COMBAT_SELF_MISSES" then
    local res = ParseAutoMissResult(msg)
    if res then IncStat("auto", res, 1) end
    if A.Refresh then A.Refresh() end
    return
  end

  -- Abilities: outcomes + DPS
  if event == "CHAT_MSG_SPELL_SELF_DAMAGE" then
    local ares = ParseAbilityResult(msg)
    if ares then IncStat("abil", ares, 1) end

    local action, amount = ParseSelfSpellDamage(msg)
    if action and amount then
      AddDamage(action, amount)
      AddDamageProc(action, amount)
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

  -- Buff gains: whitelist-style procs
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
window:SetWidth(300); window:SetHeight(235)
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

-- Tabs
local tabDPS = MakeButton(window, "DPS", 60, 18)
tabDPS:SetPoint("TOPLEFT", 8, -28)
local tabProcs = MakeButton(window, "Procs", 60, 18)
tabProcs:SetPoint("LEFT", tabDPS, "RIGHT", 6, 0)
local tabStats = MakeButton(window, "Stats", 60, 18)
tabStats:SetPoint("LEFT", tabProcs, "RIGHT", 6, 0)

local summary = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
summary:SetPoint("TOPLEFT", 10, -52)
summary:SetJustifyH("LEFT")

-- Sub-buttons for Stats tab
local statsAutoBtn = MakeButton(window, "Auto", 50, 16)
statsAutoBtn:SetPoint("TOPRIGHT", -78, -50)
local statsAbilBtn = MakeButton(window, "Abilities", 66, 16)
statsAbilBtn:SetPoint("LEFT", statsAutoBtn, "RIGHT", 4, 0)

local content = CreateFrame("Frame", nil, window)
content:SetPoint("TOPLEFT", 8, -70)
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

-- Footer buttons
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

-- Tab state
local activeTab = "dps"
local statsMode = "auto" -- "auto" or "abil"

local function SetTab(which)
  activeTab = which
  if which == "dps" then
    tabDPS:Disable(); tabProcs:Enable(); tabStats:Enable()
  elseif which == "procs" then
    tabProcs:Disable(); tabDPS:Enable(); tabStats:Enable()
  else
    tabStats:Disable(); tabDPS:Enable(); tabProcs:Enable()
  end

  if which == "stats" then
    statsAutoBtn:Show()
    statsAbilBtn:Show()
  else
    statsAutoBtn:Hide()
    statsAbilBtn:Hide()
  end
end

tabDPS:SetScript("OnClick", function() SetTab("dps"); if A.Refresh then A.Refresh() end end)
tabProcs:SetScript("OnClick", function() SetTab("procs"); if A.Refresh then A.Refresh() end end)
tabStats:SetScript("OnClick", function() SetTab("stats"); if A.Refresh then A.Refresh() end end)

statsAutoBtn:SetScript("OnClick", function()
  statsMode = "auto"
  statsAutoBtn:Disable(); statsAbilBtn:Enable()
  if A.Refresh then A.Refresh() end
end)
statsAbilBtn:SetScript("OnClick", function()
  statsMode = "abil"
  statsAbilBtn:Disable(); statsAutoBtn:Enable()
  if A.Refresh then A.Refresh() end
end)

-- default: DPS tab active
tabDPS:Disable(); tabProcs:Enable(); tabStats:Enable()
statsAutoBtn:Hide(); statsAbilBtn:Hide()
statsAutoBtn:Disable(); statsAbilBtn:Enable()

A.Refresh = function()
  lockBtn:SetText(DB().lock == 1 and "Unlock" or "Lock")

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
        r:SetValue(0); r.left:SetText(""); r.right:SetText(""); r:Hide()
      end
    end

  elseif activeTab == "procs" then
    local procs = A.data.procs[1] or {}
    local list = {}
    local totalEvents = 0
    for name, t in pairs(procs) do
      if type(t) == "table" then
        totalEvents = totalEvents + (t.count or 0)
        table.insert(list, { name=name, count=(t.count or 0), dmg=(t.dmg or 0) })
      end
    end
    table.sort(list, function(a,b)
      if a.count == b.count then return (a.dmg or 0) > (b.dmg or 0) end
      return a.count > b.count
    end)

    summary:SetText(string.format("Proc counts: %d  |  Time: %ds", totalEvents, math.floor(SegmentElapsed())))

    local top = list[1] and list[1].count or 0
    for i=1,8 do
      local r = rows[i]
      local item = list[i]
      if item and top > 0 and item.count > 0 then
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
        r:SetValue(0); r.left:SetText(""); r.right:SetText(""); r:Hide()
      end
    end

  else -- stats
    local auto, abil = EnsureStats()
    local autoTotal = SumStats(auto, { "hit","crit","glance","miss","dodge","parry","block" })
    local abilTotal = SumStats(abil, { "hit","crit","miss","dodge","parry","block","resist","immune" })

    summary:SetText(string.format("Auto: %d  |  Abil: %d  |  Time: %ds", autoTotal, abilTotal, math.floor(SegmentElapsed())))

    if statsMode == "auto" then
      statsAutoBtn:Disable(); statsAbilBtn:Enable()
      local totalAtt = autoTotal
      local cats = {
        { key="hit", name="Hits" },
        { key="crit", name="Crits" },
        { key="glance", name="Glancing" },
        { key="miss", name="Miss" },
        { key="dodge", name="Dodge" },
        { key="parry", name="Parry" },
        { key="block", name="Block" },
      }
      local tmp = {}
      for _,c in ipairs(cats) do
        table.insert(tmp, { name=c.name, val=(auto[c.key] or 0) })
      end
      table.sort(tmp, function(a,b) return a.val > b.val end)
      local top = tmp[1] and tmp[1].val or 0

      for i=1,7 do
        local r = rows[i]
        local item = tmp[i]
        if item and item.val > 0 and totalAtt > 0 then
          r:SetValue(item.val / math.max(1, top))
          r.left:SetText(item.name)
          r.right:SetText(string.format("%d (%.1f%%)", item.val, (item.val/totalAtt)*100))
          r:Show()
        else
          r:SetValue(0); r.left:SetText(""); r.right:SetText(""); r:Hide()
        end
      end

      -- Total row
      local r = rows[8]
      r:SetValue(1)
      r.left:SetText("Total Swings")
      r.right:SetText(tostring(totalAtt))
      r:Show()

    else
      statsAbilBtn:Disable(); statsAutoBtn:Enable()
      local totalAtt = abilTotal
      local cats = {
        { key="hit", name="Hits" },
        { key="crit", name="Crits" },
        { key="miss", name="Miss" },
        { key="dodge", name="Dodge" },
        { key="parry", name="Parry" },
        { key="block", name="Block" },
        { key="resist", name="Resist" },
      }
      local tmp = {}
      for _,c in ipairs(cats) do
        table.insert(tmp, { name=c.name, val=(abil[c.key] or 0) })
      end
      table.sort(tmp, function(a,b) return a.val > b.val end)
      local top = tmp[1] and tmp[1].val or 0

      for i=1,7 do
        local r = rows[i]
        local item = tmp[i]
        if item and item.val > 0 and totalAtt > 0 then
          r:SetValue(item.val / math.max(1, top))
          r.left:SetText(item.name)
          r.right:SetText(string.format("%d (%.1f%%)", item.val, (item.val/totalAtt)*100))
          r:Show()
        else
          r:SetValue(0); r.left:SetText(""); r.right:SetText(""); r:Hide()
        end
      end

      local r = rows[8]
      r:SetValue(1)
      r.left:SetText("Total Abilities")
      r.right:SetText(tostring(totalAtt))
      r:Show()
    end
  end
end

A.Refresh()

-- ----------------------------
-- Slash commands
-- ----------------------------
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

  -- default: toggle
  if window:IsShown() then
    DB().visible = 0
    window:Hide()
  else
    DB().visible = 1
    window:Show()
  end
end
