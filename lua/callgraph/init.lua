local M = {}

local kind_labels = vim.lsp.protocol.SymbolKind or {}

local function format_signature(symbol)
  local detail = symbol.detail or ""
  local name = symbol.name or "<unknown>"
  local kind = kind_labels[symbol.kind] or "Symbol"
  return string.format("[%s] %s%s", kind, name, detail ~= "" and " :: " .. detail or "")
end

local function format_file(uri)
  local path = vim.uri_to_fname(uri or "")
  return vim.fn.fnamemodify(path, ":~:.")
end

M.show_callers = function()
  local params = vim.lsp.util.make_position_params()

  vim.lsp.buf_request(0, 'textDocument/prepareCallHierarchy', params, function(err, result)
    if err then
      vim.notify('Error preparing call hierarchy: ' .. err.message, vim.log.levels.WARN)
      return
    end

    if not result or #result == 0 then
      vim.notify('No symbol found for call hierarchy', vim.log.levels.INFO)
      return
    end

    local item = result[1]
    local lines = {}

    table.insert(lines, "╭───────────────────────────────────────╮")
    table.insert(lines, "│ Call Hierarchy (UML View)            │")
    table.insert(lines, "╰───────────────────────────────────────╯")
    table.insert(lines, "Target: " .. format_signature(item))
    table.insert(lines, "File:   " .. format_file(item.uri))
    table.insert(lines, "")

    local function format_node(prefix, node, arrow, children)
      local line = prefix .. arrow .. " " .. format_signature(node)
      table.insert(lines, line)
      if children then
        for i, child in ipairs(children) do
          local next_prefix = prefix .. (i == #children and "    " or "│   ")
          format_node(next_prefix, child, "↳", {}) -- No grandchildren yet
        end
      end
    end

    -- Incoming (Callers)
    vim.lsp.buf_request(0, 'callHierarchy/incomingCalls', { item = item }, function(err_in, incoming)
      if err_in then
        vim.notify('Error fetching callers: ' .. err_in.message, vim.log.levels.WARN)
        return
      end

      table.insert(lines, "▲ Callers (who calls this?):")

      if incoming and #incoming > 0 then
        for _, call in ipairs(incoming) do
          format_node("  ", call.from, "←", {})
        end
      else
        table.insert(lines, "  (none)")
      end

      table.insert(lines, "")

      -- Outgoing (Callees)
      vim.lsp.buf_request(0, 'callHierarchy/outgoingCalls', { item = item }, function(err_out, outgoing)
        if err_out then
          vim.notify('Error fetching callees: ' .. err_out.message, vim.log.levels.WARN)
          return
        end

        table.insert(lines, "▼ Callees (what this calls):")

        if outgoing and #outgoing > 0 then
          for _, call in ipairs(outgoing) do
            format_node("  ", call.to, "→", {})
          end
        else
          table.insert(lines, "  (none)")
        end

        local buf = vim.api.nvim_create_buf(false, true)
        local width = 0

        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

        for _, l in ipairs(lines) do width = math.max(width, #l) end

        local height = #lines
        local opts = {
          relative = "editor",
          width = math.max(50, width + 4),
          height = height,
          row = math.floor((vim.o.lines - height) / 2),
          col = math.floor((vim.o.columns - width) / 2),
          style = "minimal",
          border = "rounded",
        }

        vim.api.nvim_open_win(buf, true, opts)
        vim.api.nvim_buf_set_keymap(buf, 'n', 'q', '<cmd>close<CR>', { noremap = true, silent = true })
      end)
    end)
  end)
end

vim.api.nvim_create_user_command("Callers", function()
  require("callgraph").show_callers()
end, {})

return M
