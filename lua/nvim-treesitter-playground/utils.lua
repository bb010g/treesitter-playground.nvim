local api = vim.api
local ts_utils = require "nvim-treesitter.ts_utils"
local highlighter = require "vim.treesitter.highlighter"

local M = {}

function M.debounce(fn, debounce_time)
  local timer = vim.loop.new_timer()
  local is_debounce_fn = type(debounce_time) == "function"

  return function(...)
    timer:stop()

    local time = debounce_time
    local args = { ... }

    if is_debounce_fn then
      time = debounce_time()
    end

    timer:start(
      time,
      0,
      vim.schedule_wrap(function()
        fn(unpack(args))
      end)
    )
  end
end

--- Determines if {range_1} contains (inclusive) {range_2}
---
---@param range table
---@param range table
---
---@return boolean True if {range_1} contains {range_2}
function M.range_contains(range_1, range_2)
  return (range_1[1] < range_2[1] or (range_1[1] == range_2[1] and range_1[2] <= range_2[2]))
    and (range_1[3] > range_2[3] or (range_1[3] == range_2[3] and range_1[4] >= range_2[4]))
end

--- Determines if {range_1} intersects (inclusive) {range_2}
---
---@param range table
---@param range table
---
---@return boolean True if {range_1} intersects {range_2}
function M.range_intersects(range_1, range_2)
  return (
    range_1[1] < range_2[3]
    or (
      range_1[1] == range_2[3]
      and (range_1[2] < range_2[4] or (range_1[2] == range_2[4] and range_1[4] == range_2[4]))
    )
  )
    and (
      range_2[1] < range_1[3]
      or (
        range_2[1] == range_1[3]
        and (range_2[2] < range_1[4] or (range_2[2] == range_1[4] and range_2[4] == range_1[4]))
      )
    )
end

function M.get_hl_groups_at_position(bufnr, row, col)
  local buf_highlighter = highlighter.active[bufnr]

  if not buf_highlighter then
    return {}
  end

  local range = { row, col, row, col }
  local matches = {}

  buf_highlighter.tree:for_each_tree(function(tstree, tree)
    if not tstree then
      return
    end

    local root = tstree:root()

    -- Only worry about trees within the range
    if not M.range_intersects({ root:range() }, range) then
      return
    end

    local query = buf_highlighter:get_query(tree:lang())

    -- Some injected languages may not have highlight queries.
    if not query:query() then
      return
    end

    local iter = query:query():iter_captures(root, buf_highlighter.bufnr, range[1], range[3] + 1)

    for capture, node, metadata in iter do
      local hl = query.hl_cache[capture]

      if hl and M.range_contains({ node:range() }, range) then
        local c = query._query.captures[capture] -- name of the capture in the query
        if c ~= nil then
          table.insert(matches, { capture = c, priority = metadata.priority })
        end
      end
    end
  end, true)
  return matches
end

function M.for_each_buf_window(bufnr, fn)
  if not api.nvim_buf_is_loaded(bufnr) then
    return
  end

  for _, window in ipairs(vim.fn.win_findbuf(bufnr)) do
    fn(window)
  end
end

function M.to_lookup_table(list, key_mapper)
  local result = {}

  for i, v in ipairs(list) do
    local key = v

    if key_mapper then
      key = key_mapper(v, i)
    end

    result[key] = v
  end

  return result
end

function M.node_contains(node, range)
  return M.range_contains({ node:range() }, range)
end

--- Returns a tuple with the position of the last line and last column (0-indexed).
function M.get_end_pos(bufnr)
  local bufnr = bufnr or api.nvim_get_current_buf()
  local last_row = api.nvim_buf_line_count(bufnr) - 1
  local last_line = api.nvim_buf_get_lines(bufnr, last_row, last_row + 1, true)[1]
  local last_col = last_line and #last_line or 0
  return last_row, last_col
end

return M
