require "spec_helper"

describe Chef::Compliance::Runner do
  let(:logger) { double(:logger).as_null_object }
  let(:node) { Chef::Node.new(logger: logger) }

  let(:runner) do
    described_class.new.tap do |r|
      r.node = node
      r.run_id = "my_run_id"
      r.recipes = []
    end
  end

  describe "#enabled?" do
    it "is true if the node attributes have audit profiles and the audit cookbook is not present" do
      node.normal["audit"]["profiles"]["ssh"] = { 'compliance': "base/ssh" }
      runner.recipes = %w{ fancy_cookbook::fanciness tacobell::nachos }

      expect(runner).to be_enabled
    end

    it "is false if the node attributes have audit profiles and the audit cookbook is present" do
      node.normal["audit"]["profiles"]["ssh"] = { 'compliance': "base/ssh" }
      runner.recipes = %w{ audit::default fancy_cookbook::fanciness tacobell::nachos }

      expect(runner).not_to be_enabled
    end

    it "is false if the node attributes do not have audit profiles and the audit cookbook is not present" do
      node.normal["audit"]["profiles"] = {}
      runner.recipes = %w{ fancy_cookbook::fanciness tacobell::nachos }

      expect(runner).not_to be_enabled
    end

    it "is false if the node attributes do not have audit profiles and the audit cookbook is present" do
      node.normal["audit"]["profiles"] = {}
      runner.recipes = %w{ audit::default fancy_cookbook::fanciness tacobell::nachos }

      expect(runner).not_to be_enabled
    end

    it "is false if the node attributes do not have audit attributes and the audit cookbook is not present" do
      runner.recipes = %w{ fancy_cookbook::fanciness tacobell::nachos }
      expect(runner).not_to be_enabled
    end
  end

  describe "#inspec_profiles" do
    it "returns an empty list with no profiles defined" do
      expect(runner.inspec_profiles).to eq([])
    end

    it "converts from the attribute format to the format Inspec expects" do
      node.normal["audit"]["profiles"]["linux-baseline"] = {
        'compliance': "user/linux-baseline",
        'version': "2.1.0",
      }

      node.normal["audit"]["profiles"]["ssh"] = {
        'supermarket': "hardening/ssh-hardening",
      }

      expected = [
        {
          compliance: "user/linux-baseline",
          name: "linux-baseline",
          version: "2.1.0",
        },
        {
          name: "ssh",
          supermarket: "hardening/ssh-hardening",
        },
      ]

      expect(runner.inspec_profiles).to eq(expected)
    end

    it "raises an error when the profiles are in the old audit-cookbook format" do
      node.normal["audit"]["profiles"] = [
        {
          name: "Windows 2019 Baseline",
          compliance: "admin/windows-2019-baseline",
        },
      ]

      expect { runner.inspec_profiles }.to raise_error(/profiles specified in an unrecognized format, expected a hash of hashes./)
    end
  end

  describe "#warn_for_deprecated_config_values!" do
    it "logs a warning when deprecated config values are present" do
      node.normal["audit"]["owner"] = "my_org"
      node.normal["audit"]["inspec_version"] = "90210"

      expect(logger).to receive(:warn).with(/config values 'inspec_version', 'owner' are not supported/)

      runner.warn_for_deprecated_config_values!
    end

    it "does not log a warning with no deprecated config values" do
      node.normal["audit"]["profiles"]["linux-baseline"] = {
        'compliance': "user/linux-baseline",
        'version': "2.1.0",
      }

      expect(logger).not_to receive(:warn)

      runner.warn_for_deprecated_config_values!
    end
  end

  describe "#send_report" do
    before do
      Chef::Config[:chef_server_url] = "https://chef_config_url.example.com/my_org"
    end

    it "uses the correct URL when 'server' attribute is set for chef-server-automate reporter" do
      node.normal["audit"]["server"] = "https://server_attribute_url.example.com/application/sub_application"
      report = { fake_report: true }

      reporter = double(:chef_server_automate_reporter)
      expect(reporter).to receive(:send_report).with(report)

      expected_opts = hash_including(url: URI("https://server_attribute_url.example.com/application/sub_application/organizations/my_org/data-collector"))

      expect(Chef::Compliance::Reporter::ChefServerAutomate).to receive(:new).with(expected_opts).and_return(reporter)

      runner.send_report("chef-server-automate", report)
    end

    it "falls back to chef_server_url for URL when 'server' attribute is not set for chef-server-automate reporter" do
      report = { fake_report: true }

      reporter = double(:chef_server_automate_reporter)
      expect(reporter).to receive(:send_report).with(report)

      expected_opts = hash_including(url: URI("https://chef_config_url.example.com/organizations/my_org/data-collector"))

      expect(Chef::Compliance::Reporter::ChefServerAutomate).to receive(:new).with(expected_opts).and_return(reporter)

      runner.send_report("chef-server-automate", report)
    end
  end
end
