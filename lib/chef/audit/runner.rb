autoload :Inspec, "inspec"

require_relative "default_attributes"
require_relative "reporter/audit_enforcer"
require_relative "reporter/automate"
require_relative "reporter/chef_server_automate"
require_relative "reporter/json_file"

class Chef
  module Audit
    class Runner < EventDispatch::Base
      extend Forwardable

      attr_accessor :run_id, :recipes
      attr_reader :node
      def_delegators :node, :logger

      def enabled?
        audit_cookbook_present = recipes.include?("audit::default")

        logger.info("#{self.class}##{__method__}: #{Inspec::Dist::PRODUCT_NAME} profiles? #{inspec_profiles.any?}")
        logger.info("#{self.class}##{__method__}: audit cookbook? #{audit_cookbook_present}")

        inspec_profiles.any? && !audit_cookbook_present
      end

      def node=(node)
        @node = node
        node.default["audit"] = Chef::Audit::DEFAULT_ATTRIBUTES.merge(node.default["audit"])
      end

      def node_load_completed(node, _expanded_run_list, _config)
        self.node = node
      end

      def run_started(run_status)
        self.run_id = run_status.run_id
      end

      def run_list_expanded(run_list_expansion)
        self.recipes = run_list_expansion.recipes
      end

      def run_completed(_node, _run_status)
        return unless enabled?

        logger.info("#{self.class}##{__method__}: enabling audit mode")

        report
      end

      def run_failed(_exception, _run_status)
        return unless enabled?

        logger.info("#{self.class}##{__method__}: enabling audit mode")

        report
      end

      ### Below code adapted from audit cookbook's files/default/handler/audit_report.rb

      DEPRECATED_CONFIG_VALUES = %w{
        attributes_save
        chef_node_attribute_enabled
        fail_if_not_present
        inspec_gem_source
        inspec_version
        interval
        owner
        raise_if_unreachable
      }.freeze

      def warn_for_deprecated_config_values!
        deprecated_config_values = (node["audit"].keys & DEPRECATED_CONFIG_VALUES)

        if deprecated_config_values.any?
          values = deprecated_config_values.sort.map { |v| "'#{v}'" }.join(", ")
          logger.warn "audit-cookbook config values #{values} are not supported in #{ChefUtils::Dist::Infra::PRODUCT}'s audit mode."
        end
      end

      def report(report = generate_report)
        warn_for_deprecated_config_values!

        if report.empty?
          logger.error "Audit report was not generated properly, skipped reporting"
          return
        end

        Array(node["audit"]["reporter"]).each do |reporter|
          send_report(reporter, report)
        end
      end

      def inspec_opts
        {
          backend_cache: node["audit"]["inspec_backend_cache"],
          inputs: node["audit"]["attributes"],
          logger: logger,
          output: node["audit"]["quiet"] ? ::File::NULL : STDOUT,
          report: true,
          reporter: ["json-automate"],
          reporter_backtrace_inclusion: node["audit"]["result_include_backtrace"],
          reporter_message_truncation: node["audit"]["result_message_limit"],
          waiver_file: Array(node["audit"]["waiver_file"]),
        }
      end

      def inspec_profiles
        profiles = node["audit"]["profiles"]

        # TODO: Custom exception class here?
        unless profiles.respond_to?(:map) && profiles.all? { |_, p| p.respond_to?(:transform_keys) && p.respond_to?(:update) }
          raise "#{Inspec::Dist::PRODUCT_NAME} profiles specified in an unrecognized format, expected a hash of hashes."
        end

        profiles.map do |name, profile|
          profile.transform_keys(&:to_sym).update(name: name)
        end
      end

      def load_fetchers!
        case node["audit"]["fetcher"]
        when "chef-automate"
          require_relative "fetcher/automate"
        when "chef-server"
          require_relative "fetcher/chef_server"
        when nil
          # intentionally blank
        else
          raise "Invalid value specified for audit mode's fetcher: '#{node["audit"]["fetcher"]}'. Valid values are 'chef-automate', 'chef-server', or nil."
        end
      end

      def generate_report(opts: inspec_opts, profiles: inspec_profiles)
        load_fetchers!

        logger.debug "Options are set to: #{opts}"
        runner = ::Inspec::Runner.new(opts)

        if profiles.empty?
          failed_report("No audit profiles are defined.")
          return
        end

        profiles.each { |target| runner.add_target(target) }

        logger.info "Running profiles from: #{profiles.inspect}"
        runner.run
        runner.report.tap do |r|
          logger.debug "Audit Report #{r}"
        end
      rescue Inspec::FetcherFailure => e
        failed_report("Cannot fetch all profiles: #{profiles}. Please make sure you're authenticated and the server is reachable. #{e.message}")
      rescue => e
        failed_report(e.message)
      end

      # In case InSpec raises a runtime exception without providing a valid report,
      # we make one up and add two new fields to it: `status` and `status_message`
      def failed_report(err)
        logger.error "#{Inspec::Dist::PRODUCT_NAME} has raised a runtime exception. Generating a minimal failed report."
        logger.error err
        {
          "platform": {
            "name": "unknown",
            "release": "unknown",
          },
          "profiles": [],
          "statistics": {
            "duration": 0.0000001,
          },
          "version": Inspec::VERSION,
          "status": "failed",
          "status_message": err,
        }
      end

      # extracts relevant node data
      def node_info
        runlist_roles = node.run_list.select { |item| item.type == :role }.map(&:name)
        runlist_recipes = node.run_list.select { |item| item.type == :recipe }.map(&:name)
        {
          node: node.name,
          os: {
            release: node["platform_version"],
            family: node["platform"],
          },
          environment: node.environment,
          roles: runlist_roles,
          recipes: runlist_recipes,
          policy_name: node.policy_name || "",
          policy_group: node.policy_group || "",
          chef_tags: node.tags,
          organization_name: chef_server_uri.path.split("/").last || "",
          source_fqdn: chef_server_uri.host || "",
          ipaddress: node["ipaddress"],
          fqdn: node["fqdn"],
        }
      end

      def send_report(reporter, report)
        logger.info "Reporting to #{reporter}"

        insecure = node["audit"]["insecure"]
        run_time_limit = node["audit"]["run_time_limit"]
        control_results_limit = node["audit"]["control_results_limit"]

        case reporter
        when "chef-automate"
          opts = {
            entity_uuid: node["chef_guid"],
            run_id: run_id,
            node_info: node_info,
            insecure: insecure,
            run_time_limit: run_time_limit,
            control_results_limit: control_results_limit,
          }
          Chef::Audit::Reporter::Automate.new(opts).send_report(report)
        when "chef-server-automate"
          chef_url = node["audit"]["server"] || base_chef_server_url
          chef_org = Chef::Config[:chef_server_url].split("/").last
          if chef_url
            url = construct_url(chef_url, File.join("organizations", chef_org, "data-collector"))
            opts = {
              entity_uuid: node["chef_guid"],
              run_id: run_id,
              node_info: node_info,
              insecure: insecure,
              url: url,
              run_time_limit: run_time_limit,
              control_results_limit: control_results_limit,
            }
            Chef::Audit::Reporter::ChefServer.new(opts).send_report(report)
          else
            logger.warn "Unable to determine #{ChefUtils::Dist::Server::PRODUCT} url required by #{Inspec::Dist::PRODUCT_NAME} report collector '#{reporter}'. Skipping..."
          end
        when "json-file"
          path = node["audit"]["json_file"]["location"]
          logger.info "Writing report to #{path}"
          Chef::Audit::Reporter::JsonFile.new(file: path).send_report(report)
        when "audit-enforcer"
          Chef::Audit::Reporter::AuditEnforcer.new.send_report(report)
        else
          logger.warn "#{reporter} is not a supported #{Inspec::Dist::PRODUCT_NAME} report collector"
        end
      end
    end
  end
end
