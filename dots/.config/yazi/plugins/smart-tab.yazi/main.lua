--- @sync entry

return {
  entry = function()
    local hovered = cx.active.current.hovered
    ya.emit("tab_create", hovered and hovered.cha.is_dir and { hovered.url } or { current = true })
  end,
}
