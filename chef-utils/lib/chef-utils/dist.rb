# frozen_string_literal: true
module ChefUtils
  # This class is not fully implemented, depending on it is not recommended!
  module Dist
    class Apply
      # The chef-apply product name
      PRODUCT = "Cinc Apply"

      # The chef-apply binary
      EXEC = "cinc-apply"
    end

    class Automate
      # name of the automate product
      PRODUCT = "Cinc Dashboard"
    end

    class Infra
      # When referencing a product directly, like Chef (Now Chef Infra)
      PRODUCT = "Cinc Client"

      # A short designation for the product, used in Windows event logs
      # and some nomenclature.
      SHORT = "cinc"

      # The client's alias (chef-client)
      CLIENT = "cinc-client"

      # The chef executable, as in `chef gem install` or `chef generate cookbook`
      EXEC = "cinc"

      # The chef-shell executable
      SHELL = "cinc-shell"

      # Configuration related constants
      # The chef-shell configuration file
      SHELL_CONF = "cinc_shell.rb"

      # The user's configuration directory
      USER_CONF_DIR = ".cinc"

      # The suffix for Chef's /etc/chef, /var/chef and C:\\Chef directories
      # "chef" => /etc/cinc, /var/cinc, C:\\cinc
      DIR_SUFFIX = "cinc"
    end

    class Org
      # product Website address
      WEBSITE = "https://cinc.sh"

      # The downloads site
      DOWNLOADS_URL = "downloads.cinc.sh"

      # The legacy conf folder: C:/opscode/chef. Specifically the "opscode" part
      # DIR_SUFFIX is appended to it in code where relevant
      LEGACY_CONF_DIR = "cincproject"

      # Enable forcing Chef EULA
      ENFORCE_LICENSE = false

      # product patents page
      PATENTS = "https://www.chef.io/patents"

      # knife documentation page
      KNIFE_DOCS = "https://docs.chef.io/workstation/knife/"
    end

    class Server
      # The name of the server product
      PRODUCT = "Cinc Server"

      # The server's configuration directory
      CONF_DIR = "/etc/cinc-server"

      # The servers's alias (chef-server)
      SERVER = "cinc-server"

      # The server's configuration utility
      SERVER_CTL = "cinc-server-ctl"
    end

    class Solo
      # Chef-Solo's product name
      PRODUCT = "Cinc Solo"

      # The chef-solo executable (legacy local mode)
      EXEC = "cinc-solo"
    end

    class Workstation
      # The suffix for Chef Workstation's /opt/chef-workstation or C:\\opscode\chef-workstation
      DIR_SUFFIX = "chef-workstation"
    end

    class Zero
      # chef-zero executable
      PRODUCT = "Cinc Zero"

      # The chef-zero executable (local mode)
      EXEC = "cinc-zero"
    end
  end
end
