local root = vim.fn.fnamemodify("./.repro", ":p")

--set stdpaths for .repro
for _, name in ipairs({"config", "data", "state", "cache" }) do
	vim.env[("XDG_%s_HOME"):format(name:upper())] = root .. "/" .. name
end

--bootstrap lazy (needed to download mason to install prismals
local lazypath = root .. "/plugins/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "--single-branch",
    "https://github.com/folke/lazy.nvim.git",
    lazypath,
  })
end

vim.opt.runtimepath:prepend(lazypath)

local plugins = {
  {
    "williamboman/mason.nvim",
    opts = {
      ensure_installed = {
        "prisma-language-server",
        "lua-language-server"
      }
    },
    config = function(_, opts)
      require("mason").setup(opts)

      -- Triggers a FileType event to make the LSP start without having to close the buffer and re-open it.
      local mr = require("mason-registry")
      mr:on("package:install:success", function()
        vim.defer_fn(function()
          require("lazy.core.handler.event").trigger({
            event = "FileType",
            buf = vim.api.nvim_get_current_buf(),
          })
        end, 100)
      end)

      -- Install all ensure_installed packages get installed if they are not currently installed
      mr.refresh(function()
        for _, tool in ipairs(opts.ensure_installed) do
          local p = mr.get_package(tool)
          if not p:is_installed() then
            p:install():once(
              "closed",
              vim.schedule_wrap(function()
                if p:is_installed() then
                  vim.notify(("[mason.nvim] %s was installed successfully"):format(p.name))
                else
                  vim.notify(
                    (
                      "[mason.nvim] failed to install %s. Installation logs are available in :Mason and :MasonLog"):format(p.name),
                      vim.log.levels.ERROR
                    )
                end
              end)
            )
          end
        end
      end)
    end,
  }
}

  require("lazy").setup(plugins, {
    root = root .. "/plugins",
  })

  vim.api.nvim_create_autocmd("LspAttach", {
    group = vim.api.nvim_create_augroup("UserLspAttach", { clear = true }),
    callback = function(args)
      vim.lsp.completion.enable(true, args.data.client_id, args.buf)
    end
  })

  vim.lsp.config.prismals = {
    cmd = { "prisma-language-server", "--stdio" },
    root_markers = { ".git", "package.json" },
    filetypes = { "prisma" }
  }

  vim.lsp.config.lua_ls = {
    cmd = { "lua-language-server" },
    root_markers = { ".luarc.json", "stylua.toml", ".git" },
    filetypes = {"lua"},
    on_init = function(client)
      local path = vim.tbl_get(client, "workspace_folders", 1, "name")
      if not path then
        return
      end

      client.settings = vim.tbl_deep_extend("force", client.settings, {
        Lua = {
          runtime = {
            version = 'LuaJIT'
          },
          -- Make the server aware of Neovim runtime files
          workspace = {
            checkThirdParty = false,
            library = {
              vim.env.VIMRUNTIME
            }
          }
        }	
      })
    end
  }

  vim.lsp.enable({"prismals", "lua_ls"})
