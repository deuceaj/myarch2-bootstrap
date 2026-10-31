-- Noctalia colors in LazyVim.
-- noctalia's "neovim" template writes lua/matugen.lua from the active palette
-- and signals running nvim (SIGUSR1) to reload it on theme changes.
-- Falls back to tokyonight until that file exists.
return {
  { "RRethy/base16-nvim", lazy = false, priority = 1000 },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = function()
        local ok, matugen = pcall(require, "matugen")
        if ok then
          matugen.setup()
        else
          vim.cmd.colorscheme("tokyonight")
        end
      end,
    },
  },
}
