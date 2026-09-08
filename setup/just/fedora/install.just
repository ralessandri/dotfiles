# Fedora software installation recipes.


[private]
default:
  @just --list fedora install

# Install and configure the RPM Fusion repositories.
[group('repositories')]
rpmfusion:
    ../../tasks/fedora-rpmfusion-install.sh

# Install common command-line development tools.
[group('development')]
cli:
    ../../tasks/fedora-cli-install.sh

# Install Docker and configure it as a socket-activated service.
[group('development')]
docker:
    ../../tasks/fedora-docker-install.sh

# Install DDEV and initialize its local certificate authority.
[group('development')]
ddev: docker
    ../../tasks/fedora-ddev-install.sh

# Install PHP and the configured PHP extensions.
[group('development')]
php:
    ../../tasks/fedora-php-install.sh

# Install Niri and Dank Material Shell and integrate them.
[group('desktop')]
niri-with-dms:
    ../../tasks/fedora-niridms-install.sh

# Install the default web apps.
[group('desktop')]
webapps:
    ../../tasks/fedora-webapps-default-install.sh

# Install multimedia codecs from RPM Fusion.
[group('media')]
codecs: rpmfusion
    ../../tasks/fedora-multimediacodecs-install.sh

# Refresh firmware metadata and show available firmware updates.
[group('hardware')]
firmware:
    ../../tasks/fedora-firmware-update.sh

# Install the NVIDIA 580xx driver stack.
[group('hardware')]
nvidia580:
    ../../tasks/fedora-nvidia580-install.sh
