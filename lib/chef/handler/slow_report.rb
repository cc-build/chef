#
# Copyright:: Copyright (c) Chef Software Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require_relative "../handler"
require "tty/table" unless defined?(TTY::Table)

class Chef
  class Handler
    class SlowReport < ::Chef::Handler
      attr_accessor :amount

      def initialize(amount)
        @amount = Integer(amount) rescue nil
        @amount ||= 10
      end

      def report
        top = all_resources.sort_by(&:elapsed_time).last(amount).reverse
        data = top.map { |r| [ r.to_s, r.elapsed_time, r.cookbook_name, r.recipe_name, stripped_source_line(r) ] }
        puts "\nTop #{count} slowest #{count == 1 ? "resource" : "resources"}:\n\n"
        table = TTY::Table.new(%w{resource elapsed_time cookbook recipe source}, data)
        rendered = table.render do |renderer|
          renderer.border do
            mid          "-"
            mid_mid      " "
          end
        end
        puts rendered
        puts "\n"
      end

      def count
        num = all_resources.count
        num > amount ? amount : num
      end

      def stripped_source_line(resource)
        # strip the leading path off of the source line
        resource.source_line.gsub(%r{.*/cookbooks/}, "").gsub(%r{.*/chef-[0-9\.]+/}, "")
      end
    end
  end
end
