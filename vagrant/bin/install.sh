#!/usr/bin/env bash
##
 # Copyright © 2015 by David Alger. All rights reserved
 # 
 # Licensed under the Open Software License 3.0 (OSL-3.0)
 # See included LICENSE file for full text of OSL-3.0
 # 
 # http://davidalger.com/contact/
 ##

set -e

update_mode=

##############################
# declare homebrew assertions

function assert_brew {
    echo "==> Checking brew package manager"
    if ! which brew > /dev/null; then
        echo "==> Installing brew package manager"
        curl -s https://raw.githubusercontent.com/Homebrew/install/master/install | ruby > /dev/null 2>&1
        brew doctor

        made_changes=1
    elif [ $update_mode ]; then
        echo "==> Updating brew taps"
        brew update > /dev/null
        made_changes=1
    fi
}

function assert_tap {
    echo "==> Checking tap $1"
    
    if ! brew tap | grep "$1" > /dev/null 2>&1; then
        brew tap "$1" 2> /dev/null | cat

        made_changes=1
    fi
}

function assert_pack {
    echo "==> Checking pack $1"
    
    if ! brew list "$1" > /dev/null 2>&1; then
        echo "==> Installing brew $1"
        brew install "$1" > /dev/null

        made_changes=1
    elif [ $update_mode ]; then
        echo "==> Upgrading brew $1"
        brew upgrade "$1" 2>&1 1>/dev/null \
            | sed -E 's/Error: (.*already installed)/==> Package \1/g' \
            || true   # don't fail on already installed err
        
        made_changes=1
    fi
}

function assert_cask {
    echo "==> Checking cask $1"
    
    if ! brew cask list "$1" > /dev/null 2>&1 ; then
        echo "==> Installing cask $1"
        brew cask install "$1" > /dev/null

        made_changes=1
    elif [ $update_mode ]; then
        echo "==> Skipping cask $1 upgrade (unsupported)"
    fi
}

##############################
# declare tooling assertions

function assert_cli_tools {
    echo "==> Checking command line tools"
    if ! xcode-select -p > /dev/null 2>&1 || [ $update_mode ]; then
        echo "==> Finding command line tools package"
        touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
        xcode_package=$(softwareupdate -l | grep '* Command Line' | head -n1 | sed -E 's/ +\* //g')
    
        echo "==> Installing $xcode_package"
        softwareupdate -i "$xcode_package"
    
        rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
        made_changes=1
    fi
}

function assert_devenv {
    # verify server link and mount
    echo "==> Checking /server for environment setup"

    if [[ ! -d /server ]] && [[ -L /server ]]; then
        >&2 echo "Warning: /server is a dead symbolic link pointing to nowhere. Removing and moving on..."
        sudo rm -f /server
        made_changes=1
    fi

    # nothing is at /server, so begin setup by creating it
    if [[ ! -d /server ]] && [[ ! -L /server ]]; then
        if [[ -d "/Volumes/Server" ]]; then
            echo "==> Creating /server -> /Volumes/Server symbolic link"
            sudo ln -s /Volumes/Server /server
            made_changes=1
        else
            >&2 echo "Warning: Failed to detect /Volumes/Server mount. Creating directory at /server instead"
            sudo mkdir /server
            made_changes=1
        fi
    fi

    if [[ -d /server ]] && [[ ! -L /server ]]; then
        >&2 echo "Warning: /server is a directory. This may cause case-insensitivity issues in guest machines"
    fi

    # create /sites link if not exists
    if [[ ! -d /sites ]] && [[ ! -L /sites ]]; then
        echo "==> Creating /sites -> /server/sites symbolic link"
        sudo ln -s /server/sites /sites
        made_changes=1
    fi

    # verify /server is empty (barring system dotfiles) and hasn't been git inited
    if [[ ! "$(ls /server | head -n1)" ]] && [[ ! -f /server/.git/config ]] ; then
        echo "==> Installing environment at /server"
        sudo chown $(whoami):admin /server
        cd /server
        git init -q
        git remote add origin https://github.com/classyllama/devenv.git
        git fetch -q origin
        git checkout -q master
        vagrant status | grep -v '/etc/profile' || true  # note: expected to spit out error about re-running vagrant
        echo "==> Please run `source /etc/profile` in your shell before starting vagrant"

        made_changes=1
    elif [[ ! -f /server/vagrant/vagrant.rb ]]; then
        >&2 echo "Error: /server is not empty, but does not appear to be setup either. Moving on..."
    fi
    
    # TODO: add --update support to devenv assertion
}

function assert_composer {
    # note: depends on /server being valid
    echo "==> Checking for composer"
    if [[ ! -x /usr/local/bin/composer ]]; then
        echo "==> Installing composer"
        mkdir -p /server/.shared/composer
        wget -q https://getcomposer.org/composer.phar -O /usr/local/bin/composer
        chmod +x /usr/local/bin/composer
        made_changes=1
    elif [ $update_mode ]; then
        echo "==> Updating composer via self-update"
        composer self-update > /dev/null
        made_changes=1
    fi

    # stat results in 0000 if file is not there; doubles as permission and presence check
    if [[ "$(perl -le 'printf "%04o", (stat("/server/.shared/composer/auth.json"))[2] & 07777;')" != "0640" ]]; then
        echo "==> Initializing global composer config"
        # has effect of creating auth.json with an object of empty vals at expected COMPOSER_HOME location
        COMPOSER_HOME=/server/.shared/composer /usr/local/bin/composer config -g
        chmod 640 /server/.shared/composer/auth.json
    fi
}

function assert_bin_dir {
    if [[ ! -d /usr/local/bin ]]; then
        sudo mkdir -p /usr/local/bin
        made_changes=1
    fi

    if [[ "$(stat -f "%u" /usr/local/bin/)" != "$(id -u)" ]]; then
        sudo chown $(whoami):admin /usr/local/bin
        made_changes=1
    fi
}

function configure_php {
    if [[ -f /usr/local/etc/php/7.0/php.ini ]]; then
        perl -pi -e 's/^memory_limit\s?=\s?.*/memory_limit = 2G/g' /usr/local/etc/php/7.0/php.ini
    fi
}

##############################
# declare installation routine

function install_environment {
    made_changes=
    echo "==> Checking dependencies"

    assert_cli_tools
    assert_brew
    assert_bin_dir

    # general tooling
    assert_pack ansible
    assert_pack ack
    assert_pack bash-completion
    assert_pack git
    assert_pack mysql
    assert_pack pv
    assert_pack perl
    assert_pack redis
    assert_pack ruby
    assert_pack tree
    assert_pack watch
    assert_pack imagemagick
    assert_pack wget
    assert_pack php

    configure_php

    assert_cask vagrant
    assert_pack vagrant-completion

    assert_cask virtualbox

    assert_devenv

    assert_composer

    # inform user and exit
    if [ $made_changes ]; then
        echo "Process Complete!"
    else
        echo "Nothing to do!"
    fi
}

if [[ "$1" == "--update" ]]; then
    update_mode=1
fi

if [[ "$1" != "--lib-mode" ]]; then
    install_environment
fi
