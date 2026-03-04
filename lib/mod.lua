-- sidewalk v1.0 @sonoCircuit
-- based on passersby v1.2.0 @markeats (thank you!)

local fs = require 'fileselect'
local tx = require 'textentry'
local mu = require 'musicutil'
local md = require 'core/mods'
local vx = require 'voice'

local preset_path = "/home/we/dust/data/nb_sidewalk/sidewalk_patches"
local default_patch = "/home/we/dust/data/nb_sidewalk/sidewalk_patches/default.swp"
local failsafe_patch = "/home/we/dust/code/nb_sidewalk/data/sidewalk_patches/default.swp"

local current_patch = ""
local is_active = false

local NUM_VOICES = 6

local paramlist = {
  "amp", "pan", "pan_drift", "send_a", "send_b", "glide", "pitchbend",
  "fm1_ratio", "fm1_amt", "fm2_ratio", "fm2_amt", "waveshape", "wavefold", "cutoff", "env_type", "attack", "decay",
  "lfo_shape", "lfo_rate", "lfo_drift", "cutoff_lfo", "pan_lfo", "shape_lfo", "fold_lfo", "fm1_lfo", "fm2_lfo",
  "lfo_rate_mod", "lfo_drift_mod", "cutoff_mod", "shape_mod", "fold_mod", "fm1_mod", "fm2_mod", "send_a_mod", "send_b_mod"
}

local modparams = {
  "lfo_shape", "lfo_rate", "lfo_drift", "cutoff_lfo", "pan_lfo", "shape_lfo", "fold_lfo", "fm1_lfo", "fm2_lfo",
  "lfo_rate_mod", "lfo_drift_mod", "cutoff_mod", "shape_mod", "fold_mod", "fm1_mod", "fm2_mod", "send_a_mod", "send_b_mod"
}


---------------- osc msgs ----------------

local function init_nb_sidewalk()
  osc.send({ "localhost", 57120 }, "/nb_sidewalk/init")
end

local function free_nb_sidewalk()
  osc.send({ "localhost", 57120 }, "/nb_sidewalk/free")
end

local function init_moddef()
  osc.send({ "localhost", 57120 }, "/nb_sidewalk/init_mod")
end

local function free_moddef()
  osc.send({ "localhost", 57120 }, "/nb_sidewalk/free_mod")
end

local function dont_panic()
  osc.send({ "localhost", 57120 }, "/nb_sidewalk/panic")
end

local function note_on(voice, freq, vel)
  osc.send({ "localhost", 57120 }, "/nb_sidewalk/note_on", {voice, freq, vel})
end

local function note_off(voice)
  osc.send({ "localhost", 57120 }, "/nb_sidewalk/note_off", {voice})
end

local function set_param(key, val)
  osc.send({ "localhost", 57120 }, "/nb_sidewalk/set_param", {key, val})
end

local function set_mod(key, val)
  osc.send({ "localhost", 57120 }, "/nb_sidewalk/set_mod", {key, val})
end



---------------- functions ----------------

local function save_synth_patch(txt)
  if txt then
    local patch = {}
    for _, v in ipairs(paramlist) do
      patch[v] = params:get("nb_sidewalk_"..v)
    end
    tab.save(patch, preset_path.."/"..txt..".swp")
    current_patch = txt
    print("saved sidewalk patch: "..txt)
  end
end

local function load_synth_patch(path)
  if path ~= "cancel" and path ~= "" then
    dont_panic()
    if path:match("^.+(%..+)$") == ".swp" then
      local patch = tab.load(path)
      if patch ~= nil then
        for k, v in pairs(patch) do
          params:set("nb_sidewalk_"..k, v)
        end
        local name = path:match("[^/]*$")
        current_patch = name:gsub(".swp", "")
        print("loaded sidewalk: "..current_patch)
      else
        if util.file_exists(failsafe_patch) then
          load_synth_patch(failsafe_patch)
        end
        print("error: could not find patch", path)
      end
    else
      print("error: not a sidewalk patch file")
    end
  end
end

local function round_form(param, quant, form)
  return(util.round(param, quant)..form)
end

local function pan_display(param)
  if param < -0.01 then
    return ("L < "..math.abs(util.round(param * 100, 1)))
  elseif param > 0.01 then
    return (math.abs(util.round(param * 100, 1)).." > R")
  else
    return "> <"
  end
end

local function format_waveshape(val)
  local str = ""
  if val < 0.03 then
    str = "sqr"
  elseif val > 0.02 and val < 0.498 then
    local tri = math.floor(val * 200)
    local sqr = 100 - tri 
    str = "sqr:"..sqr.." tri:"..tri
  elseif val > 0.497 and val < 0.503 then
    str = "tri"
  elseif val > 0.502 and val < 0.998 then
    local saw = math.floor((val - 0.5) * 200)
    local tri = 100 - saw 
    str = "tri:"..tri.." saw:"..saw
  else
    str = "saw"
  end
  return str
end

local function format_attack(val)
  local env = params:get("nb_sidewalk_env_type")
  return env == 1 and "n/a" or round_form(val, 0.01," s")
end

local function format_freq(freq)
  if freq < 0.1 then
    freq = round_form(freq, 0.001, "Hz")
  elseif freq < 100 then
    freq = round_form(freq, 0.01, "Hz")
  elseif util.round(freq, 1) < 1000 then
    freq = round_form(freq, 1, "Hz")
  else
    freq = round_form(freq / 1000, 0.01, "kHz")
  end
  return freq
end

local function update_mod_params()
  for _, v in ipairs(modparams) do
    local p = params:lookup_param("nb_sidewalk_"..v)
    p:bang()
  end
end

local function add_nb_sidewalk_params()
  params:add_group("nb_sidewalk_group", "sidewalk", 45)
  params:hide("nb_sidewalk_group")

  params:add_separator("nb_sidewalk_patches", "presets")

  params:add_trigger("nb_sidewalk_load_patch", ">> load")
  params:set_action("nb_sidewalk_load_patch", function() fs.enter(preset_path, load_synth_patch) end)
  
  params:add_trigger("nb_sidewalk_save_patch", "<< save")
  params:set_action("nb_sidewalk_save_patch", function() tx.enter(save_synth_patch, current_patch) end)

  params:add_separator("nb_sidewalk_levels", "levels")
  params:add_control("nb_sidewalk_amp", "amp", controlspec.new(0, 1, "lin", 0, 0.8), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_sidewalk_amp", function(val) set_param('amp', val) end)

  params:add_control("nb_sidewalk_pan", "pan", controlspec.new(-1, 1, "lin", 0, 0), function(param) return pan_display(param:get()) end)
  params:set_action("nb_sidewalk_pan", function(val) set_param('pan', val) end)  

  params:add_control("nb_sidewalk_pan_drift", "pan drift", controlspec.new(0, 1, "lin", 0, 0), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_sidewalk_pan_drift", function(val) set_param('panDrift', val) end)

  params:add_control("nb_sidewalk_send_a", "send a", controlspec.new(0, 1, "lin", 0, 0), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_sidewalk_send_a", function(val) set_param('sendA', val) end)
  
  params:add_control("nb_sidewalk_send_b", "send b", controlspec.new(0, 1, "lin", 0, 0), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_sidewalk_send_b", function(val) set_param('sendB', val) end)

  params:add_separator("nb_sidewalk_osc", "oscillators")

  params:add_number("nb_sidewalk_pitchbend", "pitchbend", 1, 24, 7, function(param) return param:get().."st" end)
  params:set_action("nb_sidewalk_pitchbend", function(val) set_param('pitchBend', val) end)

  params:add_control("nb_sidewalk_glide", "glide", controlspec.new(0, 1, "lin", 0, 0, "", 1/500), function(param) return round_form(param:get() * 1000, 1, "ms") end)
  params:set_action("nb_sidewalk_glide", function(val) set_param('glide', val) end)

  params:add_control("nb_sidewalk_waveshape", "wave shape", controlspec.new(0, 1, "lin", 0, 0.5), function(param) return format_waveshape(param:get()) end)
  params:set_action("nb_sidewalk_waveshape", function(val) set_param('waveShape', val) end)

  params:add_control("nb_sidewalk_wavefold", "wave fold", controlspec.new(0, 1, "lin", 0, 0), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_sidewalk_wavefold", function(val) set_param('waveFolds', val) end)

  params:add_control("nb_sidewalk_fm1_ratio", "fm low ratio", controlspec.new(0.1, 1, "lin", 0, 0.66), function(param) return round_form(param:get(), 0.01, "*") end)
  params:set_action("nb_sidewalk_fm1_ratio", function(val) set_param('fm1Ratio', val) end)

  params:add_control("nb_sidewalk_fm2_ratio", "fm high ratio", controlspec.new(1, 10, "lin", 0, 3.33, "", 1/900), function(param) return round_form(param:get(), 0.01, "*") end)
  params:set_action("nb_sidewalk_fm2_ratio", function(val) set_param('fm2Ratio', val) end)

  params:add_control("nb_sidewalk_fm1_amt", "fm low amount", controlspec.new(0, 1, "lin", 0, 0), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_sidewalk_fm1_amt", function(val) set_param('fm1Index', val) end)

  params:add_control("nb_sidewalk_fm2_amt", "fm high amount", controlspec.new(0, 1, "lin", 0, 0), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_sidewalk_fm2_amt", function(val) set_param('fm2Index', val) end)

  params:add_separator("nb_sidewalk_env", "filter/env")

  params:add_option("nb_sidewalk_env_type", "env type", {"lpg", "asr"}, 1)
  params:set_action("nb_sidewalk_env_type", function(val) set_param('envType', val - 1) end)

  params:add_control("nb_sidewalk_cutoff", "cutoff", controlspec.new(100, 10000, "exp", 0, 8000), function(param) return format_freq(param:get()) end)
  params:set_action("nb_sidewalk_cutoff", function(val) set_param('lpfHz', val) end)

  params:add_control("nb_sidewalk_attack", "attack", controlspec.new(0.001, 8, "exp", 0, 0.001), function(param) return format_attack(param:get()) end)
  params:set_action("nb_sidewalk_attack", function(val) set_param('attack', val) end)

  params:add_control("nb_sidewalk_decay", "decay", controlspec.new(0.01, 10, "exp", 0, 2.2), function(param) return (round_form(param:get(), 0.01,"s")) end)
  params:set_action("nb_sidewalk_decay", function(val) set_param('decay', val) end)

  params:add_separator("nb_sidewalk_lfo_src", "lfo src")
  params:add_option("nb_sidewalk_lfo_shape", "lfo shape", {"tri", "saw", "squ", "rnd"}, 1)
  params:set_action("nb_sidewalk_lfo_shape", function(val) set_mod('lfoShape', val - 1) end)

  params:add_control("nb_sidewalk_lfo_rate", "lfo rate", controlspec.new(0.001, 20, "exp", 0, 0.4, "", 1/200), function(param) return format_freq(param:get()) end)
  params:set_action("nb_sidewalk_lfo_rate", function(val) set_mod('lfoFreq', val) end)

  params:add_control("nb_sidewalk_lfo_drift", "lfo drift", controlspec.new(0, 1, "lin", 0, 0), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_sidewalk_lfo_drift", function(val) set_mod('lfoDrift', val) end)

  params:add_separator("nb_sidewalk_lfo_dst", "lfo dst")

  params:add_control("nb_sidewalk_cutoff_lfo", "lfo > cutoff", controlspec.new(0, 1, "lin", 0, 0), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_sidewalk_cutoff_lfo", function(val) set_mod('lpfHzLfo', val) end)

  params:add_control("nb_sidewalk_pan_lfo", "lfo > pan", controlspec.new(0, 1, "lin", 0, 0), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_sidewalk_pan_lfo", function(val) set_mod('panLfo', val) end)

  params:add_control("nb_sidewalk_shape_lfo", "lfo > shape", controlspec.new(0, 1, "lin", 0, 0), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_sidewalk_shape_lfo", function(val) set_mod('shapeLfo', val) end)

  params:add_control("nb_sidewalk_fold_lfo", "lfo > fold", controlspec.new(0, 1, "lin", 0, 0), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_sidewalk_fold_lfo", function(val) set_mod('foldLfo', val) end)

  params:add_control("nb_sidewalk_fm1_lfo", "lfo > fm low", controlspec.new(0, 1, "lin", 0, 0), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_sidewalk_fm1_lfo", function(val) set_mod('fm1Lfo', val) end)

  params:add_control("nb_sidewalk_fm2_lfo", "lfo > fm high", controlspec.new(0, 1, "lin", 0, 0), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_sidewalk_fm2_lfo", function(val) set_mod('fm2Lfo', val) end)

  params:add_separator("nb_sidewalk_mod_dst", "mod dst")

  params:add_control("nb_sidewalk_mod_amt", "mod amt [map me]", controlspec.new(0, 1, "lin", 0, 0), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_sidewalk_mod_amt", function(val) set_mod('modDepth', val) end)
  params:set_save("nb_sidewalk_mod_amt", false)

  params:add_control("nb_sidewalk_lfo_rate_mod", "lfo rate mod", controlspec.new(-1, 1, "lin", 0, 0, "", 1/200), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_sidewalk_lfo_rate_mod", function(val) set_mod('lfoFreqMod', val) end)

  params:add_control("nb_sidewalk_lfo_drift_mod", "lfo drift mod", controlspec.new(-1, 1, "lin", 0, 0, "", 1/200), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_sidewalk_lfo_drift_mod", function(val) set_mod('lfoDriftMod', val) end)

  params:add_control("nb_sidewalk_cutoff_mod", "cutoff mod", controlspec.new(-1, 1, "lin", 0, 0, "", 1/200), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_sidewalk_cutoff_mod", function(val) set_mod('lpfHzMod', val) end)

  params:add_control("nb_sidewalk_shape_mod", "shape mod", controlspec.new(-1, 1, "lin", 0, 0, "", 1/200), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_sidewalk_shape_mod", function(val) set_mod('shapeMod', val) end)

  params:add_control("nb_sidewalk_fold_mod", "fold mod", controlspec.new(-1, 1, "lin", 0, 0, "", 1/200), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_sidewalk_fold_mod", function(val) set_mod('foldMod', val) end)

  params:add_control("nb_sidewalk_fm1_mod", "fm low mod", controlspec.new(-1, 1, "lin", 0, 0, "", 1/200), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_sidewalk_fm1_mod", function(val) set_mod('fm1Mod', val) end)

  params:add_control("nb_sidewalk_fm2_mod", "fm high mod", controlspec.new(-1, 1, "lin", 0, 0, "", 1/200), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_sidewalk_fm2_mod", function(val) set_mod('fm2Mod', val) end)

  params:add_control("nb_sidewalk_send_a_mod", "send a mod", controlspec.new(-1, 1, "lin", 0, 0, "", 1/200), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_sidewalk_send_a_mod", function(val) set_mod('sendAMod', val) end)

  params:add_control("nb_sidewalk_send_b_mod", "send b mod", controlspec.new(-1, 1, "lin", 0, 0, "", 1/200), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_sidewalk_send_b_mod", function(val) set_mod('sendBMod', val) end)

  clock.run(function()
    clock.sleep(0.1)
    load_synth_patch(default_patch)
  end)
  
end


---------------- nb player ----------------

function add_nb_sidewalk_player()
  local player = {
    alloc = vx.new(NUM_VOICES, 2),
    slot = {},
    clk = nil
  }

  function player:describe()
    return {
      name = "nb_sidewalk",
      supports_bend = true,
      supports_slew = false
    }
  end
  
  function player:active()
    if self.name ~= nil then
      if self.clk ~= nil then
        clock.cancel(self.clk)
      end
      self.clk = clock.run(function()
        clock.sleep(0.2)
        if not is_active then
          is_active = true
          params:show("nb_sidewalk_group")
          if md.is_loaded("fx") == false then
            params:hide("nb_sidewalk_send_a")
            params:hide("nb_sidewalk_send_b")
            params:hide("nb_sidewalk_send_a_mod")
            params:hide("nb_sidewalk_send_b_mod")
          end
          init_moddef()
          update_mod_params()
          _menu.rebuild_params()
        end
      end)
    end
  end

  function player:inactive()
    if self.name ~= nil then
      if self.clk ~= nil then
        clock.cancel(self.clk)
      end
      self.clk = clock.run(function()
        clock.sleep(0.2)
        if is_active then
          is_active = false
          dont_panic()
          free_moddef()
          params:hide("nb_sidewalk_group")
          _menu.rebuild_params()
        end
      end)
    end
  end

  function player:stop_all()
    dont_panic()
  end

  function player:modulate(val)
    params:set("nb_sidewalk_mod_amt", val)
  end

  function player:set_slew(s)
  end

  function player:pitch_bend(note, val)
    set_param('bendDepth', val)
  end

  function player:modulate_note(note, key, value)
  end

  function player:note_on(note, vel)
    local freq = mu.note_num_to_freq(note)
    local slot = self.slot[note]
    if slot == nil then
      slot = self.alloc:get()
      slot.count = 1
    end
    local voice = slot.id - 1 -- sc is zero indexed!
    slot.on_release = function()
      note_off(voice)
    end
    self.slot[note] = slot
    note_on(voice, freq, vel)
  end

  function player:note_off(note)
    local slot = self.slot[note]
    if slot ~= nil then
      self.alloc:release(slot)
    end
    self.slot[note] = nil
  end

  function player:add_params()
    add_nb_sidewalk_params()
  end

  if note_players == nil then
    note_players = {}
  end
  note_players["sidewalk"] = player
  
end


---------------- mod zone ----------------

local function post_system()
  if util.file_exists(preset_path) == false then
    util.make_dir(preset_path)
    os.execute('cp '.. '/home/we/dust/code/nb_sidewalk/data/*.swp '.. preset_path)
  end
end

local function pre_init()
  init_nb_sidewalk()
  add_nb_sidewalk_player()
end

local function cleanup_sidewalk()
  free_moddef()
end

md.hook.register("system_post_startup", "nb_sidewalk post startup", post_system)
md.hook.register("script_pre_init", "nb_sidewalk pre init", pre_init)
md.hook.register("script_post_cleanup", "nb_smpkit cleanup", cleanup_sidewalk)
