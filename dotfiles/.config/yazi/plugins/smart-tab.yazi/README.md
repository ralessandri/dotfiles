# smart-tab.yazi

Creates a new tab. When a directory is hovered, the new tab opens that directory; otherwise, it opens the current directory.

## Usage

Bind the plugin in `keymap.toml`:

```toml
[[mgr.prepend_keymap]]
on   = [ "t", "t" ]
run  = "plugin smart-tab"
desc = "Create a tab in the hovered or current directory"
```
