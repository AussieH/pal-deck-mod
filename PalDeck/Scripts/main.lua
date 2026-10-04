local MOD = "PalDeck"
local VERSION = "1.1.0"

local STATE_CANDIDATES = {
  "Mods/NativeMods/UE4SS/Mods/" .. MOD .. "/state.json",
  "../../../Mods/NativeMods/UE4SS/Mods/" .. MOD .. "/state.json",
  "ue4ss/Mods/" .. MOD .. "/state.json",
  "Mods/" .. MOD .. "/state.json",
  MOD .. "-state.json",
}
local statePath = nil
local STATE_EVERY_MS = 1000

local HOME_DIR, HOME_STATE = nil, nil
do
  local base = os.getenv("APPDATA")
  if base and base ~= "" then
    HOME_DIR = base .. "\\" .. MOD
    HOME_STATE = HOME_DIR .. "\\state.json"
  end
end
local home = { ready = false, tries = 0, nextAt = 0, fails = 0, warned = false }
local writeSeq = 0

local function log(msg)
  print(string.format("[%s] %s\n", MOD, msg))
end

local function find(cls)
  local ok, o = pcall(function() return FindFirstOf(cls) end)
  if ok and o and o:IsValid() then return o end
  return nil
end

local function player()
  return find("PalPlayerCharacter")
end

local dumpPath = nil
local tracePath = nil
local MAX_PROPS = 400

local function safe(fn, fallback)
  local ok, v = pcall(fn)
  if ok and v ~= nil then return v end
  return fallback
end

local function writeWhole(path, body)
  local f = io.open(path, "wb")
  if not f then return false end
  pcall(function() f:setvbuf("full", #body + 64) end)
  local ok = f:write(body)
  f:close()
  return ok ~= nil
end

local function isValid(o) return o ~= nil and safe(function() return o:IsValid() end, false) end

local HOME_TEXTURES = {
  "/Engine/EngineResources/DefaultTexture.DefaultTexture",
  "/Engine/EngineResources/WhiteSquareTexture.WhiteSquareTexture",
  "/Engine/EngineResources/Black.Black",
}

local function makeHomeDir()
  if not HOME_DIR then return false end
  local lib = safe(function() return StaticFindObject("/Script/Engine.Default__KismetRenderingLibrary") end, nil)
  local fn = safe(function() return StaticFindObject("/Script/Engine.KismetRenderingLibrary:ExportTexture2D") end, nil)
  if not (isValid(lib) and isValid(fn)) then return false end
  local tex = nil
  for _, path in ipairs(HOME_TEXTURES) do
    local t = safe(function() return StaticFindObject(path) end, nil)
    if isValid(t) then tex = t; break end
  end
  local ctx = find("PlayerController")
  if not ctx then return nil end
  if not tex then return false end
  local dir = HOME_DIR:gsub("\\", "/")
  pcall(function() lib:ExportTexture2D(ctx, tex, dir, "folder.hdr") end)
  os.remove(HOME_DIR .. "\\folder.hdr")
  return true
end

local function homeStarter()
  return "{" .. table.concat({
    '"protocol":1', '"mod":"' .. MOD .. '"', '"version":"' .. VERSION .. '"',
    '"written":"' .. os.date("!%Y-%m-%dT%H:%M:%SZ") .. '"', '"at":' .. os.time(), '"seq":0',
    '"inGame":false', '"end":true',
  }, ",") .. "}"
end

local function homeTry(body)
  if not HOME_STATE then return false end
  if writeWhole(HOME_STATE, body or homeStarter()) then
    if not home.ready then log("home state file: " .. HOME_STATE) end
    home.ready, home.fails = true, 0
    return true
  end
  return false
end

local function homeStep()
  if home.ready or not HOME_STATE or home.tries >= 20 or os.time() < home.nextAt then return end
  home.nextAt = os.time() + 3
  if homeTry() then return end
  local made = makeHomeDir()
  if made == nil then return end
  home.tries = home.tries + 1
  if homeTry() then return end
  if home.tries >= 20 and not home.warned then
    home.warned = true
    log("home state file: could not create " .. HOME_DIR .. "; make that folder by hand and the copy for iCUE starts")
  end
end

if not homeTry() then
  ExecuteInGameThread(function() pcall(homeStep) end)
end

function devMode()
  if not dumpPath then return false end
  local f = io.open((dumpPath:gsub("dump%.txt$", "dev.txt")), "r")
  if f then f:close(); return true end
  return false
end

local function trace(msg)

  if not tracePath or not devMode() then return end
  local f = io.open(tracePath, "a")
  if f then f:write(os.date("!%H:%M:%S "), msg, "\n"); f:close() end
end

local function flush(out)
  if not dumpPath then return end
  local f = io.open(dumpPath, "w")
  if f then f:write(table.concat(out, "\n"), "\n"); f:close() end
end

local function nameOf(obj)
  if not obj then return "nil" end
  return safe(function() return obj:GetFullName() end, "<no GetFullName>")
end

local function classOf(obj)
  if not obj then return "nil" end
  return safe(function() return obj:GetClass():GetFName():ToString() end, "<no class>")
end

local function properties(obj, out, indent, deep)
  indent = indent or "    "
  local byName = {}
  local cls = safe(function() return obj:GetClass() end, nil)
  if not cls then out[#out + 1] = indent .. "<no GetClass>"; return byName end
  if type(cls.ForEachProperty) ~= "function" then
    out[#out + 1] = indent .. "<this UE4SS build has no ForEachProperty; cannot list properties>"
    return byName
  end

  local total, depth = 0, 0
  while cls and depth < 10 do
    local owner = safe(function() return cls:GetFName():ToString() end, "?")
    local n = 0
    pcall(function()
      cls:ForEachProperty(function(prop)
        n = n + 1
        total = total + 1
        local pn = safe(function() return prop:GetFName():ToString() end, "?")
        if byName[pn] == nil then byName[pn] = prop end
        if total > MAX_PROPS then return end
        local pt = safe(function() return prop:GetClass():GetFName():ToString() end, "?")
        out[#out + 1] = string.format("%s%-52s %-28s %s", indent, pn, pt, owner)
      end)
    end)
    if n == 0 and depth == 0 then out[#out + 1] = indent .. "<" .. owner .. " declares nothing of its own>" end

    if not deep or owner == "Object" then break end
    trace("    climbing past " .. owner)
    local super = safe(function() return cls:GetSuperStruct() end, nil)

    if not super or type(super.ForEachProperty) ~= "function" then break end
    cls = super
    depth = depth + 1
  end

  if total > MAX_PROPS then out[#out + 1] = string.format("%s... and %d more", indent, total - MAX_PROPS) end
  if total == 0 then out[#out + 1] = indent .. "<no properties listed>" end
  return byName
end

local function structFields(prop, value, out, indent)
  local tries = {
    { "prop:GetStruct()",       function() return prop and prop:GetStruct() end },
    { "prop:GetScriptStruct()", function() return prop and prop:GetScriptStruct() end },
    { "value:GetStruct()",      function() return value and value:GetStruct() end },
    { "value:GetClass()",       function() return value and value:GetClass() end },
  }
  for _, t in ipairs(tries) do
    local st = safe(t[2], nil)
    if st and type(st.ForEachProperty) == "function" then
      local n = 0
      pcall(function()
        st:ForEachProperty(function(f)
          n = n + 1
          if n > 150 then return end
          out[#out + 1] = string.format("%s%-48s %s", indent,
            safe(function() return f:GetFName():ToString() end, "?"),
            safe(function() return f:GetClass():GetFName():ToString() end, "?"))
        end)
      end)
      if n > 0 then out[#out + 1] = indent .. "(via " .. t[1] .. ", " .. n .. " fields)"; return end
    end
  end
  out[#out + 1] = indent .. "<no fields: tried GetStruct, GetScriptStruct on the property and the value>"
end

local function section(out, label, obj, follow, deep)
  out[#out + 1] = ""
  out[#out + 1] = "=== " .. label
  if not obj then out[#out + 1] = "    not found"; return end
  out[#out + 1] = "  class : " .. classOf(obj)
  out[#out + 1] = "  full  : " .. nameOf(obj)
  local props = properties(obj, out, nil, deep)

  for _, name in ipairs(follow or {}) do
    out[#out + 1] = ""
    out[#out + 1] = "  --> " .. label .. "." .. name
    local prop = props[name]
    local kind = prop and safe(function() return prop:GetClass():GetFName():ToString() end, "?") or "<no such property>"
    local val = safe(function() return obj[name] end, nil)
    out[#out + 1] = "      property kind : " .. kind
    if kind == "StructProperty" then
      structFields(prop, val, out, "      ")
    elseif val and safe(function() return val:IsValid() end, false) then
      out[#out + 1] = "      class : " .. classOf(val)
      properties(val, out, "      ")
    else
      out[#out + 1] = "      <not reachable: the value is empty right now>"
    end
  end
end

local function fmt(v)
  if v == nil then return "nil" end
  local t = type(v)
  if t == "number" or t == "boolean" then return tostring(v) end
  if t == "string" then return string.format("%q", v) end
  if t == "userdata" or t == "table" then
    local s = safe(function() return v:ToString() end, nil)
    if s then return tostring(s) end
    local n = safe(function() return v.Value end, nil)
    if n ~= nil then return "Value=" .. tostring(n) end
    return "<" .. t .. " " .. classOf(v) .. ">"
  end
  return "<" .. t .. ">"
end

local PAL_FIELDS = {
  "CharacterID", "NickName", "Level", "Hp", "MaxHP", "FullStomach", "MaxFullStomach",
  "SanityValue", "HungerType", "PhysicalHealth", "WorkerSick", "IsRarePal", "IsPlayer",
  "Talent_HP", "Talent_Melee", "Talent_Shot", "Talent_Defense",
}

local function readPals(out, limit)
  out[#out + 1] = ""
  out[#out + 1] = "=== values off every loaded PalIndividualCharacterParameter"
  local all = safe(function() return FindAllOf("PalIndividualCharacterParameter") end, nil)
  if not all then out[#out + 1] = "  FindAllOf returned nothing"; return end
  out[#out + 1] = "  found : " .. tostring(#all)
  local shown = 0
  for i, p in ipairs(all) do
    if shown >= (limit or 8) then
      out[#out + 1] = string.format("  ... and %d more not shown", #all - shown)
      break
    end
    local sp = safe(function() return p.SaveParameter end, nil)
    if sp then
      shown = shown + 1
      out[#out + 1] = string.format("  [%d] %s", i, nameOf(p))
      for _, f in ipairs(PAL_FIELDS) do
        out[#out + 1] = string.format("      %-16s %s", f, fmt(safe(function() return sp[f] end, nil)))
      end
    end
  end
  if shown == 0 then out[#out + 1] = "  none of them would give up SaveParameter" end
end

local PAL_BRIEF = { "CharacterID", "NickName", "Level", "Hp", "MaxHP", "FullStomach", "SanityValue", "WorkerSick", "IsRarePal" }

local function paramOfSlot(slot)
  local p = safe(function() return slot.ReplicateIndividualParameter end, nil)
  if p and safe(function() return p:IsValid() end, false) then return p, "ReplicateIndividualParameter" end

  local h = safe(function() return slot.Handle end, nil)
  if h and safe(function() return h:IsValid() end, false) then
    for _, n in ipairs({ "IndividualParameter", "CharacterParameter", "Parameter", "IndividualCharacterParameter" }) do
      local q = safe(function() return h[n] end, nil)
      if q and safe(function() return q:IsValid() end, false) then return q, "Handle." .. n end
    end
    return nil, "Handle is a " .. classOf(h) .. " but none of the expected parameter properties are on it", h
  end
  return nil, "neither ReplicateIndividualParameter nor Handle is set"
end

local function readContainer(out, label, container, limit)
  out[#out + 1] = ""
  out[#out + 1] = "=== " .. label
  if not container or not safe(function() return container:IsValid() end, false) then
    out[#out + 1] = "  not reachable right now"
    return
  end
  local slots = safe(function() return container.SlotArray end, nil)
  if slots == nil then out[#out + 1] = "  no SlotArray on it"; return end
  local count = safe(function() return #slots end, nil) or 0
  out[#out + 1] = "  slots : " .. tostring(count)

  local shown, empty, failed, handleDumped, touched = 0, 0, 0, false, 0
  local function look(idx, raw)
    if shown >= (limit or 6) then return end

    touched = touched + 1
    if touched > 120 then return end

    local slot = safe(function() return raw:get() end, nil) or raw

    if not slot or not safe(function() return slot:IsValid() end, false) then return end
    if safe(function() return slot:IsEmpty() end, false) then empty = empty + 1; return end

    local param, route, handle = paramOfSlot(slot)
    if not param then
      failed = failed + 1
      if failed == 1 then
        out[#out + 1] = string.format("  slot %s : no parameter -- %s", tostring(idx), route)

        if handle and not handleDumped then handleDumped = true; properties(handle, out, "        ") end
      end
      return
    end

    shown = shown + 1
    local sp = safe(function() return param.SaveParameter end, nil)
    if not sp then out[#out + 1] = string.format("  slot %s : parameter via %s, but no SaveParameter", tostring(idx), route); return end
    local bits = {}
    for _, f in ipairs(PAL_BRIEF) do bits[#bits + 1] = f .. "=" .. fmt(safe(function() return sp[f] end, nil)) end
    out[#out + 1] = string.format("  slot %s : %s", tostring(idx), table.concat(bits, "  "))
    if shown == 1 then
      out[#out + 1] = "        (route: " .. route .. ")"

      for _, m in ipairs({ "GetMaxHP", "GetHP", "GetMaxHPFixedPoint", "GetLevel" }) do
        local fn = safe(function() return param[m] end, nil)
        if type(fn) == "function" then
          trace("    calling " .. m .. "() on " .. classOf(param))
          out[#out + 1] = string.format("        : %-22s %s", m .. "()", fmt(safe(function() return fn(param) end, nil)))
        else
          out[#out + 1] = string.format("        : %-22s <no such function>", m .. "()")
        end
      end
    end
  end

  if not pcall(function() slots:ForEach(function(i, e) look(i, e) end) end) then
    out[#out + 1] = "  ForEach failed, indexing instead"
    for i = 1, math.min(count, 60) do
      local e = safe(function() return slots[i] end, nil)
      if e ~= nil then look(i, e) end
    end
  end
  out[#out + 1] = string.format("  (%d read, %d empty skipped, %d unreadable)", shown, empty, failed)
end

local function dump()
  local out = { "Pal Deck dump  " .. os.date("!%Y-%m-%dT%H:%M:%SZ") }

  if tracePath then
    local f = io.open(tracePath, "w")
    if f then f:write("Pal Deck trace  " .. os.date("!%Y-%m-%dT%H:%M:%SZ") .. "\n"); f:close() end
  end
  flush(out)

  local function phase(name, fn)
    trace("PHASE " .. name)
    out[#out + 1] = ""
    fn()
    flush(out)
    trace("  ok " .. name)
  end

  phase("readPals", function() readPals(out, 2) end)

  phase("palbox", function()
    local storage = find("PalPlayerDataPalStorage")
    readContainer(out, "palbox  (PalPlayerDataPalStorage.TargetContainer, 960 slots)",
      storage and safe(function() return storage.TargetContainer end, nil) or nil, 4)
  end)

  phase("base workers", function()
    local camp = find("PalBaseCampModel")
    local director = camp and safe(function() return camp.WorkerDirector end, nil) or nil
    readContainer(out, "base workers  (PalBaseCampModel.WorkerDirector.CharacterContainer)",
      director and safe(function() return director.CharacterContainer end, nil) or nil, 6)
    if director then
      out[#out + 1] = "  base camp  : " .. fmt(safe(function() return camp.BaseCampName end, nil))
      out[#out + 1] = "  order type : " .. fmt(safe(function() return director.CurrentOrderType end, nil))
      out[#out + 1] = "  buildings  : " .. fmt(safe(function() return camp.BuildingNum end, nil))
    end
  end)

  local partyContainers = {}
  phase("every character container, by size", function()
    out[#out + 1] = "=== every PalIndividualCharacterContainer, by size"
    local all = safe(function() return FindAllOf("PalIndividualCharacterContainer") end, nil)
    if not all then out[#out + 1] = "  FindAllOf returned nothing"; return end
    out[#out + 1] = "  count : " .. tostring(#all)
    for i, c in ipairs(all) do
      if i > 16 then out[#out + 1] = "  ... and more"; break end
      if c and safe(function() return c:IsValid() end, false) then
        local slots = safe(function() return c.SlotArray end, nil)
        local n = slots and safe(function() return #slots end, nil) or -1
        out[#out + 1] = string.format("  [%2d] slots=%-5s %s", i, tostring(n), nameOf(c))

        if type(n) == "number" and n > 0 and n <= 12 then partyContainers[#partyContainers + 1] = { c, n } end
      end
    end
  end)

  phase("party candidates", function()
    if #partyContainers == 0 then
      out[#out + 1] = "=== party candidates"
      out[#out + 1] = "  none: no container came back with 12 slots or fewer"
      return
    end
    for i, pair in ipairs(partyContainers) do
      if i > 4 then break end
      readContainer(out, string.format("party candidate %d  (%d slots)", i, pair[2]), pair[1], 6)
    end
  end)

  phase("incubator", function()
    section(out, "PalMapObjectHatchingEggModel",
      find("PalMapObjectHatchingEggModel"), { "HatchedCharacterSaveParameter" })
  end)

  trace("dump complete")
  out[#out + 1] = ""
  out[#out + 1] = "-- end of dump, all phases completed --"
  flush(out)
end

local function dumpDeep()
  if not devMode() then return end
  local out = { "Pal Deck deep probe  " .. os.date("!%Y-%m-%dT%H:%M:%SZ") }
  local saved = dumpPath
  dumpPath = dumpPath and dumpPath:gsub("dump%.txt$", "dump-deep.txt") or nil

  trace("DEEP superclass climb on PalPlayerState")
  section(out, "PalPlayerState", find("PalPlayerState"), {}, true)
  flush(out)
  trace("  ok superclass climb")

  trace("DEEP superclass climb on PalPlayerCharacter")
  section(out, "PalPlayerCharacter", player(), {}, true)
  flush(out)
  trace("  ok PalPlayerCharacter")

  dumpPath = saved
  log("deep probe written")

  local body = table.concat(out, "\n") .. "\n"
  if dumpPath then
    local f = io.open(dumpPath, "w")
    if f then f:write(body); f:close(); log("dump written: " .. dumpPath); return end
  end
  log("dump: no writable path; printing the first lines instead")
  for i = 1, math.min(#out, 40) do print(out[i] .. "\n") end
end

local function str(s)
  local out = tostring(s):gsub('[\\"]', '\\%0'):gsub("%c", function(c) return string.format("\\u%04x", c:byte()) end)
  return '"' .. out .. '"'
end

local function finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end
local function jstr(v) return v and str(v) or "null" end
local function jnum(v) return finite(v) and string.format("%.1f", v) or "null" end
local function jint(v) return finite(v) and string.format("%d", math.floor(v)) or "null" end

local function txt(v)
  if v == nil then return nil end
  if type(v) == "string" then return (v ~= "" and v or nil) end
  local s = safe(function() return v:ToString() end, nil)
  return s and tostring(s) or nil
end

local cached = { party = nil, bases = {}, at = 0 }

local function resolveContainers()
  local ok = cached.party and safe(function() return cached.party:IsValid() end, false)
  for _, b in ipairs(cached.bases) do
    if not safe(function() return b:IsValid() end, false) then ok = false end
  end

  if ok and #cached.bases > 0 and os.time() - cached.at < 30 then return end

  cached = { party = nil, bases = {}, at = os.time() }
  local all = safe(function() return FindAllOf("PalIndividualCharacterContainer") end, nil)
  if not all then return end
  for _, c in ipairs(all) do
    if c and safe(function() return c:IsValid() end, false) then
      local full = nameOf(c)
      if full:find("PalPlayerController", 1, true) then
        cached.party = c
      elseif full:find("PalGameStateInGame", 1, true) then
        cached.bases[#cached.bases + 1] = c
      end

    end
  end
end

local function palInfo(param)
  if not param or not safe(function() return param:IsValid() end, false) then return nil end
  local sp = safe(function() return param.SaveParameter end, nil)
  if not sp then return nil end
  local function raw(f) return safe(function() return sp[f] end, nil) end

  local hpStruct = raw("Hp")
  local hpRaw = hpStruct and safe(function() return hpStruct.Value end, nil)

  return {
    id        = txt(raw("CharacterID")),
    nick      = txt(raw("NickName")),
    level     = tonumber(raw("Level")),
    hp        = hpRaw and (hpRaw / 1000) or nil,
    hunger    = tonumber(raw("FullStomach")),
    hungerMax = tonumber(raw("MaxFullStomach")),
    sanity    = tonumber(raw("SanityValue")),
    sick      = tonumber(raw("WorkerSick")),
    rare      = raw("IsRarePal") == true,
    isPlayer  = raw("IsPlayer") == true,

    name      = englishName and englishName(txt(raw("CharacterID"))) or nil,

    talentHp      = tonumber(raw("Talent_HP")),
    talentMelee   = tonumber(raw("Talent_Melee")),
    talentShot    = tonumber(raw("Talent_Shot")),
    talentDefense = tonumber(raw("Talent_Defense")),

    gender        = tonumber(raw("Gender")),
    rank          = tonumber(raw("Rank")),
    soulHp        = tonumber(raw("Rank_HP")),
    soulAtk       = tonumber(raw("Rank_Attack")),
    soulDef       = tonumber(raw("Rank_Defence")),
    soulCraft     = tonumber(raw("Rank_CraftSpeed")),
    trust         = tonumber(raw("FriendshipPoint")),
    exp           = tonumber(raw("Exp")),
    unusedPoints  = tonumber(raw("UnusedStatusPoint")),
    passives      = passiveListOf and passiveListOf(sp) or {},
    statusPoints  = (raw("IsPlayer") == true and statusPointsOf) and statusPointsOf(sp) or nil,
  }
end

local function passivesJson(list)
  local out = {}
  for _, id in ipairs(list or {}) do
    out[#out + 1] = '{"id":' .. jstr(id) .. ',"name":' .. jstr(passiveName and passiveName(id) or nil) .. "}"
  end
  return table.concat(out, ",")
end

local function statusJson(list)
  if not list then return "null" end
  local out = {}
  for _, e in ipairs(list) do out[#out + 1] = '{"name":' .. jstr(e.name) .. ',"points":' .. jint(e.points) .. "}" end
  return "[" .. table.concat(out, ",") .. "]"
end

local function palJson(i)
  if not i then return "null" end
  return table.concat({
    '{"id":' .. jstr(i.id),
    '"nick":' .. jstr(i.nick),
    '"level":' .. jint(i.level),
    '"hp":' .. jnum(i.hp),
    '"hunger":' .. jnum(i.hunger),
    '"hungerMax":' .. jnum(i.hungerMax),
    '"sanity":' .. jnum(i.sanity),
    '"sick":' .. jint(i.sick),
    '"rare":' .. tostring(i.rare),
    '"name":' .. jstr(i.name),

    '"talents":{"hp":' .. jint(i.talentHp) .. ',"melee":' .. jint(i.talentMelee) ..
      ',"shot":' .. jint(i.talentShot) .. ',"defense":' .. jint(i.talentDefense) .. "}",
    '"gender":' .. jint(i.gender),
    '"rank":' .. jint(i.rank),
    '"souls":{"hp":' .. jint(i.soulHp) .. ',"atk":' .. jint(i.soulAtk) .. ',"def":' .. jint(i.soulDef) .. ',"craft":' .. jint(i.soulCraft) .. "}",
    '"trust":' .. jint(i.trust),
    '"exp":' .. jint(i.exp),
    '"unusedPoints":' .. jint(i.unusedPoints),
    '"passives":[' .. passivesJson(i.passives) .. "]",
    '"statusPoints":' .. statusJson(i.statusPoints) .. "}",
  }, ",")
end

local function containerPals(c, limit)
  local items = {}
  if not c or not safe(function() return c:IsValid() end, false) then return items end
  local slots = safe(function() return c.SlotArray end, nil)
  if not slots then return items end

  local byIndex = {}
  pcall(function()
    slots:ForEach(function(i, e)
      if type(i) == "number" and i <= (limit or 32) then byIndex[i] = e end
    end)
  end)

  local n = math.min(safe(function() return #slots end, 0) or 0, limit or 32)
  for i = 1, n do
    local info = nil
    local raw = byIndex[i]
    local slot = raw and (safe(function() return raw:get() end, nil) or raw)
    if slot and safe(function() return slot:IsValid() end, false)
       and not safe(function() return slot:IsEmpty() end, false) then
      info = palInfo(safe(function() return slot.ReplicateIndividualParameter end, nil))
    end
    items[i] = info
  end
  return items
end

local function playerInfo()
  local all = safe(function() return FindAllOf("PalIndividualCharacterParameter") end, nil)
  if not all then return nil end
  for _, p in ipairs(all) do

    local isPlayer = p and safe(function() return p:IsValid() and p.SaveParameter.IsPlayer == true end, false)
    if isPlayer then return palInfo(p) end
  end
  return nil
end

local function writeState()
  local p = player()
  local parts = {

    '"protocol":1',
    '"mod":' .. str(MOD),
    '"version":' .. str(VERSION),
    '"written":' .. str(os.date("!%Y-%m-%dT%H:%M:%SZ")),
    '"at":' .. os.time(),
    '"seq":' .. writeSeq,
    '"inGame":' .. (p and "true" or "false"),
  }
  writeSeq = writeSeq + 1

  if p then
    resolveContainers()

    parts[#parts + 1] = '"player":' .. palJson(playerInfo())

    local party = containerPals(cached.party, 5)
    local partyJson = {}
    for i = 1, 5 do partyJson[i] = palJson(party[i]) end
    parts[#parts + 1] = '"party":[' .. table.concat(partyJson, ",") .. "]"

    local baseJson = {}
    for bi, c in ipairs(cached.bases) do
      if bi > 6 then break end
      local workers = containerPals(c, 18)
      local n, hungry, lowSanity, sick, rare = 0, 0, 0, 0, 0
      for _, w in ipairs(workers) do
        if w then
          n = n + 1
          if w.hunger and w.hungerMax and w.hungerMax > 0 and (w.hunger / w.hungerMax) < 0.35 then hungry = hungry + 1 end
          if w.sanity and w.sanity < 50 then lowSanity = lowSanity + 1 end
          if w.sick and w.sick ~= 0 then sick = sick + 1 end
          if w.rare then rare = rare + 1 end
        end
      end

      local list = {}
      for _, w in ipairs(workers) do if w then list[#list + 1] = palJson(w) end end
      baseJson[#baseJson + 1] = string.format(
        '{"workers":%d,"hungry":%d,"lowSanity":%d,"sick":%d,"rare":%d,"list":[%s]}', n, hungry, lowSanity, sick, rare, table.concat(list, ","))
    end
    parts[#parts + 1] = '"bases":[' .. table.concat(baseJson, ",") .. "]"

    local okT, tj = pcall(function() return lookingAtJson and lookingAtJson() or "null" end)
    parts[#parts + 1] = '"target":' .. (okT and tj or "null")

    if not okT then parts[#parts + 1] = '"targetError":' .. str(tostring(tj)) end

    local okW, wj = pcall(function() return worldJson and worldJson() or "null" end)
    parts[#parts + 1] = '"world":' .. (okW and wj or "null")
    local okP, pj = pcall(function() return weaponJson and weaponJson() or "null" end)
    parts[#parts + 1] = '"weapon":' .. (okP and pj or "null")
  end

  parts[#parts + 1] = '"end":true'
  local body = "{" .. table.concat(parts, ",") .. "}"

  if home.ready then
    if writeWhole(HOME_STATE, body) then
      home.fails = 0
    else
      home.fails = home.fails + 1
      if home.fails >= 10 then home.ready, home.fails, home.tries = false, 0, 0 end
    end
  end

  if statePath then
    local f = io.open(statePath, "w")
    if f then f:write(body); f:close() end
    return
  end

  for _, candidate in ipairs(STATE_CANDIDATES) do
    local f = io.open(candidate, "w")
    if f then
      f:write(body); f:close()
      statePath = candidate
      dumpPath = candidate:gsub("state%.json$", "dump.txt")
      tracePath = candidate:gsub("state%.json$", "trace.txt")
      log("state file: " .. candidate)
      return
    end
  end
  log("state file: none of the candidate paths could be opened; state is not being written")
end

local function todo(name)
  return function()
    log(name .. ": key received, but this action is not implemented yet")
  end
end

local function oneLine(i)
  if not i then return "empty" end
  local name = i.nick or i.id or "?"
  local hunger = (i.hunger and i.hungerMax and i.hungerMax > 0)
    and string.format("%d%% fed", math.floor(i.hunger / i.hungerMax * 100)) or "fed ?"
  return string.format("%s%s  lvl %s  %s HP  %s  sanity %s",
    name, i.rare and " (rare)" or "",
    tostring(i.level or "?"), tostring(math.floor(i.hp or 0)), hunger,
    i.sanity and tostring(math.floor(i.sanity)) or "?")
end

local function partySlot(n)
  return function()
    resolveContainers()
    if not cached.party then log("Party " .. n .. ": no party container found (in a world?)"); return end
    local party = containerPals(cached.party, 5)
    log("Party " .. n .. ": " .. oneLine(party[n]))
  end
end

local function baseStatus()
  resolveContainers()
  if #cached.bases == 0 then log("Base status: no base containers found"); return end
  for bi, c in ipairs(cached.bases) do
    local workers = containerPals(c, 18)
    local n, hungry, sick = 0, 0, 0
    for _, w in ipairs(workers) do
      if w then
        n = n + 1
        if w.hunger and w.hungerMax and w.hungerMax > 0 and (w.hunger / w.hungerMax) < 0.35 then hungry = hungry + 1 end
        if w.sick and w.sick ~= 0 then sick = sick + 1 end
      end
    end
    log(string.format("Base %d: %d workers, %d hungry, %d sick", bi, n, hungry, sick))
  end
end

local ACTIONS = {

  { key = "F13", name = "Ping",          run = function()
      local p = player()
      log("Ping: mod is alive, player " .. (p and "found" or "not found (menu or loading?)"))
      writeState()
      if devMode() then dump() end
    end },
  { key = "F14", name = "Party 1",       run = partySlot(1) },
  { key = "F15", name = "Party 2",       run = partySlot(2) },
  { key = "F16", name = "Party 3",       run = partySlot(3) },
  { key = "F17", name = "Party 4",       run = partySlot(4) },
  { key = "F18", name = "Party 5",       run = partySlot(5) },
  { key = "F19", name = "Recall all",    run = todo("Recall all") },
  { key = "F20", name = "Base status",   run = baseStatus },
  { key = "F21", name = "Incubators",    run = todo("Incubators") },
  { key = "F22", name = "Feed box",      run = todo("Feed box") },
  { key = "F23", name = "Carry weight",  run = todo("Carry weight") },

  { key = "F24", name = "Tech points",   run = todo("Tech points") },
}

for _, a in ipairs(ACTIONS) do
  local code = Key[a.key]
  if code == nil then
    log("cannot bind " .. a.key .. ": this build of UE4SS has no Key." .. a.key)
  else
    RegisterKeyBind(code, function()

      ExecuteInGameThread(function()
        local ok, err = pcall(a.run)
        if not ok then log(a.name .. " failed: " .. tostring(err)) end
      end)
    end)
  end
end

local function keyName(k)
  return safe(function() return k.KeyName:ToString() end, nil) or "?"
end

local function dumpInput()
  if not dumpPath then return end
  local base = dumpPath:gsub("dump%.txt$", "")
  local outPath, marker = base .. "input.txt", base .. "input.started"
  local done = io.open(outPath, "r")
  if done then done:close(); return end
  local stuck = io.open(marker, "r")
  if stuck then stuck:close(); log("input bindings: skipped, a previous read did not finish (delete input.started to retry)"); return end
  local mk = io.open(marker, "w"); if mk then mk:write(os.date("!%Y-%m-%dT%H:%M:%SZ")); mk:close() end

  local out = { "Pal Deck input bindings  " .. os.date("!%Y-%m-%dT%H:%M:%SZ"), "" }
  local function save() local f = io.open(outPath .. ".partial", "w"); if f then f:write(table.concat(out, "\n"), "\n"); f:close() end end

  trace("INPUT enhanced input contexts")
  local contexts = safe(function() return FindAllOf("InputMappingContext") end, nil) or {}
  out[#out + 1] = "=== Enhanced Input: " .. #contexts .. " mapping contexts"
  for _, ctx in ipairs(contexts) do
    if ctx and safe(function() return ctx:IsValid() end, false) then
      local cname = safe(function() return ctx:GetFName():ToString() end, "?")
      out[#out + 1] = ""
      out[#out + 1] = "--- " .. cname
      trace("  mappings of " .. cname)
      local maps = safe(function() return ctx.Mappings end, nil)
      if maps then
        pcall(function()
          maps:ForEach(function(_, e)
            local m = safe(function() return e:get() end, nil) or e
            local action = safe(function()
              local a = m.Action
              if a and a:IsValid() then return a:GetFName():ToString() end
              return nil
            end, nil) or "?"
            out[#out + 1] = string.format("  %-44s %s", action, keyName(safe(function() return m.Key end, nil)))
          end)
        end)
      end
      save()
    end
  end

  trace("INPUT legacy InputSettings")
  local settings = safe(function() return StaticFindObject("/Script/Engine.Default__InputSettings") end, nil)
  if settings and safe(function() return settings:IsValid() end, false) then
    for _, list in ipairs({ { "ActionMappings", "ActionName" }, { "AxisMappings", "AxisName" } }) do
      out[#out + 1] = ""
      out[#out + 1] = "=== legacy " .. list[1]
      local arr = safe(function() return settings[list[1]] end, nil)
      if arr then
        pcall(function()
          arr:ForEach(function(_, e)
            local m = safe(function() return e:get() end, nil) or e
            local name = safe(function() return m[list[2]]:ToString() end, nil) or "?"
            out[#out + 1] = string.format("  %-44s %s", name, keyName(safe(function() return m.Key end, nil)))
          end)
        end)
      end
    end
  else
    out[#out + 1] = ""
    out[#out + 1] = "=== legacy InputSettings: not found"
  end

  local f = io.open(outPath, "w")
  if f then f:write(table.concat(out, "\n"), "\n"); f:close() end
  os.remove(outPath .. ".partial")
  os.remove(marker)
  trace("INPUT done")
  log("input bindings written: " .. outPath)
end

palNames = nil

local NAME_TABLES = {
  "/Game/Pal/DataTable/Text/DT_PalNameText.DT_PalNameText",
  "/Game/Pal/DataTable/Text/DT_PalNameText_Common.DT_PalNameText_Common",
}

local function readNameTable(path, sample)
  local names, rows, withText = {}, 0, 0
  trace("NAMES load " .. path)
  local dt = safe(function() return StaticFindObject(path) end, nil)
  if not dt or not safe(function() return dt:IsValid() end, false)
     or type(safe(function() return dt.ForEachRow end, nil)) ~= "function" then
    sample[#sample + 1] = "  " .. path .. ": not found"
    return names, 0, 0
  end
  local shown = 0
  pcall(function()
    dt:ForEachRow(function(rowName, row)
      rows = rows + 1

      local rn = (type(rowName) == "string" and rowName) or safe(function() return rowName:ToString() end, nil)
      local t = safe(function() return row.TextData:ToString() end, nil) or safe(function() return row.Text:ToString() end, nil)
      rn, t = rn and tostring(rn) or nil, t and tostring(t) or nil
      if rn and t and t ~= "" and t ~= "-" then
        names[rn:lower()] = t
        withText = withText + 1
      end
      if shown < 8 then shown = shown + 1; sample[#sample + 1] = string.format("  %-40s %s", tostring(rn), t and string.format("%q", t) or "(no text)") end
    end)
  end)
  sample[#sample + 1] = string.format("  %s: %d rows, %d with text", path:match("[^/]+$"), rows, withText)
  trace(string.format("NAMES %s rows %d text %d", path:match("[^.]+$"), rows, withText))
  return names, rows, withText
end

skillNames = nil
local SKILL_TABLES = {
  "/Game/Pal/DataTable/Text/DT_SkillNameText.DT_SkillNameText",
  "/Game/Pal/DataTable/Text/DT_SkillNameText_Common.DT_SkillNameText_Common",
}

itemNames = nil
local ITEM_TABLES = {
  "/Game/Pal/DataTable/Text/DT_ItemNameText.DT_ItemNameText",
  "/Game/Pal/DataTable/Text/DT_ItemNameText_Common.DT_ItemNameText_Common",
}

local function loadPalNames()
  local sample, best, bestN = {}, {}, 0
  for _, path in ipairs(NAME_TABLES) do
    local names, _, n = readNameTable(path, sample)
    if n > bestN then best, bestN = names, n end
  end
  palNames = best
  log("pal names: " .. bestN .. " loaded")

  local skills, sN = {}, 0
  for _, path in ipairs(SKILL_TABLES) do
    local names, _, n = readNameTable(path, sample)
    if n > sN then skills, sN = names, n end
  end
  local index = {}
  for k, v in pairs(skills) do
    index[k] = v
    local s1 = (k:gsub("^[^_]+_", "", 1))
    if index[s1] == nil then index[s1] = v end
    local s2 = (s1:gsub("^[^_]+_", "", 1))
    if index[s2] == nil then index[s2] = v end
  end
  skillNames = index
  log("skill names: " .. sN .. " loaded")

  local items, iN = {}, 0
  for _, path in ipairs(ITEM_TABLES) do
    local names, _, n = readNameTable(path, sample)
    if n > iN then items, iN = names, n end
  end
  itemNames = items
  log("item names: " .. iN .. " loaded")
  return sample, bestN
end

function itemName(id)
  if not itemNames or not id or id == "None" then return nil end
  return itemNames[("ITEM_NAME_" .. id):lower()]
end

function passiveName(id)
  return skillNames and id and skillNames[tostring(id):lower()] or nil
end

function englishName(id)
  if not palNames or not id or id == "None" then return nil end
  local bare = id:gsub("^[Bb][Oo][Ss][Ss]_", "")
  return palNames[("PAL_NAME_" .. id):lower()] or palNames[("PAL_NAME_" .. bare):lower()]
end

local function writeNamesCheck(sample, n)
  if not dumpPath then return end
  local path = dumpPath:gsub("dump%.txt$", "names-check.txt")
  local done = io.open(path, "r")
  if done then done:close(); return end
  local out = { "Pal Deck names check  " .. os.date("!%Y-%m-%dT%H:%M:%SZ"), "", "rows with text: " .. tostring(n), "", "first rows:" }
  for _, l in ipairs(sample or {}) do out[#out + 1] = l end
  out[#out + 1] = ""
  out[#out + 1] = "your party, id -> name:"
  resolveContainers()
  for i, pal in pairs(containerPals(cached.party, 5)) do
    if pal then out[#out + 1] = string.format("  %d  %-40s %s", i, tostring(pal.id), tostring(englishName(pal.id) or "(no match)")) end
  end
  local f = io.open(path, "w")
  if f then f:write(table.concat(out, "\n"), "\n"); f:close() end
end

local RANGE = 8000
local PAL_RADIUS = 200
local SLACK_DEG = 4

local function valid(o) return o ~= nil and safe(function() return o:IsValid() end, false) end
local function vec3(v)
  if not v then return nil end
  local x, y, z = tonumber(safe(function() return v.X end, nil)), tonumber(safe(function() return v.Y end, nil)), tonumber(safe(function() return v.Z end, nil))
  if x and y and z then return x, y, z end
  return nil
end

local myShooter = nil
local function camera()
  local p = player()
  if not p then return nil end
  if not valid(myShooter) then
    myShooter = nil
    local me = safe(function() return p:GetFName():ToString() end, nil)
    for _, c in ipairs(safe(function() return FindAllOf("PalShooterComponent") end, nil) or {}) do
      if me and valid(c) and nameOf(c):find(me, 1, true) then myShooter = c; break end
    end
  end
  if not myShooter then return nil end
  local cx, cy, cz = vec3(safe(function() return myShooter.CameraLocation end, nil))
  local r = safe(function() return myShooter.CameraRotation end, nil)
  local pitch = r and tonumber(safe(function() return r.Pitch end, nil))
  local yaw = r and tonumber(safe(function() return r.Yaw end, nil))
  if not (cx and pitch and yaw) then return nil end
  local p1, y1 = math.rad(pitch), math.rad(yaw)
  return { cx, cy, cz }, { math.cos(p1) * math.cos(y1), math.cos(p1) * math.sin(y1), math.sin(p1) }
end

local TIME_CLASS = "/Script/Pal.PalTimeManager:"
local timeFns, timeMgr, timeAt = nil, nil, 0

local function timeFn(name)
  local f = safe(function() return StaticFindObject(TIME_CLASS .. name) end, nil)
  return valid(f)
end

function worldJson()
  if timeFns == nil then
    timeFns = {
      hour = timeFn("GetCurrentPalWorldTime_Hour"),
      minute = timeFn("GetCurrentPalWorldTime_Minute"),
      day = timeFn("GetCurrentPalWorldTime_TotalDay"),
      night = timeFn("IsNight"),
    }
  end
  if not (timeFns.hour and timeFns.minute) then return "null" end
  if not valid(timeMgr) or os.time() - timeAt > 30 then
    timeMgr, timeAt = nil, os.time()
    for _, t in ipairs(safe(function() return FindAllOf("PalTimeManager") end, nil) or {}) do
      if valid(t) and not nameOf(t):find("Default__", 1, true) then timeMgr = t; break end
    end
  end
  if not timeMgr then return "null" end
  local h = tonumber(safe(function() return timeMgr:GetCurrentPalWorldTime_Hour() end, nil))
  local m = tonumber(safe(function() return timeMgr:GetCurrentPalWorldTime_Minute() end, nil))
  if not h then return "null" end
  local d = timeFns.day and tonumber(safe(function() return timeMgr:GetCurrentPalWorldTime_TotalDay() end, nil)) or nil
  local n = nil
  if timeFns.night then
    local v = safe(function() return timeMgr:IsNight() end, nil)
    if type(v) == "boolean" then n = v end
  end
  return '{"hour":' .. jint(h) .. ',"minute":' .. jint(m) .. ',"day":' .. jint(d) .. ',"night":' .. (n == nil and "null" or tostring(n)) .. "}"
end

function weaponJson()
  if not player() then return "null" end
  if not valid(myShooter) then camera() end
  if not valid(myShooter) then return "null" end
  local w = safe(function() return myShooter.HasWeapon end, nil)
  if not valid(w) then return "null" end
  local id = txt(safe(function() return w.OwnerStaticItemId end, nil))
  if id == "None" then id = nil end
  local ammo = tonumber(safe(function() return w.CurrentBulletNum end, nil))
  local mag = tonumber(safe(function() return w.MagazineSize end, nil))
  return '{"cls":' .. jstr(classOf(w)) .. ',"id":' .. jstr(id) .. ',"name":' .. jstr(itemName and itemName(id) or nil) ..
    ',"ammo":' .. jint(ammo) .. ',"magazine":' .. jint(mag) .. "}"
end

function passiveListOf(sp)
  local list = {}
  local arr = sp and safe(function() return sp.PassiveSkillList end, nil)
  if arr then
    pcall(function()
      arr:ForEach(function(_, e)
        local v = safe(function() return e:get() end, nil) or e
        local id = safe(function() return v:ToString() end, nil)
        if id then list[#list + 1] = tostring(id) end
      end)
    end)
  end
  return list
end

function statusPointsOf(sp)
  local list = {}
  local arr = sp and safe(function() return sp.GotStatusPointList end, nil)
  if arr then
    pcall(function()
      arr:ForEach(function(_, e)
        local v = safe(function() return e:get() end, nil) or e
        local name = safe(function() return v.StatusName:ToString() end, nil) or safe(function() return v.Name:ToString() end, nil)
        local pts = tonumber(safe(function() return v.StatusPoint end, nil) or safe(function() return v.Point end, nil))
        list[#list + 1] = { name = name and tostring(name) or nil, points = pts }
      end)
    end)
  end
  return list
end

function lookingAtJson()
  local cam, fwd = camera()
  if not cam then return "null" end
  local best, bestScore, bestDist = nil, nil, nil
  for _, a in ipairs(safe(function() return FindAllOf("PalMonsterCharacter") end, nil) or {}) do
    if valid(a) then
      local rc = safe(function() return a.RootComponent end, nil)

      local x, y, z
      if valid(rc) then x, y, z = vec3(safe(function() return rc.RelativeLocation end, nil)) end
      if x and y and z then
        local dx, dy, dz = x - cam[1], y - cam[2], z - cam[3]
        local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
        if dist > 100 and dist < RANGE then
          local dot = (dx * fwd[1] + dy * fwd[2] + dz * fwd[3]) / dist
          if dot > 0.8 then
            local off = math.deg(math.acos(math.min(1, dot)))
            local size = math.deg(math.atan(PAL_RADIUS / dist))
            local score = off - size
            if score < SLACK_DEG and (not bestScore or score < bestScore) then best, bestScore, bestDist = a, score, dist end
          end
        end
      end
    end
  end
  if not best then return "null" end

  local comp = safe(function() return best.CharacterParameterComponent end, nil)
  local ip = valid(comp) and safe(function() return comp.IndividualParameter end, nil) or nil
  if not valid(ip) then return "null" end
  local info = palInfo(ip)
  if not info then return "null" end
  local sp = safe(function() return ip.SaveParameter end, nil)
  local owner = sp and safe(function() return sp.OwnerPlayerUId end, nil)
  local wild = true
  if owner then
    for _, k in ipairs({ "A", "B", "C", "D" }) do
      local v = tonumber(safe(function() return owner[k] end, 0)) or 0
      if v ~= 0 then wild = false end
    end
  end

  return palJson(info):sub(1, -2) ..
    ',"wild":' .. tostring(wild) ..
    ',"distance":' .. jnum(bestDist / 100) .. "}"
end

local function probeTarget()
  if not dumpPath then return end
  local base = dumpPath:gsub("dump%.txt$", "")
  local outPath, marker = base .. "target.txt", base .. "target.started"
  local done = io.open(outPath, "r")
  if done then done:close(); return end
  local stuck = io.open(marker, "r")
  if stuck then stuck:close(); log("target probe: skipped, a previous run did not finish (delete target.started to retry)"); return end
  local mk = io.open(marker, "w"); if mk then mk:write(os.date("!%Y-%m-%dT%H:%M:%SZ")); mk:close() end

  local out = { "Pal Deck target probe, round two  " .. os.date("!%Y-%m-%dT%H:%M:%SZ"), "" }
  local function save() local f = io.open(outPath .. ".partial", "w"); if f then f:write(table.concat(out, "\n"), "\n"); f:close() end end
  local function valid(o) return o ~= nil and safe(function() return o:IsValid() end, false) end
  local function num(v) return tonumber(v) or 0 end
  local function vec(v) if not v then return "nil" end
    return string.format("(%.0f, %.0f, %.0f)", num(safe(function() return v.X end, 0)), num(safe(function() return v.Y end, 0)), num(safe(function() return v.Z end, 0))) end
  local function rot(r) if not r then return "nil" end
    return string.format("pitch %.1f yaw %.1f roll %.1f", num(safe(function() return r.Pitch end, 0)), num(safe(function() return r.Yaw end, 0)), num(safe(function() return r.Roll end, 0))) end
  local function locOf(a)
    local rc = safe(function() return a.RootComponent end, nil)
    return valid(rc) and safe(function() return rc.RelativeLocation end, nil) or nil
  end
  local function short(o) return valid(o) and safe(function() return o:GetFName():ToString() end, "?") or "nil" end

  trace("TARGET2 you")
  local p = player()
  local me = short(p)
  out[#out + 1] = "=== you  " .. me .. "  at " .. vec(p and locOf(p))
  local pc = find("PalPlayerController")
  local f = pc and safe(function() return pc.GetControlRotation end, nil)
  out[#out + 1] = "  GetControlRotation is a " .. type(f)
  save()

  trace("TARGET2 shooter components")
  out[#out + 1] = ""
  out[#out + 1] = "=== PalShooterComponent instances"
  for i, c in ipairs(safe(function() return FindAllOf("PalShooterComponent") end, nil) or {}) do
    if i > 8 then break end
    if valid(c) then
      local full = nameOf(c)
      out[#out + 1] = string.format("  %s%s", full:find(me, 1, true) and "[YOURS] " or "", full:match("[^%.]+%.[^%.]+$") or full)
      out[#out + 1] = "      camera at " .. vec(safe(function() return c.CameraLocation end, nil)) .. "  " .. rot(safe(function() return c.CameraRotation end, nil))
      out[#out + 1] = "      targetDirection " .. vec(safe(function() return c.targetDirection end, nil))
    end
  end
  save()

  trace("TARGET2 look-at components")
  out[#out + 1] = ""
  out[#out + 1] = "=== PalLookAtComponent instances"
  for i, c in ipairs(safe(function() return FindAllOf("PalLookAtComponent") end, nil) or {}) do
    if i > 25 then break end
    if valid(c) then
      local full = nameOf(c)
      local target = safe(function() return c.LookAtTargetActor end, nil)
      out[#out + 1] = string.format("  %s%-50s enabled %s  target %s  at %s",
        full:find(me, 1, true) and "[YOURS] " or "", full:match("[^%.]+%.[^%.]+$") or full,
        tostring(safe(function() return c.bIsEnableLookAt end, "?")), valid(target) and classOf(target) or "none",
        vec(safe(function() return c.LookAtTargetLocation end, nil)))
    end
  end
  save()

  trace("TARGET2 monsters")
  out[#out + 1] = ""
  out[#out + 1] = "=== Pals in the world"
  for i, a in ipairs(safe(function() return FindAllOf("PalMonsterCharacter") end, nil) or {}) do
    if i > 6 then break end
    if valid(a) then
      out[#out + 1] = string.format("--- %s  at %s", classOf(a), vec(locOf(a)))
      trace("TARGET2 monster " .. i .. " parameter route")
      local comp = safe(function() return a.CharacterParameterComponent end, nil)
      out[#out + 1] = "  .CharacterParameterComponent -> " .. (valid(comp) and classOf(comp) or "nil")
      local ip = valid(comp) and safe(function() return comp.IndividualParameter end, nil) or nil
      out[#out + 1] = "  .IndividualParameter -> " .. (valid(ip) and classOf(ip) or "nil")
      if valid(ip) then
        local info = palInfo(ip)
        local sp = safe(function() return ip.SaveParameter end, nil)
        out[#out + 1] = string.format("    %s  lv %s  talents hp %s shot %s def %s melee %s  rare %s",
          tostring(info and info.id), tostring(info and info.level), tostring(info and info.talentHp), tostring(info and info.talentShot),
          tostring(info and info.talentDefense), tostring(info and info.talentMelee), tostring(info and info.rare))
        local owner = sp and safe(function() return sp.OwnerPlayerUId end, nil)
        out[#out + 1] = "    owner " .. (owner and string.format("%s %s %s %s", tostring(safe(function() return owner.A end, "?")),
          tostring(safe(function() return owner.B end, "?")), tostring(safe(function() return owner.C end, "?")), tostring(safe(function() return owner.D end, "?"))) or "nil")
        out[#out + 1] = "    gender " .. fmt(sp and safe(function() return sp.Gender end, nil))
        local passives = sp and safe(function() return sp.PassiveSkillList end, nil)
        local list = {}
        if passives then pcall(function() passives:ForEach(function(_, e)
          local v = safe(function() return e:get() end, nil) or e
          list[#list + 1] = tostring(safe(function() return v:ToString() end, "?"))
        end) end) end
        out[#out + 1] = "    passives " .. (passives and ("[" .. table.concat(list, ", ") .. "]") or "no PassiveSkillList")
      end
      save()
    end
  end

  local fo = io.open(outPath, "w")
  if fo then fo:write(table.concat(out, "\n"), "\n"); fo:close() end
  os.remove(outPath .. ".partial")
  os.remove(marker)
  trace("TARGET2 done")
  log("target probe written: " .. outPath)
end

local inWorldSince, inputTried, namesTried, targetTried = nil, false, false, false

local function tick()
  if not home.ready then pcall(homeStep) end
  pcall(writeState)

  if not (inputTried and namesTried and targetTried) then
    if player() then
      inWorldSince = inWorldSince or os.time()
      local t = os.time() - inWorldSince
      if not inputTried and t >= 20 then
        inputTried = true
        if devMode() then ExecuteInGameThread(function() pcall(dumpInput) end) end
      end

      if not namesTried and t >= 10 then
        namesTried = true
        ExecuteInGameThread(function()
          local ok, sample, n = pcall(loadPalNames)
          if ok and devMode() then pcall(writeNamesCheck, sample, n) end
        end)
      end

      if not targetTried and t >= 40 then
        targetTried = true
        if devMode() then ExecuteInGameThread(function() pcall(probeTarget) end) end
      end
    else
      inWorldSince = nil
    end
  end
end

LoopAsync(STATE_EVERY_MS, function()
  ExecuteInGameThread(function() pcall(tick) end)
  return false
end)

log("loaded " .. VERSION .. ", " .. #ACTIONS .. " keys bound (F13 to F24), state every " .. STATE_EVERY_MS .. "ms")
