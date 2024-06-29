local GLOBALS = require("kulala.globals")
local FS = require("kulala.utils.fs")
local CONFIG = require("kulala.config")
local CFG = CONFIG.get_config()

local M = {}

local random = math.random
math.randomseed(os.time())

---Generate a random uuid
---@return string
local function uuid()
  local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
  ---@diagnostic disable-next-line redundant-return-value
  return string.gsub(template, "[xy]", function(c)
    local v = (c == "x") and random(0, 0xf) or random(8, 0xb)
    return string.format("%x", v)
  end)
end

--Return the previousRequestBody if it exists and is not empty and its ft is json
--Otherwise return an empty table
---@return table|nil
local function get_previous_response_body()
  local body = FS.read_file(GLOBALS.BODY_FILE)
  local ft = FS.read_file(GLOBALS.FILETYPE_FILE)
  if body and body ~= "" and  ft == "json" then
    return vim.fn.json_decode(body)
  end
  return nil
end


---Retrieve all dynamic variables from both rest.nvim and the ones declared by
---the user on his configuration
---@return { [string]: fun():string }[] An array-like table of tables which contains dynamic variables definition
function M.retrieve_all()
  local user_variables = CFG.custom_dynamic_variables or {}
  local rest_variables = {
    ["$uuid"] = uuid,
    ["$date"] = function()
      return os.date("%Y-%m-%d")
    end,
    ["$timestamp"] = os.time,
    ["$randomInt"] = function()
      return math.random(0, 1000)
    end,
  }

  return vim.tbl_deep_extend("force", rest_variables, user_variables)
end

local previous_request_body_parser = function(prb)
  local previous_body = get_previous_response_body()
  if not previous_body then
    return nil
  end
  -- recursively get the value of the key
  -- if the key is a table, recurse until we get the value
  local function get_value(key, tbl)
    local k, rest = key:match("([^%.]+)%.(.+)")
    if rest then
      return get_value(rest, tbl[k])
    end
    local possible_table = tbl[key]
    if type(possible_table) == "table" then
      local values = {}
      for _, v in ipairs(tbl[key]) do
        table.insert(values, v)
      end
      return table.concat(values, ",")
    end
    return tbl[key]
  end
  return get_value(prb, previous_body)
end

---Look for a dynamic variable and evaluate it
---@param name string The dynamic variable name
---@return string|nil The dynamic variable value or `nil` if the dynamic variable was not found
function M.read(name)
  -- if name starts with $previousRequestBody
  -- return the value of the key in the previousRequestBody
  local prb = name:match("^%$previousResponseBody%.(.+)")
  if prb then
    return previous_request_body_parser(prb)
  end
  local vars = M.retrieve_all()
  if not vim.tbl_contains(vim.tbl_keys(vars), name) then
    ---@diagnostic disable-next-line need-check-nil
    vim.notify("The dynamic variable '" .. name .. "' was not found. Maybe it's written wrong or doesn't exist?")
    return nil
  end

  return vars[name]()
end

return M
