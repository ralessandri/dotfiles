# Fedora-specific installation and configuration commands.
#
# Keep distribution-specific implementation details in this module. A future
# distribution can add its own module next to this one in the root justfile.

[private]
default:
  @just --list fedora


mod install "fedora/install.just"
mod config "fedora/config.just"
