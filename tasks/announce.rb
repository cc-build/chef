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

require "date"
require "erb"

class ReleaseAnnouncement
  include ERB::Util
  attr_accessor :type, :version, :maj_minor, :date, :release_notes

  def initialize(version, date, type)
    @version = version
    @maj_minor = version.split(".")[0..1].join(".")
    @date = Date.parse(date) unless date.nil?
    @release_notes = release_notes_from_file
    @type = type
  end

  def render
    puts "-" * 30
    puts ERB.new(template_for(@type)).result(binding)
    puts "-" * 30
  end

  def template_for(type)
    File.read("tasks/templates/#{type}.md.erb")
  end

  def release_notes_from_file
    File.read("RELEASE_NOTES.md").match(/^# What's New In #{@maj_minor}:\n\n(.*)/m)[1]
  end
end

desc "Generate the Release Announcement (version: X.Y.Z)"
task :announce_release, :version do |t, args|
  ReleaseAnnouncement.new(args[:version], nil, "release").render
end